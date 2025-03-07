#!/bin/bash
# Common utility functions for Dataiku DSS VM Diagnostic Automation

# Exit on error, treat unset variables as errors
set -eu

# Enhanced ANSI color and style codes for output formatting
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
GRAY='\033[0;90m'

# Bright colors
BRIGHT_RED='\033[1;31m'
BRIGHT_GREEN='\033[1;32m'
BRIGHT_YELLOW='\033[1;33m'
BRIGHT_BLUE='\033[1;34m'
BRIGHT_MAGENTA='\033[1;35m'
BRIGHT_CYAN='\033[1;36m'
BRIGHT_WHITE='\033[1;37m'

# Background colors
BG_RED='\033[0;41m'
BG_GREEN='\033[0;42m'
BG_YELLOW='\033[0;43m'
BG_BLUE='\033[0;44m'

# Text styles
BOLD='\033[1m'
UNDERLINE='\033[4m'
NC='\033[0m' # No Color

# Export colors and styles for use in modules
export BLACK RED GREEN YELLOW BLUE MAGENTA CYAN WHITE GRAY
export BRIGHT_RED BRIGHT_GREEN BRIGHT_YELLOW BRIGHT_BLUE BRIGHT_MAGENTA BRIGHT_CYAN BRIGHT_WHITE
export BG_RED BG_GREEN BG_YELLOW BG_BLUE
export BOLD UNDERLINE NC

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
    echo -e "${CYAN}ℹ️  ${BRIGHT_WHITE}$message${NC}"
    log_message "INFO: $message"
}

# Function to display a pass message
pass() {
    local message="$1"
    echo -e "${GREEN}✓ ${BRIGHT_GREEN}$message${NC}"
    log_message "PASS: $message"
}

# Function to display a fail message
fail() {
    local message="$1"
    local details="${2:-}"
    echo -e "${RED}✗ ${BRIGHT_RED}$message${NC}"
    if [[ -n "$details" ]]; then
        echo -e "${GRAY}  └─ ${RED}$details${NC}"
    fi
    log_message "FAIL: $message $details"
}

# Function to display a warning message
warning() {
    local message="$1"
    echo -e "${YELLOW}⚠️  ${BRIGHT_YELLOW}$message${NC}"
    log_message "WARNING: $message"
}

# Function to display a suggestion message
suggest() {
    local message="$1"
    echo -e "${GRAY}  └─ ${CYAN}$message${NC}"
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
    echo -e "${BLUE}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${BLUE}┃${BRIGHT_WHITE}${BOLD} ${title} ${NC}${BLUE}┃${NC}"
    echo -e "${BLUE}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    log_message "Starting $title"
}

# Function to display section footer
section_footer() {
    local result=$1
    local section_name="$2"
    
    echo ""
    if [[ $result -eq 0 ]]; then
        echo -e "${BG_GREEN}${BLACK} COMPLETE ${NC} ${GREEN}${BOLD}$section_name completed successfully.${NC}"
    else
        echo -e "${BG_RED}${WHITE} FAILED ${NC} ${RED}${BOLD}$section_name failed. Please address the issues above.${NC}"
    fi
    echo -e "${GRAY}────────────────────────────────────────────────────────────${NC}"
    
    if [[ $result -eq 0 ]]; then
        log_message "$section_name completed successfully."
        return 0
    else
        log_message "$section_name failed."
        return 1
    fi
}

# Function to display progress
show_progress() {
    local current="$1"
    local total="$2"
    local description="$3"
    local percentage=$((current * 100 / total))
    
    echo -e "\n${BRIGHT_BLUE}[$current/$total]${NC} ${BLUE}${BOLD}$description${NC}"
    
    # Create a progress bar with 30 segments
    local completed=$((percentage * 30 / 100))
    local remaining=$((30 - completed))
    
    echo -ne "${BLUE}[${NC}"
    # Print completed segments
    for ((i=0; i<completed; i++)); do
        echo -ne "${BRIGHT_BLUE}█${NC}"
    done
    # Print remaining segments
    for ((i=0; i<remaining; i++)); do
        echo -ne "${GRAY}▒${NC}"
    done
    echo -e "${BLUE}]${NC} ${BRIGHT_WHITE}${percentage}%${NC}\n"
}

# Function to display a property value in the configuration output
show_config_property() {
    local name="$1"
    local value="$2"
    
    echo -e "${GRAY}  │ ${BRIGHT_WHITE}$name:${NC} ${CYAN}$value${NC}"
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