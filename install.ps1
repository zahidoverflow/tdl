# TDL Telegram to Google Drive Backup Script
# One-liner install: irm https://zahidoverflow.github.io/tdl | iex

param(
    [string]$ChannelUrl,
    [string]$DownloadDir = "C:\tdl_temp",
    [int]$MaxDiskGB = 45
)

# Configuration prompt if not provided
if (-not $ChannelUrl) {
    Write-Host "🔄 TDL - Telegram to Google Drive Backup" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    $ChannelUrl = Read-Host "Enter Telegram channel URL (e.g., https://t.me/yourchannel)"
}

# Create download directory
New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null

# Download tdl.exe
Write-Host "📥 Downloading tdl.exe..." -ForegroundColor Yellow
$TdlZip = "$env:TEMP\tdl.zip"
$TdlDir = "$env:TEMP\tdl"

try {
    $latest = (Invoke-RestMethod "https://api.github.com/repos/zahidoverflow/tdl/releases/latest").tag_name
    $url = "https://github.com/zahidoverflow/tdl/releases/download/$latest/tdl_Windows_64bit.zip"
    
    Invoke-WebRequest -Uri $url -OutFile $TdlZip -UseBasicParsing
    Expand-Archive -Path $TdlZip -DestinationPath $TdlDir -Force
    
    $tdlExe = Get-ChildItem -Path $TdlDir -Filter "tdl.exe" -Recurse | Select-Object -First 1
    
    if (-not $tdlExe) {
        throw "tdl.exe not found in downloaded archive"
    }
    
    Copy-Item $tdlExe.FullName -Destination "$DownloadDir\tdl.exe" -Force
    Set-Location $DownloadDir
    
    Write-Host "✅ Downloaded tdl.exe" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to download tdl.exe: $_" -ForegroundColor Red
    exit 1
}

# Check if already logged in
$configDir = "$env:USERPROFILE\.tdl"
if (-not (Test-Path "$configDir\data\data")) {
    Write-Host ""
    Write-Host "🔐 First time setup - Login to Telegram" -ForegroundColor Yellow
    Write-Host "You need to authenticate with Telegram..." -ForegroundColor Yellow
    & .\tdl.exe login
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Login failed" -ForegroundColor Red
        exit 1
    }
}

# Check Google Drive credentials
if (-not (Test-Path "$configDir\gdrive_credentials.json")) {
    Write-Host ""
    Write-Host "⚠️ Google Drive credentials not found!" -ForegroundColor Red
    Write-Host "Please setup Google Drive credentials first:" -ForegroundColor Yellow
    Write-Host "1. Create credentials: https://console.cloud.google.com/apis/credentials" -ForegroundColor Cyan
    Write-Host "2. Save JSON to: $configDir\gdrive_credentials.json" -ForegroundColor Cyan
    Write-Host ""
    Read-Host "Press Enter when credentials file is ready"
    
    if (-not (Test-Path "$configDir\gdrive_credentials.json")) {
        Write-Host "❌ Credentials still not found. Exiting." -ForegroundColor Red
        exit 1
    }
}

# Main backup function
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

# Start backup
Write-Host ""
Write-Host "🚀 Starting Telegram → Google Drive Backup" -ForegroundColor Cyan
Write-Host "Channel: $ChannelUrl" -ForegroundColor White
Write-Host "Download Dir: $DownloadDir" -ForegroundColor White
Write-Host "Max Disk: ${MaxDiskGB}GB" -ForegroundColor White
Write-Host ""

# Start download in background job
Write-Host "📥 Starting channel download..." -ForegroundColor Yellow
$downloadJob = Start-Job -ScriptBlock {
    param($exe, $url, $dir)
    Set-Location (Split-Path $exe)
    & $exe dl -u $url -d $dir --continue 2>&1
} -ArgumentList "$DownloadDir\tdl.exe", $ChannelUrl, $DownloadDir

