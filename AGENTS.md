# AGENTS.md

## Repo Shape

- This repository is a work-in-progress personal fork of the original `neugaze` project.
- Current development and testing target Debian 13 with GNOME on Wayland using nVidia proprietary drivers.
- Until the code is proven reliable, install and test this repository inside the dedicated VM created for development testing.
- Rust workspace members are `neugaze`, `neugaze-core`, `neugaze-pam-core`, `neugaze-pam`, and `neugaze-gui`; root `default-members` omit the two `*-core` libraries, so use `--workspace` for whole-repo checks.
- `neugaze` owns both binaries: `neugazed` at `neugaze/src/main.rs` and CLI `neugaze` at `neugaze/src/bin/cli.rs`; the ML pipeline/user DB code also lives in this crate.
- `neugaze-core` is the shared camera/config/DBus/detection library; DBus proxy/types are generated from `neugaze-core/src/dbus.rs` with `zbus` macros.
- `neugaze-pam` is a `cdylib` PAM module; shared PAM FFI/auth logic is in `neugaze-pam-core`.
- `neugaze-gui` is the GTK4/libadwaita app; `gnome-shell-extension/` contains the GNOME Shell extension source.
- VS Code workspace launch/settings are kept in `neugaze.code-workspace`; do not add/rely on a separate `.vscode/launch.json` for repo-local configuration.

## Commands

- Recommended checks are `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace --release`, `cargo audit`, then `cargo build --workspace --release`.
- `cargo clippy --workspace --all-targets -- -D warnings` is the lint command; the local pre-commit hook is narrower, so do not treat it as CI-equivalent.
- `cargo test --workspace --release` is the test command; focused equivalent: `cargo test -p <crate> --release <test_name>`.
- `cargo build --workspace --release` is the build command.
- Native builds need OpenCV, clang/libclang, v4l, PAM, GTK4/libadwaita, and GStreamer dev packages.
- Local install is done with Cargo; packaging manifests and package build targets have been removed.
- Docs are authored as Markdown under `docs/` and no local Bun/VitePress build toolchain is required.

## Runtime Gotchas

- `neugazed` has fixed runtime paths: config `/etc/neugaze/config.toml`, templates `/var/lib/neugaze/users`, models `/var/cache/neugaze`; there is no CLI flag for alternate paths.
- The daemon owns `com.github.rlneumiller.NeuGaze` on the system DBus bus at `/com/github/rlneumiller/NeuGaze`; run it as root and stop the installed `neugazed` service before foreground local testing.
- Local daemon loop from docs: `sudo systemctl stop neugazed`, `cargo build --workspace --release`, `sudo RUST_LOG=debug ./target/release/neugazed`, then restart the service when done.
- CLI, GUI, and PAM clients always talk to whichever daemon owns the system bus name.
- Models are downloaded from InsightFace releases on first daemon run if absent; tests should not depend on network or committed model files.
- Camera config is `primary` or a GStreamer/PipeWire source string such as `pipewiresrc target-object=...`; `/dev/video*` paths are rejected in `neugaze-core/src/camera.rs`.

## Testing And Safety

- Prefer tests that can run locally around config, DBus mapping, user DB, model helpers without downloads, alignment/math, and CLI/TUI helpers.
- Do not add automated tests requiring a physical camera, running system `neugazed`, PAM installed into system auth files, a graphical session, or network downloads.
- PAM changes can lock users out: keep an active root shell, test a non-critical PAM service first, and include manual verification notes.
- Do not commit downloaded ONNX models, face embeddings, local `/etc/neugaze` config, package artifacts under `dist/`, `target/`, or `node_modules/`.

## Packaging And Extension Notes

- Local install is done with Cargo. `neugazed`, `neugaze`, and `neugaze-gui` can be built from source and installed locally.
- The GNOME extension source directory currently has only `extension.js`, `prefs.js`, and `metadata.json`.
- User-facing docs live in `docs/`; `README.md` is the GitHub landing page. Update docs when CLI, config, install, or auth behavior changes.
