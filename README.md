# tdl

<img align="right" src="docs/assets/img/logo.png" height="280" alt="">

> Telegram Downloader, but more than a downloader

English | <a href="docs/README_zh.md">中文</a>

<p>
<img src="https://img.shields.io/github/go-mod/go-version/zahidoverflow/tdl?style=flat-square" alt="">
<img src="https://img.shields.io/github/license/zahidoverflow/tdl?style=flat-square" alt="">
<img src="https://img.shields.io/github/actions/workflow/status/zahidoverflow/tdl/master.yml?branch=master&amp;style=flat-square" alt="">
<img src="https://img.shields.io/github/v/release/zahidoverflow/tdl?color=red&amp;style=flat-square" alt="">
<img src="https://img.shields.io/github/downloads/zahidoverflow/tdl/total?style=flat-square" alt="">
</p>

#### Features
- Single file start-up
- Low resource usage
- Take up all your bandwidth
- Faster than official clients
- Download files from (protected) chats
- Forward messages with automatic fallback and message routing
- Upload files to Telegram **and Google Drive**
- Auto-delete local files after upload (`--rm`)
- Export messages/members/subscribers to JSON

## Preview

It reaches my proxy's speed limit, and the **speed depends on whether you are a premium**

![](docs/assets/img/preview.gif)

## Quick Start

### One-Liner Install (Windows PowerShell)

Run in PowerShell 5+ (or PowerShell 7+):

```powershell
irm https://zahidoverflow.github.io/tdl | iex
```

If you're in Command Prompt (`cmd.exe`):

```bat
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://zahidoverflow.github.io/tdl | iex"
```

Notes:
- `tdl.exe` is downloaded into the current directory (where you run the command).
- Downloaded media is saved under `./tdl-downloads/` (so running from `Downloads` won’t upload/delete unrelated files).
- Config + credentials live in `~/.tdl/`:
  - `~/.tdl/gdrive_credentials.json`
  - `~/.tdl/gdrive_token.json` (auto-created after first auth)
- Google Drive uploads are placed in a date folder (e.g. `2025-12-15`) at Drive root.

Need to reset GitHub Pages source? See [GITHUB_PAGES_SETUP.md](GITHUB_PAGES_SETUP.md).

**[Full Quickstart Guide](docs/QUICKSTART.md)**

### Using Docker (Recommended)

Pull the latest image:
```bash
docker pull ghcr.io/zahidoverflow/tdl:latest
```

Login to Telegram:
```bash
docker run -it -v ~/.tdl:/root/.tdl ghcr.io/zahidoverflow/tdl:latest login
```

Upload a file:
```bash
docker run -it -v ~/.tdl:/root/.tdl -v /path/to/files:/files ghcr.io/zahidoverflow/tdl:latest upload -p /files/yourfile.txt
```

### Building from Source

```bash
git clone https://github.com/zahidoverflow/tdl.git
cd tdl
docker build -t tdl .
```

## Development & Tests

- Go 1.22+ is required (the Dockerfile now uses `golang:1.22-alpine`).
- Fast checks: `go test ./... ./core/... ./extension/...` (integration suite is skipped by default).
- Integration upload/download/chat tests are opt-in: start the Telegram test server expected at `127.0.0.1:10443` (see `test/testserver/`) and run `TDL_INTEGRATION=1 go test ./test -run TestCommand -timeout 5m`.
- Manual end-to-end: `tdl login`, upload with `tdl upload -p <dir> --gdrive --rm`, and download a message link with `tdl download -u <t.me/...> -d <dir> --template "{{ .FileName }}"`.

## New Features

### 🆕 Google Drive Upload

Upload files to Google Drive after uploading to Telegram.

#### Setup (5 minutes)

