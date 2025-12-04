# GitHub Copilot Instructions

This document provides guidance for AI assistants to effectively contribute to the `tdl` codebase.

## Project Overview

`tdl` is a command-line tool written in Go for interacting with the Telegram API. It's more than just a downloader, offering features like file up/downloading, message forwarding, and data exporting. The project uses the `gotd` library (`github.com/gotd/td`) as its core Telegram client.

The application is structured as a CLI using the `cobra` framework (`github.com/spf13/cobra`). The main entry point and command structure are defined in the `cmd/` directory.

## Architecture

The codebase is organized into several key directories:

- **`cmd/`**: Contains the definitions for all CLI commands (e.g., `dl`, `up`, `login`). `cmd/root.go` is the main entry point where commands, configuration, logging, and storage are initialized.
- **`app/`**: Implements the core business logic for each command. For example, `app/dl/dl.go` contains the logic for the download command. This is where most of the application's functionality resides.
- **`core/`**: Provides shared, low-level components used across the application. This includes a wrapper around the `gotd` client (`core/tclient`), downloader/uploader logic, and storage abstractions.
- **`pkg/`**: Contains reusable packages that are less coupled to the core application logic, such as `kv` for storage, `tclient` for app management, and `extensions` for the extension system.
- **`extension/`**: Defines the extension system, allowing for pluggable new features.

### Data Flow & Key Concepts

1.  **Command Execution**: A user runs a command (e.g., `tdl dl <... >`). `cobra` in `cmd/` parses the arguments.
2.  **Initialization**: The `PersistentPreRunE` function in `cmd/root.go` sets up logging (using `zap`), configuration (using `viper`), and the KV storage backend (`bbolt` by default).
3.  **Telegram Client**: The `tRun` helper function in `cmd/root.go` is a critical piece. It initializes the Telegram client (`tclient.New`), handles authentication, and passes the authenticated client to the function that executes the command's logic.
4.  **Business Logic**: The actual work is done in the corresponding `app/` package. For instance, `app/dl/dl.go` will use the `core/downloader` to fetch files.
5.  **Storage**: The `kv` package abstracts storage. Session files, user data, and other persistent information are stored per-namespace (controlled by the `-n` flag). The default storage is a `bbolt` database at `~/.tdl/data/data`.

## Developer Workflow

### Building

The project uses `goreleaser`. To build a local binary:

```sh
make build
```

The resulting binary will be in the `.tdl/dist` directory.

### Testing

The project uses `ginkgo` and `gomega` for testing. Tests are located in the `test/` directory. To run the test suite:

```sh
go test ./...
```

### Dependencies

Dependencies are managed with Go Modules. Use `go get` to add new dependencies and `go mod tidy` to clean up `go.mod` and `go.sum`.

## Conventions

- **Command Structure**: New commands should be added in the `cmd/` directory. The corresponding implementation logic should be placed in a new or existing package under `app/`.
- **Configuration**: Use `viper` to manage configuration. Add new flags in `cmd/root.go` or the specific command's file and bind them to viper.
- **Logging**: Use the `logctx` package to get a `zap.Logger` from the context. Do not create new global loggers.
- **Telegram Client Usage**: Always use the `tRun` function in `cmd/root.go` to get an authenticated Telegram client. This ensures consistent session handling and middleware application.
- **Error Handling**: Use `github.com/go-faster/errors` for wrapping errors to provide stack traces.
- **Extensibility**: For significant new features, consider implementing them as extensions using the framework in `pkg/extensions` and `extension/`.

## Key Files and Directories

- `cmd/root.go`: The heart of the CLI application. Understand this file to see how everything is wired together.
- `app/`: The core logic for each command. When modifying a command's behavior, start here.
- `core/tclient/tclient.go`: The wrapper around the `gotd` client.
- `pkg/kv/`: The storage abstraction layer.
- `Makefile`: Defines build and packaging commands.
- `go.mod`: Project dependencies.
