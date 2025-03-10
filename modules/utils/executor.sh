#!/bin/bash
# Utility functions for module execution

# Exit on error, treat unset variables as errors
set -eu

# Function to run module and handle auto-fix if needed
run_module_with_auto_fix() {
    local module_name="$1"
    local module_path="$2"
    local check_function="$3"
    local auto_fix_issue="$4"
    local module_description="$5"
    local params_prefix="$6"  # Prefix for params variables
    local status_prefix="$7"  # Prefix for status variables
    shift 7
    local check_args=("$@")   # Additional arguments for the check function
    
    # Setup progress tracking
    eval "$status_prefix"_current_check='$(('"\$$status_prefix"'_current_check + 1))'
    
    # Get the values using indirect variable references
    local current_check_var="${status_prefix}_current_check"
    local total_checks_var="${status_prefix}_total_checks"
    
    # Use eval to expand the variable names and access their values
    local current_check_val
    local total_checks_val
    eval "current_check_val=\${$current_check_var}"
    eval "total_checks_val=\${$total_checks_var}"
    
    # Call show_progress with properly quoted arguments
    show_progress "$current_check_val" "$total_checks_val" "$module_description"
    
    if [[ -f "$module_path" ]]; then
        log_message "Running $module_name checks"
        
        # Source the module to access its functions
        # shellcheck disable=SC1090
        source "$module_path"
        
        # Run checks with parameters
        if ! "$check_function" "${check_args[@]}"; then
            # If auto-fix is enabled and there's an associated auto-fix for this module
            if [[ "${AUTO_FIX}" == true && -n "$auto_fix_issue" ]]; then
                log_message "$module_name checks failed. Attempting auto-fix..."
                info "$module_name checks failed. Attempting auto-fix..."
                
                # Attempt to fix issues
                eval "$status_prefix"_fixes_attempted=true
                
                # Arguments for auto_fix_by_issue depend on the module
                case "$auto_fix_issue" in
                    "locale")
                        # Correctly retrieve the locale_required value
                        local locale_var="${params_prefix}_locale_required"
                        local locale_required
                        eval "locale_required=\${$locale_var}"
                        
                        if auto_fix_by_issue "$auto_fix_issue" "$locale_required"; then
                            if "$check_function" "${check_args[@]}"; then
                                pass "$module_name issues fixed successfully!"
                                eval "$status_prefix"_fixes_succeeded=true
                                eval "$status_prefix"_reboot_required=true
                            else
                                fail "$module_name issues could not be fixed automatically."
                                eval "$status_prefix"_all_checks_passed=false
                            fi
                        else
                            fail "Failed to automatically fix $module_name issues."
                            eval "$status_prefix"_all_checks_passed=false
                        fi
                        ;;
                    
                    "ulimits")
                        # Correctly retrieve ulimits values
                        local ulimit_files_var="${params_prefix}_ulimit_files"
                        local ulimit_processes_var="${params_prefix}_ulimit_processes"
                        local ulimit_files
                        local ulimit_processes
                        eval "ulimit_files=\${$ulimit_files_var}"
                        eval "ulimit_processes=\${$ulimit_processes_var}"
                        
                        if auto_fix_by_issue "$auto_fix_issue" "$ulimit_files" "$ulimit_processes"; then
                            info "Ulimit settings updated. Continuing with other fixes..."
                            eval "$status_prefix"_reboot_required=true
                        else
                            warning "Failed to fix ulimit settings. Continuing with other fixes..."
                        fi
                        
                        # Try to fix time sync issues
                        if auto_fix_by_issue "time_sync"; then
                            info "Time synchronization configured. Re-running checks..."
                        else
                            warning "Failed to fix time synchronization. Continuing..."
                        fi
                        
                        # Re-run limits checks to verify if fixes succeeded
                        if "$check_function" "${check_args[@]}"; then
                            pass "System limits issues fixed successfully!"
                            eval "$status_prefix"_fixes_succeeded=true
                        else
                            fail "Some system limits issues could not be fixed automatically."
                            eval "$status_prefix"_all_checks_passed=false
                        fi
                        ;;
                    
                    "software")
                        # Handle software-specific fixes with specialized logic
                        handle_software_fixes "$module_path" "$check_function" "$params_prefix" "$status_prefix" "${check_args[@]}"
                        ;;
                    
                    *)
                        # Manual intervention required
                        info "$module_name checks failed. Manual intervention required."
                        eval "$status_prefix"_all_checks_passed=false
                        ;;
                esac
            else
                # No auto-fix available or not enabled
                eval "$status_prefix"_all_checks_passed=false
            fi
        fi
    else
        fail "$module_name check module not found at $module_path"
        log_message "Error: $module_name check module not found"
        eval "$status_prefix"_all_checks_passed=false
    fi
}

