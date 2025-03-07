#!/bin/bash
# OS verification module for Dataiku DSS VM Diagnostic Automation
# This module checks OS type/version, kernel version, and locale settings

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

# Function to check OS distribution and version
check_os_distribution() {
    local allowed_distros="${1:-}"
    local allowed_versions="${2:-}"
    
    echo "[INFO] Checking OS distribution and version..."
    
    # Read OS information from /etc/os-release
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        os_name="$NAME"
        os_version="$VERSION_ID"
        
        echo "[INFO] Detected OS: $os_name $os_version"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Detected OS: $os_name $os_version" >> "$LOG_FILE"
        
        # Check if OS is in allowed distributions
        if [[ -n "$allowed_distros" ]]; then
            allowed=false
            for distro in $(echo "$allowed_distros" | tr ',' ' '); do
                if [[ "$os_name" == *"$distro"* ]]; then
                    allowed=true
                    break
                fi
            done
            
            if [[ "$allowed" == false ]]; then
                echo -e "${RED}[FAIL] OS distribution $os_name is not supported.${NC}"
                echo -e "${YELLOW}Supported distributions: $allowed_distros ${NC}"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: OS distribution $os_name is not supported. Supported: $allowed_distros" >> "$LOG_FILE"
                return 1
            fi
        fi
        
        # Check if OS version is allowed
        if [[ -n "$allowed_versions" ]]; then
            allowed=false
            for version in $(echo "$allowed_versions" | tr ',' ' '); do
                if [[ "$os_version" == "$version" || "$os_version" == *"$version"* ]]; then
                    allowed=true
                    break
                fi
            done
            
            if [[ "$allowed" == false ]]; then
                echo -e "${RED}[FAIL] OS version $os_version is not supported.${NC}"
                echo -e "${YELLOW}Supported versions: $allowed_versions ${NC}"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: OS version $os_version is not supported. Supported: $allowed_versions" >> "$LOG_FILE"
                return 1
            fi
        fi
        
        echo -e "${GREEN}[PASS] OS distribution and version check passed.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: OS distribution and version check passed." >> "$LOG_FILE"
        return 0
    else
        echo -e "${RED}[FAIL] Cannot determine OS distribution (/etc/os-release not found).${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Cannot determine OS distribution (/etc/os-release not found)." >> "$LOG_FILE"
        return 1
    fi
}

# Function to check kernel version
check_kernel_version() {
    local min_kernel_version="${1:-}"
    
    echo "[INFO] Checking kernel version..."
    
    # Get kernel version
    kernel_version=$(uname -r)
    kernel_arch=$(uname -m)
    
    echo "[INFO] Detected kernel: $kernel_version ($kernel_arch)"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Detected kernel: $kernel_version ($kernel_arch)" >> "$LOG_FILE"
    
    # Check architecture (should be x86_64)
    if [[ "$kernel_arch" != "x86_64" ]]; then
        echo -e "${RED}[FAIL] CPU architecture $kernel_arch is not supported. Required: x86_64${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: CPU architecture $kernel_arch is not supported. Required: x86_64" >> "$LOG_FILE"
        return 1
    fi
    
    # Check minimum kernel version if specified
    if [[ -n "$min_kernel_version" ]]; then
        # Basic version comparison (doesn't handle complex version schemes)
        if [[ "$(printf '%s\n' "$min_kernel_version" "$kernel_version" | sort -V | head -n1)" == "$min_kernel_version" ]]; then
            echo -e "${GREEN}[PASS] Kernel version check passed ($kernel_version >= $min_kernel_version).${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: Kernel version check passed ($kernel_version >= $min_kernel_version)." >> "$LOG_FILE"
        else
            echo -e "${RED}[FAIL] Kernel version $kernel_version is older than required minimum $min_kernel_version.${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Kernel version $kernel_version is older than required minimum $min_kernel_version." >> "$LOG_FILE"
            return 1
        fi
    else
        echo -e "${GREEN}[PASS] Kernel architecture check passed (x86_64).${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: Kernel architecture check passed (x86_64)." >> "$LOG_FILE"
    fi
    
    return 0
}

