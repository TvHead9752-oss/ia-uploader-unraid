#!/usr/bin/env bash
# =============================================================================
# lib/ui.sh — Terminal UI Helpers
# All display functions: banners, prompts, spinners, progress bars, menus.
# =============================================================================

# ── Screen control ────────────────────────────────────────────────────────────
ui_clear() {
    clear
}

ui_pause() {
    echo ""
    read -r -p "  Press Enter to continue..."
    echo ""
}

# ── Dividers and spacing ──────────────────────────────────────────────────────
ui_divider() {
    local char="${1:─}"
    local width="${TERM_WIDTH:-72}"
    printf "  "
    printf '%0.s─' $(seq 1 $((width - 2)))
    echo ""
}

ui_thin_divider() {
    local width="${TERM_WIDTH:-72}"
    printf "  "
    printf '%0.s·' $(seq 1 $((width - 2)))
    echo ""
}

# ── Banner and headers ────────────────────────────────────────────────────────
ui_banner() {
    echo ""
    echo -e "  ${COLOR_BOLD_CYAN}╔══════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "  ${COLOR_BOLD_CYAN}║${COLOR_RESET}         ${COLOR_BOLD}Internet Archive — Media Uploader${COLOR_RESET}         ${COLOR_BOLD_CYAN}║${COLOR_RESET}"
    echo -e "  ${COLOR_BOLD_CYAN}║${COLOR_RESET}    ${COLOR_DIM}Unraid Torrents → archive.org bulk upload${COLOR_RESET}    ${COLOR_BOLD_CYAN}║${COLOR_RESET}"
    echo -e "  ${COLOR_BOLD_CYAN}╚══════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""
}

