#!/usr/bin/env bash
# =============================================================================
# ia-upload.sh — Internet Archive Uploader for Unraid Media Library
# Main entry point. Sources all library modules and starts the interactive menu.
# =============================================================================

set -euo pipefail

# ── Resolve script directory regardless of where it's called from ─────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Source all library modules ────────────────────────────────────────────────
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/browser.sh"
source "$SCRIPT_DIR/lib/metadata.sh"
source "$SCRIPT_DIR/lib/uploader.sh"

# ── Dependency check ──────────────────────────────────────────────────────────
check_dependencies() {
    local missing=()

    if ! command -v ia &>/dev/null; then
        missing+=("internetarchive (pip install internetarchive)")
    fi

    if ! command -v nano &>/dev/null; then
        missing+=("nano")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        ui_header "Missing Dependencies"
        echo ""
        ui_warn "The following required tools are not installed:"
        for dep in "${missing[@]}"; do
            echo "    ${COLOR_RED}✗${COLOR_RESET}  $dep"
        done
        echo ""
        ui_info "Install them and re-run. Exiting."
        exit 1
    fi
}

# ── IA credentials check ──────────────────────────────────────────────────────
check_ia_credentials() {
    local config_file
    config_file="${HOME}/.config/internetarchive/ia.ini"

    # Also check legacy location
    if [[ ! -f "$config_file" ]]; then
        config_file="${HOME}/.config/ia.ini"
    fi

    if [[ ! -f "$config_file" ]]; then
        ui_header "Internet Archive Login Required"
        echo ""
        ui_warn "No IA credentials found. You need to configure them once."
        echo ""
        ui_info "Running: ia configure"
        echo ""
        ia configure
        echo ""
        ui_success "Credentials saved. Continuing..."
        sleep 1
    fi
}

# ── Unraid server connection check ───────────────────────────────────────────
check_server_connection() {
    # If MEDIA_BASE_PATH is a remote mount, try to confirm it's accessible
    if [[ ! -d "$MEDIA_BASE_PATH" ]]; then
        echo ""
        ui_error "Cannot reach media path: $MEDIA_BASE_PATH"
        ui_warn "Make sure your Unraid server is mounted and the path is correct."
        ui_info "Edit $SCRIPT_DIR/lib/config.sh to update MEDIA_BASE_PATH."
        echo ""

        # Offer to continue anyway (user might want to use a different path)
        ui_prompt "Enter an alternate media path (or press Enter to exit): " alt_path
        if [[ -z "$alt_path" ]] || [[ ! -d "$alt_path" ]]; then
            ui_error "Path not found. Exiting."
            exit 1
        fi

        # Override for this session
        MEDIA_BASE_PATH="$alt_path"
        MOVIES_PATH="$MEDIA_BASE_PATH/Movies"
        TELEVISION_PATH="$MEDIA_BASE_PATH/Television"
    fi
}

# ── Session state tracking ────────────────────────────────────────────────────
SESSION_QUEUED=0       # total items queued this session
SESSION_UPLOADED=0     # total items successfully uploaded
SESSION_FAILED=0       # total items that failed
SESSION_SKIPPED=0      # total items skipped
SESSION_LOG=""         # path to session log file

init_session_log() {
    mkdir -p "$LOG_DIR"
    SESSION_LOG="$LOG_DIR/session_$(date +%Y%m%d_%H%M%S).log"
    touch "$SESSION_LOG"
    log_session "Session started: $(date)"
    log_session "User: ${USER:-unknown}"
    log_session "Media path: $MEDIA_BASE_PATH"
}

log_session() {
    echo "[$(date +%H:%M:%S)] $*" >> "$SESSION_LOG"
}

export -f log_session