Write-Host "✅ Download started in background (Job ID: $($downloadJob.Id))" -ForegroundColor Green
Write-Host ""

# Monitor and upload loop
$uploadedCount = 0
$totalSizeUploaded = 0
$lastCheck = Get-Date

Write-Host "🔄 Monitoring for completed downloads..." -ForegroundColor Cyan
Write-Host ""

while ($true) {
    # Check if download job is still running
    $jobState = (Get-Job -Id $downloadJob.Id).State
    
    # Get current disk usage
    $currentSize = Get-DirSizeGB -Path $DownloadDir
    
    # Get files ready for upload (exclude tdl.exe and temp files)
    $files = Get-ChildItem $DownloadDir -File -ErrorAction SilentlyContinue | 
             Where-Object { $_.Name -ne "tdl.exe" -and $_.Extension -ne ".tmp" -and $_.Length -gt 1MB }
    
    # Upload files if we have any
    if ($files.Count -gt 0) {
        Write-Host "📤 Found $($files.Count) file(s) ready for upload" -ForegroundColor Yellow
        
        foreach ($file in $files) {
            $fileSizeMB = [math]::Round($file.Length / 1MB, 2)
            Write-Host "  → Uploading: $($file.Name) (${fileSizeMB}MB)" -ForegroundColor White
            
            # Upload to Google Drive and delete
            & .\tdl.exe up --gdrive --rm -p $file.FullName 2>&1 | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                $uploadedCount++
                $totalSizeUploaded += $file.Length
                Write-Host "    ✅ Uploaded & deleted" -ForegroundColor Green
            } else {
                Write-Host "    ⚠️ Upload failed, keeping file" -ForegroundColor Yellow
            }
            
            Start-Sleep -Seconds 2  # Prevent rate limiting
        }
        
        Write-Host ""
    }
    
    # Status update every 30 seconds
    $now = Get-Date
    if (($now - $lastCheck).TotalSeconds -ge 30) {
        $uploadedGB = [math]::Round($totalSizeUploaded / 1GB, 2)
        Write-Host "📊 Status: Uploaded $uploadedCount files (${uploadedGB}GB) | Disk: ${currentSize}GB/${MaxDiskGB}GB | Job: $jobState" -ForegroundColor Cyan
        $lastCheck = $now
    }
    
    # Check disk limit
    if ($currentSize -ge $MaxDiskGB) {
        Write-Host "⚠️ Disk limit reached! Waiting for uploads to free space..." -ForegroundColor Red
        Start-Sleep -Seconds 10
        continue
    }
    
    # Exit conditions
    if ($jobState -eq 'Completed' -and $files.Count -eq 0) {
        Write-Host ""
        Write-Host "✅ Download complete and all files uploaded!" -ForegroundColor Green
        break
    }
    
    if ($jobState -eq 'Failed') {
        Write-Host ""
        Write-Host "❌ Download job failed!" -ForegroundColor Red
        Receive-Job -Id $downloadJob.Id
        break
    }
    
    # Wait before next check
    Start-Sleep -Seconds 10
}

# Cleanup
Write-Host ""
Write-Host "🧹 Cleaning up..." -ForegroundColor Yellow
Remove-Job -Id $downloadJob.Id -Force -ErrorAction SilentlyContinue

$finalSize = [math]::Round($totalSizeUploaded / 1GB, 2)
Write-Host ""
Write-Host "🎉 Backup Complete!" -ForegroundColor Green
Write-Host "Files uploaded: $uploadedCount" -ForegroundColor White
Write-Host "Total size: ${finalSize}GB" -ForegroundColor White
Write-Host ""

# Ask to cleanup download directory
$cleanup = Read-Host "Delete download directory? (y/N)"
if ($cleanup -eq 'y' -or $cleanup -eq 'Y') {
    Remove-Item $DownloadDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "✅ Cleanup complete" -ForegroundColor Green
}
