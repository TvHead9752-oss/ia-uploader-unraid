#!/usr/bin/env bash
# =============================================================================
# lib/uploader.sh — Upload Execution & Progress Display
# Handles processing the queue CSV, calling `ia upload`, showing live progress,
# handling retries, and reporting results.
# =============================================================================

# ── Process all queue files ───────────────────────────────────────────────────
process_queue() {
    ui_clear
    ui_header "Process Upload Queue"
    echo ""

    local found_any=false

    if [[ -f "$MOVIES_QUEUE_FILE" ]]; then
        local movie_count
        movie_count=$(( $(wc -l < "$MOVIES_QUEUE_FILE") - 1 ))
        if (( movie_count > 0 )); then
            echo -e "  ${COLOR_CYAN}Movies queue:${COLOR_RESET}  $movie_count item(s)  ${COLOR_DIM}($MOVIES_QUEUE_FILE)${COLOR_RESET}"
            found_any=true
        fi
    fi

    if [[ -f "$TV_QUEUE_FILE" ]]; then
        local tv_count
        tv_count=$(( $(wc -l < "$TV_QUEUE_FILE") - 1 ))
        if (( tv_count > 0 )); then
            echo -e "  ${COLOR_CYAN}TV queue:${COLOR_RESET}     $tv_count item(s)  ${COLOR_DIM}($TV_QUEUE_FILE)${COLOR_RESET}"
            found_any=true
        fi
    fi

    if [[ "$found_any" != true ]]; then
        ui_warn "No items in queue. Add items by selecting Movies or Television first."
        echo ""
        ui_pause
        return
    fi

    echo ""
    if ! ui_confirm "Start uploading all queued items?"; then
        ui_info "Upload cancelled."
        sleep 1
        return
    fi

    # Process each queue file
    if [[ -f "$MOVIES_QUEUE_FILE" ]]; then
        local mc
        mc=$(( $(wc -l < "$MOVIES_QUEUE_FILE") - 1 ))
        if (( mc > 0 )); then
            process_queue_file "$MOVIES_QUEUE_FILE" "movies"
        fi
    fi

    if [[ -f "$TV_QUEUE_FILE" ]]; then
        local tc
        tc=$(( $(wc -l < "$TV_QUEUE_FILE") - 1 ))
        if (( tc > 0 )); then
            process_queue_file "$TV_QUEUE_FILE" "television"
        fi
    fi
}

