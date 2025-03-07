#!/bin/bash
# Software and dependency verification module for Dataiku DSS VM Diagnostic Automation
# This module checks Java, Python, essential packages, and repository access

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

# Function to check Java installation
check_java() {
    local required_versions="${1:-OpenJDK 11,OpenJDK 17}"
    
    info "Checking Java installation..."
    
    # Check if java is installed and get version
    if command -v java &>/dev/null; then
        java_version=$(java -version 2>&1 | head -n 1)
        info "Detected Java: $java_version"
        
        # Check if Java version is in the allowed list
        if [[ -n "$required_versions" ]]; then
            if value_in_list "$java_version" "$required_versions"; then
                pass "Java version check passed."
                return 0
            else
                fail "Java version check failed."
                suggest "Required Java versions: $required_versions"
                return 1
            fi
        else
            pass "Java is installed."
            return 0
        fi
    else
        fail "Java is not installed."
        suggest "Please install one of: $required_versions"
        return 1
    fi
}

# Function to check Python installation
check_python() {
    local required_versions="${1:-3.6,3.7,3.9,3.10}"
    
    info "Checking Python installation..."
    
    # Check if python3 is installed and get version
    if command -v python3 &>/dev/null; then
        python_version=$(python3 --version 2>&1 | cut -d ' ' -f 2)
        python_major=$(echo "$python_version" | cut -d. -f1)
        python_minor=$(echo "$python_version" | cut -d. -f2)
        
        info "Detected Python: $python_version"
        
        # Check if Python version is in the allowed list
        if [[ -n "$required_versions" ]]; then
            allowed=false
            for version in $(echo "$required_versions" | tr ',' ' '); do
                # Check if it's a major.minor format
                if [[ "$version" == *"."* ]]; then
                    expected_major=$(echo "$version" | cut -d. -f1)
                    expected_minor=$(echo "$version" | cut -d. -f2)
                    
                    if [[ "$python_major" == "$expected_major" && "$python_minor" == "$expected_minor" ]]; then
                        allowed=true
                        break
                    fi
                # Check if it's just a major version
                elif [[ "$python_major" == "$version" ]]; then
                    allowed=true
                    break
                fi
            done
            
            if [[ "$allowed" == true ]]; then
                pass "Python version check passed."
                return 0
            else
                fail "Python version check failed."
                suggest "Required Python versions: $required_versions"
                return 1
            fi
        else
            pass "Python is installed."
            return 0
        fi
    else
        fail "Python 3 is not installed."
        suggest "Please install one of these Python versions: $required_versions"
        return 1
    fi
}

# Function to check essential packages
check_packages() {
    local required_packages="${1:-git,nginx,zip,unzip,acl}"
    local package_manager=""
    
    info "Checking essential packages..."
    
    # Determine package manager
    if command -v apt-get &>/dev/null; then
        package_manager="apt"
    elif command -v yum &>/dev/null; then
        package_manager="yum"
    elif command -v dnf &>/dev/null; then
        package_manager="dnf"
    else
        warning "Could not determine package manager. Skipping detailed package check."
        
        # Basic check without package manager
        missing_packages=""
        for pkg in $(echo "$required_packages" | tr ',' ' '); do
            if ! command -v "$pkg" &>/dev/null; then
                missing_packages="$missing_packages $pkg"
            fi
        done
        
        if [[ -n "$missing_packages" ]]; then
            fail "Some required packages may be missing:$missing_packages"
            return 1
        else
            pass "Basic package check passed."
            return 0
        fi
    fi
    
    # Check packages based on package manager
    info "Using $package_manager package manager"
    
    missing_packages=""
    for pkg in $(echo "$required_packages" | tr ',' ' '); do
        pkg_installed=false
        
        case $package_manager in
            apt)
                if dpkg -l | grep -q "ii  $pkg "; then
                    pkg_installed=true
                fi
                ;;
            yum|dnf)
                if rpm -q "$pkg" &>/dev/null; then
                    pkg_installed=true
                fi
                ;;
        esac
        
        if [[ "$pkg_installed" == false ]]; then
            missing_packages="$missing_packages $pkg"
        fi
    done
    
    if [[ -n "$missing_packages" ]]; then
        fail "The following packages are missing:$missing_packages"
        
        case $package_manager in
            apt)
                suggest "Install with: sudo apt-get install$missing_packages"
                ;;
            yum)
                suggest "Install with: sudo yum install$missing_packages"
                ;;
            dnf)
                suggest "Install with: sudo dnf install$missing_packages"
                ;;
        esac
        
        return 1
    else
        pass "All required packages are installed."
        return 0
    fi
}

# Function to check repository access
check_repository_access() {
    local required_repos="${1:-EPEL}"
    local package_manager=""
    
    info "Checking repository access..."
    
    # Determine package manager
    if command -v apt-get &>/dev/null; then
        package_manager="apt"
    elif command -v yum &>/dev/null; then
        package_manager="yum"
    elif command -v dnf &>/dev/null; then
        package_manager="dnf"
    else
        warning "Could not determine package manager. Skipping repository check."
        return 0
    fi
    
    # Check repositories based on package manager
    missing_repos=""
    
    case $package_manager in
        apt)
            # For Debian/Ubuntu, check sources.list files
            if [[ "$required_repos" == *"EPEL"* ]]; then
                # EPEL is not relevant for apt-based systems
                info "EPEL is not required for Debian/Ubuntu-based systems."
            fi
            
            # Check if apt update works (basic repository connectivity)
            if ! apt-get update -qq &>/dev/null; then
                fail "Repository connectivity check failed."
                return 1
            fi
            ;;
            
        yum|dnf)
            # For RHEL/CentOS/Fedora, check for EPEL
            if [[ "$required_repos" == *"EPEL"* ]]; then
                if ! $package_manager repolist | grep -q "epel"; then
                    missing_repos="$missing_repos EPEL"
                fi
            fi
            ;;
    esac
    
    if [[ -n "$missing_repos" ]]; then
        fail "The following repositories are missing:$missing_repos"
        
        if [[ "$missing_repos" == *"EPEL"* ]]; then
            case $package_manager in
                yum)
                    suggest "Install EPEL with: sudo yum install epel-release"
                    ;;
                dnf)
                    suggest "Install EPEL with: sudo dnf install epel-release"
                    ;;
            esac
        fi
        
        return 1
    else
        pass "All required repositories are configured."
        return 0
    fi
}

# Main function to run all software checks
run_software_checks() {
    local java_versions="${1:-OpenJDK 11,OpenJDK 17}"
    local python_versions="${2:-3.6,3.7,3.9,3.10}"
    local required_packages="${3:-git,nginx,zip,unzip,acl}"
    local required_repos="${4:-EPEL}"
    local software_check_passed=true
    
    section_header "Running Software and Dependency Checks"
    
    # Run Java check
    if ! check_java "$java_versions"; then
        software_check_passed=false
    fi
    
    echo ""
    
    # Run Python check
    if ! check_python "$python_versions"; then
        software_check_passed=false
    fi
    
    echo ""
    
    # Run essential packages check
    if ! check_packages "$required_packages"; then
        software_check_passed=false
    fi
    
    echo ""
    
    # Run repository access check
    if ! check_repository_access "$required_repos"; then
        software_check_passed=false
    fi
    
    # Return final result
    section_footer "$([[ "$software_check_passed" == true ]] && echo 0 || echo 1)" "Software and dependency checks"
    
    return "$([[ "$software_check_passed" == true ]] && echo 0 || echo 1)"
} 