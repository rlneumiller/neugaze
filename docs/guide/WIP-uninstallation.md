# Uninstallation

This guide covers completely removing neugaze and all its components from your system.

## Quickest path: cargo uninstall

```bash
cargo uninstall neugaze
cargo uninstall neugaze-gui
```

If you also created a service unit for `neugazed`, remove it manually after uninstalling the binaries. Useful flags:

- `--keep-data` — preserve `/var/lib/neugaze` (enrolled faces)
- `--dry-run` — print the plan without running anything
- `--yes` — skip the confirmation prompt

If you'd rather run the steps yourself, follow the manual procedure below.

## Step 1: Disable integrations

Before removing packages, disable any active integrations to avoid leaving your system in a broken state.

### Reset GNOME lock screen settings

```bash
gnome-extensions disable neuneugaze@neugaze.local 2>/dev/null || true
gsettings reset-recursively org.gnome.shell.extensions.neugaze
```

Repeat this for each desktop user who enabled lock screen face unlock.

### Remove GDM login defaults and overrides

```bash
sudo rm -f /etc/dconf/db/gdm.d/00-neugaze-defaults* /etc/dconf/db/gdm.d/99-neugaze*
sudo dconf update
```

### Revert PAM configuration

```bash
sudo pam-auth-update --package --remove neugaze
```

```bash
if [ -f /etc/neugaze/authselect.previous ]; then
  profile=$(sudo sed -n 's/^Profile ID:[[:space:]]*//p' /etc/neugaze/authselect.previous)
  features=$(sudo sed -n 's/^- //p' /etc/neugaze/authselect.previous | tr '\n' ' ')
  sudo authselect select "$profile" $features --force
else
  sudo authselect select sssd --force
fi
```

```bash
# Remove any pam_neugaze.so lines
# from /etc/pam.d/system-auth or wherever you added them.
sudo nano /etc/pam.d/system-auth
```

### Stop and disable the daemon

```bash
sudo systemctl stop neugazed
sudo systemctl disable neugazed
```

## Step 2: Remove installed binaries

If you installed via Cargo:

```bash
cargo uninstall neugaze
cargo uninstall neugaze-gui
```

If you installed `neugazed` manually or created a service unit, remove the service file and stop the daemon as needed.

## Step 4: Remove leftover data

Package removal does not delete user data, downloaded models, or configuration files that were modified. Remove these manually if you want a clean slate.

Refresh compiled GNOME settings after package removal if your package manager did not run the hook:

```bash
sudo dconf update
sudo glib-compile-schemas /usr/share/glib-2.0/schemas
```

### Face enrollment data

```bash
sudo rm -rf /var/lib/neugaze
```

### Downloaded ML models and cache

```bash
sudo rm -rf /var/cache/neugaze
```

### Configuration

```bash
sudo rm -rf /etc/neugaze
```

### SELinux policy (Fedora/RPM systems only)

```bash
sudo semodule -r neugaze-gdm-camera
```

## Step 5: Reload system services

```bash
sudo systemctl daemon-reload
```

## Verify removal

```bash
# All of these should fail with "command not found"
neugaze --version
neugazed --version
neugaze-gui --help

# Should show "inactive" or "not found"
systemctl status neugazed
```
