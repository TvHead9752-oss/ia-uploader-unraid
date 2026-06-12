#!/usr/bin/env bash
# =============================================================================
# setup.sh — One-time setup and installation script
# Run this once to install dependencies, configure credentials, and set up
# the shell alias so you can run the tool with a single command.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALIAS_NAME="${IA_ALIAS_NAME:-ia-upload}"

# ── ANSI colors (inline since config.sh may not be sourced yet) ───────────────
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[32m"
C_CYAN="\033[36m"
C_YELLOW="\033[33m"
C_RED="\033[31m"
C_DIM="\033[2m"

info()    { echo -e "  ${C_CYAN}ℹ${C_RESET}  $*"; }
success() { echo -e "  ${C_GREEN}✔${C_RESET}  $*"; }
warn()    { echo -e "  ${C_YELLOW}⚠${C_RESET}  $*"; }
err()     { echo -e "  ${C_RED}✖${C_RESET}  $*" >&2; }
step()    { echo -e "\n  ${C_BOLD}${C_CYAN}▸ $*${C_RESET}"; echo ""; }
divider() { printf "  "; printf '%0.s─' $(seq 1 68); echo ""; }

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo ""
echo -e "  ${C_BOLD}${C_CYAN}╔══════════════════════════════════════════════════╗${C_RESET}"
echo -e "  ${C_BOLD}${C_CYAN}║${C_RESET}       ${C_BOLD}IA Media Uploader — Setup Script${C_RESET}         ${C_BOLD}${C_CYAN}║${C_RESET}"
echo -e "  ${C_BOLD}${C_CYAN}╚══════════════════════════════════════════════════╝${C_RESET}"
echo ""
divider
echo ""
info "This script will:"
echo ""
echo "    1.  Check and install required dependencies"
echo "    2.  Configure your Internet Archive credentials"
echo "    3.  Set your Unraid media path"
echo "    4.  Create the '${ALIAS_NAME}' shell alias"
echo "    5.  Make all scripts executable"
echo ""
divider
echo ""
read -r -p "  Press Enter to continue (Ctrl+C to cancel)..."
echo ""

# ── Step 1: Check Python / pip ────────────────────────────────────────────────
step "Step 1: Python & pip"

PYTHON_CMD=""
for cmd in python3 python; do
    if command -v "$cmd" &>/dev/null; then
        PYTHON_CMD="$cmd"
        break
    fi
done

if [[ -z "$PYTHON_CMD" ]]; then
    err "Python 3 is not installed."
    warn "On Unraid, install the NerdTools / NerdPack plugin and install python3."
    warn "Or install via: pip3 install internetarchive  (if pip is available)"
    echo ""
    read -r -p "  Press Enter to continue anyway, or Ctrl+C to abort..."
else
    PY_VERSION="$("$PYTHON_CMD" --version 2>&1)"
    success "Found: $PY_VERSION  ($PYTHON_CMD)"
fi

# ── Step 2: Install internetarchive CLI ───────────────────────────────────────
step "Step 2: internetarchive (ia) CLI"

if command -v ia &>/dev/null; then
    IA_VERSION="$(ia --version 2>&1 || echo 'unknown')"
    success "Already installed: ia  ($IA_VERSION)"
    echo ""
    read -r -p "  Reinstall/upgrade? [y/N]: " reinstall
    if [[ "${reinstall,,}" == "y" ]]; then
        info "Upgrading..."
        pip3 install --upgrade internetarchive 2>&1 | tail -5
    fi
else
    info "Installing internetarchive..."
    if command -v pip3 &>/dev/null; then
        pip3 install internetarchive 2>&1 | tail -10
    elif command -v pip &>/dev/null; then
        pip install internetarchive 2>&1 | tail -10
    else
        err "pip not found. Cannot auto-install."
        warn "Manually run: pip3 install internetarchive"
        echo ""
        read -r -p "  Press Enter to continue (ia CLI required for uploads)..."
    fi

    if command -v ia &>/dev/null; then
        success "internetarchive installed successfully."
    else
        err "Installation may have failed. Ensure 'ia' is in your PATH."
        warn "Common fix: export PATH=\"\$PATH:\$HOME/.local/bin\""
    fi
fi

# ── Step 3: Check nano ────────────────────────────────────────────────────────
step "Step 3: nano editor"

if command -v nano &>/dev/null; then
    success "nano is available."
else
    warn "nano not found. Install it via your system's package manager."
    echo ""
    echo "    Debian/Ubuntu : sudo apt-get install nano"
    echo "    CentOS/RHEL   : sudo yum install nano"
    echo "    Alpine        : apk add nano"
    echo "    Unraid        : Available via NerdTools plugin"
    echo ""
    read -r -p "  Press Enter to continue (nano required for metadata editing)..."
fi

# ── Step 4: Configure IA credentials ─────────────────────────────────────────
step "Step 4: Internet Archive credentials"

IA_CONFIG_A="${HOME}/.config/internetarchive/ia.ini"
IA_CONFIG_B="${HOME}/.config/ia.ini"

if [[ -f "$IA_CONFIG_A" ]] || [[ -f "$IA_CONFIG_B" ]]; then
    success "Credentials already configured."
    echo ""
    read -r -p "  Re-configure credentials? [y/N]: " reconf
    if [[ "${reconf,,}" == "y" ]]; then
        ia configure
    fi
else
    info "No credentials found. Let's set them up."
    echo ""
    echo -e "  ${C_DIM}You need a free account at https://archive.org/account/login${C_RESET}"
    echo ""
    ia configure
    echo ""
    if [[ -f "$IA_CONFIG_A" ]] || [[ -f "$IA_CONFIG_B" ]]; then
        success "Credentials saved."
    else
        warn "Credentials may not have saved. Check manually."
    fi
fi

# ── Step 5: Configure media path ─────────────────────────────────────────────
step "Step 5: Unraid media path"

CONFIG_FILE="$SCRIPT_DIR/lib/config.sh"

# Read current value from config
CURRENT_PATH="$(grep 'MEDIA_BASE_PATH=' "$CONFIG_FILE" | head -1 | sed 's/.*:-//' | tr -d '"}')"

