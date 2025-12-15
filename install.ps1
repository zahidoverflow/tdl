# TDL Telegram to Google Drive Backup Script
# One-liner: irm https://zahidoverflow.github.io/tdl | iex

param(
    [string]$ChannelUrl,
    [string]$DownloadDir,
    [int]$MaxDiskGB = 45,
    [string]$Namespace = "default",
    [string]$Storage,
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"

$Namespace = ([string]$Namespace).Trim()
if ([string]::IsNullOrWhiteSpace($Namespace)) { $Namespace = "default" }
$Storage = ([string]$Storage).Trim()

$homeDir = $env:USERPROFILE
if ([string]::IsNullOrWhiteSpace($homeDir)) { $homeDir = $HOME }
if ([string]::IsNullOrWhiteSpace($homeDir)) { $homeDir = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile) }
if ([string]::IsNullOrWhiteSpace($homeDir)) { $homeDir = (Get-Location).Path }
$configDir = Join-Path $homeDir ".tdl"
$logFile = Join-Path $configDir "log\latest.log"

function Get-TdlCommonArgs {
    $args = @("-n", $Namespace)
    if (-not [string]::IsNullOrWhiteSpace($Storage)) {
        $args += @("--storage", $Storage)
    }
    return $args
}

function Get-TdlStorageDir {
    if ([string]::IsNullOrWhiteSpace($Storage)) {
        return (Join-Path $configDir "data")
    }

    $pairs = $Storage -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    foreach ($pair in $pairs) {
        $kv = $pair -split '=', 2
        if ($kv.Count -ne 2) { continue }
        $key = $kv[0].Trim().ToLowerInvariant()
        $value = $kv[1].Trim()
        if ($key -eq "path" -and -not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }

    return (Join-Path $configDir "data")
}

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

function Get-TdlLogTail {
    param([int]$Lines = 80)
    if (-not (Test-Path $logFile)) { return "" }
    try {
        return (Get-Content $logFile -Tail $Lines -ErrorAction Stop) -join "`n"
    } catch {
        return ""
    }
}

function Show-TdlLogHint {
    $tail = Get-TdlLogTail
    if ([string]::IsNullOrWhiteSpace($tail)) { return }

    if ($tail -match 'connectex' -and ($tail -match 'forbidden' -or $tail -match 'access .*socket')) {
        Write-Host ""
        Write-Host "⚠️ Telegram cannot reach MTProto (blocked by firewall/ISP)." -ForegroundColor Yellow
        Write-Host "   Allow `tdl.exe` in Windows Firewall or use a VPN/proxy." -ForegroundColor Yellow
        Write-Host "   Log: $logFile" -ForegroundColor DarkGray
    } elseif ($tail -match 'unreachable network' -or $tail -match 'network is unreachable') {
        Write-Host ""
        Write-Host "⚠️ Telegram network is unreachable. Check internet or proxy settings." -ForegroundColor Yellow
        Write-Host "   Log: $logFile" -ForegroundColor DarkGray
    }
}

function Test-TdlDbLocked {
    param([string]$Text)
    return ($Text -match 'Current database is used by another process' -or
            $Text -match 'database is locked' -or
            $Text -match 'resource temporarily unavailable')
}

function Show-ChatList {
    param([string]$ExePath)

    $commonArgs = Get-TdlCommonArgs
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        Stop-TdlProcesses
        Clear-TdlLocks -ConfigDir $configDir
        Start-Sleep -Milliseconds 700

        $out = & $ExePath chat ls @commonArgs 2>&1
        $exit = $LASTEXITCODE
        $text = ($out | Out-String)
        $out | Out-Host

        if ($exit -eq 0) { return $true }
        if (Test-TdlDbLocked -Text $text) {
            Write-Host ""
            Write-Host "⚠️ TDL database is locked. Retrying... ($attempt/5)" -ForegroundColor Yellow
            Start-Sleep -Seconds ([math]::Min(5, $attempt))
            continue
        }

        if ($text -match '(?i)not authorized|please login first') {
            Write-Host ""
            Write-Host "[warn] Telegram session not authorized. Re-login required." -ForegroundColor Yellow
            Ensure-TelegramLogin
            $attempt--
            continue
        }

        Write-Host ""
        Write-Host "⚠️ Failed to list chats (exit=$exit). You can still paste a chat ID/username/link." -ForegroundColor Yellow
        if ($exit -eq -1) {
            Write-Host "   Exit -1 usually means Telegram's network is blocked (firewall, ISP or VPN requirement)." -ForegroundColor Yellow
            Write-Host "   Allow `tdl.exe` in Windows Defender Firewall or configure a VPN / proxy." -ForegroundColor Yellow
        }
        Write-Host "   Log file: $logFile" -ForegroundColor DarkGray
        Show-TdlLogHint
        return $false
    }

    Write-Host ""
    Write-Host "⚠️ Still locked after retries. Close any running tdl.exe and try again." -ForegroundColor Yellow
    Show-TdlLogHint
    return $false
}

