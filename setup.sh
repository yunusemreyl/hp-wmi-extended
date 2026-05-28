#!/usr/bin/env bash
# setup.sh — Multi-distro installer for hp-wmi-patched
#
# Supports: Debian/Ubuntu, Fedora/RHEL, Arch, openSUSE, Void, Gentoo
# Usage: sudo ./setup.sh [install|uninstall]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

MODNAME="hp-wmi-patched"
MODVER=$(grep -oP 'PACKAGE_VERSION="\K[^"]+' dkms.conf 2>/dev/null || echo "1.5.1")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Shared Machine Owner Key directory for Secure Boot
MOK_DIR="/var/lib/hp-manager/mok"

# ── Kernel version detection ──────────────────────────────────────────────────
# Kernel 7.0+ has Omen/Victus fan control in the stock hp-wmi module.
KVER_MAJOR=$(uname -r | cut -d. -f1)
KVER_MINOR=$(uname -r | cut -d. -f2)
BOARD_NAME=$(cat /sys/devices/virtual/dmi/id/board_name 2>/dev/null | tr '[:lower:]' '[:upper:]' || echo "")
FORCE_CUSTOM_HPWMI=false

# Some boards still require the patched hp-wmi path even on kernel 7.0+.
case "$BOARD_NAME" in
    8D41) FORCE_CUSTOM_HPWMI=true ;; # OMEN Max 16
esac

STOCK_FAN_SUPPORT=false
if [ "$KVER_MAJOR" -gt 7 ] || { [ "$KVER_MAJOR" -eq 7 ] && [ "$KVER_MINOR" -ge 0 ]; }; then
    STOCK_FAN_SUPPORT=true
fi
if $FORCE_CUSTOM_HPWMI; then
    STOCK_FAN_SUPPORT=false
fi

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Distro detection ──────────────────────────────────────────────────────────

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_LIKE="${ID_LIKE:-$DISTRO_ID}"
    elif [ -f /etc/arch-release ]; then
        DISTRO_ID="arch"
        DISTRO_LIKE="arch"
    elif [ -f /etc/gentoo-release ]; then
        DISTRO_ID="gentoo"
        DISTRO_LIKE="gentoo"
    else
        DISTRO_ID="unknown"
        DISTRO_LIKE="unknown"
    fi
}

# ── Dependency installation per distro ────────────────────────────────────────

