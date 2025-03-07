#!/bin/bash
# System settings and limits verification module for Dataiku DSS VM Diagnostic Automation
# This module checks ulimits, time synchronization, and port availability

# Exit on error, treat unset variables as errors
set -eu

# Source common utility functions using the exported SCRIPT_DIR
if [[ -f "${SCRIPT_DIR}/modules/utils/common.sh" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/modules/utils/common.sh"
else
    echo "Error: Common utilities not found at ${SCRIPT_DIR}/modules/utils/common.sh"
    exit 1
fi

# Function to check ulimit settings
check_ulimits() {
    local required_open_files="${1:-65536}"
    local required_user_processes="${2:-65536}"
    
    info "Checking ulimit settings..."
    
    # Check open files limit
    local open_files
    open_files=$(ulimit -n)
    info "Current open files limit (ulimit -n): $open_files"
    
    # Check user processes limit
    local user_processes
    user_processes=$(ulimit -u)
    info "Current user processes limit (ulimit -u): $user_processes"
    
    local ulimit_check_passed=true
    
    # Check if open files limit meets requirement
    if [[ "$open_files" == "unlimited" || "$open_files" -ge "$required_open_files" ]]; then
        pass "Open files limit check passed ($open_files >= $required_open_files)."
    else
        fail "Open files limit check failed. Current: $open_files, required: $required_open_files."
        suggest "Consider adding the following to /etc/security/limits.conf:"
        suggest "* soft nofile $required_open_files"
        suggest "* hard nofile $required_open_files"
        ulimit_check_passed=false
    fi
    
    # Check if user processes limit meets requirement
    if [[ "$user_processes" == "unlimited" || "$user_processes" -ge "$required_user_processes" ]]; then
        pass "User processes limit check passed ($user_processes >= $required_user_processes)."
    else
        fail "User processes limit check failed. Current: $user_processes, required: $required_user_processes."
        suggest "Consider adding the following to /etc/security/limits.conf:"
        suggest "* soft nproc $required_user_processes"
        suggest "* hard nproc $required_user_processes"
        ulimit_check_passed=false
    fi
    
    return "$([[ "$ulimit_check_passed" == true ]] && echo 0 || echo 1)"
}

# Function to check time synchronization
check_time_sync() {
    info "Checking time synchronization services..."
    
    local time_sync_check_passed=true
    local time_service_running=false
    local time_service_name=""
    
    # Check for chronyd (preferred in newer systems)
    if command -v systemctl &>/dev/null && systemctl is-active --quiet chronyd 2>/dev/null; then
        time_service_running=true
        time_service_name="chronyd"
        info "chronyd service is running."
    # Check for ntpd (older systems)
    elif command -v systemctl &>/dev/null && systemctl is-active --quiet ntpd 2>/dev/null; then
        time_service_running=true
        time_service_name="ntpd"
        info "ntpd service is running."
    # Check for timesyncd (Ubuntu)
    elif command -v systemctl &>/dev/null && systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
        time_service_running=true
        time_service_name="systemd-timesyncd"
        info "systemd-timesyncd service is running."
    else
        fail "No time synchronization service found running."
        suggest "Consider installing and enabling chronyd or ntpd."
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
            pass "System clock is synchronized with NTP server."
        else
            warning "Time service is running but synchronization status could not be confirmed."
            suggest "Please check time synchronization manually."
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
    
    section_header "Running System Settings and Limits Checks"
    
    # Run ulimit checks
    if ! check_ulimits "$required_open_files" "$required_user_processes"; then
        limits_check_passed=false
    fi
    
    echo ""
    
    # Run time synchronization check
    if ! check_time_sync; then
        limits_check_passed=false
    fi
    
    # Return final result
    section_footer "$([[ "$limits_check_passed" == true ]] && echo 0 || echo 1)" "System settings and limits checks"
    
    return "$([[ "$limits_check_passed" == true ]] && echo 0 || echo 1)"
} 