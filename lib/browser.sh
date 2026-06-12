#!/usr/bin/env bash
# =============================================================================
# lib/browser.sh — File Browser & Selection
# Handles browsing Movies/Television folders, listing items, and selection.
# For Movies: each folder = one movie. For TV: folder > season > episodes.
# =============================================================================

# ── Utility: check if a file is a video ──────────────────────────────────────
is_video_file() {
    local file="$1"
    local ext="${file##*.}"
    ext="${ext,,}"  # lowercase
    for valid in "${VIDEO_EXTENSIONS[@]}"; do
        [[ "$ext" == "$valid" ]] && return 0
    done
    return 1
}

# ── Utility: get total size of a directory in bytes ──────────────────────────
get_dir_size() {
    local dir="$1"
    du -sb "$dir" 2>/dev/null | awk '{print $1}' || echo "0"
}

# ── Utility: find video files in a directory (non-recursive) ─────────────────
find_videos_in_dir() {
    local dir="$1"
    local -n _vids_out=$2
    _vids_out=()

    while IFS= read -r -d $'\0' f; do
        if is_video_file "$f"; then
            _vids_out+=("$f")
        fi
    done < <(find "$dir" -maxdepth 1 -type f -print0 2>/dev/null)
}

# ── Utility: find video files recursively (for TV seasons) ───────────────────
find_videos_recursive() {
    local dir="$1"
    local -n _vids_r=$2
    _vids_r=()

    while IFS= read -r -d $'\0' f; do
        if is_video_file "$f"; then
            _vids_r+=("$f")
        fi
    done < <(find "$dir" -type f -print0 2>/dev/null | sort -z)
}

# ── Utility: find companion files (subs, nfo, images) for a video ────────────
find_companion_files() {
    local video_path="$1"
    local base="${video_path%.*}"
    local dir
    dir="$(dirname "$video_path")"
    local -n _companions=$2
    _companions=()

    for ext in "${EXTRA_EXTENSIONS[@]}"; do
        # Same base name, different extension
        [[ -f "${base}.${ext}" ]] && _companions+=("${base}.${ext}")
    done

    # Also grab any .nfo files in the same directory
    while IFS= read -r -d $'\0' f; do
        local already=false
        for c in "${_companions[@]}"; do
            [[ "$c" == "$f" ]] && already=true && break
        done
        "$already" || _companions+=("$f")
    done < <(find "$dir" -maxdepth 1 -name "*.nfo" -print0 2>/dev/null)
}

# =============================================================================
# MOVIES WORKFLOW
# Expected structure: Movies/MovieName (Year)/moviefile.mkv
# =============================================================================

