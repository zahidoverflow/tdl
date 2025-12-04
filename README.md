# tdl

<img align="right" src="docs/assets/img/logo.png" height="280" alt="">

> 📥 Telegram Downloader, but more than a downloader

English | <a href="README_zh.md">简体中文</a>

<p>
<img src="https://img.shields.io/github/go-mod/go-version/iyear/tdl?style=flat-square" alt="">
<img src="https://img.shields.io/github/license/iyear/tdl?style=flat-square" alt="">
<img src="https://img.shields.io/github/actions/workflow/status/iyear/tdl/master.yml?branch=master&amp;style=flat-square" alt="">
<img src="https://img.shields.io/github/v/release/iyear/tdl?color=red&amp;style=flat-square" alt="">
<img src="https://img.shields.io/github/downloads/iyear/tdl/total?style=flat-square" alt="">
</p>

#### Features:
- Single file start-up
- Low resource usage
- Take up all your bandwidth
- Faster than official clients
- Download files from (protected) chats
- Forward messages with automatic fallback and message routing
- Upload files to Telegram **and Google Drive** 🆕
- **Auto-delete local files after upload** 🆕
- Export messages/members/subscribers to JSON

## Preview

It reaches my proxy's speed limit, and the **speed depends on whether you are a premium**

![](docs/assets/img/preview.gif)

## Quick Start

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

## New Features

### 🆕 Google Drive Upload

Upload files to Google Drive after uploading to Telegram.

#### Setup

1. **Enable Google Drive API:**
   - Visit [Google Cloud Console](https://console.cloud.google.com/)
   - Create a new project or select existing one
   - Navigate to "APIs & Services" > "Library"
   - Search for "Google Drive API" and click "Enable"

2. **Create OAuth2 Credentials:**
   - Go to "APIs & Services" > "Credentials"
   - Click "Create Credentials" > "OAuth client ID"
   - Select "Desktop app" as application type
   - Download the JSON credentials file

3. **Configure tdl:**
   - Rename downloaded file to `gdrive_credentials.json`
   - Place it in `~/.tdl/` directory

4. **Add Test User (if app is in Testing mode):**
   - Go to "OAuth consent screen" > "Test users"
   - Click "ADD USERS" and add your Google email

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
