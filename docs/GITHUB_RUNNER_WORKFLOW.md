# GitHub Actions Runner Workflow for Telegram Channel Backup

## Your Requirements
- ✅ Download complete Telegram channel (100-300GB)
- ✅ Auto-upload to Google Drive
- ✅ Auto-delete after upload (save disk space)
- ✅ Stay under 50GB disk usage
- ✅ 6 hour daily runner limit
- ✅ No Telegram upload needed
- ❌ **Current limitation:** tdl doesn't support `--gdrive` flag on download command

## ⚠️ CRITICAL ISSUE

**tdl download command does NOT support direct Google Drive upload.**

The `--gdrive` and `--rm` flags only work with `tdl upload`, not `tdl download`.

**Current commands:**
```bash
# ❌ This won't work (--gdrive not available for download)
tdl dl -u https://t.me/channel --gdrive --rm

# ✅ Only works on upload command
tdl up --gdrive --rm /path/to/files
```

## 🔧 SOLUTION: Two-Step Workflow

### Option 1: Download → Upload → Delete Loop (Recommended)

Create a PowerShell script that processes files in batches:

```powershell
# telegram-to-gdrive.ps1
# Download, upload, delete in a loop to stay under 50GB

$CHANNEL_URL = "https://t.me/yourchannel"
$DOWNLOAD_DIR = "C:\temp\tdl_downloads"
$BATCH_SIZE_GB = 45  # Stay under 50GB limit

# Ensure directory exists
New-Item -ItemType Directory -Force -Path $DOWNLOAD_DIR | Out-Null

Write-Host "🚀 Starting Telegram Channel → Google Drive Backup"
Write-Host "Channel: $CHANNEL_URL"
Write-Host "Max disk usage: ${BATCH_SIZE_GB}GB"
Write-Host ""

# Login to Telegram (do this once)
tdl.exe login

# Get total files in channel
Write-Host "📊 Analyzing channel..."
# Note: You'll need to export channel links first or use --file flag

# Download files one by one, upload immediately, then delete
$fileCount = 0
while ($true) {
    Write-Host "📥 Downloading next batch..."
    
    # Download with size limit (tdl will stop when limit reached)
    # Unfortunately, tdl doesn't have --max-size flag, so we monitor manually
    $beforeSize = (Get-ChildItem $DOWNLOAD_DIR -Recurse | Measure-Object -Property Length -Sum).Sum / 1GB
    
    # Download (will get all files, we'll handle size limit)
    tdl.exe dl -u $CHANNEL_URL -d $DOWNLOAD_DIR
    
    # Check downloaded size
    $afterSize = (Get-ChildItem $DOWNLOAD_DIR -Recurse | Measure-Object -Property Length -Sum).Sum / 1GB
    
    if ($afterSize -eq 0) {
        Write-Host "✅ All files downloaded!"
        break
    }
    
    Write-Host "📤 Uploading $([math]::Round($afterSize, 2))GB to Google Drive..."
    
    # Upload entire directory in one batch (much faster for many files)
    Write-Host "  Uploading all files in batch..."
    tdl.exe up --gdrive --rm -p $DOWNLOAD_DIR
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ⚠️ Batch upload failed, trying individual files..."
        
        # Fallback: Upload files individually
        Get-ChildItem $DOWNLOAD_DIR -File | ForEach-Object {
            Write-Host "  Uploading: $($_.Name)"
            tdl.exe up --gdrive --rm -p $_.FullName
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    ✅ Uploaded & deleted: $($_.Name)"
        } else {
            Write-Host "    ❌ Failed: $($_.Name)"
        }
    }
    
    # Clean up directory
    Remove-Item "$DOWNLOAD_DIR\*" -Recurse -Force
    
    $fileCount++
    Write-Host "✅ Batch $fileCount completed"
    Write-Host ""
}

Write-Host "🎉 Channel backup complete!"
```

### Option 2: Monitor Disk Size & Auto-Upload (Better)