# ── Category picker loop ──────────────────────────────────────────────────────
run_category_loop() {
    local done=false

    while [[ "$done" != true ]]; do
        ui_clear
        ui_banner

        echo ""
        ui_info "Session log: $SESSION_LOG"
        echo ""

        # Show session stats if we've done anything
        if (( SESSION_QUEUED > 0 )); then
            echo "  ${COLOR_CYAN}Session stats:${COLOR_RESET}"
            echo "    Queued   : $SESSION_QUEUED"
            echo "    Uploaded : ${COLOR_GREEN}$SESSION_UPLOADED${COLOR_RESET}"
            echo "    Failed   : ${COLOR_RED}$SESSION_FAILED${COLOR_RESET}"
            echo "    Skipped  : ${COLOR_YELLOW}$SESSION_SKIPPED${COLOR_RESET}"
            echo ""
        fi

        ui_divider
        echo ""
        echo "  What would you like to upload?"
        echo ""
        echo "    ${COLOR_CYAN}[1]${COLOR_RESET}  Movies"
        echo "    ${COLOR_CYAN}[2]${COLOR_RESET}  Television"
        echo "    ${COLOR_CYAN}[3]${COLOR_RESET}  View upload queue"
        echo "    ${COLOR_CYAN}[4]${COLOR_RESET}  Process queue now"
        echo "    ${COLOR_CYAN}[5]${COLOR_RESET}  View session log"
        echo "    ${COLOR_CYAN}[q]${COLOR_RESET}  Quit"
        echo ""
        ui_divider

        ui_prompt "Choice: " choice

        case "$choice" in
            1)
                log_session "User selected: Movies"
                run_movies_workflow
                ;;
            2)
                log_session "User selected: Television"
                run_television_workflow
                ;;
            3)
                view_queue
                ;;
            4)
                process_queue
                ;;
            5)
                view_session_log
                ;;
            q|Q|quit|exit)
                done=true
                ;;
            *)
                ui_warn "Invalid choice. Please try again."
                sleep 1
                ;;
        esac
    done
}

# ── View session log ──────────────────────────────────────────────────────────
view_session_log() {
    if [[ -f "$SESSION_LOG" ]]; then
        ui_clear
        ui_header "Session Log"
        echo ""
        cat "$SESSION_LOG"
        echo ""
        ui_pause
    else
        ui_warn "No session log found."
        sleep 1
    fi
}

# ── View current upload queue ─────────────────────────────────────────────────
view_queue() {
    ui_clear
    ui_header "Current Upload Queue"
    echo ""

    local -a queue_files=()
    while IFS= read -r -d $'\0' f; do queue_files+=("$f"); done \
        < <(find "$QUEUE_DIR" -maxdepth 1 -name '*.csv' -print0 2>/dev/null)

    # Check if any CSV files actually exist
    local found=false
    for f in "${queue_files[@]}"; do
        [[ -f "$f" ]] && found=true && break
    done

    if [[ "$found" != true ]]; then
        ui_info "Queue is empty. Add items by selecting Movies or Television."
        echo ""
        ui_pause
        return
    fi

    for csv in "$QUEUE_DIR"/*.csv; do
        [[ -f "$csv" ]] || continue
        local basename
        basename="$(basename "$csv")"
        echo "  ${COLOR_CYAN}$basename${COLOR_RESET}"

        # Show row count minus header
        local count
        count=$(( $(wc -l < "$csv") - 1 ))
        echo "    Items: $count"
        echo ""
    done

    echo ""
    ui_info "Run option [4] from the main menu to begin uploading."
    echo ""
    ui_pause
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    # Initial setup
    check_dependencies
    check_ia_credentials
    check_server_connection
    init_session_log

    # Verify media sub-folders exist
    if [[ ! -d "$MOVIES_PATH" ]] && [[ ! -d "$TELEVISION_PATH" ]]; then
        ui_error "Neither Movies nor Television folder found under: $MEDIA_BASE_PATH"
        ui_info "Expected: $MOVIES_PATH"
        ui_info "Expected: $TELEVISION_PATH"
        exit 1
    fi

    # Run main interaction loop
    run_category_loop

    # Farewell summary
    ui_clear
    ui_header "Session Complete"
    echo ""
    echo "  ${COLOR_GREEN}Uploaded : $SESSION_UPLOADED${COLOR_RESET}"
    echo "  ${COLOR_RED}Failed   : $SESSION_FAILED${COLOR_RESET}"
    echo "  ${COLOR_YELLOW}Skipped  : $SESSION_SKIPPED${COLOR_RESET}"
    echo ""
    ui_info "Full log saved to: $SESSION_LOG"
    echo ""
}

main "$@"
