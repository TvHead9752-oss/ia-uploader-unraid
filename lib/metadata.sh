#!/usr/bin/env bash
# =============================================================================
# lib/metadata.sh — Metadata Collection & CSV Row Building
# Handles interactive metadata prompts, nano editing, preview, and CSV output.
# =============================================================================

# ── Escape a value for CSV (wrap in quotes, escape internal quotes) ───────────
csv_escape() {
    local val="$1"
    # Wrap in double quotes; escape any internal double quotes by doubling them
    val="${val//\"/\"\"}"
    echo "\"${val}\""
}

# ── Guess year from folder/filename ──────────────────────────────────────────
guess_year() {
    local name="$1"
    # Match (YYYY) pattern common in Plex/Jellyfin naming
    if [[ "$name" =~ \(([12][0-9]{3})\) ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$name" =~ ([12][0-9]{3}) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# ── Guess show name from folder name ─────────────────────────────────────────
guess_title_from_path() {
    local name="$1"
    # Remove trailing (YEAR)
    name="$(echo "$name" | sed 's/ *([0-9]\{4\})$//')"
    # Remove common quality tags
    name="$(echo "$name" | sed 's/\.\(720p\|1080p\|2160p\|4K\|BluRay\|WEBRip\|HDTV\|x264\|x265\|HEVC\).*//i')"
    # Replace dots/underscores with spaces
    name="$(echo "$name" | tr '._' ' ')"
    echo "$name"
}

# ── Guess episode info from filename ─────────────────────────────────────────
# Returns: season_num episode_num episode_title_guess
guess_episode_info() {
    local filename="$1"
    local base="${filename%.*}"

    local season_num=""
    local episode_num=""

    # Pattern: S01E02 or S1E2
    if [[ "$base" =~ [Ss]([0-9]{1,2})[Ee]([0-9]{1,3}) ]]; then
        season_num="${BASH_REMATCH[1]#0}"   # strip leading zero
        episode_num="${BASH_REMATCH[2]#0}"
    # Pattern: 1x02
    elif [[ "$base" =~ ([0-9]{1,2})x([0-9]{1,3}) ]]; then
        season_num="${BASH_REMATCH[1]#0}"
        episode_num="${BASH_REMATCH[2]#0}"
    fi

    echo "$season_num $episode_num"
}

# ── Language picker ───────────────────────────────────────────────────────────
pick_language() {
    local -n _lang_result=$1
    echo ""
    echo -e "  ${COLOR_CYAN}Common Languages:${COLOR_RESET}"
    echo ""
    for entry in "${LANGUAGE_NAMES[@]}"; do
        local num="${entry%%=*}"
        local name="${entry##*=}"
        printf "    ${COLOR_DIM}%2d.${COLOR_RESET} %-15s" "$num" "$name"
        (( num % 4 == 0 )) && echo ""
    done
    echo ""
    echo ""
    echo -e "  ${COLOR_DIM}Enter a number above, or type an ISO 639-2 code directly (e.g. eng, spa, fra)${COLOR_RESET}"
    ui_prompt "Language [eng]: " lang_input "eng"

    if [[ "$lang_input" =~ ^[0-9]+$ ]]; then
        _lang_result="${LANGUAGE_CODES[$lang_input]:-eng}"
    else
        _lang_result="${lang_input:-eng}"
    fi
}

# ── Open nano for free-text editing of a field ───────────────────────────────
edit_in_nano() {
    local field_name="$1"
    local -n _nano_result=$2
    local current_val="${3:-}"

    local tmpfile
    tmpfile="$(mktemp /tmp/ia-meta-XXXXXX.txt)"

    # Write current value + instructions
    {
        echo "$current_val"
        echo ""
        echo "# ── Instructions ─────────────────────────────────────────────"
        echo "# Field: $field_name"
        echo "# Edit the text above this line. Lines starting with # are ignored."
        echo "# Save and exit nano when done: Ctrl+X → Y → Enter"
    } > "$tmpfile"

    nano "$tmpfile"

    # Read back, strip comment lines, trim trailing whitespace/newlines
    _nano_result="$(grep -v '^#' "$tmpfile" | sed '/^[[:space:]]*$/d' | sed 's/[[:space:]]*$//')"
    rm -f "$tmpfile"
}

# =============================================================================
# MOVIE METADATA COLLECTION
# =============================================================================

collect_movie_metadata() {
    local movie_dir="$1"
    local primary_video="$2"
    local -n _movie_meta=$3

    local dirname
    dirname="$(basename "$movie_dir")"
    local guessed_title
    guessed_title="$(guess_title_from_path "$dirname")"
    local guessed_year
    guessed_year="$(guess_year "$dirname")"
    local video_filename
    video_filename="$(basename "$primary_video")"

    ui_section "Basic Information"

    # Title
    ui_prompt "Title: " title_input "$guessed_title"
    _movie_meta[title]="$title_input"

    # Year / Date
    ui_prompt "Year: " year_input "$guessed_year"
    _movie_meta[date]="$year_input"

    # Director / Creator
    ui_prompt "Director (optional): " creator_input ""
    _movie_meta[creator]="$creator_input"

    # Genres
    ui_section "Genre"
    local -a chosen_genres=()
    ui_pick_genres MOVIE_GENRES chosen_genres
    _movie_meta[genres]="$(IFS=';'; echo "${chosen_genres[*]}")"

    # Rating
    ui_section "Rating"
    echo ""
    local ri=1
    for r in "${MOVIE_RATINGS[@]}"; do
        printf "    ${COLOR_CYAN}[%d]${COLOR_RESET} %-10s" "$ri" "$r"
        (( ri % 4 == 0 )) && echo ""
        (( ri++ ))
    done
    echo ""
    echo ""
    ui_prompt "Rating number [leave blank to skip]: " rating_input ""
    if [[ "$rating_input" =~ ^[0-9]+$ ]] && (( rating_input >= 1 && rating_input <= ${#MOVIE_RATINGS[@]} )); then
        _movie_meta[rating]="${MOVIE_RATINGS[$((rating_input-1))]}"
    fi

    # Language
    ui_section "Language"
    local lang_code=""
    pick_language lang_code
    _movie_meta[language]="$lang_code"

    # Description
    ui_section "Description"
    echo -e "  ${COLOR_DIM}A brief summary of the film. Press Enter to open nano, or type directly.${COLOR_RESET}"
    echo ""

    local default_desc="$title_input"
    [[ -n "${_movie_meta[date]}" ]] && default_desc+=" (${_movie_meta[date]})"
    [[ -n "${_movie_meta[creator]}" ]] && default_desc+=". Directed by ${_movie_meta[creator]}."
    if [[ -n "${_movie_meta[genres]}" ]]; then
        default_desc+=". Genre(s): ${_movie_meta[genres]/;/, }."
    fi
    [[ -n "${_movie_meta[rating]}" ]] && default_desc+=" Rated ${_movie_meta[rating]}."

    echo -e "  ${COLOR_DIM}[n] Open in nano  [Enter] Use auto-generated  [t] Type here${COLOR_RESET}"
    ui_prompt "Description option [Enter]: " desc_choice ""

    case "${desc_choice,,}" in
        n)
            edit_in_nano "description" desc_val "$default_desc"
            _movie_meta[description]="$desc_val"
            ;;
        t)
            ui_prompt "Description: " desc_val ""
            _movie_meta[description]="$desc_val"
            ;;
        *)
            _movie_meta[description]="$default_desc"
            ;;
    esac

    # Source URL (optional)
    ui_section "Source & Rights"
    ui_prompt "Source URL (optional, e.g. IMDB link): " src_url ""
    _movie_meta[source_url]="$src_url"

    ui_prompt "License URL (optional, leave blank for none): " lic_url ""
    _movie_meta[licenseurl]="$lic_url"

    # Additional subject tags
    ui_section "Subject Tags"
    echo -e "  ${COLOR_DIM}Default tags: ${IA_DEFAULT_SUBJECTS[*]}${COLOR_RESET}"
    ui_prompt "Add extra subject tags (space-separated, optional): " extra_tags ""
    _movie_meta[extra_tags]="$extra_tags"

    # Build the identifier
    local id_base="${_movie_meta[title]}"
    [[ -n "${_movie_meta[date]}" ]] && id_base+=" ${_movie_meta[date]}"
    _movie_meta[identifier]="$(build_identifier "$id_base")"

    # Set fixed fields
    _movie_meta[mediatype]="$IA_MOVIE_MEDIATYPE"
    _movie_meta[collection]="$IA_DEFAULT_COLLECTION"
    _movie_meta[publisher]="$IA_PUBLISHER"
    _movie_meta[local_filepath]="$primary_video"
    _movie_meta[remote_filepath]="$video_filename"

    # Preview + confirm
    show_metadata_preview_movie _movie_meta

    local proceed
    while true; do
        echo ""
        echo -e "  ${COLOR_CYAN}[a]${COLOR_RESET} Accept  ${COLOR_CYAN}[e]${COLOR_RESET} Edit in nano  ${COLOR_CYAN}[s]${COLOR_RESET} Skip this item  ${COLOR_CYAN}[q]${COLOR_RESET} Back to menu"
        ui_prompt "Action: " proceed "a"

        case "${proceed,,}" in
            a)
                break
                ;;
            e)
                edit_metadata_in_nano _movie_meta
                show_metadata_preview_movie _movie_meta
                ;;
            s)
                _movie_meta[_skip]="1"
                break
                ;;
            q)
                _movie_meta[_skip]="1"
                break
                ;;
        esac
    done
}

