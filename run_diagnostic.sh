#!/bin/bash
# Dataiku DSS VM Diagnostic Automation
# Main script for running comprehensive VM diagnostics

# Exit on error, treat unset variables as errors
set -eu

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
CONFIG_FILE="${SCRIPT_DIR}/config.ini"
LOG_FILE="${SCRIPT_DIR}/diagnostics.log"
NODE_TYPE="DESIGN"
VERBOSE=false

# ANSI color codes for output formatting
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Export colors for use in modules
export GREEN RED YELLOW BLUE NC

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
        echo "===========================================" 
    } > "$LOG_FILE"
    
    # Export log file path for modules
    export LOG_FILE
}

# Function to display banner
show_banner() {
    echo -e "${BLUE}"
    echo "====================================================="
    echo "    Dataiku DSS VM Diagnostic Automation Tool"
    echo "====================================================="
    echo -e "${NC}"
    echo "Node Type: $NODE_TYPE"
    echo "Running diagnostics at $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Log file: $LOG_FILE"
    echo "---------------------------------------------------"
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
    
    # Track overall diagnostic status
    local all_checks_passed=true
    
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
        echo "Configuration Parameters:"
        echo "  - Allowed OS Distros: $allowed_os_distros"
        echo "  - Allowed OS Versions: $allowed_os_versions"
        echo "  - Min Kernel Version: $min_kernel_version"
        echo "  - Required Locale: $locale_required"
        echo "  - Required vCPUs: $vcpus"
        echo "  - Required Memory (GB): $memory_gb"
        echo "  - Min Root Disk (GB): $min_root_disk_gb"
        echo "  - Data Disk Mount: $data_disk_mount"
        echo "  - Min Data Disk (GB): $min_data_disk_gb"
        echo "  - Allowed Filesystem: $filesystem"
        echo "  - Required Open Files Limit: $ulimit_files"
        echo "  - Required User Processes Limit: $ulimit_processes"
        echo "  - Port Range to Check: $port_range"
        echo "  - Required Java Versions: $java_versions"
        echo "  - Required Python Versions: $python_versions"
        echo "  - Required Packages: $required_packages"
        echo "  - Required Repositories: $required_repos"
        echo ""
    fi
    
    # Run OS checks
    if [[ -f "${SCRIPT_DIR}/modules/check_os.sh" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Running OS checks" >> "$LOG_FILE"
        
        # Source the module to access its functions
        # shellcheck disable=SC1091
        source "${SCRIPT_DIR}/modules/check_os.sh"
        
        # Run OS checks with parameters from config
        if ! run_os_checks "$allowed_os_distros" "$allowed_os_versions" "$min_kernel_version" "$locale_required"; then
            all_checks_passed=false
        fi
    else
        echo -e "${RED}Error: OS check module not found at ${SCRIPT_DIR}/modules/check_os.sh${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: OS check module not found" >> "$LOG_FILE"
        all_checks_passed=false
    fi
    
    # Run hardware checks
    if [[ -f "${SCRIPT_DIR}/modules/check_hardware.sh" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Running hardware checks" >> "$LOG_FILE"
        
        # Source the module to access its functions
        # shellcheck disable=SC1091
        source "${SCRIPT_DIR}/modules/check_hardware.sh"
        
        # Run hardware checks with parameters from config
        if ! run_hardware_checks "$vcpus" "$memory_gb" "$min_root_disk_gb" "$data_disk_mount" "$min_data_disk_gb" "$filesystem"; then
            all_checks_passed=false
        fi
    else
        echo -e "${RED}Error: Hardware check module not found at ${SCRIPT_DIR}/modules/check_hardware.sh${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Hardware check module not found" >> "$LOG_FILE"
        all_checks_passed=false
    fi
    
    # Run system limits checks
    if [[ -f "${SCRIPT_DIR}/modules/check_limits.sh" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Running system limits checks" >> "$LOG_FILE"
        
        # Source the module to access its functions
        # shellcheck disable=SC1091
        source "${SCRIPT_DIR}/modules/check_limits.sh"
        
        # Run system limits checks with parameters from config
        if ! run_limits_checks "$ulimit_files" "$ulimit_processes" "$port_range"; then
            all_checks_passed=false
        fi
    else
        echo -e "${RED}Error: System limits check module not found at ${SCRIPT_DIR}/modules/check_limits.sh${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: System limits check module not found" >> "$LOG_FILE"
        all_checks_passed=false
    fi
    
    # Run software and dependency checks
    if [[ -f "${SCRIPT_DIR}/modules/check_software.sh" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Running software and dependency checks" >> "$LOG_FILE"
        
        # Source the module to access its functions
        # shellcheck disable=SC1091
        source "${SCRIPT_DIR}/modules/check_software.sh"
        
        # Run software checks with parameters from config
        if ! run_software_checks "$java_versions" "$python_versions" "$required_packages" "$required_repos"; then
            all_checks_passed=false
        fi
    else
        echo -e "${RED}Error: Software check module not found at ${SCRIPT_DIR}/modules/check_software.sh${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Software check module not found" >> "$LOG_FILE"
        all_checks_passed=false
    fi
    
    # Print summary
    echo ""
    echo "====================================================="
    echo "                 Diagnostic Summary"
    echo "====================================================="
    
    if [[ "$all_checks_passed" == true ]]; then
        echo -e "${GREEN}All diagnostic checks passed!${NC}"
        echo "The VM meets all requirements for Dataiku DSS installation."
        echo "$(date '+%Y-%m-%d %H:%M:%S') - All diagnostic checks passed" >> "$LOG_FILE"
        exit 0
    else
        echo -e "${RED}Some diagnostic checks failed.${NC}"
        echo "Please review the logs above and fix the issues before proceeding with installation."
        echo "Full logs are available at: $LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Some diagnostic checks failed" >> "$LOG_FILE"
        exit 1
    fi
}

# Execute main function
main "$@"
