# TDL Telegram to Google Drive Backup Script
# One-liner: irm https://zahidoverflow.github.io/tdl | iex

param(
    [string]$ChannelUrl,
    [string]$DownloadDir,
    [int]$MaxDiskGB = 45,
    [string]$Namespace = "installer"
)

$ErrorActionPreference = "Stop"

function Stop-TdlProcesses {
    $procs = Get-Process -Name "tdl" -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Host "[warn] Found other tdl.exe processes. Stopping them to clear locks..." -ForegroundColor Yellow
        $procs | ForEach-Object {
            try { Stop-Process -Id $_.Id -Force -ErrorAction Stop } catch { }
        }
    }
}

function Clear-TdlLocks {
    param([string]$ConfigDir)
    $lockPath = Join-Path $ConfigDir "data\data.lock"
    if (Test-Path $lockPath) {
        Write-Host "[info] Removing lock file: $lockPath" -ForegroundColor Yellow
        Remove-Item $lockPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-DirSizeGB {
    param([string]$Path)
    if (Test-Path $Path) {
        $size = (Get-ChildItem $Path -Recurse -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($size) {
            return [math]::Round($size / 1GB, 2)
        }
    }
    return 0
}

function Resolve-ChatInput {
    param([string]$InputValue)

    $s = ([string]$InputValue).Trim()
    if ([string]::IsNullOrWhiteSpace($s)) { return "" }

    if ($s -match '^https://t\.me/c/(\d+)') { return $matches[1] }
    if ($s -match '^-100(\d+)$') { return $matches[1] }
    if ($s -match '^-(\d+)$') { return $matches[1] }

    return $s
}

function Ensure-TdlExe {
    param([string]$ExePath)

    if (Test-Path $ExePath) {
        Write-Host "✓ Using existing tdl.exe: $ExePath" -ForegroundColor Green
        return
    }

    $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
        "AMD64" { "64bit" }
        "x86" { "32bit" }
        "ARM64" { "arm64" }
        default { "64bit" }
    }

    Write-Host "⬇️ Downloading tdl.exe ($arch)..." -ForegroundColor Yellow

    $zipPath = Join-Path $env:TEMP "tdl.zip"
    $extractDir = Join-Path $env:TEMP "tdl_extract"

    try {
        $latest = (Invoke-RestMethod "https://api.github.com/repos/zahidoverflow/tdl/releases/latest").tag_name
        $url = "https://github.com/zahidoverflow/tdl/releases/download/$latest/tdl_Windows_$arch.zip"

        Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

        $exe = Get-ChildItem -Path $extractDir -Filter "tdl.exe" -Recurse | Select-Object -First 1
        if (-not $exe) { throw "tdl.exe not found in downloaded archive" }

        Copy-Item $exe.FullName -Destination $ExePath -Force
        Write-Host "✓ Downloaded tdl.exe" -ForegroundColor Green
    } catch {
        Write-Error "Failed to download tdl.exe from zahidoverflow/tdl. Please ensure a release exists."
        throw $_
    } finally {
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Upload-Files {
    param($Dir, $Exe, $Ns, $Stg)
    
    $files = Get-ChildItem $Dir -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -ne "tdl.exe" -and
                $_.Name -ne "export.json" -and
                $_.Extension -notin @('.tmp', '.part') -and
                -not $_.Name.EndsWith('.downloading') -and
                $_.Length -gt 1MB
            }

    if ($files.Count -eq 0) { return 0 }

    Write-Host "🚀 Uploading $($files.Count) files to Google Drive..." -ForegroundColor Yellow
    $count = 0
    foreach ($file in $files) {
        $fileSizeMB = [math]::Round($file.Length / 1MB, 2)
        Write-Host "  -> $($file.Name) (${fileSizeMB}MB)" -ForegroundColor White

        & $Exe up -n $Ns -s $Stg --gdrive --rm -p $file.FullName
        if ($LASTEXITCODE -eq 0) {
            $count++
            Write-Host "     ✓ Uploaded & deleted" -ForegroundColor Green
        } else {
            Write-Host "     ❌ Upload failed, keeping file" -ForegroundColor Red
        }
    }
    return $count
}

Write-Host "🚀 TDL - Telegram -> Google Drive Backup" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

if (-not $DownloadDir) {
    $defaultDir = (Get-Location).Path
    Write-Host "📂 Download Directory" -ForegroundColor Yellow
    Write-Host "  Default: $defaultDir" -ForegroundColor Gray
    Write-Host ""
    $customDir = Read-Host "Enter download directory (press Enter for default)"
    if ([string]::IsNullOrWhiteSpace($customDir)) { $DownloadDir = $defaultDir } else { $DownloadDir = $customDir.Trim() }
}

New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
$tdlExePath = Join-Path $DownloadDir "tdl.exe"

$storagePath = Join-Path $DownloadDir "tdl-data.db"
$storageOpt = "type=bolt,path=$storagePath"

Ensure-TdlExe -ExePath $tdlExePath
Set-Location $DownloadDir

if (-not $ChannelUrl) {
    Write-Host "💬 Enter Channel / Chat:" -ForegroundColor Yellow
    Write-Host "  Option 1: Message link (e.g., https://t.me/c/2674423259/8465)" -ForegroundColor Gray
    Write-Host "  Option 2: Username (e.g., ANON_CHANNEL)" -ForegroundColor Gray
    Write-Host "  Option 3: Press Enter to list chats" -ForegroundColor Gray
    Write-Host ""

    do {
        $ChannelUrl = Read-Host "Enter link/username/ID (or press Enter to list chats)"
        if ([string]::IsNullOrWhiteSpace($ChannelUrl)) {
            Write-Host ""
            Write-Host "📋 Your accessible chats:" -ForegroundColor Cyan
            & $tdlExePath chat ls -n $Namespace -s $storageOpt 2>&1 | Out-Host
            Write-Host ""
            $ChannelUrl = Read-Host "Now enter a chat username or ID from the list above"
        }
    } while ([string]::IsNullOrWhiteSpace($ChannelUrl))
}

$ChannelUrl = Resolve-ChatInput -InputValue $ChannelUrl
Write-Host "✓ Target: $ChannelUrl" -ForegroundColor Green

# Telegram login (first time)
$configDir = Join-Path $env:USERPROFILE ".tdl"
if (-not (Test-Path (Join-Path $configDir "data\data"))) {
    Write-Host ""
    Write-Host "🔑 First time setup - Login to Telegram" -ForegroundColor Yellow
    while ($true) {
        Stop-TdlProcesses
        Clear-TdlLocks -ConfigDir $configDir
        & $tdlExePath login -n $Namespace -s $storageOpt
        if ($LASTEXITCODE -eq 0) { break }
        Write-Host ""
        Write-Host "[warn] Telegram login failed (exit=$LASTEXITCODE)." -ForegroundColor Red
        Write-Host "   Make sure no other `tdl.exe` processes are running and try again." -ForegroundColor Yellow
        Write-Host "   Locks were cleared automatically; if it still fails, close any running tdl and retry." -ForegroundColor Yellow
        Read-Host "Press Enter to retry login (Ctrl+C to cancel)"
    }
}

# Google Drive credentials
$gdriveCreds = Join-Path $configDir "gdrive_credentials.json"
if (-not (Test-Path $gdriveCreds)) {
    Write-Host ""
    Write-Host "❌ Google Drive credentials not found!" -ForegroundColor Red
    Write-Host "Save OAuth JSON here: $gdriveCreds" -ForegroundColor Yellow
    Write-Host "Create credentials: https://console.cloud.google.com/apis/credentials" -ForegroundColor Cyan
    Write-Host ""
    Read-Host "Press Enter when the credentials file is ready"
    if (-not (Test-Path $gdriveCreds)) { throw "Google Drive credentials still not found" }
}

Write-Host ""
Write-Host "🚀 Starting backup" -ForegroundColor Cyan
Write-Host "  DownloadDir: $DownloadDir" -ForegroundColor White
Write-Host "  MaxDiskGB:   $MaxDiskGB" -ForegroundColor White
Write-Host ""

Stop-TdlProcesses
Clear-TdlLocks -ConfigDir $configDir

# Step 1: Export (Blocking, run once)
$exportFile = Join-Path $DownloadDir "export.json"
if (-not (Test-Path $exportFile)) {
    Write-Host "Step 1: Exporting messages..." -ForegroundColor Yellow
    & $tdlExePath chat export -n $Namespace -s $storageOpt -c $ChannelUrl -o $exportFile
    if ($LASTEXITCODE -ne 0) { throw "Chat export failed" }
}

# Step 2: Download & Upload Loop (Sequential)
$uploadTriggerGB = 10 
if ($MaxDiskGB -lt 15) { $uploadTriggerGB = [math]::Floor($MaxDiskGB / 2) }

Write-Host "Step 2: Starting Download-Upload Loop..." -ForegroundColor Yellow
$totalUploaded = 0

while ($true) {
    # Clean up any locks from previous iteration
    Stop-TdlProcesses
    
    # Check if download is complete (hacky way: tdl dl returns 0 if done, or we check output)
    # We run tdl dl as a Job so we can kill it when disk fills up
    
    $dlJob = Start-Job -ScriptBlock {
        param($exe, $ns, $stg, $ef, $dir)
        $ErrorActionPreference = "Stop"
        # --continue is key here
        & $exe dl -n $ns -s $stg -f $ef -d $dir --continue -l 4
    } -ArgumentList $tdlExePath, $Namespace, $storageOpt, $exportFile, $DownloadDir

    Write-Host "⬇️ Downloading... (Job: $($dlJob.Id))" -ForegroundColor Cyan
    
    $jobComplete = $false
    while ($true) {
        Start-Sleep -Seconds 10
        
        # Check Job Status
        $state = (Get-Job -Id $dlJob.Id).State
        if ($state -eq 'Completed' -or $state -eq 'Failed') {
            Receive-Job -Id $dlJob.Id | Out-Host
            $jobComplete = $true
            break
        }
        
        # Check Disk Usage
        $size = Get-DirSizeGB -Path $DownloadDir
        if ($size -ge $uploadTriggerGB) {
            Write-Host "⚠️ Disk threshold reached (${size}GB). Pausing download to upload..." -ForegroundColor Yellow
            Stop-Job -Id $dlJob.Id -Force
            break
        }
    }
    
    # Ensure process is dead and lock is released
    Stop-TdlProcesses
    Start-Sleep -Seconds 2
    
    # Upload Phase
    $uploaded = Upload-Files -Dir $DownloadDir -Exe $tdlExePath -Ns $Namespace -Stg $storageOpt
    $totalUploaded += $uploaded
    
    if ($jobComplete) {
        Write-Host "✅ Download job finished." -ForegroundColor Green
        # Final cleanup check
        $remaining = Upload-Files -Dir $DownloadDir -Exe $tdlExePath -Ns $Namespace -Stg $storageOpt
        $totalUploaded += $remaining
        break
    }
}

Write-Host ""
Write-Host "🎉 Backup Complete!" -ForegroundColor Green
Write-Host "Total files uploaded: $totalUploaded"

$cleanup = Read-Host "Delete download directory? (y/N)"
if ($cleanup -eq "y" -or $cleanup -eq "Y") {
    Remove-Item $DownloadDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "✓ Cleanup complete" -ForegroundColor Green
}