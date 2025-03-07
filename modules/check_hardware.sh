#!/bin/bash
# Hardware verification module for Dataiku DSS VM Diagnostic Automation
# This module checks CPU count, memory, and disk space requirements

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

# Function to check CPU count
check_cpu_count() {
    local required_cpus="${1:-}"
    
    echo "[INFO] Checking CPU count..."
    
    # Get CPU count using nproc if available, otherwise parse /proc/cpuinfo
    if command -v nproc &>/dev/null; then
        cpu_count=$(nproc)
    else
        cpu_count=$(grep -c "^processor" /proc/cpuinfo)
    fi
    
    echo "[INFO] Detected CPUs: $cpu_count"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Detected CPUs: $cpu_count" >> "$LOG_FILE"
    
    # Check if CPU count meets requirements
    if [[ -n "$required_cpus" ]]; then
        if [[ "$cpu_count" -ge "$required_cpus" ]]; then
            echo -e "${GREEN}[PASS] CPU count check passed ($cpu_count >= $required_cpus).${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: CPU count check passed ($cpu_count >= $required_cpus)." >> "$LOG_FILE"
            return 0
        else
            echo -e "${RED}[FAIL] CPU count check failed. Found $cpu_count, required $required_cpus.${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: CPU count check failed. Found $cpu_count, required $required_cpus." >> "$LOG_FILE"
            return 1
        fi
    else
        echo -e "${YELLOW}[WARNING] No required CPU count specified. Skipping check.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: No required CPU count specified. Skipping check." >> "$LOG_FILE"
        return 0
    fi
}

# Function to check memory
check_memory() {
    local required_memory_gb="${1:-}"
    
    echo "[INFO] Checking memory size..."
    
    # Get memory size from /proc/meminfo
    if [[ -f /proc/meminfo ]]; then
        # Get total memory in kB and convert to GB
        mem_kb=$(grep "MemTotal:" /proc/meminfo | awk '{print $2}')
        mem_gb=$(awk "BEGIN {printf \"%.1f\", $mem_kb/1024/1024}")
        
        echo "[INFO] Detected memory: $mem_gb GB"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Detected memory: $mem_gb GB" >> "$LOG_FILE"
        
        # Check if memory meets requirements
        if [[ -n "$required_memory_gb" ]]; then
            # Use bc for floating point comparison
            if (( $(echo "$mem_gb >= $required_memory_gb" | bc -l) )); then
                echo -e "${GREEN}[PASS] Memory size check passed ($mem_gb GB >= $required_memory_gb GB).${NC}"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: Memory size check passed ($mem_gb GB >= $required_memory_gb GB)." >> "$LOG_FILE"
                return 0
            else
                echo -e "${RED}[FAIL] Memory size check failed. Found $mem_gb GB, required $required_memory_gb GB.${NC}"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Memory size check failed. Found $mem_gb GB, required $required_memory_gb GB." >> "$LOG_FILE"
                return 1
            fi
        else
            echo -e "${YELLOW}[WARNING] No required memory size specified. Skipping check.${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: No required memory size specified. Skipping check." >> "$LOG_FILE"
            return 0
        fi
    else
        echo -e "${RED}[FAIL] Cannot determine memory size (/proc/meminfo not found).${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Cannot determine memory size (/proc/meminfo not found)." >> "$LOG_FILE"
        return 1
    fi
}

# Function to check root disk space
check_root_disk() {
    local min_root_disk_gb="${1:-}"
    
    echo "[INFO] Checking root disk space..."
    
    # Get root disk space using df
    if command -v df &>/dev/null; then
        # Get space in KB and convert to GB
        root_disk_kb=$(df -k / | awk 'NR==2 {print $2}')
        root_disk_gb=$(awk "BEGIN {printf \"%.1f\", $root_disk_kb/1024/1024}")
        
        echo "[INFO] Detected root disk space: $root_disk_gb GB"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Detected root disk space: $root_disk_gb GB" >> "$LOG_FILE"
        
        # Check if root disk meets requirements
        if [[ -n "$min_root_disk_gb" ]]; then
            # Use bc for floating point comparison
            if (( $(echo "$root_disk_gb >= $min_root_disk_gb" | bc -l) )); then
                echo -e "${GREEN}[PASS] Root disk space check passed ($root_disk_gb GB >= $min_root_disk_gb GB).${NC}"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: Root disk space check passed ($root_disk_gb GB >= $min_root_disk_gb GB)." >> "$LOG_FILE"
                return 0
            else
                echo -e "${RED}[FAIL] Root disk space check failed. Found $root_disk_gb GB, required $min_root_disk_gb GB.${NC}"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Root disk space check failed. Found $root_disk_gb GB, required $min_root_disk_gb GB." >> "$LOG_FILE"
                return 1
            fi
        else
            echo -e "${YELLOW}[WARNING] No minimum root disk space specified. Skipping check.${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: No minimum root disk space specified. Skipping check." >> "$LOG_FILE"
            return 0
        fi
    else
        echo -e "${RED}[FAIL] Cannot determine disk space (df command not found).${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Cannot determine disk space (df command not found)." >> "$LOG_FILE"
        return 1
    fi
}

