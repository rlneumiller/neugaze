#!/bin/sh
set -eu

# Personal install script for neugaze — single system, no packaging.
# Run as root after building release artifacts as your normal user:
#
#   cargo build --workspace --release
#   sudo scripts/neugaze-install.sh install
#
# To remove an installed copy:
#   sudo scripts/neugaze-install.sh uninstall

usage() {
    cat <<'EOF'
Usage: scripts/neugaze-install.sh install|uninstall|status

Install or remove neugaze on this system without a package manager.

Run 'install' as root after building:
    cargo build --workspace --release
    sudo scripts/neugaze-install.sh install

Options:
  install     Install binaries, PAM module, service, config, and extension.
  uninstall   Remove all files written by a prior install.
  status      Show what is currently installed.
  -h|--help   Show this message.
EOF
}

die() {
    printf '%s\n' "$*" >&2
    exit 1
}

need_root() {
    [ "$(id -u)" -eq 0 ] || die "Run this script with sudo."
}

repo_root() {
    CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P
}

REPO=$(repo_root)
TARGET="$REPO/target/release"

# Installation destinations
BIN_DIR=/usr/bin
SYSTEMD_UNIT=/usr/lib/systemd/system/neugazed.service
DBUS_POLICY=/usr/share/dbus-1/system.d/com.example.Neugaze.conf
POLKIT_POLICY=/usr/share/polkit-1/actions/com.example.neugaze.policy
PAM_CONFIGS_DIR=/usr/share/pam-configs
SYSTEM_EXTENSION_DIR=/usr/share/gnome-shell/extensions/neugaze@example.com
SCHEMA_DST=/usr/share/glib-2.0/schemas/org.gnome.shell.extensions.neugaze.gschema.xml
CONFIG_DIR=/etc/neugaze
STATE_DIR=/var/lib/neugaze
CACHE_DIR=/var/cache/neugaze

artifact() {
    printf '%s/%s' "$TARGET" "$1"
}

require_artifacts() {
    missing=0
    for file in \
        "$(artifact neugazed)" \
        "$(artifact neugaze)" \
        "$(artifact neugaze-gui)" \
        "$(artifact libpam_neugaze.so)"
    do
        if [ ! -f "$file" ]; then
            printf 'Missing build artifact: %s\n' "$file" >&2
            missing=1
        fi
    done
    [ "$missing" -eq 0 ] || die "Build first: cargo build --workspace --release"
}

