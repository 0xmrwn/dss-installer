#!/bin/bash
# System settings and limits verification module for Dataiku DSS VM Diagnostic Automation
# This module checks ulimits, time synchronization, and port availability

# Exit on error, treat unset variables as errors
set -eu

# Source common utility functions if they exist
if [[ -f "$(dirname "$0")/utils/common.sh" ]]; then
    # shellcheck disable=SC1091
    source "$(dirname "$0")/utils/common.sh"
fi

# Log file path (can be overridden by the main script)
LOG_FILE=${LOG_FILE:-"diagnostics.log"}

# ANSI color codes for output formatting
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check ulimit settings
check_ulimits() {
    local required_open_files="${1:-65536}"
    local required_user_processes="${2:-65536}"
    
    echo "[INFO] Checking ulimit settings..."
    
    # Check open files limit
    local open_files
    open_files=$(ulimit -n)
    echo "[INFO] Current open files limit (ulimit -n): $open_files"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Current open files limit: $open_files" >> "$LOG_FILE"
    
    # Check user processes limit
    local user_processes
    user_processes=$(ulimit -u)
    echo "[INFO] Current user processes limit (ulimit -u): $user_processes"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Current user processes limit: $user_processes" >> "$LOG_FILE"
    
    local ulimit_check_passed=true
    
    # Check if open files limit meets requirement
    if [[ "$open_files" == "unlimited" || "$open_files" -ge "$required_open_files" ]]; then
        echo -e "${GREEN}[PASS] Open files limit check passed ($open_files >= $required_open_files).${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: Open files limit check passed." >> "$LOG_FILE"
    else
        echo -e "${RED}[FAIL] Open files limit check failed. Current: $open_files, required: $required_open_files.${NC}"
        echo -e "${YELLOW}Consider adding the following to /etc/security/limits.conf:${NC}"
        echo -e "${YELLOW}* soft nofile $required_open_files${NC}"
        echo -e "${YELLOW}* hard nofile $required_open_files${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Open files limit check failed. Current: $open_files, required: $required_open_files." >> "$LOG_FILE"
        ulimit_check_passed=false
    fi
    
    # Check if user processes limit meets requirement
    if [[ "$user_processes" == "unlimited" || "$user_processes" -ge "$required_user_processes" ]]; then
        echo -e "${GREEN}[PASS] User processes limit check passed ($user_processes >= $required_user_processes).${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: User processes limit check passed." >> "$LOG_FILE"
    else
        echo -e "${RED}[FAIL] User processes limit check failed. Current: $user_processes, required: $required_user_processes.${NC}"
        echo -e "${YELLOW}Consider adding the following to /etc/security/limits.conf:${NC}"
        echo -e "${YELLOW}* soft nproc $required_user_processes${NC}"
        echo -e "${YELLOW}* hard nproc $required_user_processes${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: User processes limit check failed. Current: $user_processes, required: $required_user_processes." >> "$LOG_FILE"
        ulimit_check_passed=false
    fi
    
    return "$([[ "$ulimit_check_passed" == true ]] && echo 0 || echo 1)"
}

# Function to check time synchronization
check_time_sync() {
    echo "[INFO] Checking time synchronization services..."
    
    local time_sync_check_passed=true
    local time_service_running=false
    local time_service_name=""
    
    # Check for chronyd (preferred in newer systems)
    if command -v systemctl &>/dev/null && systemctl is-active --quiet chronyd 2>/dev/null; then
        time_service_running=true
        time_service_name="chronyd"
        echo "[INFO] chronyd service is running."
        echo "$(date '+%Y-%m-%d %H:%M:%S') - chronyd service is running." >> "$LOG_FILE"
    # Check for ntpd (older systems)
    elif command -v systemctl &>/dev/null && systemctl is-active --quiet ntpd 2>/dev/null; then
        time_service_running=true
        time_service_name="ntpd"
        echo "[INFO] ntpd service is running."
        echo "$(date '+%Y-%m-%d %H:%M:%S') - ntpd service is running." >> "$LOG_FILE"
    # Check for timesyncd (Ubuntu)
    elif command -v systemctl &>/dev/null && systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
        time_service_running=true
        time_service_name="systemd-timesyncd"
        echo "[INFO] systemd-timesyncd service is running."
        echo "$(date '+%Y-%m-%d %H:%M:%S') - systemd-timesyncd service is running." >> "$LOG_FILE"
    else
        echo -e "${RED}[FAIL] No time synchronization service found running.${NC}"
        echo -e "${YELLOW}Consider installing and enabling chronyd or ntpd.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: No time synchronization service found running." >> "$LOG_FILE"
        time_sync_check_passed=false
    fi
    
    # If a time service is running, check if it's actually synchronized
    if [[ "$time_service_running" == true ]]; then
        local sync_status=false
        
        case "$time_service_name" in
            "chronyd")
                if command -v chronyc &>/dev/null; then
                    if chronyc tracking | grep -q "Leap status.*Normal"; then
                        sync_status=true
                    fi
                fi
                ;;
            "ntpd")
                if command -v ntpq &>/dev/null; then
                    if ntpq -p | grep -q "^\*"; then
                        sync_status=true
                    fi
                fi
                ;;
            "systemd-timesyncd")
                if command -v timedatectl &>/dev/null; then
                    if timedatectl status | grep -q "NTP synchronized: yes"; then
                        sync_status=true
                    fi
                fi
                ;;
        esac
        
        if [[ "$sync_status" == true ]]; then
            echo -e "${GREEN}[PASS] System clock is synchronized with NTP server.${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: System clock is synchronized with NTP server." >> "$LOG_FILE"
        else
            echo -e "${YELLOW}[WARNING] Time service is running but synchronization status could not be confirmed.${NC}"
            echo -e "${YELLOW}Please check time synchronization manually.${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: Time service is running but synchronization status could not be confirmed." >> "$LOG_FILE"
            # Not marking as failed since the service is running
        fi
    fi
    
    return "$([[ "$time_sync_check_passed" == true ]] && echo 0 || echo 1)"
}

# Main function to run all limit checks
run_limits_checks() {
    local required_open_files="${1:-65536}"
    local required_user_processes="${2:-65536}"
    local limits_check_passed=true
    
    echo "==============================================="
    echo "Running System Settings and Limits Checks"
    echo "==============================================="
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting system settings and limits checks" >> "$LOG_FILE"
    
    # Run ulimit checks
    if ! check_ulimits "$required_open_files" "$required_user_processes"; then
        limits_check_passed=false
    fi
    
    echo ""
    
    # Run time synchronization check
    if ! check_time_sync; then
        limits_check_passed=false
    fi
    
    echo ""
    echo "==============================================="
    
    if [[ "$limits_check_passed" == true ]]; then
        echo -e "${GREEN}System settings and limits checks completed successfully.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - System settings and limits checks completed successfully." >> "$LOG_FILE"
        return 0
    else
        echo -e "${RED}System settings and limits checks failed. Please address the issues above.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - System settings and limits checks failed." >> "$LOG_FILE"
        return 1
    fi
} 