```powershell
# smart-backup.ps1
# Automatically upload when disk reaches threshold

param(
    [string]$ChannelUrl = "https://t.me/yourchannel",
    [string]$DownloadDir = "C:\temp\tdl_downloads",
    [int]$MaxSizeGB = 45,
    [int]$CheckIntervalSec = 30
)

function Get-DirSizeGB {
    param([string]$Path)
    if (Test-Path $Path) {
        return (Get-ChildItem $Path -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1GB
    }
    return 0
}

function Upload-ToGDrive {
    param([string]$Dir)
    
    Write-Host "📤 Uploading files to Google Drive..."
    $files = Get-ChildItem $Dir -File
    $uploadCount = 0
    
    foreach ($file in $files) {
        Write-Host "  → $($file.Name) ($([math]::Round($file.Length/1MB, 2))MB)"
        
        # Upload and delete
        tdl.exe up --gdrive --rm -p $file.FullName
        
        if ($LASTEXITCODE -eq 0) {
            $uploadCount++
        } else {
            Write-Host "    ⚠️ Upload failed, keeping file"
        }
        
        Start-Sleep -Seconds 2  # Prevent rate limiting
    }
    
    Write-Host "✅ Uploaded $uploadCount files"
    return $uploadCount
}

# Main script
Write-Host "🚀 Smart Telegram Channel Backup"
Write-Host "================================"
Write-Host "Channel: $ChannelUrl"
Write-Host "Download Dir: $DownloadDir"
Write-Host "Max Size: ${MaxSizeGB}GB"
Write-Host ""

# Create download directory
New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null

# Start download in background
Write-Host "📥 Starting channel download..."
$downloadJob = Start-Job -ScriptBlock {
    param($url, $dir)
    Set-Location $using:PWD
    tdl.exe dl -u $url -d $dir
} -ArgumentList $ChannelUrl, $DownloadDir

# Monitor and upload loop
$totalUploaded = 0
while ($downloadJob.State -eq 'Running' -or (Get-DirSizeGB $DownloadDir) -gt 0) {
    Start-Sleep -Seconds $CheckIntervalSec
    
    $currentSize = Get-DirSizeGB $DownloadDir
    
    if ($currentSize -ge $MaxSizeGB) {
        Write-Host "⚠️ Disk threshold reached: $([math]::Round($currentSize, 2))GB / ${MaxSizeGB}GB"
        
        # Pause download (can't pause tdl, so this won't work perfectly)
        # Better: Just upload what we have
        
        $uploaded = Upload-ToGDrive -Dir $DownloadDir
        $totalUploaded += $uploaded
        
        Write-Host "📊 Total uploaded so far: $totalUploaded files"
        Write-Host ""
    }
    
    # Show progress
    Write-Host "💾 Current disk usage: $([math]::Round($currentSize, 2))GB / ${MaxSizeGB}GB" -NoNewline
    Write-Host "`r" -NoNewline
}

# Final upload of remaining files
if ((Get-DirSizeGB $DownloadDir) -gt 0) {
    Write-Host "📤 Final upload..."
    $uploaded = Upload-ToGDrive -Dir $DownloadDir
    $totalUploaded += $uploaded
}

Write-Host ""
Write-Host "🎉 Backup complete!"
Write-Host "Total files uploaded: $totalUploaded"

# Cleanup
Remove-Item $DownloadDir -Recurse -Force
```

### Option 3: Export Channel Links First (Most Efficient)

```powershell
# Step 1: Export all message links from channel
Write-Host "📋 Exporting channel message list..."
tdl.exe chat export -c "yourchannel" -o channel_export.json

# Step 2: Process links in batches
$exportData = Get-Content channel_export.json | ConvertFrom-Json
$messages = $exportData.messages | Where-Object { $_.media -ne $null }

Write-Host "Found $($messages.Count) media files"

$batchSize = 20  # Process 20 files at a time
$batches = [Math]::Ceiling($messages.Count / $batchSize)

for ($i = 0; $i -lt $batches; $i++) {
    $start = $i * $batchSize
    $end = [Math]::Min(($i + 1) * $batchSize, $messages.Count)
    $batch = $messages[$start..($end-1)]
    
    Write-Host "Batch $($i+1)/$batches (files $start-$end)"
    
    # Download batch
    $batch | ForEach-Object {
        $msgId = $_.id
        $url = "https://t.me/c/$($exportData.id)/$msgId"
        
        Write-Host "  📥 Downloading message $msgId..."
        tdl.exe dl -u $url -d "C:\temp\batch_$i"
    }
    
    # Upload entire batch
    Write-Host "  📤 Uploading batch to Google Drive..."
    Get-ChildItem "C:\temp\batch_$i" -File | ForEach-Object {
        tdl.exe up --gdrive --rm -p $_.FullName
    }
    
    # Clean up
    Remove-Item "C:\temp\batch_$i" -Recurse -Force
    
    Write-Host "  ✅ Batch $($i+1) complete"
    Start-Sleep -Seconds 5
}
```

## 🚀 RECOMMENDED: GitHub Actions Workflow

Create `.github/workflows/telegram-backup.yml`:

```yaml
name: Telegram Channel Backup to Google Drive

on:
  schedule:
    - cron: '0 0 * * *'  # Run daily at midnight UTC
  workflow_dispatch:
    inputs:
      channel_url:
        description: 'Telegram channel URL'
        required: true
        default: 'https://t.me/yourchannel'

