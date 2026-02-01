#!/usr/bin/env bash
# WiFi Manager - Utility Functions
# Sourced by wifi-manager.sh

# -----------------------------------------------------------------------------
# Color Definitions
# -----------------------------------------------------------------------------

if [[ "${COLOR_OUTPUT:-true}" == "true" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# -----------------------------------------------------------------------------
# Logging Functions
# -----------------------------------------------------------------------------

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_debug() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

exit_with_error() {
    log_error "$1"
    exit 1
}

# -----------------------------------------------------------------------------
# Dependency Checking
# -----------------------------------------------------------------------------

check_dependencies() {
    local deps=("grep" "sed" "awk" "md5sum" "uuidgen")
    local missing=()
    
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        exit_with_error "Missing required dependencies: ${missing[*]}"
    fi
    
    log_debug "All dependencies satisfied"
}

check_nmcli() {
    if ! command -v nmcli &> /dev/null; then
        log_warn "nmcli not found - NetworkManager operations will fail"
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# String/Filename Utilities
# -----------------------------------------------------------------------------

sanitize_filename() {
    local name="$1"
    # Match Python logic:
    # 1. Replace invalid chars with underscore: <>:"/\|?*
    # 2. Strip leading/trailing space and dot
    echo "$name" | sed 's/[<>:"/\\|?*]/_/g' | sed -e 's/^[ .]*//' -e 's/[ .]*$//'
}

decode_xml_entities() {
    local text="$1"
    # Decode common XML entities
    text=$(echo "$text" | sed \
        -e 's/&quot;/"/g' \
        -e 's/&amp;/\&/g' \
        -e "s/&apos;/'/g" \
        -e 's/&lt;/</g' \
        -e 's/&gt;/>/g' \
        -e 's/&#x22;/"/g' \
        -e 's/&#x27;/'"'"'/g' \
        -e 's/&#x26;/\&/g' \
        -e 's/&#x3c;/</g' \
        -e 's/&#x3e;/>/g')
    # Remove surrounding quotes
    text=${text%\"}
    text=${text#\"}
    echo "$text"
}

# -----------------------------------------------------------------------------
# File Utilities
# -----------------------------------------------------------------------------

get_file_hash() {
    local filepath="$1"
    if [ ! -f "$filepath" ]; then
        echo ""
        return
    fi
    # Filter out timestamp and uuid lines, then hash
    grep -vE "^(timestamp=|uuid=)" "$filepath" | md5sum | awk '{print $1}'
}

# -----------------------------------------------------------------------------
# Network Status
# -----------------------------------------------------------------------------

get_network_status() {
    local ssid="$1"
    # Check if network is currently active
    if command -v nmcli &> /dev/null; then
        local active
        active=$(nmcli -t -f NAME connection show --active 2>/dev/null | grep -Fx "$ssid" || true)
        if [ -n "$active" ]; then
            echo "Active"
            return
        fi
    fi
    echo "Saved"
}

# -----------------------------------------------------------------------------
# Path Resolution
# -----------------------------------------------------------------------------

resolve_paths() {
    # Build full paths from config
    LOCAL_DIR="${BASE_DIR}/${LOCAL_DIR_NAME}"
    XML_FILE="${BASE_DIR}/${XML_FILENAME}"
    REPORT_FILE="${BASE_DIR}/${REPORT_FILENAME}"
    
    log_debug "LOCAL_DIR: $LOCAL_DIR"
    log_debug "XML_FILE: $XML_FILE"
    log_debug "REPORT_FILE: $REPORT_FILE"
}

ensure_local_dir() {
    if [ ! -d "$LOCAL_DIR" ]; then
        mkdir -p "$LOCAL_DIR"
        log_debug "Created directory: $LOCAL_DIR"
    fi
}
