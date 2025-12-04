# TDL Telegram to Google Drive Backup Script
# One-liner install: irm https://zahidoverflow.github.io/tdl | iex

param(
    [string]$ChannelUrl,
    [string]$DownloadDir,
    [int]$MaxDiskGB = 45
)

# Configuration prompt if not provided
Write-Host "🔄 TDL - Telegram to Google Drive Backup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if (-not $ChannelUrl) {
    Write-Host "📌 Enter Channel Username or ID:" -ForegroundColor Yellow
    Write-Host "  Public channel:  channelname (without @)" -ForegroundColor Gray
    Write-Host "  Private channel: -1234567890 (with negative sign)" -ForegroundColor Gray
    Write-Host "  Or find ID using: tdl chat ls" -ForegroundColor Gray
    Write-Host ""
    
    do {
        $ChannelUrl = Read-Host "Enter channel username or ID"
        
        # Validate: must be either alphanumeric username or negative number ID
        if ($ChannelUrl -notmatch '^-?\d+$' -and $ChannelUrl -notmatch '^[a-zA-Z0-9_]+$') {
            Write-Host "❌ Invalid format!" -ForegroundColor Red
            Write-Host "   Username: channelname (no @ or https)" -ForegroundColor Yellow
            Write-Host "   ID: -100XXXXXXXXXX or -XXXXXXXXXX" -ForegroundColor Yellow
            $ChannelUrl = $null
        }
    } while (-not $ChannelUrl)
    
    # Convert to proper format for chat export
    if ($ChannelUrl -match '^\d+$') {
        # If user entered positive ID, make it negative
        $ChannelUrl = "-$ChannelUrl"
    }
}

if (-not $DownloadDir) {
    Write-Host "📁 Download Directory" -ForegroundColor Yellow
    Write-Host "  Default: C:\tdl_temp" -ForegroundColor Gray
    Write-Host ""
    $customDir = Read-Host "Enter download directory (press Enter for default)"
    
    if ([string]::IsNullOrWhiteSpace($customDir)) {
        $DownloadDir = "C:\tdl_temp"
    } else {
        $DownloadDir = $customDir.Trim()
    }
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
Write-Host "Method: Export chat → Download files → Upload to GDrive" -ForegroundColor White
Write-Host ""

# Start download in background job using chat export + download
Write-Host "📥 Starting channel download..." -ForegroundColor Yellow
$downloadJob = Start-Job -ScriptBlock {
    param($exe, $chat, $dir)
    $exe = $exe.Replace('\\', '\\\\')
    $dir = $dir.Replace('\\', '\\\\')
    
    # Step 1: Export chat to JSON (last 10000 messages - should cover most channels)
    $exportFile = "$dir\export.json"
    Write-Output "Step 1: Exporting chat metadata (last 10000 messages)..."
    & $exe chat export -c $chat -o $exportFile -T last -i 10000 -l 4 2>&1
    
    if ($LASTEXITCODE -eq 0 -and (Test-Path $exportFile)) {
        # Step 2: Download files from export
        Write-Output "Step 2: Downloading files from export..."
        & $exe dl -f $exportFile -d $dir --continue -l 4 2>&1
    } else {
        Write-Output "Export failed or no messages found"
    }
} -ArgumentList "$DownloadDir\tdl.exe", $ChannelUrl, $DownloadDir

Write-Host "✅ Download started in background (Job ID: $($downloadJob.Id))" -ForegroundColor Green
Write-Host "⏳ Waiting for first files..." -ForegroundColor Yellow
Start-Sleep -Seconds 5  # Give download time to start
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
    
    # Get files ready for upload (exclude tdl.exe, temp files, and export.json)
    $files = Get-ChildItem $DownloadDir -File -ErrorAction SilentlyContinue | 
             Where-Object { 
                 $_.Name -ne "tdl.exe" -and 
                 $_.Name -ne "export.json" -and
                 $_.Extension -ne ".tmp" -and 
                 $_.Extension -ne ".part" -and
                 -not $_.Name.EndsWith('.downloading') -and
                 $_.Length -gt 100KB  # Lower threshold for faster detection
             }
    
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
    
    # Show download job output if available
    $jobOutput = Receive-Job -Id $downloadJob.Id -Keep -ErrorAction SilentlyContinue
    if ($jobOutput) {
        $jobOutput | Select-Object -Last 3 | ForEach-Object {
            Write-Host "  [Download] $_" -ForegroundColor DarkGray
        }
    }
    
    # Exit conditions
    if ($jobState -eq 'Completed' -and $files.Count -eq 0) {
        Write-Host ""
        Write-Host "✅ Download complete and all files uploaded!" -ForegroundColor Green
        
        # Show final job output
        Write-Host ""
        Write-Host "📝 Download Job Output:" -ForegroundColor Cyan
        Receive-Job -Id $downloadJob.Id | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        break
    }
    
    if ($jobState -eq 'Failed') {
        Write-Host ""
        Write-Host "❌ Download job failed!" -ForegroundColor Red
        Write-Host "📝 Error Output:" -ForegroundColor Yellow
        Receive-Job -Id $downloadJob.Id | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
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
