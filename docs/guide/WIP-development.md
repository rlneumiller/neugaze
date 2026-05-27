# Development

This page covers source builds and tests for contributors.

For pull request workflow, testing expectations, and safety notes, see [Contributing](/guide/contributing).

## Prerequisites

- Rust 1.85+ (or install current stable via `rustup`)

```bash [Debian/Ubuntu]
sudo apt install build-essential pkg-config clang libclang-dev \
  libopencv-dev libv4l-dev libpam0g-dev \
  libgtk-4-dev libadwaita-1-dev \
  libcairo2-dev libglib2.0-dev libgdk-pixbuf-2.0-dev \
  libpango1.0-dev libgraphene-1.0-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
```

## Setup

```bash
git clone https://github.com/rlneumiller/neugaze
cd neugaze
./scripts/setup-hooks.sh
```

Git hooks are local to each clone. `./scripts/setup-hooks.sh` points Git at the tracked hook scripts so pre-commit checks stay up to date when the repo changes.

For VM-based development and test setup, see [Development VM testing](/guide/development-testing).

## Build and test rust components

```bash
cargo build --workspace --release
cargo test --workspace --release
cargo clippy --workspace --all-targets -- -D warnings
cargo fmt --all -- --check
```

## Run a locally-built daemon

The daemon takes no CLI arguments — paths are compiled in:

- Config: `/etc/neugaze/config.toml`
- User templates: `/var/lib/neugaze/users`
- Models: `/var/cache/neugaze`

It also owns `com.github.rlneumiller.NeuGaze` on the **system** DBus bus, which requires root. You cannot run a second daemon as your user.

Easiest iteration loop: stop the installed service, run your build in the foreground.

```bash
sudo systemctl stop neugazed
cargo build --workspace --release
sudo RUST_LOG=debug ./target/release/neugazed
```

`RUST_LOG` accepts standard `tracing` filters (`info`, `debug`, `neugaze=trace`, etc.). Ctrl-C to stop, then `sudo systemctl start neugazed` when you're done to restore the system daemon.

If you've never installed neugaze on this machine, you can create `/etc/neugaze/config.toml` before starting the daemon, or let it run with default values. The CLI and GUI need no special setup — they talk to whichever `neugazed` currently owns the bus name:

```bash
./target/release/neugaze list-faces
./target/release/neugaze auth --verbose
./target/release/neugaze-gui
```

## Iterating on the PAM module

`neugaze-pam` builds as a `cdylib`. After `cargo build --release` you'll have:

- `target/release/libpam_neugaze.so`

To exercise it through real PAM, copy it into the system PAM library directory (path is distro-specific):

```bash
# Debian
sudo cp target/release/libpam_neugaze.so /lib/x86_64-linux-gnu/security/pam_neugaze.so

## <span style="color:red">WARNING! Don't lock yourself out</span>
Before touching PAM files, **keep a second terminal open with an active root shell** (`sudo -s`). If the module crashes or misbehaves, you can revert from that shell. Test against a non-critical service first (e.g. add a line to `/etc/pam.d/su` or a custom service), not `system-auth` or `sudo`.

Quickest end-to-end test once the `.so` is in place:

```bash
sudo -k   # invalidate cached sudo credentials
sudo -v   # force a fresh PAM prompt
```

## Iterating on the GNOME extension

The extension source lives in `gnome-shell-extension/`. To run it from the tree without packaging:

```bash
mkdir -p ~/.local/share/gnome-shell/extensions
ln -sfn "$PWD/gnome-shell-extension" \
  ~/.local/share/gnome-shell/extensions/neuneugaze@neugaze.local

# compile the gsettings schema once
glib-compile-schemas ~/.local/share/gnome-shell/extensions/neuneugaze@neugaze.local/schemas

# on Xorg: Alt+F2 then `r`. On Wayland: log out and back in.
gnome-extensions enable neuneugaze@neugaze.local
gsettings set org.gnome.shell.extensions.neugaze enable-face-authentication true
```

Watch shell logs while you iterate:

```bash
journalctl -f /usr/bin/gnome-shell
```

For the unlock-dialog session mode (lock screen), changes only take effect after a fresh lock, not a shell reload.

## Install locally

```bash
cargo install --path neugaze --bins neugaze neugazed
cargo install --path neugaze-gui
```

The binaries are installed into Cargo's bin directory, usually `~/.cargo/bin` or `~/.local/cargo/bin`.

## Cleaning build artifacts

```bash
cargo clean
```