# Function to check data disk space and filesystem
check_data_disk() {
    local mount_point="${1:-}"
    local min_data_disk_gb="${2:-}"
    local allowed_filesystems="${3:-ext4,xfs}"
    
    echo "[INFO] Checking data disk space and filesystem type..."
    
    # First check if mount point exists
    if [[ -z "$mount_point" ]]; then
        echo -e "${YELLOW}[WARNING] No data disk mount point specified. Skipping check.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: No data disk mount point specified. Skipping check." >> "$LOG_FILE"
        return 0
    fi
    
    if [[ ! -d "$mount_point" ]]; then
        echo -e "${RED}[FAIL] Data disk mount point $mount_point does not exist.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Data disk mount point $mount_point does not exist." >> "$LOG_FILE"
        return 1
    fi
    
    # Get data disk space and filesystem using df
    if command -v df &>/dev/null; then
        # Check if mount point is actually mounted
        if ! df -T "$mount_point" 2>/dev/null | grep -q "$mount_point"; then
            echo -e "${RED}[FAIL] Data disk at $mount_point is not mounted.${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Data disk at $mount_point is not mounted." >> "$LOG_FILE"
            return 1
        fi
        
        # Get space in KB and convert to GB
        data_disk_kb=$(df -k "$mount_point" | awk 'NR==2 {print $2}')
        data_disk_gb=$(awk "BEGIN {printf \"%.1f\", $data_disk_kb/1024/1024}")
        
        # Get filesystem type
        fs_type=$(df -T "$mount_point" | awk 'NR==2 {print $2}')
        
        echo "[INFO] Detected data disk space: $data_disk_gb GB"
        echo "[INFO] Detected filesystem type: $fs_type"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Detected data disk space: $data_disk_gb GB" >> "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Detected filesystem type: $fs_type" >> "$LOG_FILE"
        
        # Check filesystem type
        if [[ -n "$allowed_filesystems" ]]; then
            allowed=false
            for fs in $(echo "$allowed_filesystems" | tr ',' ' '); do
                if [[ "$fs_type" == "$fs" ]]; then
                    allowed=true
                    break
                fi
            done
            
            if [[ "$allowed" == false ]]; then
                echo -e "${RED}[FAIL] Filesystem type $fs_type is not supported.${NC}"
                echo -e "${YELLOW}Supported filesystems: $allowed_filesystems ${NC}"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Filesystem type $fs_type is not supported. Supported: $allowed_filesystems" >> "$LOG_FILE"
                return 1
            else
                echo -e "${GREEN}[PASS] Filesystem type check passed ($fs_type).${NC}"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: Filesystem type check passed ($fs_type)." >> "$LOG_FILE"
            fi
        fi
        
        # Check if data disk meets requirements
        if [[ -n "$min_data_disk_gb" ]]; then
            # Use bc for floating point comparison
            if (( $(echo "$data_disk_gb >= $min_data_disk_gb" | bc -l) )); then
                echo -e "${GREEN}[PASS] Data disk space check passed ($data_disk_gb GB >= $min_data_disk_gb GB).${NC}"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - PASS: Data disk space check passed ($data_disk_gb GB >= $min_data_disk_gb GB)." >> "$LOG_FILE"
                return 0
            else
                echo -e "${RED}[FAIL] Data disk space check failed. Found $data_disk_gb GB, required $min_data_disk_gb GB.${NC}"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Data disk space check failed. Found $data_disk_gb GB, required $min_data_disk_gb GB." >> "$LOG_FILE"
                return 1
            fi
        else
            echo -e "${YELLOW}[WARNING] No minimum data disk space specified. Skipping size check.${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: No minimum data disk space specified. Skipping size check." >> "$LOG_FILE"
            return 0
        fi
    else
        echo -e "${RED}[FAIL] Cannot determine disk space (df command not found).${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - FAIL: Cannot determine disk space (df command not found)." >> "$LOG_FILE"
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
    
    echo "==============================================="
    echo "Running Hardware Checks"
    echo "==============================================="
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting hardware checks" >> "$LOG_FILE"
    
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
    
    echo ""
    echo "==============================================="
    
    if [[ "$hardware_check_passed" == true ]]; then
        echo -e "${GREEN}Hardware checks completed successfully.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Hardware checks completed successfully." >> "$LOG_FILE"
        return 0
    else
        echo -e "${RED}Hardware checks failed. Please address the issues above.${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Hardware checks failed." >> "$LOG_FILE"
        return 1
    fi
} 