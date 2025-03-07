#!/bin/bash
# Auto-fix module for Dataiku DSS VM Diagnostic Automation
# Contains functions to fix common issues (non-sensitive)

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

# Add to auto_fix.sh at the beginning
check_sudo_permissions() {
    if ! sudo -n true 2>/dev/null; then
        fail "Auto-fix requires sudo privileges. Please run with a user that has sudo permissions."
        return 1
    fi
    return 0
}

# Function to fix locale issues
fix_locale() {
    local required_locale="$1"
    
    info "Attempting to auto-fix locale to $required_locale..."
    log_message "Attempting to auto-fix locale to $required_locale"
    
    # Normalize locale string (remove case sensitivity and standardize format)
    local norm_required
    norm_required=$(echo "$required_locale" | tr '[:upper:]' '[:lower:]' | sed 's/utf-8/utf8/g')
    
    # Detect OS type
    if [ -f /etc/os-release ] && grep -q -i "debian\|ubuntu" /etc/os-release; then
        info "Debian/Ubuntu detected - generating locale..."
        
        # Check if locale-gen is available
        if command -v locale-gen &>/dev/null; then
            if sudo locale-gen "$required_locale"; then
                info "Generated locale: $required_locale"
                
                # Update system default locale
                if sudo update-locale LANG="$required_locale"; then
                    pass "Successfully set system locale to $required_locale"
                else
                    fail "Failed to update system locale setting"
                    return 1
                fi
            else
                fail "Failed to generate locale: $required_locale"
                return 1
            fi
        else
            fail "locale-gen command not found"
            return 1
        fi
    else
        # For RHEL/CentOS/AlmaLinux/Rocky
        info "RHEL-based system detected - setting locale..."
        
        # Install appropriate language pack if needed
        if [[ "$norm_required" == *"en_us"* ]]; then
            if command -v dnf &>/dev/null; then
                info "Installing English language pack using dnf..."
                if sudo dnf install -y glibc-langpack-en; then
                    info "English language pack installed successfully"
                else
                    warning "Failed to install English language pack"
                fi
            elif command -v yum &>/dev/null; then
                info "Installing English language pack using yum..."
                if sudo yum install -y glibc-langpack-en; then
                    info "English language pack installed successfully"
                else
                    warning "Failed to install English language pack"
                fi
            fi
        fi
        
        # Set locale using localectl
        if command -v localectl &>/dev/null; then
            if sudo localectl set-locale LANG="$required_locale"; then
                pass "Successfully set system locale to $required_locale"
            else
                fail "Failed to set locale using localectl"
                return 1
            fi
        else
            # Fallback to manually editing /etc/locale.conf
            info "localectl not found, trying to update /etc/locale.conf directly..."
            if echo "LANG=$required_locale" | sudo tee /etc/locale.conf > /dev/null; then
                pass "Successfully updated /etc/locale.conf with LANG=$required_locale"
            else
                fail "Failed to update /etc/locale.conf"
                return 1
            fi
        fi
    fi
    
    return 0
}

# Function to fix missing packages
fix_packages() {
    local missing_packages="$1"
    
    if [[ -z "$missing_packages" ]]; then
        warning "No missing packages specified for auto-fix"
        return 1
    fi
    
    info "Attempting to install missing packages: $missing_packages"
    log_message "Attempting to install missing packages: $missing_packages"
    
    # Convert string to array to handle spaces correctly
    read -ra packages_array <<< "$missing_packages"
    
    # Determine package manager
    if command -v apt-get &>/dev/null; then
        info "Using apt package manager..."
        if sudo apt-get update && sudo apt-get install -y "${packages_array[@]}"; then
            pass "Successfully installed missing packages: $missing_packages"
            return 0
        else
            fail "Failed to install packages with apt-get"
            return 1
        fi
    elif command -v dnf &>/dev/null; then
        info "Using dnf package manager..."
        if sudo dnf install -y "${packages_array[@]}"; then
            pass "Successfully installed missing packages: $missing_packages"
            return 0
        else
            fail "Failed to install packages with dnf"
            return 1
        fi
    elif command -v yum &>/dev/null; then
        info "Using yum package manager..."
        if sudo yum install -y "${packages_array[@]}"; then
            pass "Successfully installed missing packages: $missing_packages"
            return 0
        else
            fail "Failed to install packages with yum"
            return 1
        fi
    else
        warning "No supported package manager found. Cannot auto-fix packages."
        return 1
    fi
}