1. **Create Google Cloud Project & Enable Drive API:**
   - Visit [Google Cloud Console - New Project](https://console.cloud.google.com/projectcreate)
   - Enter project name and click "Create"
   - Go to [Enable Google Drive API](https://console.cloud.google.com/apis/library/drive.googleapis.com)
   - Click "Enable" button

2. **Configure OAuth Consent Screen:**
   - Go to [OAuth Consent Screen](https://console.cloud.google.com/apis/credentials/consent)
   - Select "External" user type → Click "Create"
   - Fill in:
     - App name: `tdl` (or any name)
     - User support email: your email
     - Developer contact: your email
   - Click "Save and Continue" → Skip scopes → Click "Save and Continue"
   - **Add Test Users:** Click "ADD USERS" → Enter your Google email → Click "Save"
   - Click "Save and Continue" → "Back to Dashboard"

3. **Create OAuth2 Credentials:**
   - Go to [Credentials Page](https://console.cloud.google.com/apis/credentials)
   - Click "Create Credentials" → "OAuth client ID"
   - Application type: **"Desktop app"**
   - Name: `tdl-client` (or any name)
   - Click "Create" → Click "Download JSON"

4. **Configure tdl:**
   ```bash
   # Create tdl config directory
   mkdir -p ~/.tdl
   
   # Move downloaded file and rename it
   mv ~/Downloads/client_secret_*.json ~/.tdl/gdrive_credentials.json
   ```

**Quick Links:**
- [Create New Project](https://console.cloud.google.com/projectcreate)
- [Enable Drive API](https://console.cloud.google.com/apis/library/drive.googleapis.com)
- [OAuth Consent Screen](https://console.cloud.google.com/apis/credentials/consent)
- [Create Credentials](https://console.cloud.google.com/apis/credentials)

#### Usage

**Upload to both Telegram and Google Drive:**
```bash
docker run -it -v ~/.tdl:/root/.tdl -v /path/to/files:/files \
  ghcr.io/zahidoverflow/tdl:latest upload -p /files/yourfile.txt --gdrive
```

**First-time authentication:**
1. A Google authorization URL will appear
2. Open it in your browser and sign in
3. Grant permissions to the app
4. Copy the authorization code from the redirect URL
5. Paste it into the terminal

The token will be cached in `~/.tdl/gdrive_token.json` for future uploads (no re-authentication needed).

### 🆕 Auto-Delete After Upload

Automatically delete local files after successful upload.

**Upload and delete local file:**
```bash
docker run -it -v ~/.tdl:/root/.tdl -v /path/to/files:/files \
  ghcr.io/zahidoverflow/tdl:latest upload -p /files/yourfile.txt --rm
```

**Upload to both platforms and delete:**
```bash
docker run -it -v ~/.tdl:/root/.tdl -v /path/to/files:/files \
  ghcr.io/zahidoverflow/tdl:latest upload -p /files/yourfile.txt --gdrive --rm
```

**Safety:** Files are only deleted if ALL uploads succeed. If any upload fails, the local file is preserved.

## Command Reference

### Upload Command

```bash
tdl upload [flags]
```

**New Flags:**
- `--gdrive`: Upload to Google Drive after Telegram upload
- `--rm`: Delete local file after successful upload

**Example combinations:**
```bash
# Telegram only
tdl upload -p /file.txt

# Telegram + Google Drive
tdl upload -p /file.txt --gdrive

# Telegram + auto-delete
tdl upload -p /file.txt --rm

# Telegram + Google Drive + auto-delete
tdl upload -p /file.txt --gdrive --rm
```

## File Locations

- **Telegram session:** `~/.tdl/data/`
- **Google Drive credentials:** `~/.tdl/gdrive_credentials.json`
- **Google Drive token:** `~/.tdl/gdrive_token.json` (auto-generated)
- **Logs:** `~/.tdl/log/`

## Security

**🔒 For Personal Use:**

This tool handles sensitive data (Telegram sessions, OAuth tokens). Follow these security practices:

1. **Secure Your Credentials:**
   ```bash
   chmod 700 ~/.tdl
   chmod 600 ~/.tdl/gdrive_credentials.json
   ```

2. **Enable Telegram 2FA:** Settings → Privacy and Security → Two-Step Verification

3. **Use Disk Encryption:** BitLocker (Windows), FileVault (macOS), or LUKS (Linux)

**📖 Documentation:**
- **[Quickstart Guide](docs/QUICKSTART.md)** - One-liner install for Windows/RDP
- **[Setup & Deployment](docs/SETUP.md)** - Docker deployment, CI/CD configuration
- **[Security Guide](docs/SECURITY.md)** - Comprehensive security audit and best practices
- **[Google Drive Limits](docs/GDRIVE_LIMITS.md)** - Mass upload safety, quotas, and account protection

## Documentation

For detailed documentation, please refer to [docs.iyear.me/tdl](https://docs.iyear.me/tdl/).

## Troubleshooting

### Google Drive Issues

**"unable to read client secret file"**
- Ensure `gdrive_credentials.json` exists in `~/.tdl/`
- Check file permissions are readable

**"Access blocked: tdl has not completed the Google verification process"**
- Add your email as a test user in OAuth consent screen
- Or publish the app (requires Google verification)

**"unable to retrieve Drive client"**
- Verify Google Drive API is enabled
- Check your internet connection
- Delete `~/.tdl/gdrive_token.json` and re-authenticate

### Docker Issues

**Volume mount problems:**
- Ensure `~/.tdl` directory exists: `mkdir -p ~/.tdl`
- Use absolute paths for volume mounts
- Check file permissions on mounted directories

## Sponsors

![](https://raw.githubusercontent.com/iyear/sponsor/master/sponsors.svg)

## Contributors
<a href="https://github.com/iyear/tdl/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=iyear/tdl&max=750&columns=20" alt="contributors"/>
</a>

## LICENSE

AGPL-3.0 License