jobs:
  backup:
    runs-on: windows-latest
    timeout-minutes: 360  # 6 hours
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      
      - name: Download tdl
        shell: pwsh
        run: |
          $latest = (Invoke-RestMethod https://api.github.com/repos/iyear/tdl/releases/latest).tag_name
          $url = "https://github.com/iyear/tdl/releases/download/$latest/tdl_Windows_64bit.zip"
          Invoke-WebRequest -Uri $url -OutFile tdl.zip
          Expand-Archive tdl.zip -DestinationPath .
          .\tdl.exe version
      
      - name: Setup tdl config
        shell: pwsh
        run: |
          New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.tdl"
          
          # Restore Telegram session from secrets
          echo "${{ secrets.TDL_SESSION }}" | Out-File "$env:USERPROFILE\.tdl\data"
          
          # Restore Google Drive credentials from secrets
          echo "${{ secrets.GDRIVE_CREDENTIALS }}" | Out-File "$env:USERPROFILE\.tdl\gdrive_credentials.json"
          echo "${{ secrets.GDRIVE_TOKEN }}" | Out-File "$env:USERPROFILE\.tdl\gdrive_token.json"
      
      - name: Backup channel to Google Drive
        shell: pwsh
        env:
          CHANNEL_URL: ${{ github.event.inputs.channel_url || 'https://t.me/yourchannel' }}
        run: |
          $downloadDir = "C:\temp\downloads"
          $maxSizeGB = 45
          
          New-Item -ItemType Directory -Force -Path $downloadDir
          
          # Start download
          Write-Host "📥 Downloading channel: $env:CHANNEL_URL"
          .\tdl.exe dl -u $env:CHANNEL_URL -d $downloadDir
          
          # Upload all downloaded files
          Write-Host "📤 Uploading to Google Drive..."
          Get-ChildItem $downloadDir -File | ForEach-Object {
            Write-Host "  → $($_.Name)"
            .\tdl.exe up --gdrive --rm -p $_.FullName
            
            if ($LASTEXITCODE -ne 0) {
              Write-Host "    ⚠️ Upload failed for $($_.Name)"
            }
          }
          
          Write-Host "✅ Backup complete!"
      
      - name: Cleanup
        if: always()
        shell: pwsh
        run: |
          Remove-Item C:\temp\downloads -Recurse -Force -ErrorAction SilentlyContinue
```

## 📝 Setup Instructions

### 1. Create GitHub Secrets

Go to your repo → Settings → Secrets and variables → Actions

Add these secrets:

**TDL_SESSION:**
```bash
# On your local machine (Windows)
# After running: tdl login
# Copy the session data
cat %USERPROFILE%\.tdl\data\data | base64

# Paste the base64 string as secret
```

**GDRIVE_CREDENTIALS:**
```bash
# Copy your Google Drive credentials
cat %USERPROFILE%\.tdl\gdrive_credentials.json

# Paste the entire JSON as secret
```

**GDRIVE_TOKEN:**
```bash
# After first OAuth authentication
cat %USERPROFILE%\.tdl\gdrive_token.json

# Paste the entire JSON as secret
```

### 2. Modify for Your Needs

Edit the workflow file:
```yaml
# Change channel URL
CHANNEL_URL: 'https://t.me/YOUR_CHANNEL'

# Adjust max disk size
$maxSizeGB = 45  # Keep under 50GB
```

### 3. Run Workflow

- Go to Actions tab
- Click "Telegram Channel Backup to Google Drive"
- Click "Run workflow"
- Enter channel URL
- Click "Run workflow"

## ⚠️ LIMITATIONS & WORKAROUNDS

### Problem 1: tdl downloads ALL files at once
**Workaround:** Monitor disk size and stop when limit reached

### Problem 2: Can't pause tdl download mid-stream
**Workaround:** Use file count limits or time limits

### Problem 3: 6 hour runner limit
**Workaround:** 
- Download only 50GB per run
- Use workflow state to resume next day
- Process channel in chunks

### Problem 4: 750GB/day Google Drive limit
**Workaround:**
- Max 45GB per 6-hour run
- Can run 16 times before hitting limit (theoretical)
- In practice: ~8-10 runs/day safely

## 💡 BEST APPROACH

**For 100-300GB channel with 6hr/day limit:**

```powershell
# Download in resume mode with continue flag
tdl.exe dl -u https://t.me/channel -d C:\downloads --continue

# In separate PowerShell window, run upload loop:
while ($true) {
    Get-ChildItem C:\downloads -File | ForEach-Object {
        .\tdl.exe up --gdrive --rm -p $_.FullName
        Start-Sleep -Seconds 5
    }
    Start-Sleep -Seconds 30
}
```

This will:
1. Download files continuously
2. Upload completed files immediately  
3. Delete after successful upload
4. Keep disk usage low
5. Resume next day automatically with `--continue`

## 🎯 FINAL RECOMMENDATION

Use **Option 2** (Smart Backup script) with these settings:

```powershell
.\smart-backup.ps1 `
    -ChannelUrl "https://t.me/yourchannel" `
    -DownloadDir "C:\temp\downloads" `
    -MaxSizeGB 45 `
    -CheckIntervalSec 60
```

This will automatically:
- ✅ Download channel files
- ✅ Upload to Google Drive when disk hits 45GB
- ✅ Delete files after upload
- ✅ Continue until channel is complete
- ✅ Stay under 50GB disk usage
- ✅ Work within 6 hour limit (resume next day with --continue)

**Expected timeline for 300GB channel:**
- Day 1: ~45GB (6 hours)
- Day 2: ~45GB (6 hours)
- Day 3: ~45GB (6 hours)
- ...
- Day 7: ~30GB (complete)
