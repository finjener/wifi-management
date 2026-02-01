#!/usr/bin/env bash
# WiFi Manager - nmconnection File Operations
# Sourced by wifi-manager.sh

# -----------------------------------------------------------------------------
# Create nmconnection File
# -----------------------------------------------------------------------------

create_nmconnection() {
    local ssid="$1"
    local password="$2"
    local filename="$3"
    local uuid_val
    uuid_val=$(uuidgen)
    local timestamp_val
    timestamp_val=$(date +%s)000000

    if [ -f "$filename" ]; then
        log_info "  ~ Updating: $(basename "$filename")"
    else
        log_info "  + Creating: $(basename "$filename")"
    fi

    cat <<EOF > "$filename"
[connection]
id=$ssid
uuid=$uuid_val
type=wifi
autoconnect=true
timestamp=$timestamp_val

[wifi]
mode=infrastructure
ssid=$ssid
hidden=false

EOF

    if [ -n "$password" ] && [ "$password" != "null" ]; then
        cat <<EOF >> "$filename"
[wifi-security]
auth-alg=open
key-mgmt=wpa-psk
psk=$password

EOF
    fi

    cat <<EOF >> "$filename"
[ipv4]
method=auto
dns-search=

[ipv6]
addr-gen-mode=stable-privacy
method=auto
dns-search=

[proxy]
EOF
}

# -----------------------------------------------------------------------------
# Parse nmconnection File
# -----------------------------------------------------------------------------

parse_nmconnection_file() {
    local filepath="$1"
    # Output: SSID|Security|Password
    # Use awk to parse ini-like file
    awk -F "=" '
        BEGIN { section=""; ssid=""; conn_id=""; psk=""; key_mgmt=""; }
        /^\[.*\]/ { 
            section=$0 
            gsub(/[\[\]]/, "", section)
        }
        /^ssid=/ { if(section=="wifi") ssid=$2 }
        /^id=/ { if(section=="connection") conn_id=$2 }
        /^key-mgmt=/ { if(section=="wifi-security") key_mgmt=$2 }
        /^psk=/ { if(section=="wifi-security") psk=$2 }
        
        END {
            if (ssid == "" && conn_id != "") ssid = conn_id
            if (ssid != "") {
                sec = "Unknown"
                if (index(key_mgmt, "wpa") > 0) sec = "WPA/WPA2"
                else if (index(key_mgmt, "sae") > 0) sec = "WPA3"
                else if (key_mgmt == "" && psk == "") sec = "Open"
                else if (psk != "") sec = "WPA/WPA2" # Fallback guess
                
                print ssid "|" sec "|" psk
            }
        }
    ' "$filepath"
}

# -----------------------------------------------------------------------------
# Import from Android XML
# -----------------------------------------------------------------------------

parse_android_xml() {
    local xml_file="$1"
    # Output: SSID|Password lines
    # Uses awk with record separator to parse Network blocks
    awk '
        BEGIN { RS="</Network>" }
        {
            ssid=""; psk="null";
            
            # Extract SSID
            # Look for <string name="SSID">"SomeSSID"</string>
            match($0, /<string name="SSID">([^<]+)<\/string>/, a)
            if (a[1] != "") ssid = a[1]

            # Extract PreSharedKey
            # Look for <string name="PreSharedKey">"SomePass"</string>
            match($0, /<string name="PreSharedKey">([^<]+)<\/string>/, b)
            if (b[1] != "") psk = b[1]

            if (ssid != "") {
                print ssid "|" psk
            }
        }
    ' "$xml_file"
}

cmd_import_android() {
    log_info "Starting Android Import..."
    if [ "$DRY_RUN" = true ]; then
        log_info "(Dry Run Mode)"
    fi
    
    if [ ! -f "$XML_FILE" ]; then
        exit_with_error "XML file not found: $XML_FILE"
    fi

    ensure_local_dir

    local imported_count=0
    local skipped_count=0

    while IFS="|" read -r ssid password; do
        if [ -z "$ssid" ] || [ "$ssid" == "null" ]; then
            continue
        fi

        # Decode XML entities
        ssid=$(decode_xml_entities "$ssid")
        password=$(decode_xml_entities "$password")

        local clean_name
        clean_name=$(sanitize_filename "$ssid")
        local filepath="${LOCAL_DIR}/${clean_name}.nmconnection"

        if [ -f "$filepath" ]; then
            skipped_count=$((skipped_count + 1))
            log_debug "Skipping existing: $clean_name"
        else
            if [ "$DRY_RUN" = false ]; then
                create_nmconnection "$ssid" "$password" "$filepath"
            else
                log_info "  + [Dry Run] Would create: $clean_name"
            fi
            imported_count=$((imported_count + 1))
        fi

    done < <(parse_android_xml "$XML_FILE")

    log_info "Imported: $imported_count, Skipped: $skipped_count"
    
    sync_report
}

