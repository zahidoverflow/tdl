# Deployment Guide

## Automated CI/CD Setup

This repository is configured with GitHub Actions for automated builds and deployments.

### Docker Images

Docker images are automatically built and pushed to:
- **Docker Hub**: `zahidoverflow/tdl:latest`
- **GitHub Container Registry**: `ghcr.io/zahidoverflow/tdl:latest`

#### Triggers:
- **On every push to master**: Builds and pushes `latest` tag
- **On version tags (v*)**: Builds and pushes versioned tags (e.g., `v1.2.3`)
- **Manual workflow dispatch**: Can trigger builds manually

### Using Pre-built Images

You never need to build locally! Just pull and use:

```bash
# Pull from GitHub Container Registry (recommended)
docker pull ghcr.io/zahidoverflow/tdl:latest

# Or from Docker Hub
docker pull zahidoverflow/tdl:latest
```

### Workflow Files

- **`.github/workflows/docker.yml`**: Builds multi-arch Docker images
- **`.github/workflows/master.yml`**: Runs tests and linting on PRs and master
- **`.github/workflows/release.yml`**: Creates GitHub releases with binaries

### Supported Platforms

Docker images are built for:
- linux/amd64
- linux/386
- linux/arm64
- linux/arm/v7
- linux/arm/v6
- linux/riscv64

### Secrets Required

**Optional (for Docker Hub):**
- **`DOCKERHUB_TOKEN`**: Docker Hub access token (only if you want to push to Docker Hub)

**Note**: GitHub Container Registry (GHCR) works automatically with the built-in `GITHUB_TOKEN` - no additional secrets needed!

## Local Development

If you want to build locally for testing:

```bash
# Build Docker image
docker build -t tdl .

# Or build Go binary
go build -o tdl .
```

## Release Process

1. Create and push a tag:
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

2. GitHub Actions will automatically:
   - Build multi-arch Docker images
   - Push to Docker Hub and GHCR
   - Create GitHub release with binaries
   - Update Homebrew formula

No manual intervention needed!

# Security Configuration for Ephemeral RDP Use

**Date:** 2024  
**Configuration:** optimized for ephemeral RDP environments

## Configuration Applied

### 1. TLS Verification (Configurable)
**File:** `core/util/netutil/netutil.go`  
**Default:** TLS verification enabled  
**Override (if needed):** set `TDL_INSECURE_SKIP_VERIFY=true` to disable verification for problematic/self-signed proxies (not recommended on untrusted networks).

### 2. Docker Non-Root User (Maintained)
**File:** `Dockerfile`  
**Security:** Container runs as `tdl` user (not root)  
**Impact:** Minimal overhead, good security baseline

```dockerfile
RUN apk add --no-cache ca-certificates && \
    addgroup -S tdl && \
    adduser -S tdl -G tdl
USER tdl
```

### 3. File Permission Checks REMOVED (Faster Startup)
**File:** `pkg/gdrive/gdrive.go`  
**Removed:** Permission validation on every startup  
**Benefit:** Instant startup, no delays  
**Trade-off:** No warnings for insecure permissions (acceptable for ephemeral RDP)

## Optimizations for Ephemeral RDP

| Feature | Configuration | Benefit |
|---------|--------------|---------|
| **TLS Verification** | Default on (override via `TDL_INSECURE_SKIP_VERIFY=true`) | Better proxy compatibility when needed |
| **Permission Checks** | Removed | Instant startup |
| **Portable Storage** | `~/.tdl/` folder | Easy migration between RDP sessions |
| **Docker User** | Non-root | Basic security maintained |

## Quick Start on New RDP Session

```cmd
:: 1. Copy your .tdl folder
xcopy /E /I /Y E:\.tdl %USERPROFILE%\.tdl

:: 2. Run immediately (no setup needed)
tdl.exe dl -u https://t.me/example

:: 3. Upload to Google Drive and auto-delete local files
tdl.exe up --gdrive --rm C:\Downloads\files
```

## Security Trade-offs (Ephemeral Use)

- Disabling TLS verification can expose you to MITM; only do it on trusted/disposable environments.
- OAuth tokens/sessions in `~/.tdl/` should be kept private.

## Files Modified

```
Configurable:
- core/util/netutil/netutil.go (TLS verification override via env var)
- pkg/gdrive/gdrive.go (permission checks removed)

Maintained Security:
- Dockerfile (non-root user kept)
```