# ── Movie metadata preview ────────────────────────────────────────────────────
show_metadata_preview_movie() {
    local -n _pm=$1
    ui_clear
    ui_header "Metadata Preview — ${_pm[title]:-Untitled}"

    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Identifier"   "${_pm[identifier]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Title"        "${_pm[title]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Year"         "${_pm[date]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Director"     "${_pm[creator]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Genres"       "${_pm[genres]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Rating"       "${_pm[rating]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Language"     "${_pm[language]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Mediatype"    "${_pm[mediatype]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Collection"   "${_pm[collection]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Publisher"    "${_pm[publisher]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Source URL"   "${_pm[source_url]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "License URL"  "${_pm[licenseurl]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Extra Tags"   "${_pm[extra_tags]:-}"
    echo ""
    echo -e "  ${COLOR_DIM}Description:${COLOR_RESET}"
    echo ""
    # Word-wrap description at ~70 chars
    echo "${_pm[description]:-}" | fold -s -w 68 | sed 's/^/    /'
    echo ""
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "File"         "$(basename "${_pm[local_filepath]:-}")"
}

# =============================================================================
# TV SHOW METADATA COLLECTION
# =============================================================================

collect_show_metadata() {
    local show_name="$1"
    local season_name="$2"
    local -n _show_meta=$3

    local guessed_title
    guessed_title="$(guess_title_from_path "$show_name")"

    ui_section "Show Information"

    # Show title
    ui_prompt "Show title: " show_title_input "$guessed_title"
    _show_meta[show_title]="$show_title_input"

    # Network / broadcaster
    echo ""
    echo -e "  ${COLOR_DIM}Common networks: $(IFS=', '; echo "${COMMON_NETWORKS[*]:0:12}"...)${COLOR_RESET}"
    ui_prompt "Network / broadcaster (optional): " network_input ""
    _show_meta[network]="$network_input"

    # Year(s) aired
    ui_prompt "Year(s) aired (e.g. 1994 or 1994-2004): " years_input ""
    _show_meta[date]="$years_input"

    # Genres
    ui_section "Genre"
    local -a chosen_genres=()
    ui_pick_genres TV_GENRES chosen_genres
    _show_meta[genres]="$(IFS=';'; echo "${chosen_genres[*]}")"

    # Rating
    ui_section "TV Rating"
    echo ""
    local ri=1
    for r in "${TV_RATINGS[@]}"; do
        printf "    ${COLOR_CYAN}[%d]${COLOR_RESET} %-10s" "$ri" "$r"
        (( ri++ ))
    done
    echo ""
    echo ""
    ui_prompt "Rating number [leave blank to skip]: " rating_input ""
    if [[ "$rating_input" =~ ^[0-9]+$ ]] && (( rating_input >= 1 && rating_input <= ${#TV_RATINGS[@]} )); then
        _show_meta[rating]="${TV_RATINGS[$((rating_input-1))]}"
    fi

    # Language
    ui_section "Language"
    local lang_code=""
    pick_language lang_code
    _show_meta[language]="$lang_code"

    # Show-level description
    ui_section "Show Description"
    echo -e "  ${COLOR_DIM}Brief description of the show (reused for all episodes).${COLOR_RESET}"
    echo ""
    echo -e "  ${COLOR_DIM}[n] Open in nano  [Enter] Skip for now  [t] Type here${COLOR_RESET}"
    ui_prompt "Description option [Enter]: " desc_choice ""

    case "${desc_choice,,}" in
        n)
            edit_in_nano "show description" desc_val ""
            _show_meta[show_description]="$desc_val"
            ;;
        t)
            ui_prompt "Show description: " desc_val ""
            _show_meta[show_description]="$desc_val"
            ;;
        *)
            _show_meta[show_description]=""
            ;;
    esac

    # Source URL (e.g. IMDB)
    ui_section "Source & Rights"
    ui_prompt "Source URL (e.g. IMDB, optional): " src_url ""
    _show_meta[source_url]="$src_url"

    ui_prompt "License URL (optional): " lic_url ""
    _show_meta[licenseurl]="$lic_url"

    # Extra tags
    ui_section "Subject Tags"
    echo -e "  ${COLOR_DIM}Default tags: ${IA_DEFAULT_SUBJECTS[*]}${COLOR_RESET}"
    ui_prompt "Add extra subject tags (space-separated, optional): " extra_tags ""
    _show_meta[extra_tags]="$extra_tags"

    # Fixed fields
    _show_meta[mediatype]="$IA_TV_MEDIATYPE"
    _show_meta[collection]="$IA_DEFAULT_COLLECTION"
    _show_meta[publisher]="$IA_PUBLISHER"
}

# ── Per-episode metadata ──────────────────────────────────────────────────────
collect_episode_metadata() {
    local ep_file="$1"
    local ep_filename="$2"
    local -n _ep_meta=$3

    local ep_basename="${ep_filename%.*}"
    local season_ep_info
    season_ep_info="$(guess_episode_info "$ep_basename")"
    local season_num="${season_ep_info%% *}"
    local episode_num="${season_ep_info##* }"

    _ep_meta[season]="${season_num:-}"
    _ep_meta[episode]="${episode_num:-}"

    ui_section "Episode Details"

    # Episode title
    local default_ep_title="${_ep_meta[show_title]:-}"
    [[ -n "$season_num" ]]  && default_ep_title+=" S$(printf '%02d' "$season_num")"
    [[ -n "$episode_num" ]] && default_ep_title+="E$(printf '%02d' "$episode_num")"

    ui_prompt "Episode title: " ep_title_input "$default_ep_title"
    _ep_meta[title]="$ep_title_input"

    # Episode-specific description
    echo ""
    echo -e "  ${COLOR_DIM}Episode description (optional — leave blank to use show description)${COLOR_RESET}"
    echo -e "  ${COLOR_DIM}[n] Open in nano  [Enter] Use show description  [t] Type here${COLOR_RESET}"
    ui_prompt "Description option [Enter]: " desc_choice ""

    case "${desc_choice,,}" in
        n)
            edit_in_nano "episode description" desc_val "${_ep_meta[show_description]:-}"
            _ep_meta[description]="$desc_val"
            ;;
        t)
            ui_prompt "Episode description: " desc_val ""
            _ep_meta[description]="$desc_val"
            ;;
        *)
            _ep_meta[description]="${_ep_meta[show_description]:-}"
            ;;
    esac

    # Build identifier
    local id_base="${_ep_meta[show_title]:-show}"
    [[ -n "$season_num" ]]  && id_base+=" s$(printf '%02d' "$season_num")"
    [[ -n "$episode_num" ]] && id_base+="e$(printf '%02d' "$episode_num")"
    _ep_meta[identifier]="$(build_identifier "$id_base")"

    _ep_meta[local_filepath]="$ep_file"
    _ep_meta[remote_filepath]="$(basename "$ep_file")"

    # Preview + confirm
    show_metadata_preview_tv _ep_meta

    local proceed
    while true; do
        echo ""
        echo -e "  ${COLOR_CYAN}[a]${COLOR_RESET} Accept  ${COLOR_CYAN}[e]${COLOR_RESET} Edit in nano  ${COLOR_CYAN}[s]${COLOR_RESET} Skip this episode  ${COLOR_CYAN}[q]${COLOR_RESET} Back to menu"
        ui_prompt "Action: " proceed "a"

        case "${proceed,,}" in
            a) break ;;
            e)
                edit_metadata_in_nano _ep_meta
                show_metadata_preview_tv _ep_meta
                ;;
            s|q)
                _ep_meta[_skip]="1"
                break
                ;;
        esac
    done
}

# ── TV metadata preview ───────────────────────────────────────────────────────
show_metadata_preview_tv() {
    local -n _pt=$1
    ui_clear
    ui_header "Metadata Preview — ${_pt[title]:-Untitled}"

    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Identifier"    "${_pt[identifier]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Episode Title" "${_pt[title]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Show"          "${_pt[show_title]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Season"        "${_pt[season]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Episode"       "${_pt[episode]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Network"       "${_pt[network]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Year(s)"       "${_pt[date]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Genres"        "${_pt[genres]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Rating"        "${_pt[rating]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Language"      "${_pt[language]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Mediatype"     "${_pt[mediatype]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Collection"    "${_pt[collection]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Publisher"     "${_pt[publisher]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "Source URL"    "${_pt[source_url]:-}"
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "License URL"   "${_pt[licenseurl]:-}"
    echo ""
    echo -e "  ${COLOR_DIM}Description:${COLOR_RESET}"
    echo ""
    echo "${_pt[description]:-}" | fold -s -w 68 | sed 's/^/    /'
    echo ""
    printf "  ${COLOR_CYAN}%-20s${COLOR_RESET}  %s\n" "File"          "$(basename "${_pt[local_filepath]:-}")"
}

# ── Full metadata nano editor (edit all fields at once) ───────────────────────
edit_metadata_in_nano() {
    local -n _edit_meta=$1

    local tmpfile
    tmpfile="$(mktemp /tmp/ia-fullmeta-XXXXXX.txt)"

    {
        echo "# ── Internet Archive Metadata Editor ──────────────────────────────"
        echo "# Edit any field below. Lines starting with # are ignored."
        echo "# Format:  FIELD=value"
        echo "# Save and exit: Ctrl+X → Y → Enter"
        echo "#"
        for key in title identifier date creator language description \
                   mediatype collection publisher source_url licenseurl \
                   extra_tags genres rating show_title network season episode \
                   show_description; do
            local val="${_edit_meta[$key]:-}"
            echo "${key}=${val}"
        done
    } > "$tmpfile"

    nano "$tmpfile"

    # Parse back
    while IFS='=' read -r key val; do
        # Skip comment lines and blank lines
        [[ "$key" =~ ^# ]] && continue
        [[ -z "$key" ]] && continue
        # Strip leading/trailing whitespace
        key="$(echo "$key" | xargs)"
        val="$(echo "$val" | xargs)"
        [[ -n "$key" ]] && _edit_meta["$key"]="$val"
    done < <(grep -v '^#' "$tmpfile" | grep -v '^[[:space:]]*$')

    rm -f "$tmpfile"
}

# =============================================================================
# CSV ROW BUILDERS
# =============================================================================

build_csv_row_movie() {
    local -n _bm=$1
    local primary_file="$2"
    local movie_dir="$3"

    # Build subject tags array
    local -a subjects=("${IA_DEFAULT_SUBJECTS[@]}")

    # Add genre-based subjects
    if [[ -n "${_bm[genres]:-}" ]]; then
        IFS=';' read -ra genre_arr <<< "${_bm[genres]}"
        for g in "${genre_arr[@]}"; do
            [[ -n "$g" ]] && subjects+=("$g")
        done
    fi

    # Add extra tags
    if [[ -n "${_bm[extra_tags]:-}" ]]; then
        read -ra extra_arr <<< "${_bm[extra_tags]}"
        for t in "${extra_arr[@]}"; do
            [[ -n "$t" ]] && subjects+=("$t")
        done
    fi

    # Add rating if present
    [[ -n "${_bm[rating]:-}" ]] && subjects+=("rated-${_bm[rating],,}")
    # Add network
    [[ -n "${_bm[network]:-}" ]] && subjects+=("${_bm[network]}")

    # Pad subject array to 5 slots
    while (( ${#subjects[@]} < 5 )); do subjects+=(""); done

    # Build description
    local desc="${_bm[description]:-}"

    # Output CSV row
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$(csv_escape "${_bm[identifier]:-}")" \
        "$(csv_escape "$(basename "${primary_file:-}")")" \
        "$(csv_escape "${_bm[title]:-}")" \
        "$(csv_escape "$desc")" \
        "$(csv_escape "${_bm[date]:-}")" \
        "$(csv_escape "${_bm[creator]:-}")" \
        "$(csv_escape "${_bm[language]:-eng}")" \
        "$(csv_escape "${_bm[mediatype]:-movies}")" \
        "$(csv_escape "${_bm[collection]:-opensource}")" \
        "$(csv_escape "${_bm[publisher]:-}")" \
        "$(csv_escape "${subjects[0]:-}")" \
        "$(csv_escape "${subjects[1]:-}")" \
        "$(csv_escape "${subjects[2]:-}")" \
        "$(csv_escape "${subjects[3]:-}")" \
        "$(csv_escape "${subjects[4]:-}")" \
        "$(csv_escape "${_bm[source_url]:-}")" \
        "$(csv_escape "")" \
        "$(csv_escape "${_bm[licenseurl]:-}")" \
        "$(csv_escape "${primary_file:-}")"
}

build_csv_row_tv() {
    local -n _bt=$1
    local ep_file="$2"

    local -a subjects=("${IA_DEFAULT_SUBJECTS[@]}")
    subjects+=("television")
    [[ -n "${_bt[show_title]:-}" ]] && subjects+=("${_bt[show_title]}")
    [[ -n "${_bt[network]:-}" ]]    && subjects+=("${_bt[network]}")

    if [[ -n "${_bt[genres]:-}" ]]; then
        IFS=';' read -ra genre_arr <<< "${_bt[genres]}"
        for g in "${genre_arr[@]}"; do
            [[ -n "$g" ]] && subjects+=("$g")
        done
    fi

    if [[ -n "${_bt[extra_tags]:-}" ]]; then
        read -ra extra_arr <<< "${_bt[extra_tags]}"
        for t in "${extra_arr[@]}"; do
            [[ -n "$t" ]] && subjects+=("$t")
        done
    fi

    while (( ${#subjects[@]} < 5 )); do subjects+=(""); done

    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$(csv_escape "${_bt[identifier]:-}")" \
        "$(csv_escape "$(basename "${ep_file:-}")")" \
        "$(csv_escape "${_bt[title]:-}")" \
        "$(csv_escape "${_bt[description]:-}")" \
        "$(csv_escape "${_bt[date]:-}")" \
        "$(csv_escape "${_bt[creator]:-}")" \
        "$(csv_escape "${_bt[language]:-eng}")" \
        "$(csv_escape "${_bt[mediatype]:-movies}")" \
        "$(csv_escape "${_bt[collection]:-opensource}")" \
        "$(csv_escape "${_bt[publisher]:-}")" \
        "$(csv_escape "${subjects[0]:-}")" \
        "$(csv_escape "${subjects[1]:-}")" \
        "$(csv_escape "${subjects[2]:-}")" \
        "$(csv_escape "${subjects[3]:-}")" \
        "$(csv_escape "${subjects[4]:-}")" \
        "$(csv_escape "${_bt[source_url]:-}")" \
        "$(csv_escape "")" \
        "$(csv_escape "${_bt[licenseurl]:-}")" \
        "$(csv_escape "${ep_file:-}")" \
        "$(csv_escape "${_bt[season]:-}")" \
        "$(csv_escape "${_bt[episode]:-}")"
}

export -f csv_escape guess_year guess_title_from_path guess_episode_info
export -f collect_movie_metadata collect_show_metadata collect_episode_metadata
export -f build_csv_row_movie build_csv_row_tv edit_in_nano edit_metadata_in_nano
export -f show_metadata_preview_movie show_metadata_preview_tv pick_language