# ── Process a single queue CSV file ──────────────────────────────────────────
process_queue_file() {
    local csv_file="$1"
    local category="$2"   # "movies" or "television"

    if [[ ! -f "$csv_file" ]]; then
        ui_warn "Queue file not found: $csv_file"
        return
    fi

    local total
    total=$(( $(wc -l < "$csv_file") - 1 ))

    if (( total <= 0 )); then
        ui_warn "Queue file is empty: $csv_file"
        return
    fi

    ui_clear
    ui_header "Uploading — $(echo "$category" | sed 's/./\u&/') ($total item(s))"
    echo ""
    ui_info "Queue file : $csv_file"
    ui_info "Retries    : $IA_RETRIES  (sleep ${IA_RETRIES_SLEEP}s between)"
    echo ""
    ui_divider
    echo ""

    local current=0
    local ok_count=0
    local fail_count=0
    local skip_count=0

    # Read header line to find column indices
    local header
    header="$(head -n1 "$csv_file")"
    local -A col_index=()
    local ci=0

    # Parse CSV header (simple — no quoted commas in header expected)
    IFS=',' read -ra header_cols <<< "$header"
    for col in "${header_cols[@]}"; do
        # Strip quotes
        col="${col//\"/}"
        col="${col// /}"
        col_index["$col"]=$ci
        (( ci++ ))
    done

    # Derived column positions (with defaults)
    local idx_identifier="${col_index[identifier]:-0}"
    local idx_file="${col_index[file]:-1}"
    local idx_title="${col_index[title]:-2}"
    local idx_local="${col_index[local_filepath]:-18}"

    # Build the failed items list for retry
    local -a failed_items=()

    # Upload log for this run
    local upload_log="$LOG_DIR/upload_$(date +%Y%m%d_%H%M%S)_${category}.log"
    touch "$upload_log"

    log_upload() {
        echo "[$(date +%H:%M:%S)] $*" >> "$upload_log"
    }

    log_upload "Upload started: $csv_file  ($total items)"

    # ── Process row by row ────────────────────────────────────────────────────
    while IFS= read -r row; do
        # Skip blank lines
        [[ -z "$row" ]] && continue

        (( current++ ))

        # Parse this row's CSV fields
        local -a fields=()
        parse_csv_row "$row" fields

        local identifier="${fields[$idx_identifier]:-}"
        local remote_file="${fields[$idx_file]:-}"
        local title="${fields[$idx_title]:-unknown}"
        local local_path="${fields[$idx_local]:-}"

        # Strip any surrounding quotes from values
        identifier="${identifier//\"/}"
        remote_file="${remote_file//\"/}"
        title="${title//\"/}"
        local_path="${local_path//\"/}"

        # Display current item
        echo ""
        ui_progress_bar "$current" "$total" ""
        ui_progress_done
        ui_upload_status "start" "$title"

        # Validate local file exists
        if [[ -z "$local_path" ]] || [[ ! -f "$local_path" ]]; then
            ui_upload_status "fail" "$title" "File not found: $local_path"
            log_upload "SKIP (no file): $identifier  path=$local_path"
            (( skip_count++ ))
            (( SESSION_SKIPPED++ ))
            continue
        fi

        # Validate identifier
        if [[ -z "$identifier" ]]; then
            ui_upload_status "fail" "$title" "Missing identifier"
            log_upload "SKIP (no identifier): $title"
            (( skip_count++ ))
            (( SESSION_SKIPPED++ ))
            continue
        fi

        # Check if already on IA (optional — avoids re-uploading)
        if check_already_uploaded "$identifier"; then
            ui_upload_status "skip" "$title" "(already on IA)"
            log_upload "ALREADY EXISTS: $identifier"
            (( skip_count++ ))
            (( SESSION_SKIPPED++ ))
            continue
        fi

        # Show file size
        local fsize
        fsize="$(ui_format_size "$(stat -c%s "$local_path" 2>/dev/null || echo 0)")"
        echo -e "    ${COLOR_DIM}File: $(basename "$local_path")  ($fsize)${COLOR_RESET}"

        # ── Attempt upload with retries ───────────────────────────────────────
        local attempt=0
        local upload_ok=false

        while (( attempt <= IA_RETRIES )); do
            if (( attempt > 0 )); then
                echo -e "    ${COLOR_YELLOW}↻${COLOR_RESET}  Retry $attempt/$IA_RETRIES — waiting ${IA_RETRIES_SLEEP}s..."
                sleep "$IA_RETRIES_SLEEP"
            fi

            (( attempt++ ))

            # Run upload and capture output + exit code
            local upload_output
            local exit_code

            upload_output="$(
                run_ia_upload "$csv_file" "$identifier" "$local_path" "$remote_file" 2>&1
            )"
            exit_code=$?

            if (( exit_code == 0 )); then
                upload_ok=true
                break
            fi

            log_upload "Attempt $attempt FAILED ($exit_code): $identifier"
            log_upload "Output: $upload_output"
        done

        if [[ "$upload_ok" == true ]]; then
            ui_upload_status "ok" "$title" "https://archive.org/details/$identifier"
            log_upload "SUCCESS: $identifier"
            (( ok_count++ ))
            (( SESSION_UPLOADED++ ))
        else
            ui_upload_status "fail" "$title" "Failed after $IA_RETRIES retries — see $upload_log"
            log_upload "FAILED: $identifier"
            failed_items+=("$identifier|$title")
            (( fail_count++ ))
            (( SESSION_FAILED++ ))
        fi

    done < <(tail -n +2 "$csv_file")

    # ── Upload summary ────────────────────────────────────────────────────────
    echo ""
    ui_divider
    echo ""
    ui_header "Upload Complete — $category"

    echo -e "  ${COLOR_GREEN}✔  Uploaded : $ok_count${COLOR_RESET}"
    echo -e "  ${COLOR_YELLOW}–  Skipped  : $skip_count${COLOR_RESET}"
    echo -e "  ${COLOR_RED}✖  Failed   : $fail_count${COLOR_RESET}"
    echo ""
    ui_info "Full upload log: $upload_log"
    echo ""

    # Show failed items if any
    if (( ${#failed_items[@]} > 0 )); then
        echo -e "  ${COLOR_BOLD_RED}Failed items:${COLOR_RESET}"
        for item in "${failed_items[@]}"; do
            local fid="${item%%|*}"
            local fname="${item##*|}"
            echo -e "    ${COLOR_RED}✖${COLOR_RESET}  $fname  ${COLOR_DIM}($fid)${COLOR_RESET}"
        done
        echo ""
        if ui_confirm "Retry failed items now?"; then
            retry_failed_items "$csv_file" "${failed_items[@]}"
        fi
    fi

    # Archive processed queue file
    if (( ok_count > 0 )); then
        local archive_name
        archive_name="${csv_file%.csv}_done_$(date +%Y%m%d_%H%M%S).csv"
        mv "$csv_file" "$archive_name"
        ui_info "Queue archived to: $archive_name"
    fi

    echo ""
    ui_pause
}

# ── Run the actual ia upload command ─────────────────────────────────────────
# Uses single-item upload rather than --spreadsheet so we can control progress.
run_ia_upload() {
    local csv_file="$1"
    local identifier="$2"
    local local_path="$3"
    local remote_file="$4"

    # Build ia upload command with individual file
    # We pass metadata fields directly to avoid CSV parsing issues with ia CLI
    local cmd=(
        ia upload
        "$identifier"
        "$local_path"
        --remote-name="$remote_file"
        --retries="$IA_RETRIES"
        --retries-sleep="$IA_RETRIES_SLEEP"
    )

    # Add checksum flag if enabled
    if [[ "${IA_VERIFY_CHECKSUM:-true}" == "true" ]]; then
        cmd+=(--checksum)
    fi

    # Add metadata from the CSV row for this identifier
    # Extract metadata fields and add them as --metadata flags
    local meta_args=()
    extract_metadata_args "$csv_file" "$identifier" meta_args

    for arg in "${meta_args[@]}"; do
        cmd+=("$arg")
    done

    # Execute
    "${cmd[@]}"
}

# ── Extract metadata from CSV row for ia --metadata flags ────────────────────
extract_metadata_args() {
    local csv_file="$1"
    local target_id="$2"
    local -n _meta_args=$3
    _meta_args=()

    # Read header
    local header
    header="$(head -n1 "$csv_file")"
    local -a header_cols=()

    # Simple header parse
    IFS=',' read -ra raw_cols <<< "$header"
    for col in "${raw_cols[@]}"; do
        header_cols+=("${col//\"/}")
    done

    # Find the row matching our identifier
    local target_row=""
    while IFS= read -r row; do
        [[ -z "$row" ]] && continue
        local -a fields=()
        parse_csv_row "$row" fields
        local row_id="${fields[0]//\"/}"
        if [[ "$row_id" == "$target_id" ]]; then
            target_row="$row"
            break
        fi
    done < <(tail -n +2 "$csv_file")

    [[ -z "$target_row" ]] && return

    local -a row_fields=()
    parse_csv_row "$target_row" row_fields

    # Map header columns to --metadata flags
    # Skip: identifier (col 0), file (col 1), local_filepath, season, episode
    local skip_cols=("identifier" "file" "local_filepath" "season" "episode" "REMOTE_NAME")

    local ci=0
    for col in "${header_cols[@]}"; do
        col="${col// /}"
        local val="${row_fields[$ci]:-}"
        val="${val//\"/}"

        # Skip non-metadata columns
        local skip=false
        for sc in "${skip_cols[@]}"; do
            [[ "$col" == "$sc" ]] && skip=true && break
        done

        if [[ "$skip" == false ]] && [[ -n "$val" ]]; then
            _meta_args+=("--metadata=${col}:${val}")
        fi

        (( ci++ ))
    done
}

# ── CSV row parser (handles quoted fields with embedded commas) ───────────────
parse_csv_row() {
    local row="$1"
    local -n _parsed=$2
    _parsed=()

    local field=""
    local in_quotes=false
    local i

    for (( i=0; i<${#row}; i++ )); do
        local ch="${row:$i:1}"

        if [[ "$in_quotes" == true ]]; then
            if [[ "$ch" == '"' ]]; then
                # Check for escaped quote ("")
                local next="${row:$((i+1)):1}"
                if [[ "$next" == '"' ]]; then
                    field+='"'
                    (( i++ ))
                else
                    in_quotes=false
                fi
            else
                field+="$ch"
            fi
        else
            if [[ "$ch" == '"' ]]; then
                in_quotes=true
            elif [[ "$ch" == ',' ]]; then
                _parsed+=("$field")
                field=""
            else
                field+="$ch"
            fi
        fi
    done

    # Last field
    _parsed+=("$field")
}

# ── Check if an identifier already exists on IA ───────────────────────────────
check_already_uploaded() {
    local identifier="$1"

    # Use ia CLI to check — returns non-zero if item doesn't exist
    # This is a lightweight metadata check, not a full download
    if ia metadata "$identifier" &>/dev/null 2>&1; then
        return 0   # exists
    fi
    return 1   # does not exist
}

# ── Retry failed items ────────────────────────────────────────────────────────
retry_failed_items() {
    local csv_file="$1"
    shift
    local -a failed=("$@")

    ui_clear
    ui_header "Retrying Failed Items"
    echo ""
    ui_info "${#failed[@]} item(s) to retry"
    echo ""

    local retry_ok=0
    local retry_fail=0

    for item in "${failed[@]}"; do
        local fid="${item%%|*}"
        local fname="${item##*|}"

        echo ""
        ui_upload_status "start" "$fname"

        # Find local path from CSV
        local local_path=""
        local remote_file=""

        while IFS= read -r row; do
            [[ -z "$row" ]] && continue
            local -a fields=()
            parse_csv_row "$row" fields
            local row_id="${fields[0]//\"/}"
            if [[ "$row_id" == "$fid" ]]; then
                # Assuming local_filepath is last non-empty column
                local_path="${fields[-1]//\"/}"
                remote_file="${fields[1]//\"/}"
                break
            fi
        done < <(tail -n +2 "$csv_file")

        if [[ -z "$local_path" ]] || [[ ! -f "$local_path" ]]; then
            ui_upload_status "fail" "$fname" "File missing"
            (( retry_fail++ ))
            continue
        fi

        local output
        local exit_code
        output="$(run_ia_upload "$csv_file" "$fid" "$local_path" "$remote_file" 2>&1)"
        exit_code=$?

        if (( exit_code == 0 )); then
            ui_upload_status "ok" "$fname" "https://archive.org/details/$fid"
            (( retry_ok++ ))
            (( SESSION_UPLOADED++ ))
            (( SESSION_FAILED-- ))
        else
            ui_upload_status "fail" "$fname" "Still failing"
            (( retry_fail++ ))
        fi
    done

    echo ""
    ui_divider
    echo ""
    echo -e "  ${COLOR_GREEN}✔  Recovered : $retry_ok${COLOR_RESET}"
    echo -e "  ${COLOR_RED}✖  Still failed : $retry_fail${COLOR_RESET}"
    echo ""
    ui_pause
}

# ── Bulk CSV upload (alternative path using ia --spreadsheet) ─────────────────
# Use this if you want to hand off to ia CLI's native bulk mode instead
bulk_upload_via_spreadsheet() {
    local csv_file="$1"

    if [[ ! -f "$csv_file" ]]; then
        ui_error "CSV file not found: $csv_file"
        return 1
    fi

    ui_clear
    ui_header "Bulk Upload via Spreadsheet"
    echo ""
    ui_info "Using: ia upload --spreadsheet=$csv_file"
    echo ""

    ia upload \
        --spreadsheet="$csv_file" \
        --retries="$IA_RETRIES" \
        --retries-sleep="$IA_RETRIES_SLEEP" \
        2>&1 | while IFS= read -r line; do
            # Colorize ia output
            if echo "$line" | grep -qi "success\|uploaded\|200"; then
                echo -e "  ${COLOR_GREEN}✔${COLOR_RESET}  $line"
            elif echo "$line" | grep -qi "error\|fail\|40[0-9]\|50[0-9]"; then
                echo -e "  ${COLOR_RED}✖${COLOR_RESET}  $line"
            elif echo "$line" | grep -qi "retry\|waiting\|sleep"; then
                echo -e "  ${COLOR_YELLOW}↻${COLOR_RESET}  $line"
            else
                echo -e "  ${COLOR_DIM}   $line${COLOR_RESET}"
            fi
        done

    local exit_code="${PIPESTATUS[0]}"

    echo ""
    if (( exit_code == 0 )); then
        ui_success "Bulk upload complete."
    else
        ui_error "Bulk upload finished with errors (exit code $exit_code)."
        ui_info "Check output above and your IA account page for details."
    fi

    echo ""
    ui_pause
}

export -f process_queue process_queue_file run_ia_upload
export -f parse_csv_row check_already_uploaded retry_failed_items
export -f extract_metadata_args bulk_upload_via_spreadsheet