echo -e "  Current media path: ${C_CYAN}$CURRENT_PATH${C_RESET}"
echo ""
echo -e "  ${C_DIM}This should be the path to your Torrents share on Unraid.${C_RESET}"
echo -e "  ${C_DIM}Examples:${C_RESET}"
echo "    /mnt/user/Torrents          (if running on the Unraid box itself)"
echo "    /mnt/unraid/Torrents        (if mounted via NFS on another machine)"
echo "    /mnt/smb/Torrents           (if mounted via Samba/SMB)"
echo ""
read -r -p "  Enter media path (or Enter to keep current): " new_path

if [[ -n "$new_path" ]]; then
    if [[ -d "$new_path" ]]; then
        # Update config.sh in place
        sed -i "s|MEDIA_BASE_PATH=.*|MEDIA_BASE_PATH=\"\${IA_MEDIA_PATH:-${new_path}}\"|" "$CONFIG_FILE"
        sed -i "s|MOVIES_PATH=.*|MOVIES_PATH=\"$new_path/Movies\"|" "$CONFIG_FILE"
        sed -i "s|TELEVISION_PATH=.*|TELEVISION_PATH=\"$new_path/Television\"|" "$CONFIG_FILE"
        success "Media path updated to: $new_path"
    else
        warn "Path does not exist: $new_path"
        warn "Config not changed. Edit lib/config.sh manually if needed."
    fi
else
    info "Media path unchanged: $CURRENT_PATH"
fi

# Check Movies/Television sub-folders
echo ""
local_movies="${new_path:-$CURRENT_PATH}/Movies"
local_tv="${new_path:-$CURRENT_PATH}/Television"

if [[ -d "$local_movies" ]]; then
    local mc
    mc="$(find "$local_movies" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
    success "Movies folder found  ($mc sub-folders)"
else
    warn "Movies folder not found: $local_movies"
fi

if [[ -d "$local_tv" ]]; then
    local tc
    tc="$(find "$local_tv" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
    success "Television folder found  ($tc sub-folders)"
else
    warn "Television folder not found: $local_tv"
fi

# ── Step 6: Make scripts executable ──────────────────────────────────────────
step "Step 6: File permissions"

chmod +x "$SCRIPT_DIR/ia-upload.sh"
chmod +x "$SCRIPT_DIR/setup.sh"