# Function to check locale settings
check_locale() {
    local required_locale="${1:-en_US.utf8}"
    
    echo "[INFO] Checking locale settings..."
    
    # Check if locale command exists
    if command -v locale &>/dev/null; then
        current_locale=$(locale | grep "LC_CTYPE" | cut -d= -f2 | tr -d '"')
        echo "[INFO] Current locale: $current_locale"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Current locale: $current_locale" >> "$LOG_FILE"
        
        # Normalize locale strings for comparison (remove case sensitivity and standardize format)
        local norm_current
        norm_current=$(echo "$current_locale" | tr '[:upper:]' '[:lower:]' | sed 's/utf-8/utf8/g')
        local norm_required
        norm_required=$(echo "$required_locale" | tr '[:upper:]' '[:lower:]' | sed 's/utf-8/utf8/g')
        
        # Check if required locale is available
        if locale -a | grep -qi "$required_locale"; then
            if [[ "$norm_current" == *"$norm_required"* || "$norm_required" == *"$norm_current"* ]]; then
                echo -e "${GREEN}[PASS] Locale check passed. Current locale ($current_locale) matches required ($required_locale).${NC}"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: Locale check passed." >> "$LOG_FILE"
                return 0
            else
                echo -e "${YELLOW}[WARNING] Current locale ($current_locale) does not match required locale ($required_locale).${NC}"
                
                # Check OS type to suggest appropriate command
                if [ -f /etc/os-release ] && grep -q -i "debian\|ubuntu" /etc/os-release; then
                    # Debian/Ubuntu suggestion
                    echo -e "${YELLOW}Required locale is installed but not active. Consider updating with: sudo update-locale LANG=$required_locale${NC}"
                else
                    # RHEL/CentOS/AlmaLinux/Rocky suggestion
                    echo -e "${YELLOW}Required locale is installed but not active. Consider updating with either:${NC}"
                    echo -e "${YELLOW}  - sudo localectl set-locale LANG=$required_locale${NC}"
                    echo -e "${YELLOW}  - Or manually edit /etc/locale.conf and set LANG=$required_locale${NC}"
                fi
                
                echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: Current locale ($current_locale) does not match required ($required_locale)." >> "$LOG_FILE"
                return 0
            fi
        else
            echo -e "${RED}[FAIL] Required locale ($required_locale) is not installed.${NC}"
            
            # Check OS type to suggest appropriate command
            if [ -f /etc/os-release ] && grep -q -i "debian\|ubuntu" /etc/os-release; then
                # Debian/Ubuntu suggestion
                echo -e "${YELLOW}Install with: sudo locale-gen $required_locale${NC}"
            else
                # RHEL/CentOS/AlmaLinux/Rocky suggestion
                echo -e "${YELLOW}Install with:${NC}"
                echo -e "${YELLOW}  - sudo dnf install glibc-langpack-en   # For RHEL 8/AlmaLinux/Rocky${NC}"
                echo -e "${YELLOW}  - sudo yum install glibc-langpack-en   # For older RHEL/CentOS${NC}"
            fi
            
            echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Required locale ($required_locale) is not installed." >> "$LOG_FILE"
            return 1
        fi
    else
        echo -e "${YELLOW}[WARNING] Cannot check locale settings (locale command not found).${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: Cannot check locale settings (locale command not found)." >> "$LOG_FILE"
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
    
    echo "==============================================="
    echo "Running OS and System Checks"
    echo "==============================================="
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting OS checks" >> "$LOG_FILE"
    
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
    
    echo ""
    echo "==============================================="
    
    if [[ "$os_check_passed" == true ]]; then
        echo -e "${GREEN}OS checks completed successfully.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - OS checks completed successfully." >> "$LOG_FILE"
        return 0
    else
        echo -e "${RED}OS checks failed. Please address the issues above.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - OS checks failed." >> "$LOG_FILE"
        return 1
    fi
}