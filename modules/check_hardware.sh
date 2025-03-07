#!/bin/bash
# Hardware verification module for Dataiku DSS VM Diagnostic Automation
# This module checks CPU count, memory, and disk space requirements

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

# Function to check CPU count
check_cpu_count() {
    local required_cpus="${1:-}"
    
    info "Checking CPU count..."
    
    # Get CPU count using nproc if available, otherwise parse /proc/cpuinfo
    if command -v nproc &>/dev/null; then
        cpu_count=$(nproc)
    else
        cpu_count=$(grep -c "^processor" /proc/cpuinfo)
    fi
    
    info "Detected CPUs: $cpu_count"
    
    # Check if CPU count meets requirements
    if [[ -n "$required_cpus" ]]; then
        if [[ "$cpu_count" -ge "$required_cpus" ]]; then
            pass "CPU count check passed ($cpu_count >= $required_cpus)."
            return 0
        else
            fail "CPU count check failed. Found $cpu_count, required $required_cpus."
            return 1
        fi
    else
        warning "No required CPU count specified. Skipping check."
        return 0
    fi
}

# Function to check memory
check_memory() {
    local required_memory_gb="${1:-}"
    
    info "Checking memory size..."
    
    # Get memory size from /proc/meminfo
    if [[ -f /proc/meminfo ]]; then
        # Get total memory in kB and convert to GB
        mem_kb=$(grep "MemTotal:" /proc/meminfo | awk '{print $2}')
        mem_gb=$(awk "BEGIN {printf \"%.1f\", $mem_kb/1024/1024}")
        
        info "Detected memory: $mem_gb GB"
        
        # Check if memory meets requirements
        if [[ -n "$required_memory_gb" ]]; then
            # Use bc for floating point comparison
            if (( $(echo "$mem_gb >= $required_memory_gb" | bc -l) )); then
                pass "Memory size check passed ($mem_gb GB >= $required_memory_gb GB)."
                return 0
            else
                fail "Memory size check failed. Found $mem_gb GB, required $required_memory_gb GB."
                return 1
            fi
        else
            warning "No required memory size specified. Skipping check."
            return 0
        fi
    else
        fail "Cannot determine memory size (/proc/meminfo not found)."
        return 1
    fi
}

# Function to check root disk space
check_root_disk() {
    local min_root_disk_gb="${1:-}"
    
    info "Checking root disk space..."
    
    # Get root disk space using df
    if command -v df &>/dev/null; then
        # Get space in KB and convert to GB
        root_disk_kb=$(df -k / | awk 'NR==2 {print $2}')
        root_disk_gb=$(awk "BEGIN {printf \"%.1f\", $root_disk_kb/1024/1024}")
        
        info "Detected root disk space: $root_disk_gb GB"
        
        # Check if root disk meets requirements
        if [[ -n "$min_root_disk_gb" ]]; then
            # Use bc for floating point comparison
            if (( $(echo "$root_disk_gb >= $min_root_disk_gb" | bc -l) )); then
                pass "Root disk space check passed ($root_disk_gb GB >= $min_root_disk_gb GB)."
                return 0
            else
                fail "Root disk space check failed. Found $root_disk_gb GB, required $min_root_disk_gb GB."
                return 1
            fi
        else
            warning "No minimum root disk space specified. Skipping check."
            return 0
        fi
    else
        fail "Cannot determine disk space (df command not found)."
        return 1
    fi
}

# Function to check data disk space and filesystem
check_data_disk() {
    local mount_point="${1:-}"
    local min_data_disk_gb="${2:-}"
    local allowed_filesystems="${3:-ext4,xfs}"
    
    info "Checking data disk space and filesystem type..."
    
    # First check if mount point exists
    if [[ -z "$mount_point" ]]; then
        warning "No data disk mount point specified. Skipping check."
        return 0
    fi
    
    if [[ ! -d "$mount_point" ]]; then
        fail "Data disk mount point $mount_point does not exist."
        return 1
    fi
    
    # Get data disk space and filesystem using df
    if command -v df &>/dev/null; then
        # Check if mount point is actually mounted
        if ! df -T "$mount_point" 2>/dev/null | grep -q "$mount_point"; then
            fail "Data disk at $mount_point is not mounted."
            return 1
        fi
        
        # Get space in KB and convert to GB
        data_disk_kb=$(df -k "$mount_point" | awk 'NR==2 {print $2}')
        data_disk_gb=$(awk "BEGIN {printf \"%.1f\", $data_disk_kb/1024/1024}")
        
        # Get filesystem type
        fs_type=$(df -T "$mount_point" | awk 'NR==2 {print $2}')
        
        info "Detected data disk space: $data_disk_gb GB"
        info "Detected filesystem type: $fs_type"
        
        # Check filesystem type
        if [[ -n "$allowed_filesystems" ]]; then
            if value_in_list "$fs_type" "$allowed_filesystems"; then
                pass "Filesystem type check passed ($fs_type)."
            else
                fail "Filesystem type $fs_type is not supported."
                suggest "Supported filesystems: $allowed_filesystems"
                return 1
            fi
        fi
        
        # Check if data disk meets requirements
        if [[ -n "$min_data_disk_gb" ]]; then
            # Use bc for floating point comparison
            if (( $(echo "$data_disk_gb >= $min_data_disk_gb" | bc -l) )); then
                pass "Data disk space check passed ($data_disk_gb GB >= $min_data_disk_gb GB)."
                return 0
            else
                fail "Data disk space check failed. Found $data_disk_gb GB, required $min_data_disk_gb GB."
                return 1
            fi
        else
            warning "No minimum data disk space specified. Skipping size check."
            return 0
        fi
    else
        fail "Cannot determine disk space (df command not found)."
        return 1
    fi
}

# Main function to run all hardware checks
run_hardware_checks() {
    local required_cpus="${1:-}"
    local required_memory_gb="${2:-}"
    local min_root_disk_gb="${3:-}"
    local data_disk_mount="${4:-}"
    local min_data_disk_gb="${5:-}"
    local allowed_filesystems="${6:-ext4,xfs}"
    local hardware_check_passed=true
    
    section_header "Running Hardware Checks"
    
    # Run CPU count check
    if ! check_cpu_count "$required_cpus"; then
        hardware_check_passed=false
    fi
    
    echo ""
    
    # Run memory check
    if ! check_memory "$required_memory_gb"; then
        hardware_check_passed=false
    fi
    
    echo ""
    
    # Run root disk check
    if ! check_root_disk "$min_root_disk_gb"; then
        hardware_check_passed=false
    fi
    
    echo ""
    
    # Run data disk check
    if ! check_data_disk "$data_disk_mount" "$min_data_disk_gb" "$allowed_filesystems"; then
        hardware_check_passed=false
    fi
    
    # Return final result
    section_footer "$([[ "$hardware_check_passed" == true ]] && echo 0 || echo 1)" "Hardware checks"
    
    return "$([[ "$hardware_check_passed" == true ]] && echo 0 || echo 1)"
} 