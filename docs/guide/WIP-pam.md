# PAM

This page is about normal PAM integration (`sudo`, polkit, shared auth stacks).

`neugaze auth` is useful, but it is only a daemon/camera test. It does not run through PAM.

If you specifically want GNOME lock screen or GDM login behavior, use the [GNOME Extension guide](/guide/gnome).

## What neugaze installs

- `pam_neugaze.so` (sequential mode, recommended)

Sequential means face auth runs first, then password fallback.

## Debian / Ubuntu

Packages install PAM profiles for `pam-auth-update`.

Apply or re-apply them:

```bash
sudo pam-auth-update --package
```

Pick one of the neugaze entries, then test with a real PAM prompt:

```bash
sudo -v
```

If camera opens and face auth runs, PAM wiring is active.

## Fedora / RPM systems

RPM packages install an authselect profile at:

`/usr/share/authselect/vendor/neugaze`

Enable it:

```bash
sudo authselect select neugaze with-silent-lastlog --force
```

Verify profile + PAM behavior:

```bash
sudo authselect current
sudo -v
```

## Other distros (manual)

Edit your shared auth stack (for example `/etc/pam.d/system-auth`) and place neugaze before `pam_unix.so`.

Sequential:

```text
auth    sufficient    pam_neugaze.so
auth    sufficient    pam_unix.so try_first_pass nullok
```

Then test with `sudo -v`.

## Safety notes

- Keep password auth enabled while testing.
- Keep a root shell open before changing PAM.
- Back up PAM files first so you can restore quickly.
