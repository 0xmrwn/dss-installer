#!/bin/bash
# Network and connectivity verification module for Dataiku DSS VM Diagnostic Automation
# This module checks hostname resolution, network connectivity and port availability

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

# Function to check hostname resolution
check_hostname_resolution() {
    echo "[INFO] Checking hostname resolution..."
    
    # Get the hostname
    local hostname
    hostname=$(hostname)
    echo "[INFO] System hostname: $hostname"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - System hostname: $hostname" >> "$LOG_FILE"
    
    # Check if hostname resolves to an IP
    local hostname_resolves=false
    local hostname_ip=""
    
    # First try using getent hosts (available on most Linux systems)
    if command -v getent &>/dev/null; then
        if hostname_ip=$(getent hosts "$hostname" | awk '{print $1}' 2>/dev/null); then
            if [[ -n "$hostname_ip" ]]; then
                hostname_resolves=true
            fi
        fi
    fi
    
    # If getent failed, try using dig or host command
    if [[ "$hostname_resolves" == false ]] && command -v dig &>/dev/null; then
        if hostname_ip=$(dig +short "$hostname" 2>/dev/null); then
            if [[ -n "$hostname_ip" ]]; then
                hostname_resolves=true
            fi
        fi
    elif [[ "$hostname_resolves" == false ]] && command -v host &>/dev/null; then
        if host_output=$(host "$hostname" 2>/dev/null); then
            if [[ "$host_output" =~ has\ address\ ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ]]; then
                hostname_ip="${BASH_REMATCH[1]}"
                hostname_resolves=true
            fi
        fi
    fi
    
    # Check /etc/hosts file as last resort
    if [[ "$hostname_resolves" == false ]]; then
        if grep -q "$hostname" /etc/hosts; then
            hostname_ip=$(grep "$hostname" /etc/hosts | awk '{print $1}' | head -1)
            hostname_resolves=true
        fi
    fi
    
    if [[ "$hostname_resolves" == true ]]; then
        echo -e "${GREEN}[PASS] Hostname $hostname resolves to IP: $hostname_ip${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: Hostname $hostname resolves to IP: $hostname_ip" >> "$LOG_FILE"
        return 0
    else
        echo -e "${RED}[FAIL] Hostname $hostname does not resolve to an IP address.${NC}"
        echo -e "${YELLOW}Consider adding an entry to /etc/hosts or configuring DNS properly.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Hostname $hostname does not resolve to an IP address." >> "$LOG_FILE"
        return 1
    fi
}

# Function to check network connectivity
check_network_connectivity() {
    echo "[INFO] Checking internet connectivity..."
    
    local connectivity_check_passed=true
    local test_sites=("google.com" "github.com" "pypi.org")
    
    # Check connectivity to important sites
    for site in "${test_sites[@]}"; do
        echo "[INFO] Testing connection to $site..."
        
        if ping -c 1 -W 3 "$site" &>/dev/null; then
            echo -e "${GREEN}[PASS] Connection to $site is working.${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: Connection to $site is working." >> "$LOG_FILE"
        else
            echo -e "${YELLOW}[WARNING] Cannot connect to $site.${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: Cannot connect to $site." >> "$LOG_FILE"
            connectivity_check_passed=false
        fi
    done
    
    # Check HTTPS connectivity
    if command -v curl &>/dev/null; then
        echo "[INFO] Testing HTTPS connectivity..."
        if curl -s --head --max-time 5 https://www.google.com &>/dev/null; then
            echo -e "${GREEN}[PASS] HTTPS connectivity working.${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: HTTPS connectivity working." >> "$LOG_FILE"
        else
            echo -e "${YELLOW}[WARNING] HTTPS connectivity not working.${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: HTTPS connectivity not working." >> "$LOG_FILE"
            connectivity_check_passed=false
        fi
    elif command -v wget &>/dev/null; then
        echo "[INFO] Testing HTTPS connectivity..."
        if wget -q --spider --timeout=5 https://www.google.com &>/dev/null; then
            echo -e "${GREEN}[PASS] HTTPS connectivity working.${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: HTTPS connectivity working." >> "$LOG_FILE"
        else
            echo -e "${YELLOW}[WARNING] HTTPS connectivity not working.${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: HTTPS connectivity not working." >> "$LOG_FILE"
            connectivity_check_passed=false
        fi
    else
        echo -e "${YELLOW}[WARNING] Neither curl nor wget found. Cannot test HTTPS connectivity.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: Neither curl nor wget found. Cannot test HTTPS connectivity." >> "$LOG_FILE"
    fi
    
    if [[ "$connectivity_check_passed" == true ]]; then
        echo -e "${GREEN}[PASS] Network connectivity checks passed.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: Network connectivity checks passed." >> "$LOG_FILE"
        return 0
    else
        echo -e "${YELLOW}[WARNING] Some network connectivity checks failed. Dataiku DSS may require internet access.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: Some network connectivity checks failed." >> "$LOG_FILE"
        # Not returning error status as connectivity might be intentionally restricted
        return 0
    fi
}

