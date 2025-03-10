#!/bin/bash
# Dataiku DSS VM Diagnostic Automation
# Main script for running comprehensive VM diagnostics

# Exit on error, treat unset variables as errors
set -eu

# Suppress shellcheck warnings for dynamically created variables
# shellcheck disable=SC2154

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
NODE_TYPE="DESIGN"  # Default node type for reporting only
VERBOSE=false
AUTO_FIX=false
NON_INTERACTIVE=false

# Check for common utilities using absolute path
if [[ ! -f "${SCRIPT_DIR}/modules/utils/common.sh" ]]; then
    echo "Error: Common utilities file not found at ${SCRIPT_DIR}/modules/utils/common.sh"
    echo "Please ensure the file exists before running this script."
    exit 1
fi

# Source utility modules with absolute path
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/modules/utils/common.sh"

# Check for and source other utility modules
for util in cli.sh config.sh executor.sh; do
    if [[ ! -f "${SCRIPT_DIR}/modules/utils/${util}" ]]; then
        echo "Error: Utility file not found at ${SCRIPT_DIR}/modules/utils/${util}"
        echo "Please ensure the file exists before running this script."
        exit 1
    fi
    # shellcheck disable=SC1090
    source "${SCRIPT_DIR}/modules/utils/${util}"
done

# Main function
main() {
    # Parse command line arguments
    parse_args CONFIG_FILE LOG_FILE NODE_TYPE VERBOSE AUTO_FIX NON_INTERACTIVE "$@"
    
    # Load config parameters into variables with prefix 'config_params_'
    load_config_parameters "$CONFIG_FILE" "config_params"
    
    # Override NODE_TYPE from config file if specified there
    if [[ -n "${config_params_node_type:-}" ]]; then
        NODE_TYPE="${config_params_node_type:-}"
    fi

    # Validate node type
    if ! validate_node_type "$NODE_TYPE"; then
        exit 1
    fi
    
    # Initialize log file
    init_log "$LOG_FILE" "$NODE_TYPE" "$CONFIG_FILE" "$AUTO_FIX" "$NON_INTERACTIVE"
    
    # Display banner
    show_banner "$NODE_TYPE" "$LOG_FILE" "$AUTO_FIX" "$NON_INTERACTIVE"
    
    # Export variables for modules
    export VERBOSE
    export AUTO_FIX
    export NON_INTERACTIVE
    
    # Setup status tracking with prefix 'status_'
    # shellcheck disable=SC2034  # Variables appear unused but are accessed via eval in utility scripts
    status_fixes_attempted=false
    # shellcheck disable=SC2034
    status_fixes_succeeded=false
    # shellcheck disable=SC2034
    status_reboot_required=false
    # shellcheck disable=SC2034
    status_all_checks_passed=true
    # shellcheck disable=SC2034
    status_total_checks=6  # OS, hardware, filesystem, limits, network, software
    # shellcheck disable=SC2034
    status_current_check=0
    
    # Pre-load auto-fix module if auto-fix is enabled
    if [[ "$AUTO_FIX" == true ]]; then
        if [[ -f "${SCRIPT_DIR}/modules/auto_fix.sh" ]]; then
            # shellcheck disable=SC1090,SC1091
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
    
    # Print diagnostic parameters if verbose
    if [[ "$VERBOSE" == true ]]; then
        display_verbose_config "config_params"
    fi
    
    # Run OS checks
    run_module_with_auto_fix \
        "OS" \
        "${SCRIPT_DIR}/modules/check_os.sh" \
        "run_os_checks" \
        "locale" \
        "Operating System and System Checks" \
        "config_params" \
        "status" \
        "${config_params_allowed_os_distros:-}" \
        "${config_params_allowed_os_versions:-}" \
        "${config_params_min_kernel_version:-}" \
        "${config_params_locale_required:-}"
    
    # Run hardware checks
    run_module_with_auto_fix \
        "Hardware" \
        "${SCRIPT_DIR}/modules/check_hardware.sh" \
        "run_hardware_checks" \
        "" \
        "Hardware Checks" \
        "config_params" \
        "status" \
        "${config_params_vcpus:-}" \
        "${config_params_memory_gb:-}" \
        "${config_params_min_root_disk_gb:-}" \
        "${config_params_data_disk_mount:-}" \
        "${config_params_min_data_disk_gb:-}" \
        "${config_params_filesystem:-}"
    
    # Run system limits checks
    run_module_with_auto_fix \
        "System Limits" \
        "${SCRIPT_DIR}/modules/check_limits.sh" \
        "run_limits_checks" \
        "ulimits" \
        "System Settings and Limits Checks" \
        "config_params" \
        "status" \
        "${config_params_ulimit_files:-}" \
        "${config_params_ulimit_processes:-}"
    
    # Run network and connectivity checks
    run_module_with_auto_fix \
        "Network" \
        "${SCRIPT_DIR}/modules/check_network.sh" \
        "run_network_checks" \
        "" \
        "Network and Connectivity Checks" \
        "config_params" \
        "status" \
        "${config_params_port_range:-}"
    
    # Run software and dependency checks
    run_module_with_auto_fix \
        "Software" \
        "${SCRIPT_DIR}/modules/check_software.sh" \
        "run_software_checks" \
        "software" \
        "Software and Dependency Checks" \
        "config_params" \
        "status" \
        "${config_params_java_versions:-}" \
        "${config_params_python_versions:-}" \
        "${config_params_required_packages:-}" \
        "${config_params_required_repos:-}"
    
    # Run filesystem checks - MOVED TO AFTER SOFTWARE CHECKS
    run_module_with_auto_fix \
        "Filesystem" \
        "${SCRIPT_DIR}/modules/check_filesystem.sh" \
        "run_filesystem_checks" \
        "" \
        "Filesystem Checks" \
        "config_params" \
        "status" \
        "/" \
        "${config_params_data_disk_mount:-}" \
        "${config_params_filesystem:-}"
    
    # Print diagnostic summary and exit with appropriate code
    if print_summary "status"; then
        exit 0
    else
        exit 1
    fi
}

# Execute main function
main "$@"