install_deps() {
    info "Detected distro: ${DISTRO_ID}"

    case "$DISTRO_ID" in
        ubuntu|debian|linuxmint|pop|elementary|zorin|kali)
            info "Installing dependencies (apt)..."
            apt-get update -qq
            apt-get install -y dkms build-essential linux-headers-"$(uname -r)"
            ;;
        fedora|nobara)
            info "Installing dependencies (dnf)..."
            dnf install -y dkms kernel-devel kernel-headers gcc make
            ;;
        rhel|centos|rocky|alma)
            info "Installing dependencies (dnf/yum)..."
            if command -v dnf &>/dev/null; then
                dnf install -y dkms kernel-devel kernel-headers gcc make
            else
                yum install -y dkms kernel-devel kernel-headers gcc make
            fi
            ;;
        arch|manjaro|endeavouros|garuda|cachyos)
            info "Installing dependencies (pacman)..."
            local HEADERS_PKG=""
            local RUNNING_KVER
            RUNNING_KVER=$(uname -r)

            if [[ $RUNNING_KVER == *"-cachyos"* ]]; then
                local SUFFIX
                SUFFIX=$(echo "$RUNNING_KVER" | sed 's/^[0-9.]*-[0-9]*-\(.*\)/\1/')
                if [[ -n "$SUFFIX" ]] && pacman -Si "linux-$SUFFIX-headers" &>/dev/null 2>&1; then
                    HEADERS_PKG="linux-$SUFFIX-headers"
                elif pacman -Si linux-cachyos-headers &>/dev/null 2>&1; then
                    HEADERS_PKG="linux-cachyos-headers"
                else
                    HEADERS_PKG="linux-headers"
                fi
            elif [[ $RUNNING_KVER == *"-zen"* ]]; then
                HEADERS_PKG="linux-zen-headers"
            elif [[ $RUNNING_KVER == *"-lts"* ]]; then
                HEADERS_PKG="linux-lts-headers"
            elif [[ $RUNNING_KVER == *"-hardened"* ]]; then
                HEADERS_PKG="linux-hardened-headers"
            elif [[ $RUNNING_KVER == *"-rt"* ]]; then
                HEADERS_PKG="linux-rt-headers"
            else
                HEADERS_PKG="linux-headers"
            fi

            info "Attempting to install: dkms $HEADERS_PKG base-devel"
            if ! pacman -S --needed --noconfirm dkms "$HEADERS_PKG" base-devel; then
                warn "Could not install $HEADERS_PKG. Trying generic linux-headers..."
                pacman -S --needed --noconfirm dkms linux-headers base-devel \
                    || warn "Header installation failed. DKMS might not work without headers."
            fi
            ;;
        opensuse*|suse*)
            info "Installing dependencies (zypper)..."
            zypper install -y dkms kernel-devel kernel-default-devel gcc make
            ;;
        void)
            info "Installing dependencies (xbps)..."
            xbps-install -Sy dkms linux-headers base-devel
            ;;
        gentoo)
            info "Gentoo detected. Ensure sys-kernel/dkms and linux-headers are installed."
            command -v dkms &>/dev/null || error "dkms not found. Install it with: emerge sys-kernel/dkms"
            ;;
        *)
            case "$DISTRO_LIKE" in
                *debian*|*ubuntu*)
                    info "Debian-like distro detected, using apt..."
                    apt-get update -qq
                    apt-get install -y dkms build-essential linux-headers-"$(uname -r)"
                    ;;
                *fedora*|*rhel*)
                    info "Fedora-like distro detected, using dnf..."
                    dnf install -y dkms kernel-devel kernel-headers gcc make
                    ;;
                *arch*)
                    info "Arch-like distro detected, using pacman..."
                    pacman -S --needed --noconfirm dkms linux-headers base-devel
                    ;;
                *suse*)
                    info "SUSE-like distro detected, using zypper..."
                    zypper install -y dkms kernel-devel kernel-default-devel gcc make
                    ;;
                *)
                    warn "Unknown distro '${DISTRO_ID}'. Attempting generic install..."
                    warn "Make sure you have installed: dkms, gcc, make, kernel-headers"
                    command -v dkms &>/dev/null || error "dkms not found. Please install it manually."
                    ;;
            esac
            ;;
    esac
}

# ── Helper: find module path in both /lib and /usr/lib ───────────────────────

find_module_paths() {
    local pattern="$1"
    local kver="${2:-$(uname -r)}"
    find \
        "/lib/modules/$kver" \
        "/usr/lib/modules/$kver" \
        -name "$pattern" 2>/dev/null | sort -u
}

# ── Install ───────────────────────────────────────────────────────────────────