ui_header() {
    local title="$1"
    local width="${TERM_WIDTH:-72}"
    echo ""
    ui_divider
    # Center the title
    local pad=$(( (width - ${#title} - 4) / 2 ))
    printf "  "
    printf '%0.s ' $(seq 1 $pad)
    echo -e "${COLOR_BOLD}${title}${COLOR_RESET}"
    ui_divider
    echo ""
}

ui_section() {
    local title="$1"
    echo ""
    echo -e "  ${COLOR_BOLD_CYAN}▸ ${title}${COLOR_RESET}"
    ui_thin_divider
    echo ""
}

# ── Status messages ───────────────────────────────────────────────────────────
ui_info() {
    echo -e "  ${COLOR_CYAN}ℹ${COLOR_RESET}  $*"
}

ui_success() {
    echo -e "  ${COLOR_GREEN}✔${COLOR_RESET}  $*"
}

ui_warn() {
    echo -e "  ${COLOR_YELLOW}⚠${COLOR_RESET}  $*"
}

ui_error() {
    echo -e "  ${COLOR_RED}✖${COLOR_RESET}  $*" >&2
}

ui_step() {
    echo -e "  ${COLOR_MAGENTA}→${COLOR_RESET}  $*"
}

# ── Prompts ───────────────────────────────────────────────────────────────────
# Usage: ui_prompt "Label: " varname
ui_prompt() {
    local label="$1"
    local -n _result_ref=$2
    local default="${3:-}"

    if [[ -n "$default" ]]; then
        printf "  %s${COLOR_DIM}[%s]${COLOR_RESET} " "$label" "$default"
    else
        printf "  %s" "$label"
    fi

    read -r _result_ref
    # Apply default if empty
    if [[ -z "$_result_ref" ]] && [[ -n "$default" ]]; then
        _result_ref="$default"
    fi
}

# Yes/no prompt — returns 0 for yes, 1 for no
# Usage: if ui_confirm "Are you sure?"; then ...
ui_confirm() {
    local msg="$1"
    local default="${2:-y}"
    local answer

    if [[ "$default" == "y" ]]; then
        printf "  %s ${COLOR_DIM}[Y/n]${COLOR_RESET} " "$msg"
    else
        printf "  %s ${COLOR_DIM}[y/N]${COLOR_RESET} " "$msg"
    fi

    read -r answer
    answer="${answer:-$default}"
    [[ "${answer,,}" =~ ^y ]]
}

# Numbered menu prompt
# Usage: ui_menu_prompt "Choose:" options_array varname
ui_menu_prompt() {
    local label="$1"
    shift
    local -n _opts=$1
    shift
    local -n _menu_result=$1

    echo ""
    local i=1
    for opt in "${_opts[@]}"; do
        echo -e "    ${COLOR_CYAN}[$i]${COLOR_RESET}  $opt"
        (( i++ ))
    done
    echo ""
    ui_prompt "$label" _menu_result
}

# ── Spinner ───────────────────────────────────────────────────────────────────
SPINNER_PID=""
SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

ui_spinner_start() {
    local msg="${1:-Working...}"
    (
        local i=0
        while true; do
            printf "\r  ${COLOR_CYAN}%s${COLOR_RESET}  %s " "${SPINNER_FRAMES[$i]}" "$msg"
            (( i = (i + 1) % ${#SPINNER_FRAMES[@]} ))
            sleep 0.08
        done
    ) &
    SPINNER_PID=$!
    disown "$SPINNER_PID" 2>/dev/null || true
}

ui_spinner_stop() {
    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
        printf "\r\033[K"  # Clear the spinner line
    fi
}

# ── Progress bar ──────────────────────────────────────────────────────────────
# Usage: ui_progress_bar current total label
ui_progress_bar() {
    local current="$1"
    local total="$2"
    local label="${3:-}"
    local bar_width=40
    local filled=0
    local pct=0

    if (( total > 0 )); then
        pct=$(( current * 100 / total ))
        filled=$(( current * bar_width / total ))
    fi

    local bar=""
    local i
    for (( i=0; i<bar_width; i++ )); do
        if (( i < filled )); then
            bar+="█"
        else
            bar+="░"
        fi
    done

    printf "\r  ${COLOR_CYAN}[%s]${COLOR_RESET} %3d%%  %s/%s  %s" \
        "$bar" "$pct" "$current" "$total" "$label"
}

ui_progress_done() {
    echo ""  # newline after progress bar
}

# ── Upload status line ────────────────────────────────────────────────────────
ui_upload_status() {
    local status="$1"    # "ok" | "fail" | "skip" | "start"
    local name="$2"
    local extra="${3:-}"

    case "$status" in
        start)
            echo -e "\n  ${COLOR_CYAN}↑${COLOR_RESET}  ${COLOR_BOLD}$name${COLOR_RESET}"
            ;;
        ok)
            echo -e "  ${COLOR_GREEN}✔${COLOR_RESET}  $name ${COLOR_DIM}$extra${COLOR_RESET}"
            ;;
        fail)
            echo -e "  ${COLOR_RED}✖${COLOR_RESET}  $name ${COLOR_RED}$extra${COLOR_RESET}"
            ;;
        skip)
            echo -e "  ${COLOR_YELLOW}–${COLOR_RESET}  $name ${COLOR_DIM}(skipped)${COLOR_RESET}"
            ;;
    esac
}

# ── File size formatter ───────────────────────────────────────────────────────
ui_format_size() {
    local bytes="$1"
    if (( bytes >= 1073741824 )); then
        printf "%.1f GB" "$(echo "scale=1; $bytes / 1073741824" | bc)"
    elif (( bytes >= 1048576 )); then
        printf "%.1f MB" "$(echo "scale=1; $bytes / 1048576" | bc)"
    elif (( bytes >= 1024 )); then
        printf "%.1f KB" "$(echo "scale=1; $bytes / 1024" | bc)"
    else
        printf "%d B" "$bytes"
    fi
}

# ── Multi-select checkbox menu ────────────────────────────────────────────────
# Usage: ui_checkbox_menu items_array selected_indices_array_name
# Returns selected indices (0-based) in the named array
ui_checkbox_menu() {
    local -n _items=$1
    local -n _selected=$2
    local title="${3:-Select items (Space=toggle, A=all, N=none, Enter=done)}"
    local total=${#_items[@]}
    local page_size="${BROWSER_PAGE_SIZE:-20}"
    local page=0
    local cursor=0
    local total_pages=$(( (total + page_size - 1) / page_size ))

    # Initialize selection state array
    local -a sel_state
    for (( i=0; i<total; i++ )); do
        sel_state[$i]=0
    done

    # Pre-select already selected items
    for idx in "${_selected[@]}"; do
        [[ -n "$idx" ]] && sel_state[$idx]=1
    done

    while true; do
        ui_clear
        ui_header "$title"

        local start=$(( page * page_size ))
        local end=$(( start + page_size ))
        (( end > total )) && end=$total

        echo -e "  ${COLOR_DIM}Page $((page+1))/$total_pages  ·  Items $((start+1))–$end of $total${COLOR_RESET}"
        echo ""

        local i
        for (( i=start; i<end; i++ )); do
            local marker="  "
            local hl_start=""
            local hl_end=""

            # Highlight cursor position
            if (( i == cursor )); then
                hl_start="${COLOR_BOLD_CYAN}"
                hl_end="${COLOR_RESET}"
                marker="${COLOR_CYAN}▶${COLOR_RESET} "
            fi

            # Checkbox state
            local box="${COLOR_DIM}☐${COLOR_RESET}"
            if (( sel_state[i] == 1 )); then
                box="${COLOR_GREEN}☑${COLOR_RESET}"
            fi

            printf "  %s%s %-3s %s%s\n" \
                "$marker" "$box" "$((i+1))." "${hl_start}${_items[$i]}${hl_end}"
        done

        echo ""
        ui_thin_divider
        echo ""
        echo -e "  ${COLOR_DIM}↑/↓ or j/k=move  Space=toggle  A=select all  N=none  PgDn/PgUp=page  Enter=done${COLOR_RESET}"
        echo ""

        # Read single keypress
        local key
        IFS= read -r -s -n1 key

        # Handle escape sequences (arrow keys)
        if [[ "$key" == $'\x1b' ]]; then
            local seq
            IFS= read -r -s -n2 -t 0.1 seq
            key="${key}${seq}"
        fi

        case "$key" in
            $'\x1b[A'|k|K)   # Up arrow or k
                (( cursor > 0 )) && (( cursor-- ))
                # Page back if cursor went above
                if (( cursor < page * page_size )); then
                    (( page > 0 )) && (( page-- ))
                fi
                ;;
            $'\x1b[B'|j|J)   # Down arrow or j
                (( cursor < total - 1 )) && (( cursor++ ))
                # Page forward if cursor went below
                if (( cursor >= (page + 1) * page_size )); then
                    (( page < total_pages - 1 )) && (( page++ ))
                fi
                ;;
            $'\x1b[6~'|' '*)  # Page Down — only trigger on actual PgDn
                if [[ "$key" == $'\x1b[6~' ]]; then
                    (( page < total_pages - 1 )) && (( page++ ))
                    cursor=$(( page * page_size ))
                else
                    # Space — toggle current item
                    if (( sel_state[cursor] == 0 )); then
                        sel_state[$cursor]=1
                    else
                        sel_state[$cursor]=0
                    fi
                fi
                ;;
            $'\x1b[5~')  # Page Up
                (( page > 0 )) && (( page-- ))
                cursor=$(( page * page_size ))
                ;;
            a|A)  # Select all
                for (( i=0; i<total; i++ )); do sel_state[$i]=1; done
                ;;
            n|N)  # Select none
                for (( i=0; i<total; i++ )); do sel_state[$i]=0; done
                ;;
            ' ')  # Space — toggle (fallback)
                if (( sel_state[cursor] == 0 )); then
                    sel_state[$cursor]=1
                else
                    sel_state[$cursor]=0
                fi
                ;;
            '')   # Enter
                break
                ;;
        esac
    done

    # Build return array of selected 0-based indices
    _selected=()
    for (( i=0; i<total; i++ )); do
        if (( sel_state[i] == 1 )); then
            _selected+=("$i")
        fi
    done
}

