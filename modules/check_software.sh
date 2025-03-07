#!/bin/bash
# Software and dependency verification module for Dataiku DSS VM Diagnostic Automation
# This module checks Java, Python, essential packages, and repository access

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

# Function to check Java installation
check_java() {
    local required_versions="${1:-OpenJDK 11,OpenJDK 17}"
    
    echo "[INFO] Checking Java installation..."
    
    # Check if java is installed and get version
    if command -v java &>/dev/null; then
        java_version=$(java -version 2>&1 | head -n 1)
        echo "[INFO] Detected Java: $java_version"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Detected Java: $java_version" >> "$LOG_FILE"
        
        # Check if Java version is in the allowed list
        if [[ -n "$required_versions" ]]; then
            allowed=false
            for version in $(echo "$required_versions" | tr ',' ' '); do
                if [[ "$java_version" == *"$version"* ]]; then
                    allowed=true
                    break
                fi
            done
            
            if [[ "$allowed" == true ]]; then
                echo -e "${GREEN}[PASS] Java version check passed.${NC}"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: Java version check passed." >> "$LOG_FILE"
                return 0
            else
                echo -e "${RED}[FAIL] Java version check failed.${NC}"
                echo -e "${YELLOW}Required Java versions: $required_versions${NC}"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Java version check failed. Required: $required_versions" >> "$LOG_FILE"
                return 1
            fi
        else
            echo -e "${GREEN}[PASS] Java is installed.${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: Java is installed." >> "$LOG_FILE"
            return 0
        fi
    else
        echo -e "${RED}[FAIL] Java is not installed.${NC}"
        echo -e "${YELLOW}Please install one of: $required_versions${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Java is not installed." >> "$LOG_FILE"
        return 1
    fi
}

# Function to check Python installation
check_python() {
    local required_versions="${1:-3.6,3.7,3.9,3.10}"
    
    echo "[INFO] Checking Python installation..."
    
    # Check if python3 is installed and get version
    if command -v python3 &>/dev/null; then
        python_version=$(python3 --version 2>&1 | cut -d ' ' -f 2)
        python_major=$(echo "$python_version" | cut -d. -f1)
        python_minor=$(echo "$python_version" | cut -d. -f2)
        
        echo "[INFO] Detected Python: $python_version"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Detected Python: $python_version" >> "$LOG_FILE"
        
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
                echo -e "${GREEN}[PASS] Python version check passed.${NC}"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: Python version check passed." >> "$LOG_FILE"
                return 0
            else
                echo -e "${RED}[FAIL] Python version check failed.${NC}"
                echo -e "${YELLOW}Required Python versions: $required_versions${NC}"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Python version check failed. Required: $required_versions" >> "$LOG_FILE"
                return 1
            fi
        else
            echo -e "${GREEN}[PASS] Python is installed.${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: Python is installed." >> "$LOG_FILE"
            return 0
        fi
    else
        echo -e "${RED}[FAIL] Python 3 is not installed.${NC}"
        echo -e "${YELLOW}Please install one of these Python versions: $required_versions${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Python 3 is not installed." >> "$LOG_FILE"
        return 1
    fi
}

