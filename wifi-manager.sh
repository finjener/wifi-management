#!/usr/bin/env bash

# WiFi Manager - Bash Implementation
# A tool for synchronizing WiFi networks between Android devices and Linux.
#
# USAGE:
#   ./wifi-manager.sh [COMMAND] [OPTIONS]
#
# COMMANDS:
#   import-android   Import networks from Android XML file (data/WifiConfigStore.xml)
#   pull-android     Pull WiFi config from Android device via ADB (requires root)
#   push-android     Push WiFi config to Android device via ADB (requires root)
#   sync-local       Bidirectional sync: Report <-> Local connection files
#   install          Install local connections to system (requires sudo)
#   backup           Backup system connections to local directory (requires sudo)
#
# OPTIONS:
#   --dry-run        Preview changes without making any modifications
#   --help           Show this help message
#
# EXAMPLES:
#   ./wifi-manager.sh import-android
#   ./wifi-manager.sh install --dry-run
#   sudo ./wifi-manager.sh backup

set -e  # Exit on error
set -u  # Exit on undefined variable

# -----------------------------------------------------------------------------
# Script Location & Configuration Loading
# -----------------------------------------------------------------------------

# Resolve script directory (handles symlinks)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration (user config takes precedence)
load_config() {
    # Default config in script directory
    local default_config="${SCRIPT_DIR}/config.env"
    
    # User config location
    local user_config="${HOME}/.config/wifi-manager/config.env"
    
    # Load default config first
    if [ -f "$default_config" ]; then
        # shellcheck source=config.env
        source "$default_config"
    fi
    
    # Override with user config if exists
    if [ -f "$user_config" ]; then
        # shellcheck source=/dev/null
        source "$user_config"
    fi
    
    # Set BASE_DIR (allow env override)
    BASE_DIR="${WIFI_MANAGER_BASE:-data}"
    
    # Convert relative BASE_DIR to absolute
    if [[ "$BASE_DIR" != /* ]]; then
        BASE_DIR="${SCRIPT_DIR}/${BASE_DIR}"
    fi
}

# -----------------------------------------------------------------------------
# Source Library Modules
# -----------------------------------------------------------------------------

source_libraries() {
    local lib_dir="${SCRIPT_DIR}/lib"
    
    if [ ! -d "$lib_dir" ]; then
        echo "Error: Library directory not found: $lib_dir" >&2
        exit 1
    fi
    
    # Source in dependency order
    source "${lib_dir}/utils.sh"
    source "${lib_dir}/sync.sh"
    source "${lib_dir}/nmconnection.sh"
    source "${lib_dir}/adb.sh"
}

# -----------------------------------------------------------------------------
# Global State
# -----------------------------------------------------------------------------

DRY_RUN=false

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------

show_help() {
    cat << 'EOF'
WiFi Manager - Synchronize WiFi networks between Android and Linux

USAGE:
    wifi-manager.sh [COMMAND] [OPTIONS]

COMMANDS:
    import-android   Import networks from Android XML file (data/WifiConfigStore.xml)
    pull-android     Pull WiFi config from Android device via ADB (requires root)
    push-android     Push WiFi config to Android device via ADB (requires root)
    sync-local       Bidirectional sync: Report <-> Local connection files
    install          Install local connections to system (requires sudo)
    backup           Backup system connections to local directory (requires sudo)

OPTIONS:
    --dry-run        Preview changes without making any modifications
    --help           Show this help message

EXAMPLES:
    # Import from local XML file
    ./wifi-manager.sh import-android

    # Preview what install would do
    ./wifi-manager.sh install --dry-run

    # Backup system networks (requires root)
    sudo ./wifi-manager.sh backup

    # Pull from Android device and import
    ./wifi-manager.sh pull-android

CONFIGURATION:
    Default config:  ./config.env
    User override:   ~/.config/wifi-manager/config.env

EOF
}

# -----------------------------------------------------------------------------
# Command Dispatcher
# -----------------------------------------------------------------------------

main() {
    # Load configuration and libraries
    load_config
    source_libraries
    
    # Check dependencies
    check_dependencies
    
    # Resolve full paths
    resolve_paths
    
    # Parse arguments
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        show_help
        exit 0
    fi

    local command=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            import-android|install|backup|sync-local|pull-android|push-android)
                command="$1"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown argument: $1" >&2
                echo "Run with --help for usage information." >&2
                exit 1
                ;;
        esac
    done

    if [ -z "$command" ]; then
        show_help
        exit 1
    fi

    # Dispatch command
    case "$command" in
        import-android)
            cmd_import_android
            ;;
        install)
            cmd_install
            ;;
        backup)
            cmd_backup
            ;;
        sync-local)
            sync_report
            ;;
        pull-android)
            cmd_pull_android
            ;;
        push-android)
            cmd_push_android
            ;;
    esac
}

main "$@"
