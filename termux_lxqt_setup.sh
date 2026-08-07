#!/bin/bash
# Termux LXQt Native Desktop Installer
#
# Install:
#   curl -fsSL https://raw.githubusercontent.com/ThanapatFungpharit/termux-lxqt/refs/heads/main/termux_lxqt_setup.sh | bash
if [ -z "${BASH_VERSION:-}" ]; then
    echo "This installer needs bash, not sh. Run it as: curl -fsSL <url> | bash" >&2
    exit 1
fi

set -euo pipefail
IFS=$'\n\t'

readonly VERSION="3.2.0"
readonly LOG_FILE="$HOME/termux_setup.log"
readonly TEMP_DIR=$(mktemp -d)
readonly SCRIPT_START=$(date +%s)

# SSH is always installed (no longer optional)
readonly INSTALL_SSH=true

# Only self-delete if $0 is a real file (not `curl | bash`)
if [[ -f "${0:-}" ]]; then
    readonly SCRIPT_PATH="$(realpath "$0")"
else
    readonly SCRIPT_PATH=""
fi

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

STEP=0
TOTAL_STEPS=11

exec 2>>"$LOG_FILE"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

print_status() {
    local status=$1; shift
    local message="$*"
    case "$status" in
        ok)    echo -e "  ${GREEN}✓${NC} $message" ;;
        warn)  echo -e "  ${YELLOW}!${NC} $message" ;;
        error) echo -e "  ${RED}✗${NC} $message" ;;
        info)  echo -e "  ${CYAN}→${NC} $message" ;;
    esac
    log "[$status] $message"
}

format_duration() {
    local secs=$1
    if [[ $secs -ge 60 ]]; then
        printf '%dm %ds' "$((secs / 60))" "$((secs % 60))"
    else
        printf '%ds' "$secs"
    fi
}

progress_bar() {
    local current=$1 total=$2 width=20
    local filled=$((current * width / total))
    local empty=$((width - filled))
    local bar=""
    [[ $filled -gt 0 ]] && bar=$(printf '%0.s█' $(seq 1 "$filled"))
    [[ $empty -gt 0 ]] && bar+=$(printf '%0.s░' $(seq 1 "$empty"))
    printf '%s' "$bar"
}

print_step() {
    STEP=$((STEP + 1))
    if [[ $STEP -gt 1 ]]; then
        local prev_elapsed=$(( $(date +%s) - STEP_START ))
        print_status ok "Done in $(format_duration "$prev_elapsed")"
    fi
    STEP_START=$(date +%s)
    local pct=$((STEP * 100 / TOTAL_STEPS))
    echo -e "\n${BLUE}┌─────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC} Step ${STEP}/${TOTAL_STEPS}  [$(progress_bar "$STEP" "$TOTAL_STEPS")]  ${pct}%"
    echo -e "${BLUE}│${NC} $*"
    echo -e "${BLUE}└─────────────────────────────────────────┘${NC}"
    log "=== STEP $STEP/$TOTAL_STEPS: $* ==="
}

skip_step() {
    STEP=$((STEP + 1))
    if [[ $STEP -gt 1 ]] && [[ -n "${STEP_START:-}" ]]; then
        local prev_elapsed=$(( $(date +%s) - STEP_START ))
        print_status ok "Done in $(format_duration "$prev_elapsed")"
    fi
    STEP_START=$(date +%s)
    local pct=$((STEP * 100 / TOTAL_STEPS))
    echo -e "\n${BLUE}┌─────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC} Step ${STEP}/${TOTAL_STEPS}  [$(progress_bar "$STEP" "$TOTAL_STEPS")]  ${pct}%"
    echo -e "${BLUE}│${NC} $* ${YELLOW}(skipped — not selected)${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────┘${NC}"
    log "=== STEP $STEP/$TOTAL_STEPS: $* — SKIPPED ==="
}

print_header() {
    echo -e "\n${BLUE}╔═════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  $*"
    echo -e "${BLUE}╚═════════════════════════════════════════╝${NC}\n"
}

die() {
    echo -e "\n${RED}FATAL: $*${NC}"
    log "FATAL: $*"
    exit 1
}

finish() {
    local ret=$?
    rm -rf "$TEMP_DIR"
    termux-wake-unlock 2>/dev/null || true
    if [[ $ret -ne 0 && $ret -ne 130 ]]; then
        echo -e "\n${RED}Installation failed (exit $ret). Check $LOG_FILE for details.${NC}"
        log "Installation failed with exit code $ret"
    fi
}
trap finish EXIT

check_system() {
    print_header "System Compatibility Check"
    local errors=0

    if [[ "$(uname -o 2>/dev/null)" == "Android" ]]; then
        print_status ok "Android $(getprop ro.build.version.release)"
    else
        print_status error "Not running on Android"
        errors=$((errors + 1))
    fi

    local arch
    arch=$(uname -m)
    if [[ "$arch" == "aarch64" ]]; then
        print_status ok "Architecture: $arch"
    else
        print_status error "Unsupported architecture: $arch (requires aarch64)"
        errors=$((errors + 1))
    fi

    if [[ -d "${PREFIX:-}" ]]; then
        print_status ok "Termux PREFIX found: $PREFIX"
    else
        print_status error "Termux PREFIX directory not found"
        errors=$((errors + 1))
    fi

    local free_kb free_human
    free_kb=$(df "$HOME" | awk 'NR==2 {print $4}')
    free_human=$(df -h "$HOME" | awk 'NR==2 {print $4}')
    if [[ $free_kb -gt 4194304 ]]; then
        print_status ok "Free storage: $free_human"
    else
        print_status warn "Low storage: $free_human (4 GB recommended)"
    fi

    local ram_mb
    ram_mb=$(free -m | awk 'NR==2 {print $2}')
    if [[ $ram_mb -gt 2048 ]]; then
        print_status ok "RAM: ${ram_mb} MB"
    else
        print_status warn "Low RAM: ${ram_mb} MB (2 GB recommended)"
    fi

    if [[ $errors -gt 0 ]]; then
        echo -e "\n${RED}Found $errors unmet requirement(s). Cannot continue.${NC}"
        echo "Requirements: Termux from GitHub, ARM64 Android device, 4 GB free, 2 GB RAM"
        return 1
    fi
    echo -e "\n${GREEN}All requirements met.${NC}"
}