# Function to fix time synchronization issues
fix_time_sync() {
    info "Attempting to fix time synchronization service..."
    log_message "Attempting to fix time synchronization service"
    
    local installed_service=false
    
    # Check if system is using systemd
    if command -v systemctl &>/dev/null; then
        # Check if chronyd is already installed
        if command -v chronyc &>/dev/null; then
            info "chronyd/chrony is already installed, enabling and starting service..."
            installed_service=true
            # Try chronyd first (RHEL/CentOS)
            if systemctl list-unit-files | grep -q chronyd; then
                if sudo systemctl enable chronyd && sudo systemctl start chronyd; then
                    pass "Successfully enabled and started chronyd service"
                    return 0
                fi
            # Then try chrony (Ubuntu/Debian)
            elif systemctl list-unit-files | grep -q chrony; then
                if sudo systemctl enable chrony && sudo systemctl start chrony; then
                    pass "Successfully enabled and started chrony service"
                    return 0
                fi
            else
                fail "Failed to enable and start time synchronization service"
            fi
        # Check if ntpd is already installed
        elif command -v ntpd &>/dev/null; then
            info "ntpd is already installed, enabling and starting service..."
            installed_service=true
            if sudo systemctl enable ntpd && sudo systemctl start ntpd; then
                pass "Successfully enabled and started ntpd service"
                return 0
            else
                fail "Failed to enable and start ntpd service"
            fi
        fi
        
        # If no time service is installed, try to install chronyd (preferred)
        if [[ "$installed_service" == false ]]; then
            info "No time synchronization service detected, attempting to install chrony..."
            
            # Install chrony based on package manager
            if command -v apt-get &>/dev/null; then
                if sudo apt-get update && sudo apt-get install -y chrony; then
                    info "Successfully installed chrony package"
                    if sudo systemctl enable chronyd && sudo systemctl start chronyd; then
                        pass "Successfully enabled and started chronyd service"
                        return 0
                    else
                        fail "Failed to enable and start chronyd service after installation"
                    fi
                else
                    fail "Failed to install chrony package with apt-get"
                fi
            elif command -v dnf &>/dev/null; then
                if sudo dnf install -y chrony; then
                    info "Successfully installed chrony package"
                    if sudo systemctl enable chronyd && sudo systemctl start chronyd; then
                        pass "Successfully enabled and started chronyd service"
                        return 0
                    else
                        fail "Failed to enable and start chronyd service after installation"
                    fi
                else
                    fail "Failed to install chrony package with dnf"
                fi
            elif command -v yum &>/dev/null; then
                if sudo yum install -y chrony; then
                    info "Successfully installed chrony package"
                    if sudo systemctl enable chronyd && sudo systemctl start chronyd; then
                        pass "Successfully enabled and started chronyd service"
                        return 0
                    else
                        fail "Failed to enable and start chronyd service after installation"
                    fi
                else
                    fail "Failed to install chrony package with yum"
                fi
            else
                fail "No supported package manager found. Cannot install chrony."
            fi
        fi
    else
        warning "Systemctl not available. Manual intervention required for time sync."
        return 1
    fi
    
    return 1
}

# Function to fix repository issues (EPEL)
fix_repositories() {
    local missing_repos="$1"
    
    if [[ -z "$missing_repos" ]]; then
        warning "No missing repositories specified for auto-fix"
        return 1
    fi
    
    info "Attempting to configure missing repositories: $missing_repos"
    log_message "Attempting to configure missing repositories: $missing_repos"
    
    # Convert string to array to handle spaces correctly
    read -ra repos_array <<< "$missing_repos"
    
    # Process each repository individually
    for repo in "${repos_array[@]}"; do
        # Check for EPEL repository
        if [[ "$repo" == "EPEL" ]]; then
            # Determine package manager and OS version
            if command -v dnf &>/dev/null; then
                info "Using dnf to install EPEL repository..."
                if sudo dnf install -y epel-release; then
                    pass "Successfully installed EPEL repository"
                else
                    fail "Failed to install EPEL repository with dnf"
                    return 1
                fi
            elif command -v yum &>/dev/null; then
                info "Using yum to install EPEL repository..."
                if sudo yum install -y epel-release; then
                    pass "Successfully installed EPEL repository"
                else
                    fail "Failed to install EPEL repository with yum"
                    return 1
                fi
            else
                warning "No supported package manager found for installing EPEL repository"
                return 1
            fi
        else
            warning "Auto-fix for repository '$repo' not implemented"
            # Continue with other repositories rather than failing immediately
        fi
    done
    
    # If we got here, at least one repository was processed
    return 0
}

# Function to fix ulimit settings
fix_ulimits() {
    local required_files="$1"
    local required_processes="$2"
    
    info "Attempting to fix ulimit settings..."
    log_message "Attempting to fix ulimit settings"
    
    # Create limits.conf entry
    local limits_file="/etc/security/limits.conf"
    local temp_file
    temp_file=$(mktemp)
    
    # Check if we can write to the file
    if ! sudo test -w "$limits_file"; then
        fail "Cannot write to $limits_file. Ulimit settings cannot be fixed."
        return 1
    fi
    
    # Create new limits entries
    sudo cat "$limits_file" | sudo tee "$temp_file" > /dev/null
    echo "# Added by Dataiku DSS diagnostic auto-fix" | sudo tee -a "$temp_file" > /dev/null
    echo "* soft nofile $required_files" | sudo tee -a "$temp_file" > /dev/null
    echo "* hard nofile $required_files" | sudo tee -a "$temp_file" > /dev/null
    echo "* soft nproc $required_processes" | sudo tee -a "$temp_file" > /dev/null
    echo "* hard nproc $required_processes" | sudo tee -a "$temp_file" > /dev/null
    
    # Replace the original file
    sudo cp "$temp_file" "$limits_file"
    rm "$temp_file"
    
    pass "Ulimit settings updated. You may need to log out and back in for changes to take effect."
    return 0
}

# Main auto-fix function that calls fixes based on issue type
auto_fix_by_issue() {
    local issue="$1"
    local param="${2:-}"
    local param2="${3:-}"
    
    case "$issue" in
        "locale")
            fix_locale "$param" # $param = required locale
            ;;
        "packages")
            fix_packages "$param" # $param = list of missing packages
            ;;
        "time_sync")
            fix_time_sync
            ;;
        "repositories")
            fix_repositories "$param" # $param = list of missing repositories
            ;;
        "ulimits")
            fix_ulimits "$param" "$param2" # $param = required files, $param2 = required processes
            ;;
        *)
            warning "No auto-fix routine defined for issue: $issue"
            return 1
            ;;
    esac
}

# Add to auto_fix.sh
confirm_action() {
    local message="$1"
    
    # Skip confirmation if running in non-interactive mode
    if [[ -t 0 ]]; then
        echo -e "${YELLOW}$message${NC} (y/n) "
        read -r answer
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    return 0
} 