do_install() {
    [[ $EUID -ne 0 ]] && error "This script must be run as root (use sudo)."
    local ORIG_WMI=""

    detect_distro
    install_deps

    if $FORCE_CUSTOM_HPWMI; then
        warn "Board ${BOARD_NAME:-unknown} detected — forcing custom hp-wmi install path on kernel $(uname -r)."
    fi

    if $STOCK_FAN_SUPPORT; then
        warn "Kernel $(uname -r) detected (>= 7.0) — stock hp-wmi already has fan control."
        warn "You may not need this patched driver. Press Ctrl+C to abort, or wait 5 seconds to proceed anyway..."
        sleep 5
    fi

    # Detect Clang-built kernel and set LLVM=1 automatically
    if grep -iq "clang" /proc/version; then
        info "Kernel built with Clang/LLVM detected. Automatically setting LLVM=1 for build..."
        export LLVM=1
    fi

    cd "$SCRIPT_DIR"

    # Clean up old DKMS entries for this specific module name
    if dkms status "$MODNAME" 2>/dev/null | grep -q "$MODNAME"; then
        warn "Removing existing DKMS entries for $MODNAME..."
        for v in $(dkms status "$MODNAME" | head -n 1 | grep -oP '(?<='"$MODNAME"'[/, ])[^,:]+' | tr -d ' '); do
            [ -z "$v" ] && continue
            dkms remove -m "$MODNAME" -v "$v" --all 2>/dev/null || true
        done
    fi

    rm -rf "/usr/src/${MODNAME}-${MODVER}"
    mkdir -p "/usr/src/${MODNAME}-${MODVER}"

    # Copy source files into the DKMS tree
    cp "$SCRIPT_DIR/dkms.conf" "$SCRIPT_DIR/Makefile" "$SCRIPT_DIR"/*.c \
       "/usr/src/${MODNAME}-${MODVER}/"
    cp "$SCRIPT_DIR"/*.h "/usr/src/${MODNAME}-${MODVER}/" 2>/dev/null || true

    info "Checking for stock hp-wmi driver path..."
    ORIG_WMI=$(modinfo -n hp-wmi 2>/dev/null || true)
    if [[ -n "$ORIG_WMI" ]] && [[ -f "$ORIG_WMI" ]] && [[ ! "$ORIG_WMI" == *"updates"* ]] && [[ ! "$ORIG_WMI" == *"dkms"* ]]; then
        info "Stock driver detected at: $ORIG_WMI"
    else
        ORIG_WMI=""
    fi

    # Install via DKMS
    info "Installing via DKMS..."
    if ! dkms status "$MODNAME/$MODVER" 2>/dev/null | grep -Eq "^${MODNAME}/${MODVER}([,:]|$)"; then
        dkms add -m "$MODNAME" -v "$MODVER" || true
    else
        info "DKMS source already present for $MODNAME/$MODVER, skipping dkms add."
    fi
    dkms build   -m "$MODNAME" -v "$MODVER"          || error "DKMS build failed. Check logs."
    dkms install -m "$MODNAME" -v "$MODVER" --force   || error "DKMS install failed."

    # Refresh module dependency database so modprobe picks up the new .ko
    depmod -a

    # After DKMS install succeeds, archive stock hp-wmi so the DKMS module wins consistently.
    if [[ -n "$ORIG_WMI" ]] && [[ -f "$ORIG_WMI" ]]; then
        if [[ ! -f "${ORIG_WMI}.backup" ]]; then
            info "Backing up stock driver: $ORIG_WMI"
            mv "$ORIG_WMI" "${ORIG_WMI}.backup"
        else
            info "Stock backup already exists: ${ORIG_WMI}.backup"
        fi
    fi

    # ── Secure Boot handling ─────────────────────────────────────────────────
    SECUREBOOT=false
    if command -v mokutil &>/dev/null; then
        if mokutil --sb-state 2>/dev/null | grep -qi "SecureBoot enabled"; then
            SECUREBOOT=true
        fi
    fi

    if $SECUREBOOT; then
        mkdir -p "$MOK_DIR"

        # Generate MOK key if missing (shared with other drivers under /var/lib/hp-manager/mok)
        if [ ! -f "$MOK_DIR/MOK.priv" ] || [ ! -f "$MOK_DIR/MOK.der" ]; then
            info "Generating MOK key for Secure Boot..."
            openssl req -new -x509 -newkey rsa:2048 \
                -keyout "$MOK_DIR/MOK.priv" \
                -outform DER -out "$MOK_DIR/MOK.der" \
                -days 36500 -subj "/CN=hp-manager-mok/" -nodes 2>/dev/null
            chmod 600 "$MOK_DIR/MOK.priv"
        else
            ok "Using existing MOK key from $MOK_DIR"
        fi

        # Sign installed modules
        KVER=$(uname -r)
        info "Signing custom module for Secure Boot..."
        SIGN_SCRIPT=$(find \
            "/usr/src/linux-headers-$KVER/scripts" \
            "/usr/src/kernels/$KVER/scripts" \
            "/lib/modules/$KVER/build/scripts" \
            "/usr/lib/modules/$KVER/build/scripts" \
            -name "sign-file" -type f 2>/dev/null | head -n 1)

        if [ -n "$SIGN_SCRIPT" ]; then
            MOD_PATH=$(find_module_paths "hp-wmi.ko" "$KVER" | grep -v "backup" | head -n 1)
            if [ -n "$MOD_PATH" ]; then
                "$SIGN_SCRIPT" sha256 "$MOK_DIR/MOK.priv" "$MOK_DIR/MOK.der" "$MOD_PATH" \
                    || warn "Failed to sign hp-wmi.ko"
            fi
        else
            warn "sign-file script not found! Module could not be signed. Secure Boot may block it."
        fi

        # Enrol MOK if not yet enrolled
        if mokutil --test-key "$MOK_DIR/MOK.der" 2>/dev/null | grep -qi "not enrolled"; then
            info "Enrolling MOK key..."
            MOK_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16 || true)
            printf "%s\n%s\n" "$MOK_PASSWORD" "$MOK_PASSWORD" | mokutil --import "$MOK_DIR/MOK.der" 2>/dev/null \
                || warn "Failed to import MOK key."

            echo ""
            echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
            echo -e "${YELLOW}║  🔒 Secure Boot is ENABLED                                ║${NC}"
            echo -e "${YELLOW}║                                                           ║${NC}"
            echo -e "${YELLOW}║  A Machine Owner Key (MOK) has been registered to sign    ║${NC}"
            echo -e "${YELLOW}║  the custom driver.                                       ║${NC}"
            echo -e "${YELLOW}║                                                           ║${NC}"
            echo -e "${YELLOW}║  ${RED}PLEASE REBOOT YOUR SYSTEM NOW.${YELLOW}                           ║${NC}"
            echo -e "${YELLOW}║  Upon reboot, a blue 'Perform MOK management' screen      ║${NC}"
            echo -e "${YELLOW}║  will appear. Follow these exact steps:                   ║${NC}"
            echo -e "${YELLOW}║                                                           ║${NC}"
            echo -e "${YELLOW}║  1. Select 'Enroll MOK'                                   ║${NC}"
            echo -e "${YELLOW}║  2. Select 'Continue'                                     ║${NC}"
            echo -e "${YELLOW}║  3. Select 'Yes'                                          ║${NC}"
            echo -e "${YELLOW}║  4. Enter password: ${GREEN}${MOK_PASSWORD}${YELLOW}$(printf '%*s' $((27 - ${#MOK_PASSWORD})) '')║${NC}"
            echo -e "${YELLOW}║  5. Select 'Reboot'                                       ║${NC}"
            echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}"
            echo ""
            warn "Skipping module load. The module will load automatically after MOK enrollment."
        else
            ok "MOK key is already enrolled."
        fi
    fi

    # ── Load module ──────────────────────────────────────────────────────────
    MOK_PENDING=false
    if $SECUREBOOT && mokutil --test-key "$MOK_DIR/MOK.der" 2>/dev/null | grep -qi "not enrolled"; then
        MOK_PENDING=true
    fi

    if $MOK_PENDING; then
        info "MOK enrollment pending — skipping module load until reboot."
    else
        info "Loading custom hp-wmi module..."
        modprobe -r hp_wmi 2>/dev/null || true
        if modprobe hp_wmi 2>/dev/null; then
            ok "Custom hp-wmi loaded successfully"
        else
            warn "Custom hp-wmi could not be loaded — check: dmesg | tail -20"
        fi
    fi

    echo ""
    info "The module will be automatically rebuilt on kernel updates via DKMS."
    info "Fan control: /sys/devices/platform/hp-wmi/hwmon/hwmon*/pwm1_enable"
    info "Fan speed:   /sys/devices/platform/hp-wmi/hwmon/hwmon*/fan*_target"
    echo ""
}

