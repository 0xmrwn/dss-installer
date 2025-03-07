#!/bin/bash
# Dataiku DSS VM Diagnostic Automation
# Main script for running comprehensive VM diagnostics

# Exit on error, treat unset variables as errors
set -eu

# Script directory - export so modules can use it
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

# Create modules/utils directory if it doesn't exist
if [[ ! -d "${SCRIPT_DIR}/modules/utils" ]]; then
    mkdir -p "${SCRIPT_DIR}/modules/utils"
fi

# Default values
CONFIG_FILE="${SCRIPT_DIR}/config.ini"
LOG_FILE="${SCRIPT_DIR}/diagnostics.log"
NODE_TYPE="DESIGN"
VERBOSE=false
AUTO_FIX=false  # Added default auto-fix flag
NON_INTERACTIVE=false  # Add non-interactive mode flag

# Check for common utilities using absolute path
if [[ ! -f "${SCRIPT_DIR}/modules/utils/common.sh" ]]; then
    echo "Error: Common utilities file not found at ${SCRIPT_DIR}/modules/utils/common.sh"
    echo "Please ensure the file exists before running this script."
    exit 1
fi

# Source common utility functions with absolute path
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/modules/utils/common.sh"

# Function to display usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Run diagnostic checks for Dataiku DSS installation."
    echo ""
    echo "Options:"
    echo "  -c, --config FILE    Path to configuration file (default: config.ini)"
    echo "  -n, --node TYPE      Node type: DESIGN, AUTO (default: DESIGN)"
    echo "  -l, --log FILE       Path to log file (default: diagnostics.log)"
    echo "  -v, --verbose        Enable verbose output"
    echo "  --auto-fix           Attempt to automatically fix non-sensitive issues"
    echo "  --non-interactive    Run in non-interactive mode, don't prompt for confirmations"
    echo "  -h, --help           Display this help message and exit"
    echo ""
    exit 1
}

# Function to parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -n|--node)
                NODE_TYPE="${2^^}" # Convert to uppercase
                shift 2
                ;;
            -l|--log)
                LOG_FILE="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --auto-fix)
                AUTO_FIX=true
                shift
                ;;
            --non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done
    
    # Validate node type
    if [[ "$NODE_TYPE" != "DESIGN" && "$NODE_TYPE" != "AUTO" ]]; then
        echo "Error: Invalid node type. Must be DESIGN or AUTO."
        exit 1
    fi
    
    # Validate config file
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Error: Config file not found: $CONFIG_FILE"
        exit 1
    fi
}