# Function to check essential packages
check_packages() {
    local required_packages="${1:-git,nginx,zip,unzip,acl}"
    local package_manager=""
    
    echo "[INFO] Checking essential packages..."
    
    # Determine package manager
    if command -v apt-get &>/dev/null; then
        package_manager="apt"
    elif command -v yum &>/dev/null; then
        package_manager="yum"
    elif command -v dnf &>/dev/null; then
        package_manager="dnf"
    else
        echo -e "${YELLOW}[WARNING] Could not determine package manager. Skipping detailed package check.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: Could not determine package manager." >> "$LOG_FILE"
        
        # Basic check without package manager
        missing_packages=""
        for pkg in $(echo "$required_packages" | tr ',' ' '); do
            if ! command -v "$pkg" &>/dev/null; then
                missing_packages="$missing_packages $pkg"
            fi
        done
        
        if [[ -n "$missing_packages" ]]; then
            echo -e "${RED}[FAIL] Some required packages may be missing:$missing_packages${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Some required packages may be missing:$missing_packages" >> "$LOG_FILE"
            return 1
        else
            echo -e "${GREEN}[PASS] Basic package check passed.${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: Basic package check passed." >> "$LOG_FILE"
            return 0
        fi
    fi
    
    # Check packages based on package manager
    echo "[INFO] Using $package_manager package manager"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Using $package_manager package manager" >> "$LOG_FILE"
    
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
        echo -e "${RED}[FAIL] The following packages are missing:$missing_packages${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: The following packages are missing:$missing_packages" >> "$LOG_FILE"
        
        case $package_manager in
            apt)
                echo -e "${YELLOW}Install with: sudo apt-get install$missing_packages${NC}"
                ;;
            yum)
                echo -e "${YELLOW}Install with: sudo yum install$missing_packages${NC}"
                ;;
            dnf)
                echo -e "${YELLOW}Install with: sudo dnf install$missing_packages${NC}"
                ;;
        esac
        
        return 1
    else
        echo -e "${GREEN}[PASS] All required packages are installed.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: All required packages are installed." >> "$LOG_FILE"
        return 0
    fi
}

# Function to check repository access
check_repository_access() {
    local required_repos="${1:-EPEL}"
    local package_manager=""
    
    echo "[INFO] Checking repository access..."
    
    # Determine package manager
    if command -v apt-get &>/dev/null; then
        package_manager="apt"
    elif command -v yum &>/dev/null; then
        package_manager="yum"
    elif command -v dnf &>/dev/null; then
        package_manager="dnf"
    else
        echo -e "${YELLOW}[WARNING] Could not determine package manager. Skipping repository check.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: Could not determine package manager. Skipping repository check." >> "$LOG_FILE"
        return 0
    fi
    
    # Check repositories based on package manager
    missing_repos=""
    
    case $package_manager in
        apt)
            # For Debian/Ubuntu, check sources.list files
            if [[ "$required_repos" == *"EPEL"* ]]; then
                # EPEL is not relevant for apt-based systems
                echo "[INFO] EPEL is not required for Debian/Ubuntu-based systems."
                echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO: EPEL is not required for Debian/Ubuntu-based systems." >> "$LOG_FILE"
            fi
            
            # Check if apt update works (basic repository connectivity)
            if ! apt-get update -qq &>/dev/null; then
                echo -e "${RED}[FAIL] Repository connectivity check failed.${NC}"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Repository connectivity check failed." >> "$LOG_FILE"
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
        echo -e "${RED}[FAIL] The following repositories are missing:$missing_repos${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: The following repositories are missing:$missing_repos" >> "$LOG_FILE"
        
        if [[ "$missing_repos" == *"EPEL"* ]]; then
            case $package_manager in
                yum)
                    echo -e "${YELLOW}Install EPEL with: sudo yum install epel-release${NC}"
                    ;;
                dnf)
                    echo -e "${YELLOW}Install EPEL with: sudo dnf install epel-release${NC}"
                    ;;
            esac
        fi
        
        return 1
    else
        echo -e "${GREEN}[PASS] All required repositories are configured.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: All required repositories are configured." >> "$LOG_FILE"
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
    
    echo "==============================================="
    echo "Running Software and Dependency Checks"
    echo "==============================================="
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting software and dependency checks" >> "$LOG_FILE"
    
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
    
    echo ""
    echo "==============================================="
    
    if [[ "$software_check_passed" == true ]]; then
        echo -e "${GREEN}Software and dependency checks completed successfully.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Software and dependency checks completed successfully." >> "$LOG_FILE"
        return 0
    else
        echo -e "${RED}Software and dependency checks failed. Please address the issues above.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Software and dependency checks failed." >> "$LOG_FILE"
        return 1
    fi
} 