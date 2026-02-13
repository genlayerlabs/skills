#!/usr/bin/env bash

# ============================================================================
# SHARED LOGGING FUNCTIONS
# ============================================================================
# This script provides consistent logging functions across all scripts
#
# Required environment variables:
#   DEBUG_MODE - Enable debug logging (true/false, defaults to false)
#
# Usage:
#   source this script and use function:
#   log_info "Your message here"
#   log_success "Your success message here"
#   log_warning "Warning message"
#   log_error "Error message"
#   log_debug "Debug message (only shown if DEBUG_MODE=true)"
#
#   source this script and use log() function:
#   log "info" "Your message here"
#   log "error" "Error message"
#   log "debug" "Debug message (only shown if DEBUG_MODE=true)"

# Set default for DEBUG_MODE if not already set
: "${DEBUG_MODE:=false}"
# Timestamp configuration
: "${LOG_SHOW_TIMESTAMP:=true}"
: "${LOG_TIMESTAMP_FORMAT:=%Y-%m-%d %H:%M:%S}"

log_timestamp_prefix() {
    if [[ "${LOG_SHOW_TIMESTAMP:-true}" == "true" ]]; then
        local ts
        ts="$(date +"${LOG_TIMESTAMP_FORMAT}")"
        echo -n "[${ts}] "
    fi
}

# Color definitions
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

log_info() {
    echo -e "$(log_timestamp_prefix)${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "$(log_timestamp_prefix)${GREEN}[SUCCESS]${NC} $*" >&2
}

log_warning() {
    echo -e "$(log_timestamp_prefix)${YELLOW}[WARNING]${NC} $*" >&2
}

log_error() {
    echo -e "$(log_timestamp_prefix)${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
    if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
        echo -e "$(log_timestamp_prefix)${GRAY}[DEBUG]${NC} $*" >&2
    fi
}

# Generic log function that accepts level and message
log() {
    local level="$1"
    shift

    case "$level" in
        "info"|"INFO")
            log_info "$@"
            ;;
        "success"|"SUCCESS")
            log_success "$@"
            ;;
        "warning"|"WARNING")
            log_warning "$@"
            ;;
        "error"|"ERROR")
            log_error "$@"
            ;;
        "debug"|"DEBUG")
            log_debug "$@"
            ;;
        *)
            echo -e "$(log_timestamp_prefix)[UNKNOWN] $*" >&2
            ;;
    esac
}
