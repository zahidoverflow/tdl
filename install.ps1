# TDL Telegram to Google Drive Backup Script
# One-liner: irm https://zahidoverflow.github.io/tdl | iex

param(
    [string]$ChannelUrl,
    [string]$DownloadDir,
    [int]$MaxDiskGB = 45
)

$ErrorActionPreference = "Stop"

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

    if ($s -match '^https://t\.me/c/(\d+)') {
        return $matches[1]
    }
    if ($s -match '^-100(\d+)$') {
        return $matches[1]
    }
    if ($s -match '^-(\d+)$') {
        return $matches[1]
    }

    return $s
}

function Ensure-TdlExe {
    param(
        [string]$ExePath
    )

    if (Test-Path $ExePath) {
        Write-Host "? Using existing tdl.exe: $ExePath" -ForegroundColor Green
        return
    }

    $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
        "AMD64" { "64bit" }
        "x86" { "32bit" }
        "ARM64" { "arm64" }
        default { "64bit" }
    }

    Write-Host "?? Downloading tdl.exe ($arch)..." -ForegroundColor Yellow

    $zipPath = Join-Path $env:TEMP "tdl.zip"
    $extractDir = Join-Path $env:TEMP "tdl_extract"

    try {
        $latest = (Invoke-RestMethod "https://api.github.com/repos/zahidoverflow/tdl/releases/latest").tag_name
        $url = "https://github.com/zahidoverflow/tdl/releases/download/$latest/tdl_Windows_$arch.zip"

        Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

        $exe = Get-ChildItem -Path $extractDir -Filter "tdl.exe" -Recurse | Select-Object -First 1
        if (-not $exe) {
            throw "tdl.exe not found in downloaded archive"
        }

        Copy-Item $exe.FullName -Destination $ExePath -Force
        Write-Host "? Downloaded tdl.exe" -ForegroundColor Green
    } finally {
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "?? TDL - Telegram -> Google Drive Backup" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

if (-not $DownloadDir) {
    Write-Host "?? Download Directory" -ForegroundColor Yellow
    Write-Host "  Default: C:\tdl_temp" -ForegroundColor Gray
    Write-Host ""
    $customDir = Read-Host "Enter download directory (press Enter for default)"
    if ([string]::IsNullOrWhiteSpace($customDir)) {
        $DownloadDir = "C:\tdl_temp"
    } else {
        $DownloadDir = $customDir.Trim()
    }
}

New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
$tdlExePath = Join-Path $DownloadDir "tdl.exe"

Ensure-TdlExe -ExePath $tdlExePath
Set-Location $DownloadDir

if (-not $ChannelUrl) {
    Write-Host "?? Enter Channel / Chat:" -ForegroundColor Yellow
    Write-Host "  Option 1: Message link (e.g., https://t.me/c/2674423259/8465)" -ForegroundColor Gray
    Write-Host "  Option 2: Username (e.g., ANON_CHANNEL)" -ForegroundColor Gray
    Write-Host "  Option 3: Press Enter to list chats" -ForegroundColor Gray
    Write-Host ""

    do {
        $ChannelUrl = Read-Host "Enter link/username/ID (or press Enter to list chats)"
        if ([string]::IsNullOrWhiteSpace($ChannelUrl)) {
            Write-Host ""
            Write-Host "?? Your accessible chats:" -ForegroundColor Cyan
            & $tdlExePath chat ls 2>&1 | Out-Host
            Write-Host ""
            $ChannelUrl = Read-Host "Now enter a chat username or ID from the list above"
        }
    } while ([string]::IsNullOrWhiteSpace($ChannelUrl))
}

$ChannelUrl = Resolve-ChatInput -InputValue $ChannelUrl
Write-Host "? Target: $ChannelUrl" -ForegroundColor Green

# Telegram login (first time)
$configDir = Join-Path $env:USERPROFILE ".tdl"
if (-not (Test-Path (Join-Path $configDir "data\\data"))) {
    Write-Host ""
    Write-Host "?? First time setup - Login to Telegram" -ForegroundColor Yellow
    & $tdlExePath login
    if ($LASTEXITCODE -ne 0) { throw "Telegram login failed" }
}

# Google Drive credentials
$gdriveCreds = Join-Path $configDir "gdrive_credentials.json"
if (-not (Test-Path $gdriveCreds)) {
    Write-Host ""
    Write-Host "?? Google Drive credentials not found!" -ForegroundColor Red
    Write-Host "Save OAuth JSON here: $gdriveCreds" -ForegroundColor Yellow
    Write-Host "Create credentials: https://console.cloud.google.com/apis/credentials" -ForegroundColor Cyan
    Write-Host ""
    Read-Host "Press Enter when the credentials file is ready"
    if (-not (Test-Path $gdriveCreds)) { throw "Google Drive credentials still not found" }
}

Write-Host ""
Write-Host "?? Starting backup" -ForegroundColor Cyan
Write-Host "  DownloadDir: $DownloadDir" -ForegroundColor White
Write-Host "  MaxDiskGB:   $MaxDiskGB" -ForegroundColor White
Write-Host ""

$downloadJob = Start-Job -ScriptBlock {
    param($exe, $chat, $dir)

    $ErrorActionPreference = "Stop"

    $exportFile = Join-Path $dir "export.json"

    Write-Output "Step 1: Exporting messages (for download)..."
    & $exe chat export -c $chat -o $exportFile 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exportFile)) {
        throw "chat export failed (exit=$LASTEXITCODE)"
    }

    Write-Output "Step 2: Downloading media from export..."
    & $exe dl -f $exportFile -d $dir --continue -l 4 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "download failed (exit=$LASTEXITCODE)"
    }
    Write-Output "Download finished"
} -ArgumentList $tdlExePath, $ChannelUrl, $DownloadDir

