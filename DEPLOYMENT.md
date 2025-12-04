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
