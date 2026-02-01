#!/usr/bin/env bash
# WiFi Manager - Report & Sync Operations
# Sourced by wifi-manager.sh

# -----------------------------------------------------------------------------
# Sync Report to Connections
# Creates missing .nmconnection files from report entries
# -----------------------------------------------------------------------------

sync_report_to_connections() {
    log_debug "Syncing report entries to connections..."
    
    local report_data=""
    if [ -f "$REPORT_FILE" ]; then
        # Parse table: | Network Name | Security Type | Password | ...
        # Skip header/separator lines
        report_data=$(awk -F "|" '
            /^\|.*\|/ {
                if ($0 ~ /^\| Network Name/) next
                if ($0 ~ /^\|--/) next
                
                # Strip whitespace
                ssid = $2; gsub(/^ +| +$/, "", ssid)
                # Unescape: \| -> |, \\ -> \
                gsub(/\\\|/, "|", ssid)
                gsub(/\\\\/, "\\", ssid)
                
                sec = $3; gsub(/^ +| +$/, "", sec)
                
                pass = $4; gsub(/^ +| +$/, "", pass)
                # Remove backticks `pass`
                gsub(/^`|`$/, "", pass)
                if (pass == "N/A") pass = ""
                
                print ssid "|" sec "|" pass
            }
        ' "$REPORT_FILE")
    fi

    # Iterate Report Items and Create Missing Connections
    if [ -n "$report_data" ]; then
        while IFS="|" read -r r_ssid r_sec r_pass; do
            [ -z "$r_ssid" ] && continue

            local clean_name
            clean_name=$(sanitize_filename "$r_ssid")
            local filepath="${LOCAL_DIR}/${clean_name}.nmconnection"

            if [ ! -f "$filepath" ]; then
                # Create from report
                if [ "$DRY_RUN" = false ]; then
                    create_nmconnection "$r_ssid" "$r_pass" "$filepath"
                else
                    log_info "  + [Dry Run] Would create from report: $clean_name"
                fi
            else
                # File exists, check if we need to inject password (if missing in file but present in report)
                local file_info
                file_info=$(parse_nmconnection_file "$filepath")
                IFS="|" read -r f_ssid f_sec f_pass <<< "$file_info"
                
                if [ -z "$f_pass" ] && [ -n "$r_pass" ]; then
                    if [ "$DRY_RUN" = false ]; then
                        log_info "  ~ Inject password from report: $clean_name"
                        # Re-create file to inject password (simple overwrite)
                        create_nmconnection "$r_ssid" "$r_pass" "$filepath"
                    fi
                fi
            fi
        done <<< "$report_data"
    fi
}

# -----------------------------------------------------------------------------
# Generate Report from Connections
# -----------------------------------------------------------------------------

generate_report() {
    log_debug "Generating report from connections..."
    
    # Enable nullglob
    shopt -s nullglob
    local files=("${LOCAL_DIR}"/*.nmconnection)
    shopt -u nullglob

    local temp_list
    temp_list=$(mktemp)
    
    for filepath in "${files[@]}"; do
        if [ -f "$filepath" ]; then
            parse_nmconnection_file "$filepath" >> "$temp_list"
        fi
    done

    # Sort by SSID (case insensitive)
    sort -t "|" -k1,1f "$temp_list" -o "$temp_list"

    if [ "$DRY_RUN" = false ]; then
        {
            echo "# Saved WiFi Networks"
            echo ""
            echo "*Generated on $(date '+%Y-%m-%d %H:%M:%S')*"
            echo ""
            echo "## Network List"
            echo ""
            echo "| Network Name | Security Type | Password | Status |"
            echo "|--------------|---------------|----------|--------|"

            while IFS="|" read -r ssid sec pass; do
                # Escape pipes in SSID
                safe_ssid=$(echo "$ssid" | sed 's/\\/\\\\/g' | sed 's/|/\\|/g')
                safe_pass="N/A"
                if [ -n "$pass" ]; then
                    safe_pass="\`$pass\`"
                fi
                # Get actual network status
                status=$(get_network_status "$ssid")
                
                echo "| $safe_ssid | $sec | $safe_pass | $status |"
            done < "$temp_list"

            echo ""
            echo "---"
            echo ""
            echo "**⚠️ Security Notice**: This file contains sensitive network passwords."
        } > "$REPORT_FILE"
        
        log_info "Report updated: $REPORT_FILE"
    else
        log_info "[Dry Run] Would regenerate report."
    fi

    rm -f "$temp_list"
}

# -----------------------------------------------------------------------------
# Full Bidirectional Sync
# -----------------------------------------------------------------------------

sync_report() {
    log_info "Syncing report..."
    
    # Ensure local directory exists
    ensure_local_dir
    
    # 1. Sync Report entries -> Local files (create missing)
    sync_report_to_connections
    
    # 2. Regenerate Report from all Local files
    generate_report
    
    log_info "✓ Report and local connections synced successfully"
}