find_pam_dir() {
    multiarch=
    if command -v gcc >/dev/null 2>&1; then
        multiarch=$(gcc -print-multiarch 2>/dev/null || true)
    fi

    for dir in \
        "/lib/$multiarch/security" \
        "/usr/lib/$multiarch/security" \
        /usr/lib64/security \
        /usr/lib/security
    do
        case "$dir" in
            /lib//security|/usr/lib//security) continue ;;
        esac
        [ -d "$dir" ] && printf '%s' "$dir" && return 0
    done

    return 1
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

install_binaries() {
    install -m 0755 "$(artifact neugazed)"    "$BIN_DIR/neugazed"
    install -m 0755 "$(artifact neugaze)"     "$BIN_DIR/neugaze"
    install -m 0755 "$(artifact neugaze-gui)" "$BIN_DIR/neugaze-gui"
    printf 'installed: %s/neugazed neugaze neugaze-gui\n' "$BIN_DIR"
}

install_pam_modules() {
    pam_dir=$(find_pam_dir) || die "Could not find a PAM security module directory."
    install -m 0755 "$(artifact libpam_neugaze.so)" "$pam_dir/pam_neugaze.so"
    printf 'installed: %s/pam_neugaze.so\n' "$pam_dir"
}

create_runtime_dirs() {
    install -d -m 0755 "$CONFIG_DIR"
    install -d -m 0700 "$STATE_DIR"
    install -d -m 0700 "$CACHE_DIR"
    printf 'created: %s %s %s\n' "$CONFIG_DIR" "$STATE_DIR" "$CACHE_DIR"
}

install_config() {
    config_file="$CONFIG_DIR/config.toml"
    if [ -e "$config_file" ]; then
        printf 'skipped (already exists): %s\n' "$config_file"
        return
    fi

    cat >"$config_file" <<'EOF'
# NeuGaze daemon configuration
# Security level determines which InsightFace models and threshold to use.
#
# Preset levels:
#   low      - MobileFaceNet + SCRFD-500M, threshold 0.3  (fastest, least secure)
#   medium   - MobileFaceNet + SCRFD-500M, threshold 0.4  (default)
#   high     - ResNet50 + SCRFD-10G, threshold 0.5        (more accurate)
#   maximum  - ResNet50 + SCRFD-10G, threshold 0.6        (strictest)
#
# Models are automatically downloaded from the official InsightFace GitHub
# releases if not already present in the models directory.

[security]
level = "medium"

[cameras]
rgb = "primary"
# Reject frames where this fraction of pixels are below dark_pixel_value.
dark_threshold = 0.6
dark_pixel_value = 10

[auth]
abort_if_ssh = true
abort_if_lid_closed = true

[enrollment]
max_templates = 3

# Liveness anti-spoofing runs a local MiniFASNet-V2 PAD model on the detected face crop.
# The model is downloaded into /var/cache/neugaze on first use if missing.
[liveness]
enabled = true
threshold = 0.8
max_frames = 40
EOF
    printf 'installed: %s\n' "$config_file"
}

install_dbus_policy() {
    install -d "$(dirname -- "$DBUS_POLICY")"
    cat >"$DBUS_POLICY" <<'EOF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <!-- Only root can own the service -->
  <policy user="root">
    <allow own="com.example.Neugaze"/>
    <allow send_destination="com.example.Neugaze"/>
    <allow send_interface="com.example.Neugaze"/>
  </policy>

  <!-- Any user can call methods on the service -->
  <policy context="default">
    <allow send_destination="com.example.Neugaze"/>
    <allow send_interface="com.example.Neugaze"/>
  </policy>
</busconfig>
EOF
    printf 'installed: %s\n' "$DBUS_POLICY"
}

install_polkit_policy() {
    install -d "$(dirname -- "$POLKIT_POLICY")"
    cat >"$POLKIT_POLICY" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
  "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <vendor>NeuGaze</vendor>
  <vendor_url>https://neugaze.example.com</vendor_url>

  <action id="com.example.neugaze.manage-faces">
    <description>Manage NeuGaze face enrollments</description>
    <message>Authentication is required to manage NeuGaze face enrollments.</message>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>auth_admin_keep</allow_active>
    </defaults>
  </action>

  <action id="com.example.neugaze.manage-config">
    <description>Manage NeuGaze daemon configuration</description>
    <message>Authentication is required to change NeuGaze daemon configuration.</message>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>auth_admin_keep</allow_active>
    </defaults>
  </action>
</policyconfig>
EOF
    printf 'installed: %s\n' "$POLKIT_POLICY"
}

install_systemd_unit() {
    install -d "$(dirname -- "$SYSTEMD_UNIT")"
    cat >"$SYSTEMD_UNIT" <<'EOF'
[Unit]
Description=NeuGaze Facial Authentication Daemon
After=dbus.service
Requires=dbus.service

[Service]
ExecStart=/usr/bin/neugazed
Restart=on-failure
RestartSec=5
StateDirectory=neugaze
StateDirectoryMode=0700
CacheDirectory=neugaze
UMask=0077
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
LockPersonality=yes
SystemCallArchitectures=native
CapabilityBoundingSet=CAP_DAC_READ_SEARCH
ReadWritePaths=/etc/neugaze

[Install]
WantedBy=multi-user.target
EOF
    printf 'installed: %s\n' "$SYSTEMD_UNIT"
}

install_gnome_extension() {
    install -d "$SYSTEM_EXTENSION_DIR"
    install -m 0644 "$REPO/gnome-shell-extension/metadata.json" "$SYSTEM_EXTENSION_DIR/metadata.json"
    install -m 0644 "$REPO/gnome-shell-extension/extension.js"  "$SYSTEM_EXTENSION_DIR/extension.js"
    install -m 0644 "$REPO/gnome-shell-extension/prefs.js"      "$SYSTEM_EXTENSION_DIR/prefs.js"
    printf 'installed: %s/{metadata.json,extension.js,prefs.js}\n' "$SYSTEM_EXTENSION_DIR"

    # Per-user install for the invoking user when run under sudo.
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
        home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        sudo_group=$(id -gn "$SUDO_USER")
        user_ext_dir="$home/.local/share/gnome-shell/extensions/neugaze@example.com"
        install -d -o "$SUDO_USER" -g "$sudo_group" "$user_ext_dir"
        for f in metadata.json extension.js prefs.js; do
            install -m 0644 -o "$SUDO_USER" -g "$sudo_group" \
                "$REPO/gnome-shell-extension/$f" "$user_ext_dir/$f"
        done
        printf 'installed: %s/{metadata.json,extension.js,prefs.js}\n' "$user_ext_dir"
    fi
}

install_gschema() {
    install -d "$(dirname -- "$SCHEMA_DST")"
    cat >"$SCHEMA_DST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<schemalist>
  <schema id="org.gnome.shell.extensions.neugaze" path="/org/gnome/shell/extensions/neugaze/">
    <key name="enable-face-authentication" type="b">
      <default>false</default>
      <summary>Enable face authentication</summary>
      <description>
        Controls whether face authentication is attempted by the NeuGaze GNOME
        extension for the current dconf profile.
      </description>
    </key>

    <key name="max-face-tries" type="i">
      <default>3</default>
      <summary>Maximum face authentication attempts</summary>
      <description>
        Number of failed face attempts before face auth is stopped for the
        current authentication cycle.
      </description>
    </key>
  </schema>
</schemalist>
EOF
    if command -v glib-compile-schemas >/dev/null 2>&1; then
        glib-compile-schemas /usr/share/glib-2.0/schemas
        printf 'installed and compiled: %s\n' "$SCHEMA_DST"
    else
        printf 'installed: %s (run glib-compile-schemas manually)\n' "$SCHEMA_DST"
    fi
}

install_pam_config() {
    if [ -d "$PAM_CONFIGS_DIR" ] && command -v pam-auth-update >/dev/null 2>&1; then
        cat >"$PAM_CONFIGS_DIR/neugaze" <<'EOF'
Name: NeuGaze Face Authentication (Sequential)
Default: yes
Priority: 255
Auth-Type: Primary
Auth:
        [success=end default=ignore]    pam_neugaze.so
EOF
        pam-auth-update --package >/dev/null 2>&1 || true
        printf 'installed: %s/neugaze (pam-auth-update ran)\n' "$PAM_CONFIGS_DIR"
    else
        printf 'NOTE: pam-auth-update not available.\n'
        printf '  To enable PAM face auth manually, add to /etc/pam.d/common-auth or a\n'
        printf '  service-specific PAM file before the first auth line:\n'
        printf '    auth  [success=end default=ignore]  pam_neugaze.so\n'
    fi
}

enable_services() {
    if [ -d /run/systemd/system ]; then
        systemctl daemon-reload
        dbus-send --system --type=method_call \
            --dest=org.freedesktop.DBus /org/freedesktop/DBus \
            org.freedesktop.DBus.ReloadConfig >/dev/null 2>&1 || true
        systemctl restart polkit >/dev/null 2>&1 || true
        systemctl enable --now neugazed
        printf 'enabled and started: neugazed.service\n'
    else
        printf 'NOTE: systemd is not running. Start neugazed manually when ready.\n'
    fi
}

do_install() {
    require_artifacts
    install_binaries
    install_pam_modules
    create_runtime_dirs
    install_config
    install_dbus_policy
    install_polkit_policy
    install_systemd_unit
    install_gnome_extension
    install_gschema
    install_pam_config
    enable_services

    cat <<'EOF'

NeuGaze installed successfully.

Next steps:
  1. Enroll your face:       neugaze enroll
  2. Enable the GNOME extension in GNOME Extensions, then enable face auth in its preferences.
  3. For GDM login face auth, see docs/guide/WIP-pam.md.

To update after rebuilding:
  cargo build --workspace --release
  sudo scripts/neugaze-install.sh install
EOF
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

do_uninstall() {
    pam_dir=$(find_pam_dir 2>/dev/null || true)

    if [ -d /run/systemd/system ]; then
        systemctl disable --now neugazed >/dev/null 2>&1 || true
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi

    for f in \
        "$BIN_DIR/neugazed" \
        "$BIN_DIR/neugaze" \
        "$BIN_DIR/neugaze-gui" \
        "$SYSTEMD_UNIT" \
        "$DBUS_POLICY" \
        "$POLKIT_POLICY" \
        "$SCHEMA_DST" \
        "$PAM_CONFIGS_DIR/neugaze"
    do
        if [ -e "$f" ]; then
            rm -f "$f"
            printf 'removed: %s\n' "$f"
        fi
    done

    if [ -n "$pam_dir" ]; then
        for mod in neugaze-pam.so; do
            f="$pam_dir/$mod"
            if [ -e "$f" ]; then
                rm -f "$f"
                printf 'removed: %s\n' "$f"
            fi
        done
    fi

    if [ -d "$SYSTEM_EXTENSION_DIR" ]; then
        rm -rf "$SYSTEM_EXTENSION_DIR"
        printf 'removed: %s\n' "$SYSTEM_EXTENSION_DIR"
    fi

    if command -v pam-auth-update >/dev/null 2>&1; then
        pam-auth-update --package >/dev/null 2>&1 || true
    fi

    if command -v glib-compile-schemas >/dev/null 2>&1; then
        glib-compile-schemas /usr/share/glib-2.0/schemas >/dev/null 2>&1 || true
    fi

    printf '\nNeuGaze uninstalled.\n'
    printf 'Runtime data is preserved: %s  %s  %s\n' "$CONFIG_DIR" "$STATE_DIR" "$CACHE_DIR"
    printf 'Remove them manually if you want a clean slate:\n'
    printf '  sudo rm -rf %s %s %s\n' "$CONFIG_DIR" "$STATE_DIR" "$CACHE_DIR"
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------

show_status() {
    printf 'repo:   %s\n' "$REPO"
    printf 'target: %s\n' "$TARGET"
    printf '\nInstalled files:\n'
    for f in \
        "$BIN_DIR/neugazed" \
        "$BIN_DIR/neugaze" \
        "$BIN_DIR/neugaze-gui" \
        "$SYSTEMD_UNIT" \
        "$DBUS_POLICY" \
        "$POLKIT_POLICY" \
        "$SCHEMA_DST" \
        "$SYSTEM_EXTENSION_DIR/extension.js" \
        "$CONFIG_DIR/config.toml"
    do
        if [ -e "$f" ]; then
            printf '  present: %s\n' "$f"
        else
            printf '  missing: %s\n' "$f"
        fi
    done

    pam_dir=$(find_pam_dir 2>/dev/null || true)
    if [ -n "$pam_dir" ]; then
        for mod in neugaze-pam.so; do
            f="$pam_dir/$mod"
            if [ -e "$f" ]; then
                printf '  present: %s\n' "$f"
            else
                printf '  missing: %s\n' "$f"
            fi
        done
    fi

    printf '\nService:\n'
    systemctl show neugazed -p ActiveState -p SubState -p ExecStart 2>/dev/null || \
        printf '  systemd not available or neugazed not loaded\n'
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

cmd=${1:-}
case "$cmd" in
    install)
        need_root
        do_install
        ;;
    uninstall)
        need_root
        do_uninstall
        ;;
    status)
        show_status
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
