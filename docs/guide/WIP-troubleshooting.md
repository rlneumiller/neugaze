# Troubleshooting

If neugaze is installed but not authenticating reliably, use this page as a quick diagnostic checklist.

## 1. Daemon is not running

Check the daemon:

```bash
systemctl status neugazed
```

If the output says `active (running)`, this part is fine.

Fix:

```bash
sudo systemctl enable --now neugazed
```

If it still fails:

```bash
journalctl -u neugazed -n 200 --no-pager
```

That command shows the most recent daemon log messages.

## 2. Camera is not detected

Use the primary GStreamer camera source first:

```toml
[cameras]
rgb = "primary"
```

If you need a specific camera, run `neugaze config` and select one of the detected PipeWire cameras, or set a GStreamer source manually:

```toml
[cameras]
rgb = "pipewiresrc target-object=<pipewire-target>"
```

Direct `/dev/video*` paths are not supported.

Then restart daemon:

```bash
sudo systemctl restart neugazed
```

## 3. Enrollment works, auth fails often

Try this sequence:

1. Keep `level = "medium"` in config.
2. Improve sample coverage:

```bash
neugaze refine-face default
```

3. Test scores:

```bash
neugaze auth --verbose
```

4. Add a second profile for a common variation:

```bash
neugaze add-face glasses
```

## 4. Lock screen does not trigger face auth

Enable or re-enable the extension from your GNOME session:

```bash
gnome-extensions enable neuneugaze@neugaze.local
gsettings set org.gnome.shell.extensions.neugaze enable-face-authentication true
```

If `gnome-extensions enable` reports `Extension "neuneugaze@neugaze.local" does not exist`, GNOME Shell has not picked up the newly installed extension yet. Reboot, then re-run the command. On Wayland this is the only way; Shell does not rescan extensions in a running session. The one-line installer works around this by writing the equivalent dconf keys directly, which take effect on the next login without needing `gnome-extensions enable` to succeed.

For GDM login, if the face-auth text appears but the camera light never turns on, check the daemon logs for camera/PipeWire errors:

```bash
journalctl -u neugazed -b
```

Older neugaze builds could try to use the selected user's PipeWire runtime before that user session existed. Update neugaze if you see this behavior.

## 5. PAM auth flow seems broken

Reinstall from source (recommended):

```bash
cargo install --path neugaze --bins neugaze neugazed
cargo install --path neugaze-gui
```

This rebuilds the binaries from source.

## 6. First run is slow

This is normal when models are downloaded initially.

After first successful run, subsequent auth attempts should be faster.

## 7. Verify installed version and binaries

```bash
neugaze --version
which neugaze
which neugaze-gui
```

What these do:

- `neugaze --version`: confirms the CLI is installed
- `which neugaze`: shows where the CLI binary is located
- `which neugaze-gui`: shows where the GUI binary is located

## 8. Collect useful logs before asking for help

```bash
systemctl status neugazed
journalctl -u neugazed -n 300 --no-pager
neugaze auth --verbose
```

Include distro version and desktop environment (GNOME/KDE/etc.) when reporting issues.