# -----------------------------------------------------------------------------
# Install to System
# -----------------------------------------------------------------------------

cmd_install() {
    log_info "Starting System Installation..."
    
    # Sync from report first (in case user added networks manually)
    sync_report_to_connections

    if [ "$DRY_RUN" = true ]; then
        log_info "(Dry Run Mode)"
    fi
    
    # Sudo check
    if [ "$EUID" -ne 0 ] && [ "$DRY_RUN" = false ]; then
        exit_with_error "This command requires root privileges (use sudo)."
    fi

    if [ ! -d "$LOCAL_DIR" ]; then
        log_warn "Local directory not found: $LOCAL_DIR"
        return
    fi
    
    local installed_count=0
    local updated_count=0

    # Enable nullglob to handle case where no files exist
    shopt -s nullglob
    for local_path in "$LOCAL_DIR"/*.nmconnection; do
        local filename
        filename=$(basename "$local_path")
        local system_path="$SYSTEM_DIR/$filename"

        local do_install=false
        local do_update=false

        if [ ! -f "$system_path" ]; then
            do_install=true
        else
            # Compare hashes
            local local_hash system_hash
            local_hash=$(get_file_hash "$local_path")
            system_hash=$(get_file_hash "$system_path")
            
            if [ "$local_hash" != "$system_hash" ]; then
                do_update=true
            fi
        fi

        if [ "$do_install" = true ]; then
            log_info "  + Install: $filename"
            installed_count=$((installed_count + 1))
            if [ "$DRY_RUN" = false ]; then
                cp "$local_path" "$system_path"
                chmod 600 "$system_path"
                chown root:root "$system_path"
            fi
        elif [ "$do_update" = true ]; then
            log_info "  ~ Update: $filename"
            updated_count=$((updated_count + 1))
            if [ "$DRY_RUN" = false ]; then
                cp "$local_path" "$system_path"
                chmod 600 "$system_path"
                chown root:root "$system_path"
            fi
        fi
    done
    shopt -u nullglob

    if [ "$DRY_RUN" = false ] && { [ $installed_count -gt 0 ] || [ $updated_count -gt 0 ]; }; then
        log_info "Reloading NetworkManager..."
        nmcli connection reload
    fi

    log_info "Installed: $installed_count, Updated: $updated_count"
    sync_report
}

# -----------------------------------------------------------------------------
# Backup from System
# -----------------------------------------------------------------------------

cmd_backup() {
    log_info "Starting System Backup..."
    
    # Sync from report first
    sync_report_to_connections

    if [ "$DRY_RUN" = true ]; then
        log_info "(Dry Run Mode)"
    fi

    # Sudo check
    if [ "$EUID" -ne 0 ] && [ "$DRY_RUN" = false ]; then
        exit_with_error "This command requires root privileges (use sudo)."
    fi

    ensure_local_dir

    local pulled_count=0
    local updated_count=0
    local sudo_user="${SUDO_USER:-}"

    # Enable nullglob
    shopt -s nullglob
    for system_path in "$SYSTEM_DIR"/*.nmconnection; do
        local filename
        filename=$(basename "$system_path")
        local local_path="$LOCAL_DIR/$filename"

        local do_pull=false
        local do_update=false

        if [ ! -f "$local_path" ]; then
            do_pull=true
        else
            local sys_hash loc_hash
            sys_hash=$(get_file_hash "$system_path")
            loc_hash=$(get_file_hash "$local_path")
            
            if [ "$sys_hash" != "$loc_hash" ]; then
                do_update=true
            fi
        fi

        if [ "$do_pull" = true ]; then
            log_info "  + Pull: $filename"
            pulled_count=$((pulled_count + 1))
            if [ "$DRY_RUN" = false ]; then
                cp "$system_path" "$local_path"
                chmod 664 "$local_path"
                if [ -n "$sudo_user" ]; then
                    chown "$sudo_user:$sudo_user" "$local_path"
                fi
            fi
        elif [ "$do_update" = true ]; then
            log_info "  ~ Update: $filename"
            updated_count=$((updated_count + 1))
            if [ "$DRY_RUN" = false ]; then
                cp "$system_path" "$local_path"
                chmod 664 "$local_path"
                if [ -n "$sudo_user" ]; then
                    chown "$sudo_user:$sudo_user" "$local_path"
                fi
            fi
        fi
    done
    shopt -u nullglob

    log_info "Pulled: $pulled_count, Updated: $updated_count"
    sync_report
}