pkg_install() {
    local pkgs=("$@")
    local to_install=()
    for p in "${pkgs[@]}"; do
        if ! pkg list-installed 2>/dev/null | grep -q "^${p}/"; then
            to_install+=("$p")
        else
            print_status ok "Already installed: $p"
        fi
    done
    if [[ ${#to_install[@]} -gt 0 ]]; then
        print_status info "Installing: ${to_install[*]}"
        pkg install -y "${to_install[@]}" -o Dpkg::Options::="--force-confold" \
            || die "Failed to install: ${to_install[*]}"
    fi
}

download_if_missing() {
    local url=$1
    local dest=$2
    if [[ -f "$dest" ]]; then
        print_status ok "Already downloaded: $(basename "$dest")"
    else
        mkdir -p "$(dirname "$dest")"
        print_status info "Downloading: $(basename "$dest")"
        wget -q --show-progress -O "$dest" "$url" \
            || die "Failed to download $url"
    fi
}

# Run a command inside the Debian proot as root (proot-distro's default
# login when no --user is given). Used for package management, service
# management, and anything else that needs privileges the created user
# doesn't have.
pd_run() { proot-distro login debian --shared-tmp -- env DISPLAY=:0 "$@"; }

# Same, but as a specific unprivileged user inside the proot.
pd_run_as() {
    local user=$1; shift
    proot-distro login debian --user "$user" --shared-tmp -- env DISPLAY=:0 "$@"
}

setup_base() {
    print_step "Repository & Storage"

    termux-change-repo </dev/tty || die "Failed to change repository"

    if [[ -d ~/storage ]]; then
        print_status ok "Storage access already granted"
    else
        print_status info "Requesting storage access..."
        termux-setup-storage || die "Storage setup failed. Clear Termux data in App Info and retry."
    fi

    local upgradable
    upgradable=$(apt list --upgradable 2>/dev/null | grep -c upgradable || true)
    if [[ "$upgradable" -gt 0 ]]; then
        print_status info "Upgrading $upgradable existing package(s)..."
        pkg upgrade -y -o Dpkg::Options::="--force-confold" \
            || die "Package upgrade failed"
    else
        print_status ok "No package upgrades pending"
    fi

    local props="$HOME/.termux/termux.properties"
    if [[ -f "$props" ]]; then
        sed -i '12s/^#//' "$props"
        print_status ok "termux.properties updated"
    else
        print_status warn "termux.properties not found — skipping"
    fi
}

install_core_deps() {
    print_step "Core Dependencies"
    # Kept intentionally minimal — this is only what's needed to bootstrap
    # and drive the proot itself (proot-distro, the repos its packages need
    # pulled from, wget to fetch it, pulseaudio for the Android audio HAL).
    # git is deliberately absent: it now lives inside the proot and is used
    # from there (see install_utilities), since it has no dependency on
    # anything Termux-specific.
    pkg_install wget proot-distro x11-repo tur-repo pulseaudio
}

install_display_bridge() {
    print_step "Display, GPU & Audio Bridge"
    # LXQt itself now lives inside the Debian proot (install_proot), since
    # that's a full, standard Linux filesystem and package set — more
    # compatible and stable to build a desktop on than Termux's own
    # userland. Everything here is the one thing that genuinely can't
    # move: these talk directly to Android's windowing/GPU/audio HALs,
    # which a proot process has no path to — termux-x11 is the X server
    # itself, and the GPU/Vulkan packages back the relay that gpu_start()
    # spins up for it. Nothing else (shell cosmetics, CLI tools, package
    # managers other than what's needed to run/manage the proot) belongs
    # in Termux — see install_proot for where those actually live now.
    pkg_install \
        termux-x11-nightly \
        virglrenderer-android mesa-vulkan-icd-freedreno-dri3
}

create_directories() {
    print_step "Directory Structure"
    local dirs=(
        "$HOME/Desktop"
        "$HOME/Downloads"
        "$HOME/.fonts"
        "$HOME/.config"
        "$HOME/.config/autostart"
        "$HOME/.config/gtk-3.0"
        "$HOME/.config/lxqt"
        "$HOME/.config/openbox"
        "$HOME/.config/pcmanfm-qt/lxqt"
        "$HOME/.config/qterminal.org"
    )
    for d in "${dirs[@]}"; do
        mkdir -p "$d"
    done
    print_status ok "Directories created"
}

install_themes_and_fonts() {
    print_step "Themes, Icons & Fonts"
    local td="$TEMP_DIR"
    local pids=()

    # All these downloads are independent of each other, so they're kicked
    # off in the background and waited on together instead of one-at-a-time.
    # This turns ~8 sequential network round-trips into roughly the time of
    # the single slowest one. Extraction/install of each archive still
    # happens after its own download finishes, in the "wait" section below.

    if [[ ! -f "$PREFIX/share/backgrounds/termux-desktop/dark_waves.png" ]]; then
        ( download_if_missing \
            "https://raw.githubusercontent.com/phoenixbyrd/Termux_XFCE/main/dark_waves.png" \
            "$PREFIX/share/backgrounds/termux-desktop/dark_waves.png" ) &
        pids+=($!)
    else
        print_status ok "Wallpaper already present"
    fi

    # Orchis is vinceliuice's Material-Design GTK theme — flat, rounded,
    # and built specifically for GNOME-style desktops, unlike the
    # macOS-styled WhiteSur theme this used to ship with.
    if [[ ! -d "$PREFIX/share/themes/Orchis-Dark" ]]; then
        ( download_if_missing \
            "https://raw.githubusercontent.com/vinceliuice/Orchis-theme/master/release/Orchis.tar.xz" \
            "$td/orchis.tar.xz" ) &
        pids+=($!)
    fi

    # Bibata is the compact, minimal cursor set most modern GNOME/KDE
    # setups ship with by default — cleaner and less "Windows-y" than
    # a Fluent-style cursor set.
    if [[ ! -d "$PREFIX/share/icons/Bibata-Modern-Classic" ]]; then
        ( download_if_missing \
            "https://github.com/ful1e5/Bibata_Cursor/releases/download/v2.0.7/Bibata-Modern-Classic.tar.xz" \
            "$td/bibata.tar.xz" ) &
        pids+=($!)
    fi

    if [[ ! -f "$HOME/.fonts/CascadiaMonoPL-Regular.otf" ]]; then
        ( download_if_missing \
            "https://github.com/microsoft/cascadia-code/releases/download/v2111.01/CascadiaCode-2111.01.zip" \
            "$td/cascadia.zip" ) &
        pids+=($!)
    fi

    if [[ ! -f "$HOME/.fonts/MesloLGSNerdFont-Regular.ttf" ]]; then
        ( download_if_missing \
            "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/Meslo.zip" \
            "$td/meslo.zip" ) &
        pids+=($!)
    fi

    # Inter is the clean, neutral UI sans-serif most modern GNOME/KDE
    # distros use for their interface font. Cascadia stays reserved for
    # the terminal only — it was doing double duty as the UI font before,
    # which is part of what made things look less "stock modern desktop."
    if [[ ! -f "$HOME/.fonts/InterVariable.ttf" ]]; then
        ( download_if_missing \
            "https://github.com/rsms/inter/releases/download/v4.0/Inter-4.0.zip" \
            "$td/inter.zip" ) &
        pids+=($!)
    fi

    ( download_if_missing \
        "https://github.com/phoenixbyrd/Termux_XFCE/raw/main/NotoColorEmoji-Regular.ttf" \
        "$HOME/.fonts/NotoColorEmoji-Regular.ttf" ) &
    pids+=($!)

    ( download_if_missing \
        "https://github.com/phoenixbyrd/Termux_XFCE/raw/main/font.ttf" \
        "$HOME/.termux/font.ttf" ) &
    pids+=($!)

    print_status info "Downloading themes and fonts in parallel (${#pids[@]} jobs)..."
    local job_failed=0
    for pid in "${pids[@]}"; do
        wait "$pid" || job_failed=1
    done
    [[ $job_failed -eq 0 ]] || die "One or more theme/font downloads failed — see $LOG_FILE"
    print_status ok "Downloads complete"

    # Extraction/install steps run after their download has landed. Each
    # is still idempotent (skipped if already installed).
    if [[ ! -d "$PREFIX/share/themes/Orchis-Dark" ]]; then
        mkdir -p "$td/orchis" "$PREFIX/share/themes"
        tar -xf "$td/orchis.tar.xz" -C "$td/orchis/"
        mv "$td/orchis/Orchis-Dark" "$PREFIX/share/themes/"
        print_status ok "Orchis-Dark theme installed"
    else
        print_status ok "Orchis-Dark already installed"
    fi

    if [[ ! -d "$PREFIX/share/icons/Bibata-Modern-Classic" ]]; then
        mkdir -p "$PREFIX/share/icons"
        tar -xf "$td/bibata.tar.xz" -C "$PREFIX/share/icons/"
        print_status ok "Bibata-Modern-Classic cursor theme installed"
    else
        print_status ok "Bibata-Modern-Classic already installed"
    fi

    if [[ ! -f "$HOME/.fonts/CascadiaMonoPL-Regular.otf" ]]; then
        unzip -q "$td/cascadia.zip" -d "$td/cascadia/"
        find "$td/cascadia/otf/static" -name "*.otf" -exec mv {} "$HOME/.fonts/" \;
        find "$td/cascadia/ttf"        -name "*.ttf" -exec mv {} "$HOME/.fonts/" \;
        print_status ok "Cascadia Code fonts installed"
    else
        print_status ok "Cascadia Code already installed"
    fi

    if [[ ! -f "$HOME/.fonts/MesloLGSNerdFont-Regular.ttf" ]]; then
        unzip -q "$td/meslo.zip" -d "$td/meslo/"
        find "$td/meslo" -iname "*.ttf" -exec mv {} "$HOME/.fonts/" \;
        [[ -f "$HOME/.fonts/MesloLGSNerdFont-Regular.ttf" ]] || die "MesloLGSNerdFont-Regular.ttf not found in downloaded archive"
        print_status ok "Meslo Nerd Font installed"
    else
        print_status ok "Meslo Nerd Font already installed"
    fi

    if [[ ! -f "$HOME/.fonts/InterVariable.ttf" ]]; then
        unzip -q "$td/inter.zip" -d "$td/inter/"
        find "$td/inter" -iname "InterVariable*.ttf" -exec mv {} "$HOME/.fonts/" \;
        [[ -f "$HOME/.fonts/InterVariable.ttf" ]] || die "InterVariable.ttf not found in downloaded archive"
        print_status ok "Inter UI font installed"
    else
        print_status ok "Inter UI font already installed"
    fi
}

write_openbox_theme() {
    local theme_dir="$PREFIX/share/themes/Modern-Flat-Dark/openbox-3"
    mkdir -p "$theme_dir"
    cat > "$theme_dir/themerc" <<'EOF'
window.active.border.color: #5686D5
window.inactive.border.color: #2B2B2B
window.active.title.bg: Flat Solid
window.active.title.bg.color: #242424
window.inactive.title.bg: Flat Solid
window.inactive.title.bg.color: #1C1C1C
window.active.label.text.color: #E8E8E8
window.inactive.label.text.color: #8A8A8A
window.active.button.unpressed.bg: Flat Solid
window.active.button.unpressed.bg.color: #242424
window.active.button.unpressed.image.color: #E8E8E8
window.inactive.button.unpressed.bg: Flat Solid
window.inactive.button.unpressed.bg.color: #1C1C1C
window.inactive.button.unpressed.image.color: #8A8A8A
window.active.button.hover.bg: Flat Solid
window.active.button.hover.bg.color: #5686D5
window.active.button.hover.image.color: #FFFFFF
window.active.button.pressed.bg: Flat Solid
window.active.button.pressed.bg.color: #3F6BB0
window.handle.width: 0
window.client.padding.width: 0
border.width: 1
padding.width: 0
menu.overlap: 0
window.label.text.justify: left
menu.title.bg: Flat Solid
menu.title.bg.color: #242424
menu.title.text.color: #E8E8E8
menu.items.bg: Flat Solid
menu.items.bg.color: #1C1C1C
menu.items.text.color: #E8E8E8
menu.items.active.bg: Flat Solid
menu.items.active.bg.color: #5686D5
menu.items.active.text.color: #FFFFFF
osd.bg: Flat Solid
osd.bg.color: #242424
osd.border.color: #5686D5
osd.label.text.color: #E8E8E8
EOF
    print_status ok "Modern-Flat-Dark Openbox theme written"
}

write_lxqt_config() {
    print_step "LXQt Configuration"

    write_openbox_theme

    cat > "$HOME/.config/gtk-3.0/settings.ini" <<'EOF'
[Settings]
gtk-theme-name=Orchis-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Bibata-Modern-Classic
gtk-cursor-theme-size=28
gtk-font-name=Inter 10
gtk-application-prefer-dark-theme=1
gtk-decoration-layout=menu:minimize,maximize,close
EOF

    cat > "$HOME/.Xresources" <<'EOF'
Xcursor.theme: Bibata-Modern-Classic
Xcursor.size: 28
Xft.antialias: 1
Xft.hinting: 1
Xft.hintstyle: hintslight
Xft.rgba: rgb
EOF

    cat > "$HOME/.config/qterminal.org/qterminal.ini" <<'EOF'
[General]
useCommonAppearance=false
saveGeometryOnExit=false

[Appearance]
colorScheme=Linux
fontFamily=Cascadia Mono PL
fontSize=12
opacity=90
showTabBarShortcut=false

[Interface]
ShowMenu=false
EOF

    cat > "$HOME/.config/pcmanfm-qt/lxqt/settings.conf" <<'EOF'
[System]
Iconsize=32
[Behavior]
SingleClick=true
[Desktop]
Wallpaper=/data/data/com.termux/files/usr/share/backgrounds/termux-desktop/dark_waves.png
WallpaperMode=stretch
BackgroundColor=#000000
ShowHidden=false
EOF

    cat > "$HOME/.config/pcmanfm-qt/lxqt/desktop-items-0.conf" <<'EOF'
[*]
wallpaper=/data/data/com.termux/files/usr/share/backgrounds/termux-desktop/dark_waves.png
wallpaperMode=stretch
showHidden=false
showMyComputerIcon=false
showTrashIcon=false
showHomeIcon=false
EOF

    cat > "$HOME/.config/openbox/lxqt-rc.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <theme>
    <name>Modern-Flat-Dark</name>
    <titleLayout>LIC</titleLayout>
    <keepBorder>yes</keepBorder>
    <animateIconify>no</animateIconify>
    <font place="ActiveWindow">
      <name>Inter</name>
      <size>10</size>
      <weight>Bold</weight>
      <slant>Normal</slant>
    </font>
    <font place="InactiveWindow">
      <name>Inter</name>
      <size>10</size>
      <weight>Normal</weight>
      <slant>Normal</slant>
    </font>
  </theme>
  <margins>
    <top>0</top>
    <bottom>0</bottom>
    <left>0</left>
    <right>0</right>
  </margins>
</openbox_config>
EOF

    print_status ok "LXQt configuration written"
}

write_desktop_entries() {
    print_step "Desktop Entries"
    mkdir -p "$PREFIX/share/applications"

    cat > "$PREFIX/share/applications/firefox.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Firefox
Exec=firefox-esr %u
Icon=firefox
Categories=Network;WebBrowser;
Terminal=false
StartupNotify=true
EOF

    cat > "$PREFIX/share/applications/kill_termux_x11.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Kill Termux X11
Exec=kill_termux_x11
Icon=system-shutdown
Categories=System;
StartupNotify=false
EOF

    print_status ok "Desktop entries written"
}

write_scripts_and_aliases() {
    print_step "Scripts"
    local username=$1

    cat > "$HOME/.config/gtk-3.0/bookmarks" <<EOF
file:///data/data/com.termux/files/home/Downloads
file:///data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/debian/home/$username Debian Home
file:///data/data/com.termux/files/home/storage/shared/ Android Storage
EOF

    cat > "$PREFIX/bin/start" <<'EOF'
#!/bin/bash
pkill -f "termux.x11" 2>/dev/null || true

termux-wake-lock 2>/dev/null || true

MANUFACTURER=$(getprop ro.product.manufacturer | tr '[:upper:]' '[:lower:]')

if [[ "$MANUFACTURER" == "samsung" ]]; then
    rm -rf ~/.config/pulse
    LD_PRELOAD=/system/lib64/libskcodec.so \
        pulseaudio --start \
            --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
            --exit-idle-time=-1
else
    pulseaudio --start \
        --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
        --exit-idle-time=-1
fi

export PULSE_SERVER=127.0.0.1
export XDG_RUNTIME_DIR="${TMPDIR}/runtime-$(id -u)"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

termux-x11 :0 >/dev/null &
sleep 3
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1
sleep 1

gpu_start() {
    local egl vulkan gpu
    egl=$(getprop ro.hardware.egl)
    vulkan=$(getprop ro.hardware.vulkan)
    gpu=$(echo -e "$egl\n$vulkan" | sort -u | tr '\n' ' ' | sed 's/ $//')

    local common_flags="MESA_NO_ERROR=1 MESA_GL_VERSION_OVERRIDE=4.3COMPAT MESA_GLES_VERSION_OVERRIDE=3.2 LIBGL_DRI3_DISABLE=1"

    if echo "$gpu" | grep -qi "adreno"; then
        echo "GPU: $gpu (Adreno)"
        env $common_flags virgl_test_server_android &>/dev/null &
    elif echo "$gpu" | grep -qi "mali"; then
        echo "GPU: $gpu (Mali)"
        env $common_flags virgl_test_server_android --angle-gl &>/dev/null &
    else
        echo "Unknown GPU: $gpu — aborting" >&2
        exit 1
    fi
}

gpu_start

dbus-daemon --session --address=unix:path="$PREFIX/var/run/dbus-session" &

xrdb -merge "$HOME/.Xresources" 2>/dev/null || true

PROOT_USER=$(basename "$PREFIX"/var/lib/proot-distro/installed-rootfs/debian/home/*)

proot-distro login debian --user "$PROOT_USER" --shared-tmp \
    -b "$PREFIX:$PREFIX" -b "$HOME:$HOME" -b /system:/system -- \
    env \
        HOME="$HOME" \
        DISPLAY=:0 \
        GALLIUM_DRIVER=virpipe \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$PREFIX/var/run/dbus-session" \
        QT_QPA_PLATFORMTHEME=gtk3 \
        XDG_DATA_DIRS="$PREFIX/share:/usr/share" \
        PATH="$PREFIX/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        startlxqt &>/dev/null &

wait
EOF
    chmod +x "$PREFIX/bin/start"

    cat > "$PREFIX/bin/kill_termux_x11" <<'EOF'
#!/bin/bash
am broadcast -a com.termux.x11.ACTION_STOP -p com.termux.x11 >/dev/null 2>&1
pkill -f termux || true
EOF
    chmod +x "$PREFIX/bin/kill_termux_x11"

    for script in prun zrun zrunhud; do
        local extra_env=""
        [[ "$script" == "zrun"    ]] && extra_env="MESA_LOADER_DRIVER_OVERRIDE=zink TU_DEBUG=noconform"
        [[ "$script" == "zrunhud" ]] && extra_env="MESA_LOADER_DRIVER_OVERRIDE=zink TU_DEBUG=noconform GALLIUM_HUD=fps"

        cat > "$PREFIX/bin/$script" <<EOF
#!/bin/bash
varname=\$(basename "\$PREFIX/var/lib/proot-distro/installed-rootfs/debian/home/"*)
proot-distro login debian --user "\$varname" --shared-tmp -- env DISPLAY=:0 $extra_env "\$@"
EOF
        chmod +x "$PREFIX/bin/$script"
    done

    print_status ok "Scripts written"
}

install_utilities() {
    print_step "App Installer & Utilities"
    local username=$1
    local ai_dir="$HOME/.config/App-Installer"

    if [[ ! -d "$ai_dir" ]]; then
        proot-distro login debian --user "$username" --shared-tmp -b "$HOME:$HOME" -- \
            env HOME="$HOME" git clone https://github.com/phoenixbyrd/App-Installer.git "$ai_dir" \
            || die "Failed to clone App-Installer"
        chmod +x "$ai_dir"/*
        print_status ok "App Installer cloned"
    else
        print_status ok "App Installer already present"
    fi

    cat > "$PREFIX/share/applications/app-installer.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=App Installer
Exec=/data/data/com.termux/files/home/.config/App-Installer/app-installer
Icon=package-install
Categories=System;
Terminal=false
StartupNotify=false
EOF
    cp "$PREFIX/share/applications/app-installer.desktop" "$HOME/Desktop/"
    chmod +x "$HOME/Desktop/app-installer.desktop"

    download_if_missing \
        "https://github.com/phoenixbyrd/Termux_XFCE/raw/refs/heads/main/cp2menu" \
        "$PREFIX/bin/cp2menu"
    chmod +x "$PREFIX/bin/cp2menu"

    cat > "$PREFIX/share/applications/cp2menu.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=cp2menu
Exec=cp2menu
Icon=edit-move
Categories=System;
Terminal=false
StartupNotify=false
EOF
    print_status ok "Utilities installed"
}

install_proot() {
    print_step "Debian Proot Environment"
    local username=$1
    local rootfs="$PREFIX/var/lib/proot-distro/installed-rootfs/debian"
    local home="$rootfs/home/$username"

    # A real login is the only thing that actually proves the container is
    # usable — directory paths and `proot-distro list` output are both
    # unreliable proxies for this. Try logging in; only install if that
    # genuinely fails.
    if proot-distro login debian --shared-tmp -- true >/dev/null 2>&1; then
        print_status ok "Debian proot already installed"
    else
        print_status info "Installing Debian proot..."
        proot-distro install debian || die "Failed to install Debian proot — see $LOG_FILE"
        proot-distro login debian --shared-tmp -- true >/dev/null 2>&1 \
            || die "Debian proot installed but login still fails — see $LOG_FILE"
        print_status ok "Debian proot installed"
    fi

    pd_run apt-get update -qq
    # Only upgrade if there's actually something pending — on a freshly
    # bootstrapped proot there rarely is, and this check is much cheaper
    # than a full upgrade pass.
    if [[ "$(pd_run apt-get -s upgrade 2>/dev/null | grep -c '^Inst ')" -gt 0 ]]; then
        pd_run apt-get upgrade -y -qq
    else
        print_status ok "Proot packages already current"
    fi
    # RUNLEVEL=1 tells maintainer scripts they're in a non-booted/chroot-like
    # environment, so they skip hardware probing (udev/hwdb triggers trying
    # to enumerate /sys/bus/usb, which doesn't exist in a proot and otherwise
    # prints "No such file or directory" noise and can leave packages queued
    # after the failing one un-configured).
    pd_run env RUNLEVEL=1 DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends sudo onboard conky-all flameshot firefox-esr \
        tmux curl wget git gnupg eza bat fastfetch openssh-server procps \
        lxqt openbox qterminal pcmanfm-qt obconf-qt pavucontrol-qt \
        qt5-gtk-platformtheme libgl1-mesa-dri mesa-utils \
        papirus-icon-theme fonts-noto-color-emoji \
        -o Dpkg::Options::="--force-confold"

    # Belt-and-braces: if any package's postinst/trigger failed partway
    # through (e.g. the udisks2 USB-scan noise above), this finishes
    # configuring whatever was left half-installed instead of silently
    # leaving packages like sudo un-configured.
    pd_run dpkg --configure -a 2>>"$LOG_FILE" || true

    # Check the actual sudo binary, not just /etc/sudoers — that file can
    # exist on its own (e.g. left over from an earlier reset/partial run)
    # even when the sudo package itself never got installed. --reinstall
    # is also the wrong tool here since it requires apt to think the
    # package is already installed; a plain install is what actually pulls
    # it in if it's missing.
    if ! pd_run bash -c 'command -v sudo' >/dev/null 2>&1; then
        print_status warn "sudo not found in proot — installing it"
        pd_run env RUNLEVEL=1 DEBIAN_FRONTEND=noninteractive apt-get install -y sudo \
            || die "Failed to install sudo — see $LOG_FILE"
        pd_run dpkg --configure -a 2>>"$LOG_FILE" || true
        pd_run bash -c 'command -v sudo' >/dev/null 2>&1 \
            || die "sudo package installed but binary still not found — see $LOG_FILE"
    fi

    pd_run groupadd -f storage
    pd_run groupadd -f wheel
    if pd_run id "$username" >/dev/null 2>&1; then
        print_status ok "Proot user '$username' already exists"
    else
        pd_run useradd -m -g users -G wheel,audio,video,storage -s /bin/bash "$username" \
            || die "Failed to create proot user '$username' — see $LOG_FILE"
        print_status ok "Proot user '$username' created"
    fi

    local sudoers="$rootfs/etc/sudoers"
    if [[ ! -f "$sudoers" ]]; then
        pd_run dpkg --configure -a 2>>"$LOG_FILE" || true
    fi
    [[ -f "$sudoers" ]] || die "sudo package installed but $sudoers is missing — check $LOG_FILE"
    if ! grep -q "^$username " "$sudoers" 2>/dev/null; then
        chmod u+rw "$sudoers"
        echo "$username ALL=(ALL) NOPASSWD:ALL" >> "$sudoers"
        chmod 440 "$sudoers"
        print_status ok "Sudo configured"
    fi

    if [[ -x "$home/.local/bin/uv" ]]; then
        print_status ok "uv already installed in proot"
    else
        print_status info "Installing uv (Python package manager) in proot..."
        if pd_run_as "$username" bash -c "curl -LsSf https://astral.sh/uv/install.sh | sh"; then
            print_status ok "uv installed in proot"
        else
            print_status warn "uv install failed — skipping (run the installer manually later)"
        fi
    fi

    if ! grep -q "DISPLAY" "$home/.bashrc" 2>/dev/null; then
        echo 'export DISPLAY=:0' >> "$home/.bashrc"
    fi

    if ! grep -q "alias ls='eza -F --icons'" "$home/.bashrc" 2>/dev/null; then
        cat >> "$home/.bashrc" <<'BASHRC'

export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export PATH="$HOME/.local/bin:$PATH"

export EDITOR="${EDITOR:-nano}"

case $- in
    *i*)
        ip_addr=$(hostname -I 2>/dev/null | awk '{print $1}')
        [[ -n "$ip_addr" ]] && echo -e "SSH: ssh $USER@$ip_addr -p 8022\n"
        command -v fastfetch >/dev/null && fastfetch
        ;;
esac

alias ls='eza -F --icons'
alias la='eza -AF --icons'
alias ll='eza -lHAF --icons'
alias cat='batcat'

alias bashconfig='$EDITOR ~/.bashrc'
alias ohmybash='$EDITOR ~/.oh-my-bash'
alias troot='cd /data/data/com.termux/files/home'
BASHRC
    fi

    local omb_dir="$home/.oh-my-bash"
    if [[ ! -d "$omb_dir" ]]; then
        print_status info "Installing Oh My Bash..."
        pd_run_as "$username" git clone --depth=1 \
            https://github.com/ohmybash/oh-my-bash.git "$omb_dir" \
            || print_status warn "Oh My Bash clone failed — skipping"
    else
        print_status ok "Oh My Bash already installed"
    fi

    if [[ -d "$omb_dir" ]] && ! grep -q '^export OSH=' "$home/.bashrc" 2>/dev/null; then
        cat >> "$home/.bashrc" <<'BASHRC'

export OSH="$HOME/.oh-my-bash"

completions=(
    git
    composer
    ssh
    uv
    tmux
)

aliases=(
    general
    chmod
)

plugins=(
    git
    bashmarks
)

source "$OSH"/oh-my-bash.sh
BASHRC
        print_status ok "Oh My Bash configuration added"
    fi

    local tz
    tz=$(getprop persist.sys.timezone)
    if [[ -n "$tz" && -f "$rootfs/usr/share/zoneinfo/$tz" ]]; then
        ln -sf "/usr/share/zoneinfo/$tz" "$rootfs/etc/localtime"
        print_status ok "Timezone set to $tz"
    fi

    local mesa_deb="mesa-vulkan-kgsl_24.1.0-devel-20240120_arm64.deb"
    if pd_run dpkg -s mesa-vulkan-kgsl 2>/dev/null | grep -q "^Status:.*installed"; then
        print_status ok "Mesa Vulkan KGSL already installed"
    else
        print_status info "Installing Mesa Vulkan KGSL (hardware acceleration)..."
        local mesa_ok=true

        local sources="$rootfs/etc/apt/sources.list.d/snapshot.list"
        if [[ ! -f "$sources" ]]; then
            echo "deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/20240101T000000Z bookworm main" \
                > "$sources"
            pd_run apt-get update -qq || true
        fi

        pd_run apt-get install -y libllvm15 2>/dev/null \
            || print_status warn "libllvm15 not available from repos — dpkg may still resolve it"

        pd_run wget -q \
            "https://github.com/phoenixbyrd/Termux_XFCE/raw/main/$mesa_deb" \
            -O "/tmp/$mesa_deb" || mesa_ok=false

        if [[ "$mesa_ok" == true ]]; then
            pd_run dpkg -i --force-downgrade "/tmp/$mesa_deb" 2>>"$LOG_FILE" \
                || mesa_ok=false
            pd_run apt-get install -f -y 2>>"$LOG_FILE" \
                || mesa_ok=false
        fi

        if [[ "$mesa_ok" == true ]]; then
            print_status ok "Mesa Vulkan KGSL installed"
        else
            print_status warn "Mesa Vulkan KGSL install failed (see $LOG_FILE) — desktop will still work without it"
        fi
    fi

    mkdir -p "$home/.config"

    cp -r "$PREFIX/share/icons/Bibata-Modern-Classic" "$rootfs/usr/share/icons/" 2>/dev/null || true
    echo 'Xcursor.theme: Bibata-Modern-Classic' > "$home/.Xresources"

    if [[ ! -d "$home/.config/conky" ]]; then
        download_if_missing \
            "https://github.com/phoenixbyrd/Termux_XFCE/raw/main/conky.tar.gz" \
            "$TEMP_DIR/conky.tar.gz"
        tar -xzf "$TEMP_DIR/conky.tar.gz" -C "$TEMP_DIR/"
        mv "$TEMP_DIR/.config/conky" "$home/.config/"
        print_status ok "Conky config installed"
    fi

    local conky_src="$rootfs/usr/share/applications/conky.desktop"
    if [[ -f "$conky_src" ]]; then
        cp "$conky_src" "$HOME/.config/autostart/"
        sed -i 's|^Exec=.*$|Exec=conky -c .config/conky/Alterf/Alterf.conf|' \
            "$HOME/.config/autostart/conky.desktop"
    fi

    local fs_src="$rootfs/usr/share/applications/org.flameshot.Flameshot.desktop"
    if [[ -f "$fs_src" ]]; then
        cp "$fs_src" "$HOME/.config/autostart/"
        sed -i 's|^Exec=.*$|Exec=flameshot|' \
            "$HOME/.config/autostart/org.flameshot.Flameshot.desktop"
    fi

    chmod +x "$HOME/.config/autostart/"*.desktop 2>/dev/null || true
    print_status ok "Proot setup complete"
}

get_local_ip() {
    local ip
    ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}')
    if [[ -z "$ip" ]]; then
        ip=$(ip -4 addr show 2>/dev/null | awk '/inet /{print $2}' | grep -v '^127\.' | cut -d/ -f1 | head -n1)
    fi
    echo "${ip:-unknown}"
}

install_ssh() {
    print_step "SSH Server"
    local username=$1
    local sshd_config="$PREFIX/var/lib/proot-distro/installed-rootfs/debian/etc/ssh/sshd_config"

    pd_run ssh-keygen -A

    if grep -q "^Port " "$sshd_config" 2>/dev/null; then
        sed -i 's/^Port .*/Port 8022/' "$sshd_config"
    elif grep -q "^#Port " "$sshd_config" 2>/dev/null; then
        sed -i 's/^#Port .*/Port 8022/' "$sshd_config"
    else
        echo "Port 8022" >> "$sshd_config"
    fi

    if ! pd_run pgrep -x sshd >/dev/null 2>&1; then
        pd_run /usr/sbin/sshd
        print_status ok "sshd started on port 8022 (inside the Debian proot)"
    else
        print_status ok "sshd already running"
    fi

    local home="$PREFIX/var/lib/proot-distro/installed-rootfs/debian/home/$username"
    if ! grep -q "pgrep -x sshd" "$home/.bashrc" 2>/dev/null; then
        cat >> "$home/.bashrc" <<'BASHRC'

pgrep -x sshd >/dev/null || sudo /usr/sbin/sshd
alias start-sshd='sudo /usr/sbin/sshd'
alias stop-sshd='sudo pkill sshd'
BASHRC
    fi

    echo -e "${YELLOW}Set a password for SSH login (Debian user '$username'):${NC}"
    pd_run_as "$username" passwd </dev/tty || print_status warn "No password set — run 'passwd' later to enable SSH login"

    SSH_LOGIN="$username@$(get_local_ip) -p 8022"
    print_status ok "Connect with: ssh $SSH_LOGIN"
    print_status ok "Lands you in the Debian proot — once inside, use 'start-sshd' / 'stop-sshd' to toggle the server later"
}

main() {
    clear
    print_header "LXQt Desktop Installer v${VERSION}"

    if termux-wake-lock 2>/dev/null; then
        print_status ok "Wake lock acquired (prevents Android OOM kill)"
    else
        print_status warn "termux-wake-lock unavailable — ensure battery optimisation is disabled for Termux"
    fi

    echo -e "${YELLOW}Requirements:${NC}"
    echo "  • Termux from GitHub (not Play Store)"
    echo "  • ARM64 (aarch64) Android device"
    echo "  • termux-x11 installed: https://github.com/termux/termux-x11/releases"
    echo "  • 4 GB free storage, 2 GB RAM recommended"

    check_system || exit 1

    echo -e "\n${GREEN}This installer will set up:${NC}"
    echo "  • A Debian proot environment hosting the LXQt desktop, dev tools,"
    echo "    and SSH server (Firefox, tmux, uv, git, sudo access)"
    echo "  • Termux supplying only the X server, GPU relay, and audio underneath it"
    echo "  • Orchis-Dark theme, Papirus icons, Bibata cursors, Inter/Cascadia fonts"
    echo ""
    echo -e "${YELLOW}Press Enter to continue, or Ctrl+C to cancel.${NC}"
    read -r </dev/tty

    local username=""
    while true; do
        echo -n "Enter username for the Debian proot environment (this is also where LXQt runs): " >/dev/tty
        read -r username </dev/tty
        if [[ -z "$username" ]]; then
            print_status warn "Username cannot be empty. Try again."
            continue
        fi
        if [[ ! "$username" =~ ^[a-z][a-z0-9_]{0,31}$ ]]; then
            print_status warn "Invalid username '$username'. Use lowercase letters, digits, or underscores (max 32 chars)."
            continue
        fi
        break
    done

    setup_base
    install_core_deps
    install_display_bridge
    create_directories
    install_themes_and_fonts
    write_lxqt_config
    write_desktop_entries
    write_scripts_and_aliases "${username:-termux}"

    install_proot "$username"

    install_utilities "$username"

    install_ssh "$username"

    print_status ok "Done in $(format_duration $(( $(date +%s) - STEP_START )))"

    termux-reload-settings

    local total_elapsed=$(( $(date +%s) - SCRIPT_START ))

    clear
    print_header "Setup Complete! (took $(format_duration "$total_elapsed"))"
    echo -e "${GREEN}Available commands:${NC}\n"
    echo -e "  ${YELLOW}start${NC}      — Launch the LXQt desktop (runs inside the Debian proot)"
    echo -e "  ${YELLOW}prun${NC}       — Run a Debian app from Termux, outside the desktop session"
    echo -e "  ${YELLOW}zrun${NC}       — Same as prun, with GPU acceleration (Zink)"
    echo -e "  ${YELLOW}zrunhud${NC}    — Same as zrun + FPS overlay"
    echo -e "  ${CYAN}(all shell config — tmux, uv, Oh My Bash, ls/cat aliases — lives inside the proot; Termux itself has none)${NC}"
    echo ""
    echo -e "${CYAN}SSH:${NC} ssh ${SSH_LOGIN:-<user>@<device-ip> -p 8022}"
    echo -e "  ${YELLOW}start-sshd${NC} / ${YELLOW}stop-sshd${NC} — toggle the SSH server (run these from inside the proot)"
    echo ""
    echo -e "${CYAN}Firefox tip:${NC} Disable hardware acceleration in Firefox settings"
    echo -e "  (Settings → search 'performance' → uncheck Use hardware acceleration)\n"
    echo -e "${YELLOW}Run 'start' to launch your desktop.${NC}\n"
    echo -e "${CYAN}Customize:${NC} right-click the panel → Configure Panel, or open"
    echo -e "  \"Appearance\" from the menu for themes/icons/fonts (obconf-qt is"
    echo -e "  also installed for window-decoration settings).\n"
    echo -e "Log file: ${LOG_FILE}\n"

    if [[ -n "$SCRIPT_PATH" && -f "$SCRIPT_PATH" ]]; then
        rm -f -- "$SCRIPT_PATH"
    fi

    # shellcheck disable=SC1091
    source "$PREFIX/etc/bash.bashrc" 2>/dev/null || true
}

main