# Function to check port availability
check_ports() {
    local port_range="${1:-}"
    
    echo "[INFO] Checking port availability..."
    
    if [[ -z "$port_range" ]]; then
        echo -e "${YELLOW}[WARNING] No port range specified for checking. Skipping port check.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: No port range specified for checking." >> "$LOG_FILE"
        return 0
    fi
    
    echo "[INFO] Checking if ports in range $port_range are available..."
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Checking if ports in range $port_range are available" >> "$LOG_FILE"
    
    # Parse port range
    local start_port
    local end_port
    if [[ "$port_range" =~ ([0-9]+)-([0-9]+) ]]; then
        start_port="${BASH_REMATCH[1]}"
        end_port="${BASH_REMATCH[2]}"
    else
        echo -e "${RED}[FAIL] Invalid port range format: $port_range. Expected format: START-END (e.g., 10000-10010)${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Invalid port range format: $port_range" >> "$LOG_FILE"
        return 1
    fi
    
    local used_ports=""
    local ports_check_passed=true
    
    # Check if ss is available, otherwise try netstat
    if command -v ss &>/dev/null; then
        echo "[INFO] Using ss to check port usage..."
        
        for port in $(seq "$start_port" "$end_port"); do
            if ss -tuln | grep -q ":$port "; then
                used_ports="$used_ports $port"
                echo -e "${RED}[FAIL] Port $port is already in use.${NC}"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Port $port is already in use." >> "$LOG_FILE"
                ports_check_passed=false
            fi
        done
    elif command -v netstat &>/dev/null; then
        echo "[INFO] Using netstat to check port usage..."
        
        for port in $(seq "$start_port" "$end_port"); do
            if netstat -tuln | grep -q ":$port "; then
                used_ports="$used_ports $port"
                echo -e "${RED}[FAIL] Port $port is already in use.${NC}"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Port $port is already in use." >> "$LOG_FILE"
                ports_check_passed=false
            fi
        done
    else
        echo -e "${YELLOW}[WARNING] Neither ss nor netstat commands found. Cannot check port availability.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: Neither ss nor netstat commands found. Cannot check port availability." >> "$LOG_FILE"
        return 0 # Not marking as failed since we can't check
    fi
    
    if [[ "$ports_check_passed" == true ]]; then
        echo -e "${GREEN}[PASS] All ports in range $port_range are available.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: All ports in range $port_range are available." >> "$LOG_FILE"
    else
        echo -e "${RED}[FAIL] Some ports in range $port_range are already in use: $used_ports${NC}"
        echo -e "${YELLOW}Please free up these ports or configure Dataiku DSS to use a different port range.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Some ports in range $port_range are already in use: $used_ports" >> "$LOG_FILE"
    fi
    
    return "$([[ "$ports_check_passed" == true ]] && echo 0 || echo 1)"
}

# Main function to run all network checks
run_network_checks() {
    local port_range="${1:-}"
    local network_check_passed=true
    
    echo "==============================================="
    echo "Running Network and Connectivity Checks"
    echo "==============================================="
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting network and connectivity checks" >> "$LOG_FILE"
    
    # Run hostname resolution check
    if ! check_hostname_resolution; then
        network_check_passed=false
    fi
    
    echo ""
    
    # Run general network connectivity check
    if ! check_network_connectivity; then
        # Not marking as failed as connectivity might be intentionally restricted
        echo "[INFO] Connectivity issues found but continuing with checks."
    fi
    
    echo ""
    
    # Run port availability check
    if ! check_ports "$port_range"; then
        network_check_passed=false
    fi
    
    echo ""
    echo "==============================================="
    
    if [[ "$network_check_passed" == true ]]; then
        echo -e "${GREEN}Network and connectivity checks completed successfully.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Network and connectivity checks completed successfully." >> "$LOG_FILE"
        return 0
    else
        echo -e "${RED}Network and connectivity checks failed. Please address the issues above.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Network and connectivity checks failed." >> "$LOG_FILE"
        return 1
    fi
} 