# ── Uninstall ─────────────────────────────────────────────────────────────────

do_uninstall() {
    [[ $EUID -ne 0 ]] && error "This script must be run as root (use sudo)."

    info "Unloading custom hp-wmi module..."
    modprobe -r hp_wmi 2>/dev/null || true

    info "Removing DKMS entry..."
    if dkms status "$MODNAME/$MODVER" 2>/dev/null | grep -q "$MODNAME"; then
        dkms remove -m "$MODNAME" -v "$MODVER" --all
        rm -rf "/usr/src/${MODNAME}-${MODVER}"
        ok "Uninstalled successfully."
    else
        warn "DKMS entry not found. Nothing to remove."
    fi

    # Restore original driver backups
    info "Restoring original driver backups (if any)..."
    KVER=$(uname -r)
    FOUND_BACKUP=false

    while IFS= read -r BU_FILE; do
        ORIG_FILE="${BU_FILE%.backup}"
        info "Restoring $ORIG_FILE from backup..."
        mv "$BU_FILE" "$ORIG_FILE"
        FOUND_BACKUP=true
    done < <(find_module_paths "hp-wmi.ko*.backup" "$KVER")

    if [ "$FOUND_BACKUP" = true ]; then
        depmod -a
        info "Reloading original hp-wmi module..."
        modprobe hp_wmi 2>/dev/null || warn "Could not reload original hp-wmi module."
    else
        info "No backup found — skipping restore."
    fi
}

usage() {
    echo "Usage: sudo $0 [install|uninstall]"
    echo ""
    echo "  install      Build and install the custom hp-wmi module via DKMS"
    echo "  uninstall    Remove the custom module and restore the original stock module"
    echo ""
    echo "If no argument is given, 'install' is assumed."
}

case "${1:-install}" in
    install)   do_install ;;
    uninstall) do_uninstall ;;
    -h|--help) usage ;;
    *)         usage; exit 1 ;;
esac
