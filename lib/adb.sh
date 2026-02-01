#!/usr/bin/env bash
# WiFi Manager - ADB Operations
# Sourced by wifi-manager.sh

# -----------------------------------------------------------------------------
# ADB Utilities
# -----------------------------------------------------------------------------

check_adb() {
    if ! command -v adb &> /dev/null; then
        exit_with_error "ADB not found. Please install Android Platform Tools."
    fi
    
    local devices
    devices=$(adb devices | grep -w "device")
    if [ -z "$devices" ]; then
        exit_with_error "No Android device connected (or unauthorized). Check USB debugging."
    fi
    
    log_debug "ADB device connected"
}

get_device_wifi_path() {
    # Try newer path first, then older
    local target_path="$ADB_WIFI_PATH"
    
    if ! adb shell "su -c 'ls \"$target_path\"'" &>/dev/null; then
        target_path="$ADB_WIFI_PATH_OLD"
        if ! adb shell "su -c 'ls \"$target_path\"'" &>/dev/null; then
            echo ""
            return 1
        fi
    fi
    
    echo "$target_path"
}

# -----------------------------------------------------------------------------
# Pull from Android Device
# -----------------------------------------------------------------------------

cmd_pull_android() {
    log_info "Starting ADB Pull..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "(Dry Run Mode)"
        return
    fi
    
    check_adb

    local target_path
    target_path=$(get_device_wifi_path)
    
    if [ -z "$target_path" ]; then
        exit_with_error "WifiConfigStore.xml not found on device (checked new and old paths)."
    fi

    log_info "Pulling from: $target_path"
    
    # Create temp copy on device to avoid direct system file access issues
    local temp_remote="${ADB_TEMP_PATH}"
    
    adb shell "su -c 'cp \"$target_path\" \"$temp_remote\"'"
    adb shell "su -c 'chmod 666 \"$temp_remote\"'"
    
    mkdir -p "${BASE_DIR}"
    if adb pull "$temp_remote" "$XML_FILE"; then
        log_info "Successfully pulled to $XML_FILE"
        # Clean up
        adb shell "rm \"$temp_remote\""
    else
        adb shell "rm \"$temp_remote\""
        exit_with_error "Failed to pull file via ADB."
    fi
    
    # Auto-trigger import after pull
    log_info "Triggering Import..."
    cmd_import_android
}

# -----------------------------------------------------------------------------
# Push to Android Device
# -----------------------------------------------------------------------------

cmd_push_android() {
    log_info "Starting ADB Push..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "(Dry Run Mode)"
        return
    fi

    check_adb
    
    if [ ! -f "$XML_FILE" ]; then
        exit_with_error "Local XML file not found: $XML_FILE"
    fi

    # Determine target path
    local target_path
    target_path=$(get_device_wifi_path)
    
    # If no existing path found, default to new path
    if [ -z "$target_path" ]; then
        target_path="$ADB_WIFI_PATH"
    fi

    log_warn "This will overwrite WiFi config on the device: $target_path"
    read -p "Are you sure? [y/N]: " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Aborted."
        return
    fi
    
    local temp_remote="${ADB_TEMP_PATH}.push"
    
    # Push to sdcard
    if ! adb push "$XML_FILE" "$temp_remote"; then
        exit_with_error "Failed to push file to temp location."
    fi

    log_info "Moving to system location..."
    
    # Create backup on device
    adb shell "su -c 'cp \"$target_path\" \"${target_path}.bak\"'" 2>/dev/null || true
    
    # Overwrite
    if adb shell "su -c 'cp \"$temp_remote\" \"$target_path\"'"; then
        # Fix permissions
        adb shell "su -c 'chmod 600 \"$target_path\"'"
        adb shell "su -c 'chown wifi:wifi \"$target_path\"'" 2>/dev/null || \
            adb shell "su -c 'chown system:wifi \"$target_path\"'" 2>/dev/null || true
        
        adb shell "rm \"$temp_remote\""
        log_info "Push successful."
        
        log_info "Restarting WiFi service..."
        adb shell "su -c 'svc wifi disable'"
        sleep 1
        adb shell "su -c 'svc wifi enable'"
        log_info "Done."
    else
        adb shell "rm \"$temp_remote\""
        exit_with_error "Failed to move file to system location. Check root access."
    fi
}
