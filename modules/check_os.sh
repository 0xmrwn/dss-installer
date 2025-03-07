#!/bin/bash
# OS verification module for Dataiku DSS VM Diagnostic Automation
# This module checks OS type/version, kernel version, and locale settings

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

# Function to check OS distribution and version
check_os_distribution() {
    local allowed_distros="${1:-}"
    local allowed_versions="${2:-}"
    
    info "Checking OS distribution and version..."
    
    # Read OS information from /etc/os-release
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        os_name="$NAME"
        os_version="$VERSION_ID"
        
        info "Detected OS: $os_name $os_version"
        
        # Check if OS is in allowed distributions
        if [[ -n "$allowed_distros" ]]; then
            if value_in_list "$os_name" "$allowed_distros"; then
                # OS is in allowed list, continue with version check
                :
            else
                fail "OS distribution $os_name is not supported."
                suggest "Supported distributions: $allowed_distros"
                return 1
            fi
        fi
        
        # Check if OS version is allowed
        if [[ -n "$allowed_versions" ]]; then
            if value_in_list "$os_version" "$allowed_versions"; then
                # Version is in allowed list
                :
            else
                fail "OS version $os_version is not supported."
                suggest "Supported versions: $allowed_versions"
                return 1
            fi
        fi
        
        pass "OS distribution and version check passed."
        return 0
    else
        fail "Cannot determine OS distribution (/etc/os-release not found)."
        return 1
    fi
}

# Function to check kernel version
check_kernel_version() {
    local min_kernel_version="${1:-}"
    
    info "Checking kernel version..."
    
    # Get kernel version
    kernel_version=$(uname -r)
    kernel_arch=$(uname -m)
    
    info "Detected kernel: $kernel_version ($kernel_arch)"
    
    # Check architecture (should be x86_64)
    if [[ "$kernel_arch" != "x86_64" ]]; then
        fail "CPU architecture $kernel_arch is not supported. Required: x86_64"
        return 1
    fi
    
    # Check minimum kernel version if specified
    if [[ -n "$min_kernel_version" ]]; then
        # Use common version comparison function
        if version_gte "$kernel_version" "$min_kernel_version"; then
            pass "Kernel version check passed ($kernel_version >= $min_kernel_version)."
        else
            fail "Kernel version $kernel_version is older than required minimum $min_kernel_version."
            return 1
        fi
    else
        pass "Kernel architecture check passed (x86_64)."
    fi
    
    return 0
}

# Function to check locale settings
check_locale() {
    local required_locale="${1:-en_US.utf8}"
    
    info "Checking locale settings..."
    
    # Check if locale command exists
    if command -v locale &>/dev/null; then
        current_locale=$(locale | grep "LC_CTYPE" | cut -d= -f2 | tr -d '"')
        info "Current locale: $current_locale"
        
        # Normalize locale strings for comparison (remove case sensitivity and standardize format)
        local norm_current
        norm_current=$(echo "$current_locale" | tr '[:upper:]' '[:lower:]' | sed 's/utf-8/utf8/g')
        local norm_required
        norm_required=$(echo "$required_locale" | tr '[:upper:]' '[:lower:]' | sed 's/utf-8/utf8/g')
        
        # Check if required locale is available
        if locale -a | grep -qi "$required_locale"; then
            if [[ "$norm_current" == *"$norm_required"* || "$norm_required" == *"$norm_current"* ]]; then
                pass "Locale check passed. Current locale ($current_locale) matches required ($required_locale)."
                return 0
            else
                warning "Current locale ($current_locale) does not match required locale ($required_locale)."
                
                # Check OS type to suggest appropriate command
                if [ -f /etc/os-release ] && grep -q -i "debian\|ubuntu" /etc/os-release; then
                    # Debian/Ubuntu suggestion
                    suggest "Required locale is installed but not active. Consider updating with: sudo update-locale LANG=$required_locale"
                else
                    # RHEL/CentOS/AlmaLinux/Rocky suggestion
                    suggest "Required locale is installed but not active. Consider updating with either:"
                    suggest "  - sudo localectl set-locale LANG=$required_locale"
                    suggest "  - Or manually edit /etc/locale.conf and set LANG=$required_locale"
                fi
                
                return 0
            fi
        else
            fail "Required locale ($required_locale) is not installed."
            
            # Check OS type to suggest appropriate command
            if [ -f /etc/os-release ] && grep -q -i "debian\|ubuntu" /etc/os-release; then
                # Debian/Ubuntu suggestion
                suggest "Install with: sudo locale-gen $required_locale"
            else
                # RHEL/CentOS/AlmaLinux/Rocky suggestion
                suggest "Install with:"
                suggest "  - sudo dnf install glibc-langpack-en   # For RHEL 8/AlmaLinux/Rocky"
                suggest "  - sudo yum install glibc-langpack-en   # For older RHEL/CentOS"
            fi
            
            return 1
        fi
    else
        warning "Cannot check locale settings (locale command not found)."
        return 0
    fi
}

# Main function to run all OS checks
run_os_checks() {
    local allowed_distros="${1:-}"
    local allowed_versions="${2:-}"
    local min_kernel_version="${3:-}"
    local required_locale="${4:-en_US.utf8}"
    local os_check_passed=true
    
    section_header "Running OS and System Checks"
    
    # Run OS distribution check
    if ! check_os_distribution "$allowed_distros" "$allowed_versions"; then
        os_check_passed=false
    fi
    
    echo ""
    
    # Run kernel version check
    if ! check_kernel_version "$min_kernel_version"; then
        os_check_passed=false
    fi
    
    echo ""
    
    # Run locale check
    if ! check_locale "$required_locale"; then
        os_check_passed=false
    fi
    
    # Return final result
    section_footer "$([[ "$os_check_passed" == true ]] && echo 0 || echo 1)" "OS checks"
    
    return "$([[ "$os_check_passed" == true ]] && echo 0 || echo 1)"
}