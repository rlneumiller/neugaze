# Development VM testing

This page describes how to use a Debian 13 GNOME Wayland VM for safe neugaze development and manual testing.

## VM setup script

A helper script is included at `scripts/neugaze-vm-run.sh`.
It prepares the VM image directory, downloads the Debian 13 netinst ISO if needed, creates the QCOW2 disk, and then:

- if the disk does not yet contain Debian, launches an automated preseeded installer
  that installs GNOME, the native neugaze build dependencies, and `rustup`
- if the disk already contains Debian, boots the installed VM directly

### Run the script

```bash
chmod +x scripts/neugaze-vm-run.sh
sudo ./scripts/neugaze-vm-run.sh
```

The script uses `qemu-system-x86_64` directly and does not require libvirt.

### Optional settings

The following environment variables can override defaults:

- `VM_NAME` — default `neugaze-debian13`
- `IMAGE_DIR` — default `/var/lib/libvirt/images/neugaze`
- `DISK_NAME` — default `neugaze-ready-debian13.qcow2`
- `NEUGAZE_VM_USERNAME` — default `neugaze-user`
- `NEUGAZE_VM_USER_PASSWORD` — default `neugaze-user-password`

If the VM disk already contains Debian, re-running the same script boots that VM again.

## Installing Debian GNOME

The script performs a non-interactive automated Debian install whenever the VM disk is empty.
The installer is preseeded to choose:

- `en_US.UTF-8` locale
- US keyboard layout
- guided LVM partitioning on the full disk
- GNOME desktop with the required build dependencies

After the installer finishes, the VM powers off and the script exits.

## Starting the VM after installation

After the first run completes, start the VM again by rerunning the same script:

```bash
sudo ./scripts/neugaze-vm-run.sh
```

This will detect the existing Debian install on the disk and boot it.

The default guest login is:

- username: `neugaze-user`
- password: `neugaze-user-password`

The installed user is configured as a sudo user; root login is disabled.
The VM also forwards guest SSH to host loopback only at `127.0.0.1:2222`, so the guest is reachable from the host but not exposed on the LAN.

## VS Code Remote-SSH

Fresh automated installs include `openssh-server`, so once the VM is booted you can connect from the host with:

```bash
ssh -p 2222 neugaze-user@127.0.0.1
```
### Add the host ssh config to enable vscode connection via Remote-ssh

Add a host entry on the host machine by editing `~/.ssh/config` on the host, not inside the VM.
If the SSH config does not exist yet, create it with restrictive permissions:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/config
chmod 600 ~/.ssh/config
```

Then add this host entry:

```sshconfig
Host neugaze-vm
  HostName 127.0.0.1
  Port 2222
  User neugaze-user
```

After saving the file, test the alias from the host:

```bash
ssh neugaze-vm
```

Then use VS Code Remote-SSH to connect to `neugaze-vm`.

## Check whether the VM is running

On the host, verify whether `qemu-system-x86_64` is running:

```bash
pgrep -a qemu-system-x86_64
```

If you prefer to inspect the guest from inside the VM, use the guest's terminal or desktop environment after it boots.

## Build dependencies inside the VM

The VM setup script already installs the native Debian packages required for building `neugaze` as part of the automated Debian GNOME installation.

## Get the source and install

Inside the VM:

```bash
git clone https://github.com/neugaze/neugaze.git
cd neugaze
./scripts/setup-hooks.sh
cargo install --path neugaze --bins neugaze neugazed
cargo install --path neugaze-gui
```

If the `cargo` install directory is not on your `PATH`, add it:

```bash
export PATH="$HOME/.cargo/bin:$PATH"
```

## Verify the install

```bash
neugaze --version
neugaze-gui --help
neugazed --version
```

## Run the daemon and test locally

Start the daemon in one terminal:

```bash
neugazed
```

In another terminal:

```bash
neugaze add-face default
neugaze auth --verbose
```

These commands exercise the core daemon and camera path without touching system PAM or the lock screen.

## Safety notes

Using a VM isolates the host from PAM and login-stack changes.
Still keep snapshots or backups before you test PAM integration, and prefer a non-critical PAM service for early experiments.