# ── Metadata preview display ──────────────────────────────────────────────────
ui_show_metadata() {
    local -n _meta=$1

    echo ""
    ui_section "Metadata Preview"

    local fields=(
        "title" "identifier" "description" "date" "creator"
        "language" "mediatype" "collection" "source_url"
        "host_institution" "publisher" "subject_tags"
    )

    for field in "${fields[@]}"; do
        local val="${_meta[$field]:-}"
        if [[ -n "$val" ]]; then
            printf "  ${COLOR_CYAN}%-18s${COLOR_RESET}  %s\n" "$field" "$val"
        fi
    done

    # Show file path
    if [[ -n "${_meta[local_filepath]:-}" ]]; then
        printf "  ${COLOR_CYAN}%-18s${COLOR_RESET}  %s\n" "local_filepath" "${_meta[local_filepath]}"
    fi

    echo ""
}

# ── Genre picker (numbered list with multi-select) ────────────────────────────
ui_pick_genres() {
    local -n _genre_list=$1
    local -n _genre_result=$2

    echo ""
    echo -e "  ${COLOR_CYAN}Available Genres:${COLOR_RESET}"
    echo ""

    local i=1
    for g in "${_genre_list[@]}"; do
        printf "    ${COLOR_DIM}%2d.${COLOR_RESET} %-20s" "$i" "$g"
        (( i % 3 == 0 )) && echo ""
        (( i++ ))
    done
    (( (i-1) % 3 != 0 )) && echo ""

    echo ""
    ui_prompt "Enter genre numbers (space-separated, e.g. 1 4 7): " genre_input

    _genre_result=()
    for num in $genre_input; do
        if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 )) && (( num <= ${#_genre_list[@]} )); then
            _genre_result+=("${_genre_list[$((num-1))]}")
        fi
    done
}