# Function to handle software-specific fixes
handle_software_fixes() {
    local module_path="$1"
    local check_function="$2"
    local params_prefix="$3"  # Prefix for params variables
    local status_prefix="$4"  # Prefix for status variables
    shift 4
    local check_args=("$@")

    # Global variables to track issues
    MISSING_PACKAGES=""
    MISSING_REPOS=""
    MISSING_JAVA=false
    
    # Check if we have global variables for missing packages/repos
    if [[ -z "$MISSING_PACKAGES" ]]; then
        # Fall back to log parsing if global variables aren't set
        MISSING_PACKAGES=$(grep -a "FAIL: The following packages are missing:" "$LOG_FILE" | tail -1 | sed 's/.*missing://')
    fi
    
    if [[ -z "$MISSING_REPOS" ]]; then
        # Fall back to log parsing if global variables aren't set
        MISSING_REPOS=$(grep -a "FAIL: The following repositories are missing:" "$LOG_FILE" | tail -1 | sed 's/.*missing://')
    fi
    
    # Check for missing Java installation
    if grep -q "FAIL: Java is not installed" "$LOG_FILE"; then
        MISSING_JAVA=true
    fi
    
    # Check if missing packages were found
    if [[ -n "$MISSING_PACKAGES" ]]; then
        # Attempt to fix missing packages
        eval "$status_prefix"_fixes_attempted=true
        if auto_fix_by_issue "packages" "$MISSING_PACKAGES"; then
            info "Packages fixed, checking repositories..."
        else
            fail "Failed to automatically install missing packages."
        fi
    fi
    
    # Check if missing repositories were found
    if [[ -n "$MISSING_REPOS" ]]; then
        # Attempt to fix missing repositories
        eval "$status_prefix"_fixes_attempted=true
        if auto_fix_by_issue "repositories" "$MISSING_REPOS"; then
            info "Repositories fixed, re-running software checks..."
        else
            fail "Failed to automatically configure missing repositories."
        fi
    fi
    
    # Check if Java needs to be installed
    if [[ "$MISSING_JAVA" == true ]]; then
        eval "$status_prefix"_fixes_attempted=true
        info "Attempting to fix missing Java installation..."
        # Correctly retrieve java_versions value
        local java_versions_var="${params_prefix}_java_versions"
        local java_versions
        eval "java_versions=\${$java_versions_var}"
        if auto_fix_by_issue "java" "$java_versions"; then
            info "Java installation succeeded, re-running software checks..."
        else
            fail "Failed to automatically install Java."
            log_message "Java auto-installation failed. Continuing with other checks."
            info "Manual Java installation will be required later."
        fi
    fi
    
    # Re-run software checks to verify if fixes succeeded
    if "$check_function" "${check_args[@]}"; then
        pass "Software issues fixed successfully!"
        eval "$status_prefix"_fixes_succeeded=true
    else
        fail "Some software issues could not be fixed automatically."
        eval "$status_prefix"_all_checks_passed=false
    fi
}

# Function to print diagnostic summary
print_summary() {
    local status_prefix="$1"  # Prefix for status variables
    
    echo ""
    echo -e "${BRIGHT_BLUE}${BOLD}DIAGNOSTIC SUMMARY${NC}"
    echo -e "${GRAY}──────────────────────────────────────────${NC}"
    
    # Access the status variables using the safer approach
    local fixes_attempted_var="${status_prefix}_fixes_attempted"
    local fixes_succeeded_var="${status_prefix}_fixes_succeeded"
    local reboot_required_var="${status_prefix}_reboot_required"
    local all_checks_passed_var="${status_prefix}_all_checks_passed"
    
    local fixes_attempted
    local fixes_succeeded
    local reboot_required
    local all_checks_passed
    
    eval "fixes_attempted=\${$fixes_attempted_var}"
    eval "fixes_succeeded=\${$fixes_succeeded_var}"
    eval "reboot_required=\${$reboot_required_var}"
    eval "all_checks_passed=\${$all_checks_passed_var}"
    
    if [[ "$AUTO_FIX" == true && "$fixes_attempted" == true ]]; then
        echo -e "${BRIGHT_WHITE}${BOLD}Auto-Fix Status:${NC}"
        if [[ "$fixes_succeeded" == true ]]; then
            echo -e "${GREEN}[✔] ${BRIGHT_GREEN}Some issues were successfully fixed automatically.${NC}"
        else
            echo -e "${YELLOW}[!]  ${BRIGHT_YELLOW}Auto-fix was attempted but couldn't resolve all issues.${NC}"
        fi
        echo ""
    fi
    
    # Display reboot notification if needed
    if [[ "$reboot_required" == true ]]; then
        echo -e "${YELLOW}[!]  ${BRIGHT_YELLOW}REBOOT REQUIRED: Some changes may require a system reboot.${NC}"
        echo -e "${CYAN}Consider rebooting the system before proceeding with installation.${NC}"
        echo ""
    fi
    
    if [[ "$all_checks_passed" == true ]]; then
        echo -e "${GREEN}[✔] ${BRIGHT_GREEN}${BOLD}All diagnostic checks passed!${NC}"
        echo -e "${GREEN}The VM meets all requirements for Dataiku DSS installation.${NC}"
        log_message "All diagnostic checks passed"
        return 0
    else
        echo -e "${RED}[x] ${BRIGHT_RED}${BOLD}Some diagnostic checks failed.${NC}"
        echo -e "${RED}Please review the logs above and fix the issues before proceeding with installation.${NC}"
        echo ""
        echo -e "${BRIGHT_WHITE}Full logs are available at:${NC} ${CYAN}$LOG_FILE${NC}"
        log_message "Some diagnostic checks failed"
        return 1
    fi
} 