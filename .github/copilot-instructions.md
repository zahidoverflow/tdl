# GitHub Copilot Instructions

This document provides guidance for AI assistants to effectively contribute to the `tdl` codebase.

## Project Overview

`tdl` is a command-line tool written in Go for interacting with the Telegram API. It offers features like file up/downloading, message forwarding, data exporting, and **Google Drive integration**. The project uses the `gotd` library as its core Telegram client.

## Architecture

- **`cmd/`**: CLI command definitions (using `cobra`)
- **`app/`**: Core business logic for each command
- **`core/`**: Shared low-level components (tclient, downloader, uploader)
- **`pkg/`**: Reusable packages (kv storage, gdrive, extensions)
- **`extension/`**: Extension system for pluggable features
- **`test/`**: Integration tests
- **`docs/`**: Documentation (SETUP.md, SECURITY.md, README_zh.md)
- **`scripts/`**: Installation scripts

## Key Features

- Google Drive upload integration (`pkg/gdrive/`)
- Auto-delete after upload (`--rm` flag)
- OAuth2 authentication for Google Drive
- BBolt database for session storage

## Documentation Structure

- **`README.md`** - Main project documentation
- **`docs/SETUP.md`** - Deployment and configuration guide
- **`docs/SECURITY.md`** - Security audit and best practices
- **`docs/README_zh.md`** - Chinese documentation

## Developer Workflow

- Build: `make build` or `go build`
- Test: `go test ./...`
- Format: `gofumpt -l -w .`

## Conventions

- Use `viper` for configuration
- Use `logctx` package for logging
- Use `tRun` in `cmd/root.go` for authenticated Telegram client
- Error handling with `github.com/go-faster/errors`