run_movies_workflow() {
    if [[ ! -d "$MOVIES_PATH" ]]; then
        ui_clear
        ui_header "Movies"
        ui_error "Movies folder not found: $MOVIES_PATH"
        ui_pause
        return
    fi

    # Scan for movie folders
    ui_clear
    ui_header "Movies — Scanning..."
    ui_spinner_start "Scanning $MOVIES_PATH"

    local -a movie_dirs=()
    local -a movie_labels=()

    while IFS= read -r -d $'\0' dir; do
        # Only include dirs that actually contain at least one video file
        local -a vids=()
        find_videos_in_dir "$dir" vids
        # Also check one level deeper (some movies have sub-folders)
        if (( ${#vids[@]} == 0 )); then
            find_videos_recursive "$dir" vids
        fi
        if (( ${#vids[@]} > 0 )); then
            movie_dirs+=("$dir")
            local dirname
            dirname="$(basename "$dir")"
            local size_bytes
            size_bytes="$(get_dir_size "$dir")"
            local size_fmt
            size_fmt="$(ui_format_size "$size_bytes")"
            movie_labels+=("${dirname}  ${COLOR_DIM}(${#vids[@]} file(s) · $size_fmt)${COLOR_RESET}")
        fi
    done < <(find "$MOVIES_PATH" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

    ui_spinner_stop

    if (( ${#movie_dirs[@]} == 0 )); then
        ui_clear
        ui_header "Movies"
        ui_warn "No movie folders with video files found in:"
        ui_info "$MOVIES_PATH"
        echo ""
        ui_info "Expected structure:  Movies/Movie Title (Year)/video.mkv"
        ui_pause
        return
    fi

    # Selection loop — keep returning here until user is done
    local keep_browsing=true
    while [[ "$keep_browsing" == true ]]; do
        # Checkbox selection UI
        local -a selected_indices=()
        ui_checkbox_menu movie_labels selected_indices "Movies — Select titles to upload"

        if (( ${#selected_indices[@]} == 0 )); then
            if ui_confirm "No movies selected. Return to main menu?"; then
                keep_browsing=false
                return
            fi
            continue
        fi

        # Process each selected movie
        local -a queued_this_batch=()
        for idx in "${selected_indices[@]}"; do
            local dir="${movie_dirs[$idx]}"
            local label="${movie_labels[$idx]}"

            # Strip ANSI codes from label for display
            local clean_label
            clean_label="$(echo -e "$label" | sed 's/\x1b\[[0-9;]*m//g')"

            ui_clear
            ui_header "Movie: $clean_label"

            # Find video files in this folder
            local -a vid_files=()
            find_videos_in_dir "$dir" vid_files
            if (( ${#vid_files[@]} == 0 )); then
                find_videos_recursive "$dir" vid_files
            fi

            if (( ${#vid_files[@]} == 0 )); then
                ui_warn "No video files found in $dir — skipping."
                sleep 1
                continue
            fi

            # If multiple videos, let user pick which one is the "main" file
            local primary_video="${vid_files[0]}"
            if (( ${#vid_files[@]} > 1 )); then
                echo -e "  ${COLOR_CYAN}Multiple video files found:${COLOR_RESET}"
                echo ""
                local vi=1
                for vf in "${vid_files[@]}"; do
                    local vfname
                    vfname="$(basename "$vf")"
                    local vfsize
                    vfsize="$(ui_format_size "$(stat -c%s "$vf" 2>/dev/null || echo 0)")"
                    echo -e "    ${COLOR_CYAN}[$vi]${COLOR_RESET}  $vfname  ${COLOR_DIM}($vfsize)${COLOR_RESET}"
                    (( vi++ ))
                done
                echo ""
                local vid_choice
                ui_prompt "Primary video file [1]: " vid_choice "1"
                if [[ "$vid_choice" =~ ^[0-9]+$ ]] && (( vid_choice >= 1 )) && (( vid_choice <= ${#vid_files[@]} )); then
                    primary_video="${vid_files[$((vid_choice-1))]}"
                fi
            fi

            # Gather metadata
            local -A meta=()
            collect_movie_metadata "$dir" "$primary_video" meta

            if [[ "${meta[_skip]:-}" == "1" ]]; then
                (( SESSION_SKIPPED++ ))
                log_session "Skipped: $clean_label"
                continue
            fi

            # Write to queue
            local queue_row
            queue_row="$(build_csv_row_movie meta "$primary_video" "$dir")"

            # Ensure queue CSV has header
            if [[ ! -f "$MOVIES_QUEUE_FILE" ]]; then
                write_movies_csv_header
            fi

            echo "$queue_row" >> "$MOVIES_QUEUE_FILE"
            (( SESSION_QUEUED++ ))
            queued_this_batch+=("${meta[title]}")
            log_session "Queued movie: ${meta[title]} → ${meta[identifier]}"
        done

        # Summary of this batch
        if (( ${#queued_this_batch[@]} > 0 )); then
            ui_clear
            ui_header "Batch Summary"
            echo ""
            ui_success "Added ${#queued_this_batch[@]} movie(s) to queue:"
            echo ""
            for t in "${queued_this_batch[@]}"; do
                echo -e "    ${COLOR_GREEN}✔${COLOR_RESET}  $t"
            done
            echo ""
            ui_info "Queue file: $MOVIES_QUEUE_FILE"
            echo ""

            if ui_confirm "Upload now?"; then
                process_queue_file "$MOVIES_QUEUE_FILE" "movies"
            else
                ui_info "Items saved to queue. Use option [4] from main menu to upload later."
            fi
        fi

        # Ask if they want to pick more movies
        echo ""
        if ! ui_confirm "Select more movies?"; then
            keep_browsing=false
        fi
    done
}

# =============================================================================
# TELEVISION WORKFLOW
# Expected: Television/Show Name/Season XX/S01E01.mkv
# =============================================================================

run_television_workflow() {
    if [[ ! -d "$TELEVISION_PATH" ]]; then
        ui_clear
        ui_header "Television"
        ui_error "Television folder not found: $TELEVISION_PATH"
        ui_pause
        return
    fi

    # Step 1: Pick show(s)
    ui_clear
    ui_header "Television — Scanning..."
    ui_spinner_start "Scanning $TELEVISION_PATH"

    local -a show_dirs=()
    local -a show_labels=()

    while IFS= read -r -d $'\0' dir; do
        # Count total episodes
        local -a all_eps=()
        find_videos_recursive "$dir" all_eps
        if (( ${#all_eps[@]} > 0 )); then
            show_dirs+=("$dir")
            local show_name
            show_name="$(basename "$dir")"
            # Count seasons
            local season_count
            season_count="$(find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
            local size_fmt
            size_fmt="$(ui_format_size "$(get_dir_size "$dir")")"
            show_labels+=("${show_name}  ${COLOR_DIM}($season_count season(s) · ${#all_eps[@]} ep(s) · $size_fmt)${COLOR_RESET}")
        fi
    done < <(find "$TELEVISION_PATH" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

    ui_spinner_stop

    if (( ${#show_dirs[@]} == 0 )); then
        ui_clear
        ui_header "Television"
        ui_warn "No TV show folders with video files found in:"
        ui_info "$TELEVISION_PATH"
        echo ""
        ui_info "Expected structure:  Television/Show Name/Season 01/S01E01.mkv"
        ui_pause
        return
    fi

    local keep_browsing=true
    while [[ "$keep_browsing" == true ]]; do
        # Pick shows
        local -a selected_show_indices=()
        ui_checkbox_menu show_labels selected_show_indices "Television — Select shows"

        if (( ${#selected_show_indices[@]} == 0 )); then
            if ui_confirm "No shows selected. Return to main menu?"; then
                keep_browsing=false
                return
            fi
            continue
        fi

        # For each show, pick seasons, then episodes
        for show_idx in "${selected_show_indices[@]}"; do
            local show_dir="${show_dirs[$show_idx]}"
            local show_name
            show_name="$(basename "$show_dir")"

            browse_show_seasons "$show_dir" "$show_name"
        done

        echo ""
        if ! ui_confirm "Select more shows?"; then
            keep_browsing=false
        fi
    done
}

# ── Browse seasons within a show ──────────────────────────────────────────────
browse_show_seasons() {
    local show_dir="$1"
    local show_name="$2"

    # Find season subdirectories
    local -a season_dirs=()
    local -a season_labels=()

    while IFS= read -r -d $'\0' dir; do
        local -a eps=()
        find_videos_recursive "$dir" eps
        if (( ${#eps[@]} > 0 )); then
            season_dirs+=("$dir")
            local sname
            sname="$(basename "$dir")"
            local size_fmt
            size_fmt="$(ui_format_size "$(get_dir_size "$dir")")"
            season_labels+=("$sname  ${COLOR_DIM}(${#eps[@]} episode(s) · $size_fmt)${COLOR_RESET}")
        fi
    done < <(find "$show_dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

    # If no season subdirectories, treat show root as a flat episode list
    if (( ${#season_dirs[@]} == 0 )); then
        season_dirs=("$show_dir")
        season_labels=("All Episodes (flat)")
    fi

    local -a selected_season_indices=()
    ui_checkbox_menu season_labels selected_season_indices "$show_name — Select seasons"

    if (( ${#selected_season_indices[@]} == 0 )); then
        ui_warn "No seasons selected for $show_name."
        sleep 1
        return
    fi

    for season_idx in "${selected_season_indices[@]}"; do
        local season_dir="${season_dirs[$season_idx]}"
        local season_label="${season_labels[$season_idx]}"
        local clean_season
        clean_season="$(echo -e "$season_label" | sed 's/\x1b\[[0-9;]*m//g' | cut -d'(' -f1 | xargs)"

        browse_season_episodes "$season_dir" "$show_name" "$clean_season"
    done
}

# ── Browse episodes within a season ──────────────────────────────────────────
browse_season_episodes() {
    local season_dir="$1"
    local show_name="$2"
    local season_name="$3"

    local -a ep_files=()
    find_videos_recursive "$season_dir" ep_files

    if (( ${#ep_files[@]} == 0 )); then
        ui_warn "No episodes found in $season_dir"
        sleep 1
        return
    fi

    # Build labels
    local -a ep_labels=()
    for ep in "${ep_files[@]}"; do
        local epname
        epname="$(basename "$ep")"
        local epsize
        epsize="$(ui_format_size "$(stat -c%s "$ep" 2>/dev/null || echo 0)")"
        ep_labels+=("$epname  ${COLOR_DIM}($epsize)${COLOR_RESET}")
    done

    local -a selected_ep_indices=()
    ui_checkbox_menu ep_labels selected_ep_indices "$show_name / $season_name — Select episodes"

    if (( ${#selected_ep_indices[@]} == 0 )); then
        ui_warn "No episodes selected."
        sleep 1
        return
    fi

    # Collect show-level metadata once, reuse for all selected episodes
    ui_clear
    ui_header "$show_name — Show Metadata"
    ui_info "Enter metadata for the show. This applies to all selected episodes."
    echo ""

    local -A show_meta=()
    collect_show_metadata "$show_name" "$season_name" show_meta

    if [[ "${show_meta[_skip]:-}" == "1" ]]; then
        ui_warn "Skipping all episodes for $show_name."
        (( SESSION_SKIPPED += ${#selected_ep_indices[@]} ))
        return
    fi

    # Per-episode processing
    local -a queued_eps=()
    for ep_idx in "${selected_ep_indices[@]}"; do
        local ep_file="${ep_files[$ep_idx]}"
        local ep_name
        ep_name="$(basename "$ep_file")"

        ui_clear
        ui_header "Episode: $ep_name"

        local -A ep_meta=()
        # Copy show-level metadata
        for k in "${!show_meta[@]}"; do
            ep_meta["$k"]="${show_meta[$k]}"
        done

        collect_episode_metadata "$ep_file" "$ep_name" ep_meta

        if [[ "${ep_meta[_skip]:-}" == "1" ]]; then
            (( SESSION_SKIPPED++ ))
            log_session "Skipped episode: $ep_name"
            continue
        fi

        # Ensure TV queue CSV exists
        if [[ ! -f "$TV_QUEUE_FILE" ]]; then
            write_tv_csv_header
        fi

        local queue_row
        queue_row="$(build_csv_row_tv ep_meta "$ep_file")"
        echo "$queue_row" >> "$TV_QUEUE_FILE"
        (( SESSION_QUEUED++ ))
        queued_eps+=("${ep_meta[title]}")
        log_session "Queued episode: ${ep_meta[title]} → ${ep_meta[identifier]}"
    done

    if (( ${#queued_eps[@]} > 0 )); then
        ui_clear
        ui_header "Episodes Queued"
        echo ""
        ui_success "Added ${#queued_eps[@]} episode(s) to queue:"
        echo ""
        for t in "${queued_eps[@]}"; do
            echo -e "    ${COLOR_GREEN}✔${COLOR_RESET}  $t"
        done
        echo ""
        ui_info "Queue file: $TV_QUEUE_FILE"
        echo ""

        if ui_confirm "Upload now?"; then
            process_queue_file "$TV_QUEUE_FILE" "television"
        else
            ui_info "Items saved to queue. Use option [4] from main menu to upload later."
        fi
    fi
}

# ── CSV header writers ────────────────────────────────────────────────────────
write_movies_csv_header() {
    mkdir -p "$QUEUE_DIR"
    echo "identifier,file,title,description,date,creator,language,mediatype,collection,publisher,subject[0],subject[1],subject[2],subject[3],subject[4],source_url,host_institution,licenseurl,local_filepath" \
        > "$MOVIES_QUEUE_FILE"
}

write_tv_csv_header() {
    mkdir -p "$QUEUE_DIR"
    echo "identifier,file,title,description,date,creator,language,mediatype,collection,publisher,subject[0],subject[1],subject[2],subject[3],subject[4],source_url,host_institution,licenseurl,local_filepath,season,episode" \
        > "$TV_QUEUE_FILE"
}

# ── Build sanitized IA identifier ────────────────────────────────────────────
# IA identifiers: lowercase, alphanumeric + hyphens only, no spaces
build_identifier() {
    local raw="$1"
    local prefix="${IA_IDENTIFIER_PREFIX:-archive-media}"

    # Lowercase, replace spaces/underscores/dots with hyphens, strip non-alnum-hyphen
    local clean
    clean="$(echo "$raw" | tr '[:upper:]' '[:lower:]' | tr ' _.' '-' | sed 's/[^a-z0-9-]//g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')"

    echo "${prefix}-${clean}"
}

export -f is_video_file find_videos_in_dir find_videos_recursive
export -f get_dir_size find_companion_files build_identifier
export -f write_movies_csv_header write_tv_csv_header
