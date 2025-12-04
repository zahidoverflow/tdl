# TDL Smart Backup - Telegram to Google Drive
# Execute with: irm https://zahidoverflow.github.io/tdl | iex

param(
    [string]$ChannelUrl,
    [string]$DownloadDir = "$env:TEMP\tdl_downloads",
    [int]$MaxSizeGB = 45
)

Write-Host @"
╔═══════════════════════════════════════════════╗
║  TDL Smart Backup - Telegram → Google Drive  ║
║  Auto-upload | Auto-delete | Disk limit 50GB ║
╚═══════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

# Prompt for channel URL if not provided
if (-not $ChannelUrl) {
    $ChannelUrl = Read-Host "`nEnter Telegram channel URL (e.g., https://t.me/yourchannel)"
}

Write-Host "`n📋 Configuration:" -ForegroundColor Yellow
Write-Host "   Channel: $ChannelUrl"
Write-Host "   Download: $DownloadDir"
Write-Host "   Max disk: ${MaxSizeGB}GB`n"

# Check if tdl.exe exists
if (-not (Get-Command tdl.exe -ErrorAction SilentlyContinue)) {
    Write-Host "⚠️  tdl.exe not found. Installing..." -ForegroundColor Yellow
    
    # Download latest tdl
    $latest = (Invoke-RestMethod https://api.github.com/repos/iyear/tdl/releases/latest).tag_name
    $url = "https://github.com/iyear/tdl/releases/download/$latest/tdl_Windows_64bit.zip"
    
    Write-Host "   Downloading from: $url"
    Invoke-WebRequest -Uri $url -OutFile "$env:TEMP\tdl.zip"
    Expand-Archive "$env:TEMP\tdl.zip" -DestinationPath "$env:TEMP\tdl" -Force
    
    # Add to PATH for this session
    $env:PATH = "$env:TEMP\tdl;$env:PATH"
    
    Write-Host "   ✅ tdl.exe installed`n" -ForegroundColor Green
}

# Create download directory
New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null

# Helper function to get directory size in GB
function Get-DirSizeGB {
    param([string]$Path)
    if (Test-Path $Path) {
        $size = (Get-ChildItem $Path -Recurse -File -ErrorAction SilentlyContinue | 
                 Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($size) { return [math]::Round($size / 1GB, 2) }
    }
    return 0
}

# Helper function to upload and delete files
function Upload-AndClean {
    $files = Get-ChildItem $DownloadDir -File -ErrorAction SilentlyContinue
    $uploaded = 0
    
    foreach ($file in $files) {
        # Skip files smaller than 1MB (likely still downloading)
        if ($file.Length -lt 1MB) { continue }
        
        $sizeMB = [math]::Round($file.Length / 1MB, 1)
        Write-Host "  📤 $($file.Name) (${sizeMB}MB)" -ForegroundColor Cyan
        
        # Upload to Google Drive with auto-delete
        $output = & tdl.exe up --gdrive --rm -p $file.FullName 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $uploaded++
            Write-Host "     ✅ Uploaded & deleted" -ForegroundColor Green
        } else {
            Write-Host "     ❌ Failed: $output" -ForegroundColor Red
            # Delete failed upload file to free space
            Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
        }
        
        Start-Sleep -Seconds 2  # Prevent rate limiting
    }
    
    return $uploaded
}

Write-Host "🚀 Starting backup process...`n" -ForegroundColor Green

# Start download in background
$downloadJob = Start-Job -ScriptBlock {
    param($url, $dir, $tdlPath)
    $env:PATH = $tdlPath
    Set-Location $using:PWD
    & tdl.exe dl -u $url -d $dir --continue
} -ArgumentList $ChannelUrl, $DownloadDir, $env:PATH

Write-Host "📥 Download started in background (Job ID: $($downloadJob.Id))`n" -ForegroundColor Yellow

# Monitor and upload loop
$totalUploaded = 0
$lastCheck = Get-Date

while ($downloadJob.State -eq 'Running' -or (Get-DirSizeGB $DownloadDir) -gt 0.1) {
    Start-Sleep -Seconds 10
    
    $currentSize = Get-DirSizeGB $DownloadDir
    $elapsed = [math]::Round(((Get-Date) - $lastCheck).TotalSeconds, 0)
    
    # Show status every 30 seconds
    if ($elapsed -ge 30) {
        Write-Host "💾 Disk: ${currentSize}GB / ${MaxSizeGB}GB | Uploaded: $totalUploaded files" -ForegroundColor Gray
        $lastCheck = Get-Date
    }
    
    # Upload when disk usage exceeds threshold OR download is complete
    if ($currentSize -ge $MaxSizeGB -or ($downloadJob.State -ne 'Running' -and $currentSize -gt 0)) {
        if ($currentSize -ge $MaxSizeGB) {
            Write-Host "`n⚠️  Disk limit reached: ${currentSize}GB / ${MaxSizeGB}GB" -ForegroundColor Yellow
        } else {
            Write-Host "`n📤 Download complete, uploading remaining files..." -ForegroundColor Green
        }
        
        $uploaded = Upload-AndClean
        $totalUploaded += $uploaded
        
        Write-Host "`n✅ Batch complete: $uploaded files uploaded | Total: $totalUploaded`n" -ForegroundColor Green
    }
}

# Final cleanup
Write-Host "`n🎉 Backup complete!" -ForegroundColor Green
Write-Host "   Total files uploaded: $totalUploaded"
Write-Host "   Download job status: $($downloadJob.State)`n"

# Clean up
Remove-Job $downloadJob -Force -ErrorAction SilentlyContinue
if ((Get-DirSizeGB $DownloadDir) -eq 0) {
    Remove-Item $DownloadDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