for lib_file in "$SCRIPT_DIR/lib/"*.sh; do
    chmod +x "$lib_file"
    success "Executable: $lib_file"
done

# ── Step 7: Shell alias ───────────────────────────────────────────────────────
step "Step 7: Shell alias"

SHELL_NAME="$(basename "${SHELL:-bash}")"
SHELL_RC=""

case "$SHELL_NAME" in
    bash)
        if [[ -f "$HOME/.bashrc" ]]; then
            SHELL_RC="$HOME/.bashrc"
        elif [[ -f "$HOME/.bash_profile" ]]; then
            SHELL_RC="$HOME/.bash_profile"
        fi
        ;;
    zsh)
        SHELL_RC="$HOME/.zshrc"
        ;;
    fish)
        SHELL_RC="$HOME/.config/fish/config.fish"
        ;;
    *)
        SHELL_RC="$HOME/.profile"
        ;;
esac

ALIAS_LINE="alias ${ALIAS_NAME}='${SCRIPT_DIR}/ia-upload.sh'"

# Check if alias already exists
if [[ -n "$SHELL_RC" ]] && grep -q "alias ${ALIAS_NAME}=" "$SHELL_RC" 2>/dev/null; then
    success "Alias '${ALIAS_NAME}' already exists in $SHELL_RC"
else
    echo -e "  Detected shell: ${C_CYAN}$SHELL_NAME${C_RESET}"
    echo -e "  Shell config  : ${C_CYAN}${SHELL_RC:-not found}${C_RESET}"
    echo ""
    echo -e "  Alias to add:"
    echo -e "    ${C_CYAN}${ALIAS_LINE}${C_RESET}"
    echo ""

    read -r -p "  Add alias to $SHELL_RC? [Y/n]: " add_alias
    if [[ "${add_alias,,}" != "n" ]]; then
        if [[ -n "$SHELL_RC" ]]; then
            {
                echo ""
                echo "# Internet Archive Media Uploader — added by setup.sh"
                echo "$ALIAS_LINE"
            } >> "$SHELL_RC"
            success "Alias added to $SHELL_RC"
            info "Run: source $SHELL_RC  (or open a new terminal)"
        else
            warn "Could not determine shell config file."
            info "Add this line manually to your shell config:"
            echo ""
            echo "    $ALIAS_LINE"
        fi
    else
        info "Alias not added automatically."
        echo ""
        echo "  Add this manually to your shell config:"
        echo ""
        echo "    $ALIAS_LINE"
    fi
fi

# ── Optional: Add to PATH instead ────────────────────────────────────────────
echo ""
echo -e "  ${C_DIM}Optional: You can also add this to your PATH instead of using an alias:${C_RESET}"
echo "    export PATH=\"\$PATH:$SCRIPT_DIR\""
echo ""

# ── Optional: SSH alias (if running remotely) ─────────────────────────────────
echo -e "  ${C_DIM}Optional: Add to ~/.ssh/config or .bashrc on your local machine to SSH+run:${C_RESET}"
echo "    alias ${ALIAS_NAME}='ssh your-unraid-user@your-unraid-ip ${SCRIPT_DIR}/ia-upload.sh'"
echo ""

# ── Step 8: Final summary ─────────────────────────────────────────────────────
divider
echo ""
echo -e "  ${C_BOLD}${C_GREEN}Setup complete!${C_RESET}"
echo ""
echo "  To start uploading:"
echo ""
echo -e "    ${C_CYAN}source ${SHELL_RC:-~/.bashrc}${C_RESET}   ← reload your shell config"
echo -e "    ${C_CYAN}${ALIAS_NAME}${C_RESET}              ← launch the uploader"
echo ""
echo "  Or run directly:"
echo ""
echo -e "    ${C_CYAN}${SCRIPT_DIR}/ia-upload.sh${C_RESET}"
echo ""
divider
echo ""
echo -e "  ${C_DIM}Config file : $SCRIPT_DIR/lib/config.sh${C_RESET}"
echo -e "  ${C_DIM}Queue files : $SCRIPT_DIR/queue/${C_RESET}"
echo -e "  ${C_DIM}Upload logs : $SCRIPT_DIR/logs/${C_RESET}"
echo ""