# Function to read a value from INI file
read_ini() {
    local section="$1"
    local key="$2"
    local default="${3:-}"
    
    # Try to get value from specified section
    local value
    value=$(awk -F "=" -v section="[$section]" -v key="$key" '
        BEGIN { in_section = 0 }
        /^\[/ { in_section = ($0 == section) }
        in_section && $1 ~ "^[ \t]*"key"[ \t]*$" { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }
    ' "$CONFIG_FILE" | tr -d '\r')
    
    # If not found in section, try DEFAULT section
    if [[ -z "$value" && "$section" != "DEFAULT" ]]; then
        value=$(awk -F "=" -v key="$key" '
            BEGIN { in_section = 0 }
            /^\[DEFAULT\]/ { in_section = 1 }
            /^\[/ && !/^\[DEFAULT\]/ { in_section = 0 }
            in_section && $1 ~ "^[ \t]*"key"[ \t]*$" { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }
        ' "$CONFIG_FILE" | tr -d '\r')
    fi
    
    # If still not found, use default
    if [[ -z "$value" ]]; then
        value="$default"
    fi
    
    echo "$value"
}

# Function to initialize the log file
init_log() {
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Initialize log file with header
    {
        echo "===========================================" 
        echo "Dataiku DSS VM Diagnostic - $(date '+%Y-%m-%d %H:%M:%S')"
        echo "===========================================" 
        echo "Node Type: $NODE_TYPE"
        echo "Config File: $CONFIG_FILE"
        echo "Auto-Fix: $AUTO_FIX"
        echo "Non-Interactive: $NON_INTERACTIVE"
        echo "===========================================" 
    } > "$LOG_FILE"
    
    # Export log file path for modules
    export LOG_FILE
}

# Function to display banner
show_banner() {
    echo ""
    echo -e "${BRIGHT_BLUE}${BOLD}DATAIKU DSS VM DIAGNOSTIC TOOL${NC}"
    echo -e "${GRAY}──────────────────────────────────────────${NC}"
    echo ""
    echo -e "${BRIGHT_WHITE}${BOLD}Environment Configuration:${NC}"
    echo -e "${BRIGHT_WHITE}Node Type:${NC}      ${BLUE}${BOLD}$NODE_TYPE${NC}"
    echo -e "${BRIGHT_WHITE}Run Time:${NC}       ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${BRIGHT_WHITE}Log Path:${NC}       ${GRAY}$LOG_FILE${NC}"
    
    # Auto-fix status with colorful indicator
    if [[ "$AUTO_FIX" == true ]]; then
        echo -e "${BRIGHT_WHITE}Auto-Fix:${NC}       ${GREEN}${BOLD}Enabled${NC} ${GREEN}(Will attempt to fix non-sensitive issues)${NC}"
    else
        echo -e "${BRIGHT_WHITE}Auto-Fix:${NC}       ${YELLOW}Disabled${NC}"
    fi
    
    # Interactive mode status
    if [[ "$NON_INTERACTIVE" == true ]]; then
        echo -e "${BRIGHT_WHITE}Mode:${NC}           ${BLUE}Non-Interactive${NC} ${GRAY}(No confirmations will be requested)${NC}"
    else
        echo -e "${BRIGHT_WHITE}Mode:${NC}           ${BLUE}Interactive${NC}"
    fi
    echo -e "${GRAY}──────────────────────────────────────────${NC}"
    echo ""
}

# Main function
main() {
    # Parse command line arguments
    parse_args "$@"
    
    # Initialize log file
    init_log
    
    # Display banner
    show_banner
    
    # Export variables for modules
    export VERBOSE
    export AUTO_FIX
    export NON_INTERACTIVE
    
    # Track whether auto-fixes were attempted
    local fixes_attempted=false
    local fixes_succeeded=false
    local reboot_required=false
    
    # Pre-load auto-fix module if auto-fix is enabled
    if [[ "$AUTO_FIX" == true ]]; then
        if [[ -f "${SCRIPT_DIR}/modules/auto_fix.sh" ]]; then
            # shellcheck disable=SC1091
            source "${SCRIPT_DIR}/modules/auto_fix.sh"
            # Check sudo permissions
            if ! check_sudo_permissions; then
                warning "Auto-fix is enabled but sudo permissions are not available."
                warning "Some fixes may fail. Consider running as a user with sudo privileges."
            fi
        else
            warning "Auto-fix module not found at ${SCRIPT_DIR}/modules/auto_fix.sh"
            warning "Auto-fix functionality will be disabled."
            AUTO_FIX=false
        fi
    fi
    
    # Track overall diagnostic status
    local all_checks_passed=true
    
    # Setup progress tracking
    local total_checks=5  # OS, hardware, limits, network, software
    local current_check=0
    
    # Read OS check parameters from config file
    local allowed_os_distros
    allowed_os_distros=$(read_ini "$NODE_TYPE" "allowed_os_distros")
    local allowed_os_versions
    allowed_os_versions=$(read_ini "$NODE_TYPE" "allowed_os_versions")
    local min_kernel_version
    min_kernel_version=$(read_ini "$NODE_TYPE" "min_kernel_version")
    local locale_required
    locale_required=$(read_ini "$NODE_TYPE" "locale_required")
    
    # Read hardware check parameters from config file
    local vcpus
    vcpus=$(read_ini "$NODE_TYPE" "vcpus")
    local memory_gb
    memory_gb=$(read_ini "$NODE_TYPE" "memory_gb")
    local min_root_disk_gb
    min_root_disk_gb=$(read_ini "$NODE_TYPE" "min_root_disk_gb")
    local data_disk_mount
    data_disk_mount=$(read_ini "$NODE_TYPE" "data_disk_mount")
    local min_data_disk_gb
    min_data_disk_gb=$(read_ini "$NODE_TYPE" "min_data_disk_gb")
    local filesystem
    filesystem=$(read_ini "$NODE_TYPE" "filesystem")
    
    # Read system limits check parameters from config file
    local ulimit_files
    ulimit_files=$(read_ini "$NODE_TYPE" "ulimit_files")
    local ulimit_processes
    ulimit_processes=$(read_ini "$NODE_TYPE" "ulimit_processes")
    local port_range
    port_range=$(read_ini "$NODE_TYPE" "port_range")
    
    # Read software check parameters from config file
    local java_versions
    java_versions=$(read_ini "$NODE_TYPE" "java_versions")
    local python_versions
    python_versions=$(read_ini "$NODE_TYPE" "python_versions")
    local required_packages
    required_packages=$(read_ini "$NODE_TYPE" "required_packages")
    local required_repos
    required_repos=$(read_ini "$NODE_TYPE" "required_repos")
    
    # Print diagnostic parameters if verbose
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BRIGHT_WHITE}${BOLD}Configuration Parameters:${NC}"
        echo -e "${GRAY}──────────────────────────────────────────${NC}"
        
        echo -e "${CYAN}${BOLD}Operating System Requirements:${NC}"
        show_config_property "Allowed OS Distros" "$allowed_os_distros"
        show_config_property "Allowed OS Versions" "$allowed_os_versions"
        show_config_property "Min Kernel Version" "$min_kernel_version"
        show_config_property "Required Locale" "$locale_required"
        echo ""
        
        echo -e "${CYAN}${BOLD}Hardware Requirements:${NC}"
        show_config_property "Required vCPUs" "$vcpus"
        show_config_property "Required Memory (GB)" "$memory_gb"
        show_config_property "Min Root Disk (GB)" "$min_root_disk_gb"
        show_config_property "Data Disk Mount" "$data_disk_mount"
        show_config_property "Min Data Disk (GB)" "$min_data_disk_gb"
        show_config_property "Allowed Filesystem" "$filesystem"
        echo ""
        
        echo -e "${CYAN}${BOLD}System Limits:${NC}"
        show_config_property "Required Open Files Limit" "$ulimit_files"
        show_config_property "Required User Processes Limit" "$ulimit_processes"
        show_config_property "Port Range to Check" "$port_range"
        echo ""
        
        echo -e "${CYAN}${BOLD}Software Requirements:${NC}"
        show_config_property "Required Java Versions" "$java_versions"
        show_config_property "Required Python Versions" "$python_versions"
        show_config_property "Required Packages" "$required_packages"
        show_config_property "Required Repositories" "$required_repos"
        echo -e "${GRAY}──────────────────────────────────────────${NC}"
        echo ""
    fi
    
    # Run OS checks
    current_check=$((current_check + 1))
    show_progress "$current_check" "$total_checks" "Operating System and System Checks"
    
    if [[ -f "${SCRIPT_DIR}/modules/check_os.sh" ]]; then
        log_message "Running OS checks"
        
        # Source the module to access its functions
        # shellcheck disable=SC1091
        source "${SCRIPT_DIR}/modules/check_os.sh"
        
        # Run OS checks with parameters from config
        if ! run_os_checks "$allowed_os_distros" "$allowed_os_versions" "$min_kernel_version" "$locale_required"; then
            # If auto-fix is enabled, try to fix locale issues
            if [[ "$AUTO_FIX" == true ]]; then
                log_message "OS checks failed. Attempting auto-fix for locale issues."
                info "OS checks failed. Attempting auto-fix for locale issues..."
                
                # Attempt to fix locale issues
                fixes_attempted=true
                if auto_fix_by_issue "locale" "$locale_required"; then
                    # Re-run OS checks to verify if fix succeeded
                    if run_os_checks "$allowed_os_distros" "$allowed_os_versions" "$min_kernel_version" "$locale_required"; then
                        pass "OS locale issues fixed successfully!"
                        fixes_succeeded=true
                        # Mark for potential reboot
                        reboot_required=true
                    else
                        fail "OS locale issues could not be fixed automatically."
                        all_checks_passed=false
                    fi
                else
                    fail "Failed to automatically fix locale issues."
                    all_checks_passed=false
                fi
            else
                all_checks_passed=false
            fi
        fi
    else
        fail "OS check module not found at ${SCRIPT_DIR}/modules/check_os.sh"
        log_message "Error: OS check module not found"
        all_checks_passed=false
    fi
    
    # Run hardware checks
    current_check=$((current_check + 1))
    show_progress "$current_check" "$total_checks" "Hardware Checks"
    
    if [[ -f "${SCRIPT_DIR}/modules/check_hardware.sh" ]]; then
        log_message "Running hardware checks"
        
        # Source the module to access its functions
        # shellcheck disable=SC1091
        source "${SCRIPT_DIR}/modules/check_hardware.sh"
        
        # Run hardware checks with parameters from config
        if ! run_hardware_checks "$vcpus" "$memory_gb" "$min_root_disk_gb" "$data_disk_mount" "$min_data_disk_gb" "$filesystem"; then
            # Hardware checks usually require manual intervention, so we don't attempt auto-fixes
            info "Hardware checks failed. Manual intervention required."
            all_checks_passed=false
        fi
    else
        fail "Hardware check module not found at ${SCRIPT_DIR}/modules/check_hardware.sh"
        log_message "Error: Hardware check module not found"
        all_checks_passed=false
    fi
    
    # Run system limits checks
    current_check=$((current_check + 1))
    show_progress "$current_check" "$total_checks" "System Settings and Limits Checks"
    
    if [[ -f "${SCRIPT_DIR}/modules/check_limits.sh" ]]; then
        log_message "Running system limits checks"
        
        # Source the module to access its functions
        # shellcheck disable=SC1091
        source "${SCRIPT_DIR}/modules/check_limits.sh"
        
        # Run system limits checks with parameters from config
        if ! run_limits_checks "$ulimit_files" "$ulimit_processes"; then
            # If auto-fix is enabled, try to fix time sync and ulimit issues
            if [[ "$AUTO_FIX" == true ]]; then
                log_message "System limits checks failed. Attempting auto-fix..."
                info "System limits checks failed. Attempting auto-fix..."
                
                # First try to fix ulimit settings
                fixes_attempted=true
                if auto_fix_by_issue "ulimits" "$ulimit_files" "$ulimit_processes"; then
                    info "Ulimit settings updated. Continuing with other fixes..."
                    reboot_required=true
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
                if run_limits_checks "$ulimit_files" "$ulimit_processes"; then
                    pass "System limits issues fixed successfully!"
                    fixes_succeeded=true
                else
                    fail "Some system limits issues could not be fixed automatically."
                    all_checks_passed=false
                fi
            else
                all_checks_passed=false
            fi
        fi
    else
        fail "System limits check module not found at ${SCRIPT_DIR}/modules/check_limits.sh"
        log_message "Error: System limits check module not found"
        all_checks_passed=false
    fi
    
    # Run network and connectivity checks
    current_check=$((current_check + 1))
    show_progress "$current_check" "$total_checks" "Network and Connectivity Checks"
    
    if [[ -f "${SCRIPT_DIR}/modules/check_network.sh" ]]; then
        log_message "Running network and connectivity checks"
        
        # Source the module to access its functions
        # shellcheck disable=SC1091
        source "${SCRIPT_DIR}/modules/check_network.sh"
        
        # Run network checks with parameters from config
        if ! run_network_checks "$port_range"; then
            # Network issues often require manual intervention, so we don't attempt auto-fixes
            info "Network checks failed. Manual intervention required."
            all_checks_passed=false
        fi
    else
        fail "Network check module not found at ${SCRIPT_DIR}/modules/check_network.sh"
        log_message "Error: Network check module not found"
        all_checks_passed=false
    fi
    
    # Run software and dependency checks
    current_check=$((current_check + 1))
    show_progress "$current_check" "$total_checks" "Software and Dependency Checks"
    
    if [[ -f "${SCRIPT_DIR}/modules/check_software.sh" ]]; then
        log_message "Running software and dependency checks"
        
        # Source the module to access its functions
        # shellcheck disable=SC1091
        source "${SCRIPT_DIR}/modules/check_software.sh"
        
        # Global variable to store missing packages
        MISSING_PACKAGES=""
        MISSING_REPOS=""
        MISSING_JAVA=false
        
        # Run software checks with parameters from config
        if ! run_software_checks "$java_versions" "$python_versions" "$required_packages" "$required_repos"; then
            # If auto-fix is enabled, try to fix missing packages, repos, and Java
            if [[ "$AUTO_FIX" == true ]]; then
                log_message "Software checks failed. Attempting auto-fix for Java installation and other software dependencies."
                info "Software checks failed. Attempting auto-fix for Java installation and other software dependencies..."
                
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
                    fixes_attempted=true
                    if auto_fix_by_issue "packages" "$MISSING_PACKAGES"; then
                        info "Packages fixed, checking repositories..."
                    else
                        fail "Failed to automatically install missing packages."
                    fi
                fi
                
                # Check if missing repositories were found
                if [[ -n "$MISSING_REPOS" ]]; then
                    # Attempt to fix missing repositories
                    fixes_attempted=true
                    if auto_fix_by_issue "repositories" "$MISSING_REPOS"; then
                        info "Repositories fixed, re-running software checks..."
                    else
                        fail "Failed to automatically configure missing repositories."
                    fi
                fi
                
                # Check if Java needs to be installed
                if [[ "$MISSING_JAVA" == true ]]; then
                    fixes_attempted=true
                    info "Attempting to fix missing Java installation..."
                    if auto_fix_by_issue "java" "$java_versions"; then
                        info "Java installation succeeded, re-running software checks..."
                    else
                        fail "Failed to automatically install Java."
                        log_message "Java auto-installation failed. Continuing with other checks."
                        info "Manual Java installation will be required later."
                    fi
                fi
                
                # Re-run software checks to verify if fixes succeeded
                if run_software_checks "$java_versions" "$python_versions" "$required_packages" "$required_repos"; then
                    pass "Software issues fixed successfully!"
                    fixes_succeeded=true
                else
                    fail "Some software issues could not be fixed automatically."
                    all_checks_passed=false
                fi
            else
                all_checks_passed=false
            fi
        fi
    else
        fail "Software check module not found at ${SCRIPT_DIR}/modules/check_software.sh"
        log_message "Error: Software check module not found"
        all_checks_passed=false
    fi
    
    # Print summary
    echo ""
    echo -e "${BRIGHT_BLUE}${BOLD}DIAGNOSTIC SUMMARY${NC}"
    echo -e "${GRAY}──────────────────────────────────────────${NC}"
    
    if [[ "$AUTO_FIX" == true && "$fixes_attempted" == true ]]; then
        echo -e "${BRIGHT_WHITE}${BOLD}Auto-Fix Status:${NC}"
        if [[ "$fixes_succeeded" == true ]]; then
            echo -e "${GREEN}✓ ${BRIGHT_GREEN}Some issues were successfully fixed automatically.${NC}"
        else
            echo -e "${YELLOW}⚠️  ${BRIGHT_YELLOW}Auto-fix was attempted but couldn't resolve all issues.${NC}"
        fi
        echo ""
    fi
    
    # Display reboot notification if needed
    if [[ "$reboot_required" == true ]]; then
        echo -e "${YELLOW}⚠️  ${BRIGHT_YELLOW}REBOOT REQUIRED: Some changes may require a system reboot.${NC}"
        echo -e "${CYAN}Consider rebooting the system before proceeding with installation.${NC}"
        echo ""
    fi
    
    if [[ "$all_checks_passed" == true ]]; then
        echo -e "${GREEN}✓ ${BRIGHT_GREEN}${BOLD}All diagnostic checks passed!${NC}"
        echo -e "${GREEN}The VM meets all requirements for Dataiku DSS installation.${NC}"
        log_message "All diagnostic checks passed"
        exit 0
    else
        echo -e "${RED}✗ ${BRIGHT_RED}${BOLD}Some diagnostic checks failed.${NC}"
        echo -e "${RED}Please review the logs above and fix the issues before proceeding with installation.${NC}"
        echo ""
        echo -e "${BRIGHT_WHITE}Full logs are available at:${NC} ${CYAN}$LOG_FILE${NC}"
        log_message "Some diagnostic checks failed"
        exit 1
    fi
}

# Execute main function
main "$@"
