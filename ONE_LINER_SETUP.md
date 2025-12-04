# TDL One-Liner Setup Guide

## ✅ Done! You can now run:

```powershell
irm https://zahidoverflow.github.io/tdl/install.ps1 | iex
```

## 📋 Setup Steps

### 1. Enable GitHub Pages (One-time setup)

1. Go to your repo: https://github.com/zahidoverflow/tdl
2. Click **Settings** → **Pages** (left sidebar)
3. Under "Source", select **Deploy from a branch**
4. Under "Branch", select **master** and **/docs**
5. Click **Save**
6. Wait 1-2 minutes for deployment

### 2. Verify GitHub Pages is live

Visit: https://zahidoverflow.github.io/tdl/

You should see the TDL Smart Backup page.

### 3. Test the one-liner

On Windows PowerShell (as Admin):

```powershell
irm https://zahidoverflow.github.io/tdl/install.ps1 | iex
```

The script will:
- ✅ Auto-download tdl.exe if not found
- ✅ Prompt for channel URL
- ✅ Start downloading in background
- ✅ Monitor disk usage (45GB limit)
- ✅ Auto-upload to Google Drive
- ✅ Auto-delete after upload
- ✅ Continue until complete

## 🚀 GitHub Actions Setup

Create `.github/workflows/backup.yml`:

```yaml
name: Telegram Channel Backup

on:
  schedule:
    - cron: '0 0 * * *'  # Daily at midnight
  workflow_dispatch:
    inputs:
      channel_url:
        description: 'Channel URL'
        required: true

jobs:
  backup:
    runs-on: windows-latest
    timeout-minutes: 360
    
    steps:
      - name: Setup credentials
        shell: pwsh
        run: |
          New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.tdl"
          
          # Restore session (base64 encoded)
          [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${{ secrets.TDL_SESSION }}")) | 
            Out-File "$env:USERPROFILE\.tdl\data" -Encoding utf8
          
          # Restore Google Drive credentials
          "${{ secrets.GDRIVE_CREDENTIALS }}" | Out-File "$env:USERPROFILE\.tdl\gdrive_credentials.json"
          "${{ secrets.GDRIVE_TOKEN }}" | Out-File "$env:USERPROFILE\.tdl\gdrive_token.json"
      
      - name: Run backup
        shell: pwsh
        run: |
          $channel = "${{ github.event.inputs.channel_url || secrets.CHANNEL_URL }}"
          irm https://zahidoverflow.github.io/tdl/install.ps1 -OutFile backup.ps1
          .\backup.ps1 -ChannelUrl $channel -MaxSizeGB 45
```

### Create GitHub Secrets

Go to repo **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

**TDL_SESSION:**
```powershell
# On your local machine after: tdl login
$data = Get-Content "$env:USERPROFILE\.tdl\data\data" -Raw
[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($data))
# Copy output and paste as secret
```

**GDRIVE_CREDENTIALS:**
```powershell
Get-Content "$env:USERPROFILE\.tdl\gdrive_credentials.json" -Raw
# Paste the entire JSON
```

**GDRIVE_TOKEN:**
```powershell
Get-Content "$env:USERPROFILE\.tdl\gdrive_token.json" -Raw
# Paste the entire JSON
```

**CHANNEL_URL:**
```
https://t.me/yourchannel
```

## 📊 What Happens

```
1. RDP/Runner starts
2. Execute: irm https://zahidoverflow.github.io/tdl/install.ps1 | iex
3. Script downloads tdl.exe (if needed)
4. Prompts for channel URL (or uses parameter)
5. Starts download in background job
6. Monitors disk usage every 10 seconds
7. When disk hits 45GB:
   - Upload all files to Google Drive
   - Delete after successful upload
   - Continue downloading
8. Repeat until channel complete
9. Exit gracefully
```

## 💾 Disk Usage Pattern

```
0GB  ────────────────────────────────────────────────
     ↓ Download starts
15GB ██████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     ↓ Downloading...
30GB ████████████████████░░░░░░░░░░░░░░░░░░░░░░
     ↓ Still downloading...
45GB ██████████████████████████████░░░░░░░░░░░░
     ↑ LIMIT HIT - Start upload
     ↓ Uploading + deleting...
10GB ██████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     ↓ Space freed, resume download
     ↓ Cycle repeats...
```

## 🎯 Timeline for 300GB Channel

With GitHub Actions (6hr/day limit):

- **Day 1:** 45GB downloaded & uploaded ✅
- **Day 2:** 45GB (resume with --continue) ✅
- **Day 3:** 45GB ✅
- **Day 4:** 45GB ✅
- **Day 5:** 45GB ✅
- **Day 6:** 45GB ✅
- **Day 7:** 30GB ✅ **COMPLETE**

## ⚡ Advanced Usage

### Run with parameters
```powershell
irm https://zahidoverflow.github.io/tdl/install.ps1 -OutFile backup.ps1
.\backup.ps1 -ChannelUrl "https://t.me/channel" -DownloadDir "D:\temp" -MaxSizeGB 40
```

### Check job status
```powershell
Get-Job
Receive-Job -Id 1 -Keep  # See download progress
```

### Stop gracefully
```powershell
Stop-Job -Id 1
Remove-Job -Id 1
```

## 🔥 Emergency Commands

### Kill everything
```powershell
Get-Job | Stop-Job
Get-Job | Remove-Job
Stop-Process -Name tdl -Force
```

### Clean up disk
```powershell
Remove-Item "$env:TEMP\tdl_downloads" -Recurse -Force
```

### Check Google Drive quota
Visit: https://console.cloud.google.com/iam-admin/quotas

Filter by "Drive API" to see usage.

## 🎉 That's It!

Your one-liner is ready:
```powershell
irm https://zahidoverflow.github.io/tdl/install.ps1 | iex
```

Works on:
- ✅ Local Windows machine
- ✅ RDP sessions
- ✅ GitHub Actions Windows runners
- ✅ Any Windows environment with PowerShell

No compilation, no installation, just execute and go! 🚀
