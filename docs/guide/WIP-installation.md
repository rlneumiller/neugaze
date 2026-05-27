# Installation

Before building from source, install the native development dependencies required by the Rust bindings.

```bash
sudo apt-get update
sudo apt-get install -y pkg-config libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libadwaita-1-dev
```

Install the CLI, daemon, and GUI from source with Cargo:

```bash
cargo install --path neugaze --bins neugaze neugazed
cargo install --path neugaze-gui
```

If Cargo's binary directory is not on your `PATH`, add it:

```bash
export PATH="$HOME/.cargo/bin:$PATH"
```

Cargo install builds and installs the local binaries, but it does not set up a systemd service, PAM integration, or the GNOME Shell extension.

## Verify installation

```bash
neugaze --version
neugaze-gui --help
neugazed --version
```

## Run the daemon

Start `neugazed` manually:

```bash
neugazed
```

If you want daemon management, create your own service unit or supervisor configuration.

## First run

```bash
neugaze add-face default
neugaze auth --verbose
```

## Development and source builds

See the [Development guide](/guide/development) for source builds, tests, and local install instructions.
