# CLI Guide

Use the `neugaze` command for enrollment, testing, and managing face profiles.

All commands talk to the running `neugazed` daemon over DBus.

## Most common workflow

```bash
neugaze add-face default
neugaze auth --verbose
neugaze refine-face default
neugaze list-faces
```

## Authenticate

```bash
neugaze auth
```

Useful options:

```bash
neugaze auth --verbose   # show score table
neugaze auth --perf      # show timing details
```

Result meanings:

- `Authenticated as: ...`: pass
- `Access Denied`: no stored face passed current threshold

## Enroll a new face profile

```bash
neugaze add-face <name>
```

Examples:

```bash
neugaze add-face default
neugaze add-face glasses
```

Use separate profiles when your appearance changes often.

## Improve a profile

```bash
neugaze refine-face <name>
```

Use this if recognition is inconsistent in dim light or side angles.

## List, rename, and remove

```bash
neugaze list-faces
neugaze rename-face <old> <new>
neugaze remove-face <name>
```

## Delete all faces for current user

```bash
neugaze clear-user
```

This is destructive.

## Uninstall neugaze completely

```bash
neugaze uninstall              # interactive
neugaze uninstall --yes        # skip confirmation
neugaze uninstall --keep-data  # preserve enrolled faces in /var/lib/neugaze
neugaze uninstall --dry-run    # preview the plan, run nothing
```

Removes the installed packages, repository config, GNOME/GDM lock and login settings, PAM/authselect integration, SELinux policy, the model cache (`/var/cache/neugaze`), the system config (`/etc/neugaze`), and — unless `--keep-data` is set — enrolled face data (`/var/lib/neugaze`). Each step is best-effort and uses `sudo`, so you'll be prompted for your password.

See the [uninstallation guide](/guide/uninstallation) if you'd rather run the steps manually.

## Interactive configuration

Use the interactive wizard to edit daemon config through DBus:

```bash
neugaze config
```

Show-only mode:

```bash
neugaze config --show
```

This prints the current security level, camera source, and enrollment template settings without editing them.

## Manage another user

Most commands support `-u`:

```bash
neugaze list-faces -u alice
neugaze add-face work -u alice
```

## Troubleshooting commands

```bash
systemctl status neugazed
journalctl -u neugazed -n 100 --no-pager
neugaze auth --verbose
```

If you need help diagnosing failures, see the [troubleshooting guide](/guide/troubleshooting).
