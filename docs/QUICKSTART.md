# TDL - One-Liner Telegram to Google Drive Backup

## Quick Start (GitHub Actions RDP)

**Just run this in PowerShell:**

```powershell
irm https://zahidoverflow.github.io/tdl | iex
```

That's it! The script will:
1. ✅ Download latest `tdl.exe`
2. ✅ Prompt for Telegram channel URL
3. ✅ Auto-login to Telegram (first time)
4. ✅ Download files from channel
5. ✅ Upload to Google Drive automatically
6. ✅ Delete files after upload (stays under 50GB)
7. ✅ Resume automatically if interrupted

## First Time Setup

### 1. Setup Google Drive (5 minutes - one time only)

Before running the script, you need Google Drive credentials:

**Quick Setup:**
1. Go to: https://console.cloud.google.com/projectcreate
2. Create project, enable Drive API: https://console.cloud.google.com/apis/library/drive.googleapis.com
3. Create OAuth credentials (Desktop app): https://console.cloud.google.com/apis/credentials
4. Download JSON and save to: `C:\Users\YourName\.tdl\gdrive_credentials.json`

**Detailed guide:** See main [README.md](../README.md#new-features)

### 2. Run the Script

Open PowerShell in your RDP and run:

```powershell
irm https://zahidoverflow.github.io/tdl | iex
```

Enter your channel URL when prompted (e.g., `https://t.me/yourchannel`)

### 3. First Time Authentication

- **Telegram:** Login with phone number (one time)
- **Google Drive:** Browser will open for OAuth (one time)

After first run, credentials are saved. Next time just run the one-liner and it works instantly!

## Advanced Usage

### Custom Parameters

```powershell
# Download script and run with parameters
$script = irm https://zahidoverflow.github.io/tdl
Invoke-Expression "$script -ChannelUrl 'https://t.me/yourchannel' -MaxDiskGB 40 -DownloadDir 'D:\backup'"
```

**Parameters:**
- `-ChannelUrl`: Telegram channel URL
- `-DownloadDir`: Where to download files (default: `C:\tdl_temp`)
- `-MaxDiskGB`: Max disk usage in GB (default: 45)

### For GitHub Actions Runner

Add this to your workflow:

```yaml
- name: Backup Telegram to Google Drive
  shell: pwsh
  run: |
    # Restore credentials from secrets
    New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.tdl\data"
    [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("${{ secrets.TDL_SESSION }}")) | Out-File "$env:USERPROFILE\.tdl\data\data"
    ${{ secrets.GDRIVE_CREDENTIALS }} | Out-File "$env:USERPROFILE\.tdl\gdrive_credentials.json"
    ${{ secrets.GDRIVE_TOKEN }} | Out-File "$env:USERPROFILE\.tdl\gdrive_token.json"
    
    # Run backup
    irm https://zahidoverflow.github.io/tdl | iex -ChannelUrl 'https://t.me/yourchannel'
```

## How It Works

```
1. Download tdl.exe from latest release
2. Start background download job (continues downloading)
3. Monitor download folder every 10 seconds
4. Upload completed files to Google Drive
5. Delete files after successful upload
6. Repeat until channel is fully backed up
```

**Features:**
- ⚡ Concurrent download + upload (max efficiency)
- 💾 Stays under disk limit (pauses if exceeded)
- 🔄 Auto-resume with `--continue` flag
- 🚫 Auto-delete after upload
- 📊 Real-time progress updates
- ⏱️ Perfect for 6-hour GitHub runner limits

## Disk Usage

The script keeps disk usage under your limit (default 45GB):
- Downloads run in background
- Uploads happen as files complete
- Files deleted immediately after upload
- If disk fills, upload loop clears space automatically

**For 300GB channel:**
- Day 1: ~45GB (6 hours)
- Day 2: ~45GB (resume from where it stopped)
- Day 3: ~45GB
- ...continues until complete

## Troubleshooting

### "Cannot download tdl.exe"
- Check internet connection
- GitHub may be rate limiting, wait a few minutes

### "Google Drive credentials not found"
- Make sure `C:\Users\YourName\.tdl\gdrive_credentials.json` exists
- Follow setup guide above

### "Rate limit exceeded"
- Script automatically adds 2-second delays
- If persistent, increase delay in script

### "Disk full"
- Script monitors and pauses downloads automatically
- Check if uploads are working (need valid GDrive credentials)

## Security

- ✅ Credentials stored in `%USERPROFILE%\.tdl\` (user-only access)
- ✅ OAuth tokens encrypted by Google
- ✅ Telegram sessions use official protocol
- ✅ No data sent to third parties

**For RDP:** Since RDP is ephemeral, credentials are lost after session. Either:
1. Use GitHub Secrets to restore credentials (recommended for automation)
2. Re-authenticate each session (manual use)

## FAQ

**Q: Will my Google account get banned?**  
A: No. Google enforces 750GB/day quota but doesn't ban accounts. Script respects limits.

**Q: What if GitHub runner stops at 6 hours?**  
A: Next run automatically continues with `--continue` flag. No data loss.

**Q: Can I use this locally (not in GitHub Actions)?**  
A: Yes! Works on any Windows machine with PowerShell.

**Q: Does it work with private channels?**  
A: Yes, if you have access with your Telegram account.

## Links

- **Main Repo:** https://github.com/zahidoverflow/tdl
- **Original Project:** https://github.com/iyear/tdl
- **Google Drive Setup:** [README.md](../README.md#new-features)
- **Security Guide:** [docs/SECURITY.md](SECURITY.md)
- **GDrive Limits:** [docs/GDRIVE_LIMITS.md](GDRIVE_LIMITS.md)
