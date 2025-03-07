#!/bin/bash
# Common utility functions for Dataiku DSS VM Diagnostic Automation

# Exit on error, treat unset variables as errors
set -eu

# ANSI color codes for output formatting
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Export colors for use in modules
export GREEN RED YELLOW BLUE NC

# Default log file path (can be overridden by the main script)
LOG_FILE=${LOG_FILE:-"diagnostics.log"}

# Function to log a message to file
log_message() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp - $message" >> "$LOG_FILE"
}

# Function to display an info message
info() {
    local message="$1"
    echo "[INFO] $message"
    log_message "INFO: $message"
}

# Function to display a pass message
pass() {
    local message="$1"
    echo -e "${GREEN}[PASS] $message${NC}"
    log_message "PASS: $message"
}

# Function to display a fail message
fail() {
    local message="$1"
    local details="${2:-}"
    echo -e "${RED}[FAIL] $message${NC}"
    if [[ -n "$details" ]]; then
        echo -e "${RED}       $details${NC}"
    fi
    log_message "FAIL: $message $details"
}

# Function to display a warning message
warning() {
    local message="$1"
    echo -e "${YELLOW}[WARNING] $message${NC}"
    log_message "WARNING: $message"
}

# Function to display a suggestion message
suggest() {
    local message="$1"
    echo -e "${YELLOW}$message${NC}"
}

# Function to handle check results
# Usage: report_check_result $? "Check description"
report_check_result() {
    local result=$1
    local description="$2"
    
    if [[ $result -eq 0 ]]; then
        pass "$description check passed."
        return 0
    else
        fail "$description check failed."
        return 1
    fi
}

# Function to display section header
section_header() {
    local title="$1"
    echo ""
    echo "==============================================="
    echo "$title"
    echo "==============================================="
    log_message "Starting $title"
}

# Function to display section footer
section_footer() {
    local result=$1
    local section_name="$2"
    
    echo ""
    echo "==============================================="
    
    if [[ $result -eq 0 ]]; then
        echo -e "${GREEN}$section_name completed successfully.${NC}"
        log_message "$section_name completed successfully."
        return 0
    else
        echo -e "${RED}$section_name failed. Please address the issues above.${NC}"
        log_message "$section_name failed."
        return 1
    fi
}

# Function to compare versions (handles numeric version comparisons)
# Returns 0 if version1 >= version2, 1 otherwise
version_gte() {
    local version1="$1"
    local version2="$2"
    
    if [[ "$(printf '%s\n' "$version2" "$version1" | sort -V | head -n1)" = "$version2" ]]; then
        return 0
    else
        return 1
    fi
}

# Function to check if a value is in a comma-separated list
# Usage: value_in_list "value" "item1,item2,item3"
value_in_list() {
    local value="$1"
    local list="$2"
    
    for item in $(echo "$list" | tr ',' ' '); do
        if [[ "$value" == *"$item"* || "$item" == *"$value"* ]]; then
            return 0
        fi
    done
    
    return 1
} 