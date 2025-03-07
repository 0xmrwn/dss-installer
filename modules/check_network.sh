#!/bin/bash
# Network and connectivity verification module for Dataiku DSS VM Diagnostic Automation
# This module checks hostname resolution, network connectivity and port availability

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

# Function to check hostname resolution
check_hostname_resolution() {
    info "Checking hostname resolution..."
    
    # Get the hostname
    local hostname
    hostname=$(hostname)
    info "System hostname: $hostname"
    
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
        pass "Hostname $hostname resolves to IP: $hostname_ip"
        return 0
    else
        fail "Hostname $hostname does not resolve to an IP address."
        suggest "Consider adding an entry to /etc/hosts or configuring DNS properly."
        return 1
    fi
}

# Function to check network connectivity
check_network_connectivity() {
    info "Checking internet connectivity..."
    
    local connectivity_check_passed=true
    local test_sites=("google.com" "github.com" "pypi.org")
    
    # Check connectivity to important sites
    for site in "${test_sites[@]}"; do
        info "Testing connection to $site..."
        
        if ping -c 1 -W 3 "$site" &>/dev/null; then
            pass "Connection to $site is working."
        else
            warning "Cannot connect to $site."
            connectivity_check_passed=false
        fi
    done
    
    # Check HTTPS connectivity
    if command -v curl &>/dev/null; then
        info "Testing HTTPS connectivity..."
        if curl -s --head --max-time 5 https://www.google.com &>/dev/null; then
            pass "HTTPS connectivity working."
        else
            warning "HTTPS connectivity not working."
            connectivity_check_passed=false
        fi
    elif command -v wget &>/dev/null; then
        info "Testing HTTPS connectivity..."
        if wget -q --spider --timeout=5 https://www.google.com &>/dev/null; then
            pass "HTTPS connectivity working."
        else
            warning "HTTPS connectivity not working."
            connectivity_check_passed=false
        fi
    else
        warning "Neither curl nor wget found. Cannot test HTTPS connectivity."
    fi
    
    if [[ "$connectivity_check_passed" == true ]]; then
        pass "Network connectivity checks passed."
        return 0
    else
        warning "Some network connectivity checks failed. Dataiku DSS may require internet access."
        # Not returning error status as connectivity might be intentionally restricted
        return 0
    fi
}

# Function to check port availability
check_ports() {
    local port_range="${1:-}"
    
    info "Checking port availability..."
    
    if [[ -z "$port_range" ]]; then
        warning "No port range specified for checking. Skipping port check."
        return 0
    fi
    
    info "Checking if ports in range $port_range are available..."
    
    # Parse port range
    local start_port
    local end_port
    if [[ "$port_range" =~ ([0-9]+)-([0-9]+) ]]; then
        start_port="${BASH_REMATCH[1]}"
        end_port="${BASH_REMATCH[2]}"
    else
        fail "Invalid port range format: $port_range. Expected format: START-END (e.g., 10000-10010)"
        return 1
    fi
    
    local used_ports=""
    local ports_check_passed=true
    
    # Check if ss is available, otherwise try netstat
    if command -v ss &>/dev/null; then
        info "Using ss to check port usage..."
        
        for port in $(seq "$start_port" "$end_port"); do
            if ss -tuln | grep -q ":$port "; then
                used_ports="$used_ports $port"
                fail "Port $port is already in use."
                ports_check_passed=false
            fi
        done
    elif command -v netstat &>/dev/null; then
        info "Using netstat to check port usage..."
        
        for port in $(seq "$start_port" "$end_port"); do
            if netstat -tuln | grep -q ":$port "; then
                used_ports="$used_ports $port"
                fail "Port $port is already in use."
                ports_check_passed=false
            fi
        done
    else
        warning "Neither ss nor netstat commands found. Cannot check port availability."
        return 0 # Not marking as failed since we can't check
    fi
    
    if [[ "$ports_check_passed" == true ]]; then
        pass "All ports in range $port_range are available."
    else
        fail "Some ports in range $port_range are already in use: $used_ports"
        suggest "Please free up these ports or configure Dataiku DSS to use a different port range."
    fi
    
    return "$([[ "$ports_check_passed" == true ]] && echo 0 || echo 1)"
}

# Main function to run all network checks
run_network_checks() {
    local port_range="${1:-}"
    local network_check_passed=true
    
    section_header "Running Network and Connectivity Checks"
    
    # Run hostname resolution check
    if ! check_hostname_resolution; then
        network_check_passed=false
    fi
    
    echo ""
    
    # Run general network connectivity check
    if ! check_network_connectivity; then
        # Not marking as failed as connectivity might be intentionally restricted
        info "Connectivity issues found but continuing with checks."
    fi
    
    echo ""
    
    # Run port availability check
    if ! check_ports "$port_range"; then
        network_check_passed=false
    fi
    
    # Return final result
    section_footer "$([[ "$network_check_passed" == true ]] && echo 0 || echo 1)" "Network and connectivity checks"
    
    return "$([[ "$network_check_passed" == true ]] && echo 0 || echo 1)"
} 