$script:ActiveDownloadJobId = $null

function Invoke-Cleanup {
    if ($script:ActiveDownloadJobId) {
        try { Stop-Job -Id $script:ActiveDownloadJobId -Force -ErrorAction SilentlyContinue } catch { }
        try { Remove-Job -Id $script:ActiveDownloadJobId -Force -ErrorAction SilentlyContinue } catch { }
        $script:ActiveDownloadJobId = $null
    }
    Stop-TdlProcesses
}

function Ensure-TelegramLogin {
    Write-Host ""
    Write-Host "🔑 First time setup - Login to Telegram" -ForegroundColor Yellow
    while ($true) {
        Stop-TdlProcesses
        Clear-TdlLocks -ConfigDir $configDir
        Start-Sleep -Seconds 1

        $commonArgs = Get-TdlCommonArgs
        & $tdlExePath login @commonArgs
        if ($LASTEXITCODE -eq 0) {
            $script:DidLoginThisRun = $true
            return
        }

        Write-Host ""
        Write-Host "[warn] Telegram login failed (exit=$LASTEXITCODE)." -ForegroundColor Red
        Write-Host "   Make sure no other `tdl.exe` processes are running and try again." -ForegroundColor Yellow
        Write-Host "   Locks were cleared automatically; if it still fails, close any running tdl and retry." -ForegroundColor Yellow
        Read-Host "Press Enter to retry login (Ctrl+C to cancel)"
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

    $tempDir = [IO.Path]::GetTempPath()
    $zipPath = Join-Path $tempDir "tdl.zip"
    $extractDir = Join-Path $tempDir "tdl_extract_$PID"

    try {
        $url = "https://github.com/zahidoverflow/tdl/releases/latest/download/tdl_Windows_$arch.zip"

        Invoke-WebRequest -Uri $url -OutFile $zipPath
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
    param($Dir, $Exe, $Ns)

    if (-not (Test-Path $Dir)) { return 0 }

    $commonArgs = @("-n", ([string]$Ns).Trim())
    if (-not [string]::IsNullOrWhiteSpace($Storage)) {
        $commonArgs += @("--storage", $Storage)
    }
    
    $files = @(Get-ChildItem $Dir -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -ne "tdl.exe" -and
                $_.Name -ne "export.json" -and
                $_.Extension -notin @('.tmp', '.part') -and
                -not $_.Name.EndsWith('.downloading') -and
                $_.Length -gt 0
            })

    if ($files.Count -eq 0) { return 0 }

    Write-Host "🚀 Uploading $($files.Count) files to Google Drive..." -ForegroundColor Yellow
    $count = 0
    foreach ($file in $files) {
        $fileSizeMB = [math]::Round($file.Length / 1MB, 2)
        Write-Host "  -> $($file.Name) (${fileSizeMB}MB)" -ForegroundColor White

        & $Exe up @commonArgs --gdrive --rm -p $file.FullName 2>&1 | Out-Host
        if ($LASTEXITCODE -eq 0) {
            $count++
            Write-Host "     ✓ Uploaded & deleted" -ForegroundColor Green
        } else {
            Write-Host "     ❌ Upload failed, keeping file" -ForegroundColor Red
        }
    }
    return [int]$count
}

try {
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
$mediaDir = Join-Path $DownloadDir "tdl-downloads"
$null = New-Item -ItemType Directory -Force -Path $mediaDir -ErrorAction SilentlyContinue

Ensure-TdlExe -ExePath $tdlExePath
Set-Location $DownloadDir

# Telegram login (first time)
Write-Host "🔍 Checking Telegram session..." -ForegroundColor Gray
Stop-TdlProcesses
Clear-TdlLocks -ConfigDir $configDir
$script:DidLoginThisRun = $false

$storageDir = Get-TdlStorageDir
$null = New-Item -ItemType Directory -Force -Path $storageDir -ErrorAction SilentlyContinue
$namespaceFile = Join-Path $storageDir $Namespace
$legacyNamespaceFile = Join-Path $storageDir (" " + $Namespace)
if ((Test-Path $namespaceFile) -and (Test-Path $legacyNamespaceFile)) {
    Write-Host "[warn] Found both namespaces '$Namespace' and ' $Namespace'. Using '$Namespace'." -ForegroundColor Yellow
} elseif ((-not (Test-Path $namespaceFile)) -and (Test-Path $legacyNamespaceFile)) {
    Write-Host "[warn] Found legacy namespace file: $legacyNamespaceFile" -ForegroundColor Yellow
    Write-Host "[warn] Renaming it to: $namespaceFile" -ForegroundColor Yellow
    try { Move-Item -Path $legacyNamespaceFile -Destination $namespaceFile -Force -ErrorAction Stop } catch { }
}
if (-not (Test-Path $namespaceFile)) {
    Ensure-TelegramLogin
} else {
    Write-Host "✓ Session valid" -ForegroundColor Green
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

if ($CheckOnly) {
    Write-Host ""
    Write-Host "✅ Preflight OK" -ForegroundColor Green
    Write-Host "  tdl.exe:  $tdlExePath" -ForegroundColor White
    Write-Host "  config:   $configDir" -ForegroundColor White
    Write-Host "  gdrive:    $gdriveCreds" -ForegroundColor White
    return
}

if (-not $ChannelUrl) {
    Write-Host ""
    Write-Host "💬 Enter Channel / Chat:" -ForegroundColor Yellow
    Write-Host "  Option 1: Message link (e.g., https://t.me/c/2674423259/8465)" -ForegroundColor Gray
    Write-Host "  Option 2: Username (e.g., ANON_CHANNEL)" -ForegroundColor Gray
    Write-Host "  Option 3: Press Enter to list chats" -ForegroundColor Gray
    Write-Host ""

    do {
        $ChannelUrl = Read-Host "Enter link/username/ID (or press Enter to list chats)"
        if ($ChannelUrl -match '^\s*(3|ls|list)\s*$') { $ChannelUrl = "" }
        if ([string]::IsNullOrWhiteSpace($ChannelUrl)) {
            Write-Host ""
            Write-Host "📋 Your accessible chats:" -ForegroundColor Cyan
            $null = Show-ChatList -ExePath $tdlExePath
            Write-Host ""
            $ChannelUrl = Read-Host "Now enter a chat username or ID from the list above"
        }
    } while ([string]::IsNullOrWhiteSpace($ChannelUrl))
}

$ChannelUrl = Resolve-ChatInput -InputValue $ChannelUrl
Write-Host "✓ Target: $ChannelUrl" -ForegroundColor Green

Write-Host ""
Write-Host "🚀 Starting backup" -ForegroundColor Cyan
Write-Host "  DownloadDir: $DownloadDir" -ForegroundColor White
Write-Host "  MediaDir:    $mediaDir" -ForegroundColor White
Write-Host "  MaxDiskGB:   $MaxDiskGB" -ForegroundColor White
Write-Host ""

Stop-TdlProcesses
Clear-TdlLocks -ConfigDir $configDir

# Step 1: Export (Blocking, run once)
$exportFile = Join-Path $DownloadDir "export.json"
if (Test-Path $exportFile) {
    $existingExport = Get-Item $exportFile -ErrorAction SilentlyContinue
    if ($existingExport -and $existingExport.Length -eq 0) {
        Remove-Item $exportFile -Force -ErrorAction SilentlyContinue
    }
}
if (-not (Test-Path $exportFile)) {
    Write-Host "Step 1: Exporting messages..." -ForegroundColor Yellow
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Stop-TdlProcesses
        Clear-TdlLocks -ConfigDir $configDir

        $commonArgs = Get-TdlCommonArgs
        & $tdlExePath chat export @commonArgs -c $ChannelUrl -o $exportFile
        if ($LASTEXITCODE -eq 0) { break }

        Remove-Item $exportFile -Force -ErrorAction SilentlyContinue
        if (-not $script:DidLoginThisRun) {
            Ensure-TelegramLogin
            $attempt = 0
            continue
        }
        if ($attempt -ge 3) { throw "Chat export failed (exit=$LASTEXITCODE)" }

        Write-Host ""
        Write-Host "⚠️ Chat export failed (exit=$LASTEXITCODE). Retrying... ($attempt/3)" -ForegroundColor Yellow
        Start-Sleep -Seconds 3
    }
}

# Step 2: Download & Upload Loop (Sequential)
$uploadTriggerGB = 10 
if ($MaxDiskGB -lt 15) { $uploadTriggerGB = [math]::Floor($MaxDiskGB / 2) }

Write-Host "Step 2: Starting Download-Upload Loop..." -ForegroundColor Yellow
$totalUploaded = 0
$downloadFailureCount = 0

while ($true) {
    # Clean up any locks from previous iteration
    Stop-TdlProcesses
    Clear-TdlLocks -ConfigDir $configDir
    Start-Sleep -Milliseconds 700
    
    # Check if download is complete (hacky way: tdl dl returns 0 if done, or we check output)
    # We run tdl dl as a Job so we can kill it when disk fills up
    
    $dlJob = Start-Job -ScriptBlock {
        param($exe, $commonArgs, $ef, $dir)
        $ErrorActionPreference = "Stop"
        # --continue is key here
        & $exe dl @commonArgs -f $ef -d $dir --continue -l 4
        if ($LASTEXITCODE -ne 0) { throw "tdl download failed (exit=$LASTEXITCODE)" }
    } -ArgumentList $tdlExePath, (Get-TdlCommonArgs), $exportFile, $mediaDir
    $script:ActiveDownloadJobId = $dlJob.Id

    Write-Host "⬇️ Downloading... (Job: $($dlJob.Id))" -ForegroundColor Cyan
    
    $jobComplete = $false
    $jobFailed = $false
    while ($true) {
        Start-Sleep -Seconds 10
        
        # Check Job Status
        $state = (Get-Job -Id $dlJob.Id).State
        if ($state -eq 'Completed') {
            Receive-Job -Id $dlJob.Id | Out-Host
            $jobComplete = $true
            break
        }
        if ($state -eq 'Failed') {
            $jobOut = Receive-Job -Id $dlJob.Id -ErrorAction SilentlyContinue 2>&1
            $jobText = ($jobOut | Out-String)
            $jobOut | Out-Host
            $jobFailed = $true
            $downloadFailureCount++

            if ($jobText -match '(?i)not authorized|please login first') {
                Write-Host ""
                Write-Host "⚠️ Telegram session not authorized. Re-login required." -ForegroundColor Yellow
                Ensure-TelegramLogin
                $downloadFailureCount = 0
                break
            }

            if (Test-TdlDbLocked -Text $jobText) {
                Write-Host ""
                Write-Host "⚠️ TDL database is locked. Retrying after cleanup..." -ForegroundColor Yellow
            }

            if ($downloadFailureCount -ge 3) {
                throw "Download job failed too many times. If you see a database lock error, close other tdl.exe processes and rerun."
            }

            Write-Host ""
            Write-Host "⚠️ Download job failed. Retrying... ($downloadFailureCount/3)" -ForegroundColor Yellow
            Stop-TdlProcesses
            Clear-TdlLocks -ConfigDir $configDir
            Start-Sleep -Seconds 3
            break
        }
        
        # Check Disk Usage
        $size = Get-DirSizeGB -Path $mediaDir
        if ($size -ge $uploadTriggerGB) {
            Write-Host "⚠️ Disk threshold reached (${size}GB). Pausing download to upload..." -ForegroundColor Yellow
            Stop-Job -Id $dlJob.Id -Force
            break
        }
    }

    if (-not $jobFailed) { $downloadFailureCount = 0 }
    
    # Ensure process is dead and lock is released
    Stop-TdlProcesses
    Start-Sleep -Seconds 2
    
    # Upload Phase
    Remove-Job -Id $dlJob.Id -Force -ErrorAction SilentlyContinue
    $script:ActiveDownloadJobId = $null

    $uploaded = Upload-Files -Dir $mediaDir -Exe $tdlExePath -Ns $Namespace
    $totalUploaded += $uploaded
    
    if ($jobComplete) {
        Write-Host "✅ Download job finished." -ForegroundColor Green
        # Final cleanup check
        $remaining = Upload-Files -Dir $mediaDir -Exe $tdlExePath -Ns $Namespace
        $totalUploaded += $remaining
        break
    }
}

Write-Host ""
Write-Host "🎉 Backup Complete!" -ForegroundColor Green
Write-Host "Total files uploaded: $totalUploaded"

$cleanup = Read-Host "Delete downloaded files folder (tdl-downloads)? (y/N)"
if ($cleanup -eq "y" -or $cleanup -eq "Y") {
    Remove-Item $mediaDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "✓ Cleanup complete" -ForegroundColor Green
}
} catch {
    if ($_.Exception -is [System.Management.Automation.PipelineStoppedException] -or $_.Exception -is [System.OperationCanceledException]) {
        return
    }
    Write-Host ""
    Write-Host "❌ $($_.Exception.Message)" -ForegroundColor Red
    throw
} finally {
    Invoke-Cleanup
}
