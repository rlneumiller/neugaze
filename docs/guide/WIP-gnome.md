# GNOME Extension

neugaze lock screen and GDM integration are GNOME-specific and use the extension source in `gnome-shell-extension/`. This repo no longer provides a packaged `neugaze-gnome-extension` installer, so extension installation must be done manually or from source.

This extension starts the `gdm-face` PAM service inside GNOME Shell authentication flows.

You do not need to enable this extension for the CLI, the GUI, or normal PAM prompts such as `sudo`. Leave it disabled on non-GNOME desktops.

## Should I enable it?

Enable it if you use GNOME and want face unlock from the lock screen.

Do not enable it if you only want CLI/GUI enrollment, normal PAM authentication, or you are not using GNOME.

## Enable the extension

If the package is installed but the extension is not enabled yet, first reboot so GNOME Shell scans the newly installed extension. Then, from your GNOME session:

```bash
gnome-extensions enable neuneugaze@neugaze.local
gsettings set org.gnome.shell.extensions.neugaze enable-face-authentication true
```

`gnome-extensions enable` will report `Extension "neuneugaze@neugaze.local" does not exist` if you run it before rebooting. Shell only scans extension directories at session start, so running the command immediately after install (without a session restart) always fails. If you cannot reboot yet, the equivalent dconf write works at any time and takes effect on the next login:

```bash
gsettings set org.gnome.shell enabled-extensions \
  "$(gsettings get org.gnome.shell enabled-extensions | sed "s/]\$/, 'neuneugaze@neugaze.local']/; s/^@as \[\]\$/['neuneugaze@neugaze.local']/")"
gsettings set org.gnome.shell.extensions.neugaze enable-face-authentication true
```

## Login warning (GNOME keyring)

GDM loads the extension from package defaults, but face authentication for the GDM login screen is disabled by default.

This is mostly about GNOME keyring behavior. GNOME keyring is normally unlocked by your login password. If you log in with face only, that password is never entered, so the keyring may stay locked.

When that happens, apps that read saved secrets (browser credentials, git credentials, Wi-Fi secrets, chat clients, etc.) can keep prompting for a keyring password until you unlock it manually.

## Optional: enable face at GDM login

If you still want this, enable it in GDM's system dconf profile:

```bash
sudo mkdir -p /etc/dconf/profile /etc/dconf/db/gdm.d
sudo tee /etc/dconf/profile/gdm >/dev/null <<'EOF'
user-db:user
system-db:gdm
file-db:/usr/share/gdm/greeter-dconf-defaults
EOF
sudo tee /etc/dconf/db/gdm.d/99-neugaze >/dev/null <<'EOF'
[org/gnome/shell]
enabled-extensions=['neuneugaze@neugaze.local']

[org/gnome/shell/extensions/neugaze]
enable-face-authentication=true
EOF
sudo dconf update
```

Then reboot. Restarting GDM also works, but it immediately logs out active desktop sessions.

```bash
sudo reboot
```

At the GDM login screen, the selected user's desktop session may not exist yet. neugaze still matches against that user's enrolled faces, but uses the active greeter PipeWire camera session when needed.

## Disable face at GDM login

```bash
sudo rm -f /etc/dconf/db/gdm.d/99-neugaze*
sudo dconf update
```

## Verify GNOME flow

- Lock screen, then try unlock with face.
- If login face auth is enabled, test a full logout/login cycle.
