# Development VM testing

This page describes how to use a Debian 13 GNOME Wayland VM for safe neugaze development and manual testing.

## VM setup script

A helper script is included at `scripts/neugaze-vm-setup.sh`.
It prepares the VM image directory, downloads the Debian 13 netinst ISO, creates a sparse QCOW2 disk, and activates the libvirt `default` network.

### Run the script

```bash
chmod +x scripts/neugaze-vm-setup.sh
./scripts/neugaze-vm-setup.sh
```

That will prepare:

- `/var/lib/libvirt/images/neugaze/debian-13.5.0-amd64-netinst.iso`
- `/var/lib/libvirt/images/neugaze/debian13-gnome-wayland.qcow2`
- the libvirt `default` network, if it is defined but inactive

If you want the script to launch the installer immediately, run:

```bash
./scripts/neugaze-vm-setup.sh --install
```

## Installing Debian GNOME

The script creates the VM disk and ISO and prints the `virt-install` command to start the installer.
Use the installer UI to install a standard Debian desktop and choose GNOME.
Wayland is the default GNOME session on Debian.

## Starting the VM after installation

After installation completes and the guest shuts down, start the VM again from the host:

```bash
virsh start neugaze-debian13
```

Then connect to the VM using a graphical tool such as `virt-manager` or `virt-viewer`, or use the libvirt console from your desktop environment.

With `virt-viewer`, run it as root because it needs access to the guest display:

```bash
sudo virt-viewer neugaze-debian13
```

The default guest login is:

- username: `neu-user`
- password: `neu-user-password`
- root password: `password`

If you changed the default VM name by setting `VM_NAME` before running `scripts/neugaze-vm-setup.sh`, use that name instead of `neugaze-debian13`.

## Check whether the VM is running

On the host, verify the VM state with:

```bash
virsh list --all
```

Look for the VM name and confirm its state is `running`.

If `virsh domstate neugaze-debian13` fails with `failed to get domain`, the VM name is probably different or the domain is not defined yet. Use `virsh list --all` to find the correct name.

Alternatively, check a single domain directly:

```bash
virsh domstate neugaze-debian13
```

If it returns `running`, the VM is active.

## Build dependencies inside the VM

After Debian is installed and you are logged in to the VM, install the native dependencies:

```bash
sudo apt update
sudo apt install -y build-essential pkg-config clang libclang-dev \
  libopencv-dev libv4l-dev libpam0g-dev \
  libgtk-4-dev libadwaita-1-dev \
  libcairo2-dev libglib2.0-dev libgdk-pixbuf-2.0-dev \
  libpango1.0-dev libgraphene-1.0-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
```

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