Write-Host "? Download started (Job ID: $($downloadJob.Id))" -ForegroundColor Green
Write-Host ""

$uploadedCount = 0
$totalSizeUploadedBytes = 0
$lastStatus = Get-Date

while ($true) {
    $jobState = (Get-Job -Id $downloadJob.Id).State
    $currentSize = Get-DirSizeGB -Path $DownloadDir

    $files = Get-ChildItem $DownloadDir -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -ne "tdl.exe" -and
            $_.Name -ne "export.json" -and
            $_.Extension -notin @(".tmp", ".part") -and
            -not $_.Name.EndsWith(".downloading") -and
            $_.Length -gt 1MB
        }

    if ($files.Count -gt 0) {
        Write-Host "?? Found $($files.Count) file(s) ready for upload" -ForegroundColor Yellow
        foreach ($file in $files) {
            $fileSizeMB = [math]::Round($file.Length / 1MB, 2)
            Write-Host "  -> $($file.Name) (${fileSizeMB}MB)" -ForegroundColor White

            & $tdlExePath up --gdrive --rm -p $file.FullName
            if ($LASTEXITCODE -eq 0) {
                $uploadedCount++
                $totalSizeUploadedBytes += $file.Length
                Write-Host "     ? Uploaded & deleted" -ForegroundColor Green
            } else {
                Write-Host "     ?? Upload failed, keeping file" -ForegroundColor Yellow
            }

            Start-Sleep -Seconds 2
        }
        Write-Host ""
    }

    $now = Get-Date
    if (($now - $lastStatus).TotalSeconds -ge 30) {
        $uploadedGB = [math]::Round($totalSizeUploadedBytes / 1GB, 2)
        Write-Host "?? Status: Uploaded $uploadedCount files (${uploadedGB}GB) | Disk: ${currentSize}GB/${MaxDiskGB}GB | Job: $jobState" -ForegroundColor Cyan
        $lastStatus = $now
    }

    $jobOutput = Receive-Job -Id $downloadJob.Id -Keep -ErrorAction SilentlyContinue
    if ($jobOutput) {
        $jobOutput | Select-Object -Last 3 | ForEach-Object {
            Write-Host "  [Download] $_" -ForegroundColor DarkGray
        }
    }

    if ($currentSize -ge $MaxDiskGB) {
        Write-Host "?? Disk limit reached (${currentSize}GB >= ${MaxDiskGB}GB). Waiting for uploads to free space..." -ForegroundColor Red
        Start-Sleep -Seconds 10
        continue
    }

    if ($jobState -eq "Completed" -and $files.Count -eq 0) {
        Write-Host ""
        Write-Host "? Download complete and all files uploaded!" -ForegroundColor Green
        break
    }

    if ($jobState -eq "Failed") {
        Write-Host ""
        Write-Host "? Download job failed!" -ForegroundColor Red
        Receive-Job -Id $downloadJob.Id -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host "  $_" -ForegroundColor Red
        }
        break
    }

    Start-Sleep -Seconds 10
}

Write-Host ""
Write-Host "?? Cleaning up..." -ForegroundColor Yellow
Remove-Job -Id $downloadJob.Id -Force -ErrorAction SilentlyContinue

$finalGB = [math]::Round($totalSizeUploadedBytes / 1GB, 2)
Write-Host ""
Write-Host "?? Backup Complete!" -ForegroundColor Green
Write-Host "Files uploaded: $uploadedCount" -ForegroundColor White
Write-Host "Total size: ${finalGB}GB" -ForegroundColor White
Write-Host ""

$cleanup = Read-Host "Delete download directory? (y/N)"
if ($cleanup -eq "y" -or $cleanup -eq "Y") {
    Remove-Item $DownloadDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "? Cleanup complete" -ForegroundColor Green
}
