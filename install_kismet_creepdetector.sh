#!/usr/bin/env bash
# install_kismet_creepdetector.sh
# Automates Kismet + creepdetector plugin setup on Raspberry Pi OS
# Run as root/sudo

set -euo pipefail

echo "=== Kismet + creepdetector plugin auto-installer ==="
echo "This script assumes Raspberry Pi OS (Bookworm or similar)."
echo "It will install Kismet from official packages, add the creepdetector plugin,"
echo "and prompt for reboot at the end."
echo ""

# ────────────────────────────────────────────────
# 1. Stop Kismet if running
# ────────────────────────────────────────────────
if systemctl is-active --quiet kismet; then
    echo "Stopping Kismet service..."
    systemctl stop kismet
else
    echo "Kismet service not running (or not installed yet)."
fi

# ────────────────────────────────────────────────
# 2. Add Kismet repository (safe re-run; checks if already present)
# ────────────────────────────────────────────────
echo "Adding/Updating Kismet repository..."

KEYRING="/usr/share/keyrings/kismet-archive-keyring.gpg"
LISTFILE="/etc/apt/sources.list.d/kismet.list"

if [[ ! -f "$KEYRING" ]]; then
    echo "Downloading Kismet signing key..."
    wget -O - https://www.kismetwireless.net/repos/kismet-release.gpg.asc \
        | gpg --dearmor | tee "$KEYRING" > /dev/null
else
    echo "Kismet keyring already exists."
fi

REPO_LINE='deb [signed-by=/usr/share/keyrings/kismet-archive-keyring.gpg] https://www.kismetwireless.net/repos/apt/release/bookworm bookworm main'

if ! grep -qF "kismetwireless.net" "$LISTFILE" 2>/dev/null; then
    echo "Adding repo line to $LISTFILE..."
    echo "$REPO_LINE" | tee "$LISTFILE"
else
    echo "Kismet repo already in sources.list.d."
fi

# ────────────────────────────────────────────────
# 3. Update package lists & install Kismet
# ────────────────────────────────────────────────
echo "Updating apt cache..."
apt update -qq

echo "Installing Kismet core + Wi-Fi capture support..."
# Install core + linux-wifi (most common); add others like bluetooth if needed later
apt install -y kismet-core kismet-capture-linux-wifi

# Optional: install more capture tools if you know you'll need them
# apt install -y kismet-capture-linux-bluetooth kismet-capture-rz-killerbee ...

# ────────────────────────────────────────────────
# 4. Add current user to kismet group (for non-root access)
# ────────────────────────────────────────────────
CURRENT_USER="${SUDO_USER:-$USER}"
if ! groups "$CURRENT_USER" | grep -q '\bkismet\b'; then
    echo "Adding user '$CURRENT_USER' to group 'kismet'..."
    usermod -aG kismet "$CURRENT_USER"
    echo "Group added. A logout/login or reboot is required for this to take effect."
else
    echo "User '$CURRENT_USER' already in kismet group."
fi

# ────────────────────────────────────────────────
# 5. Install build tools + git if missing
# ────────────────────────────────────────────────
echo "Ensuring build tools are installed..."
apt install -y git build-essential pkg-config

# ────────────────────────────────────────────────
# 6. Install creepdetector plugin (user install)
# ────────────────────────────────────────────────
PLUGIN_DIR="/home/$CURRENT_USER/plugin-kismet-creepdetector"

if [[ -d "$PLUGIN_DIR" ]]; then
    echo "Plugin directory already exists. Pulling latest..."
    cd "$PLUGIN_DIR"
    git pull || echo "Git pull failed (maybe not a git repo?). Continuing anyway."
else
    echo "Cloning creepdetector plugin..."
    cd "/home/$CURRENT_USER"
    git clone https://github.com/hobobandy/plugin-kismet-creepdetector.git
    cd plugin-kismet-creepdetector
fi

echo "Building & user-installing plugin..."
make userinstall

echo ""
echo "Plugin installed to ~/.kismet/plugins/creepdetector/"
echo "You can later tweak settings in:"
echo "~/.kismet/plugins/creepdetector/httpd/js/creepdetector.js"
echo ""

# ────────────────────────────────────────────────
# 7. Final instructions & reboot prompt
# ────────────────────────────────────────────────
echo "=== Setup complete! ==="
echo ""
echo "Next steps:"
echo "  1. Log out and back in (or reboot) so the 'kismet' group change takes effect."
echo "  2. Start Kismet with your capture interface, e.g.:"
echo "       kismet -c wlan1mon"
echo "     or enable the systemd service: sudo systemctl enable --now kismet"
echo "  3. Open http://localhost:2501 (or Pi's IP:2501) in browser"
echo "  4. Look for the new 'Creepdetector' tab at the bottom."
echo ""

read -p "Reboot now to apply group changes? (recommended) [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Rebooting in 5 seconds... (Ctrl+C to cancel)"
    sleep 5
    reboot
else
    echo "Skipping reboot. Remember to log out/in or reboot later."
fi

echo "Done!"
