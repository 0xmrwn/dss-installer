#!/bin/bash
# Filesystem verification module for Dataiku DSS VM Diagnostic Automation
# This module checks filesystem types and mount points

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

# Function to check filesystem type for a given mount point
check_filesystem_type() {
    local mount_point="${1:-}"
    local allowed_filesystems="${2:-ext4,xfs}"
    
    info "Checking filesystem type for mount point: $mount_point"
    
    # First check if mount point exists
    if [[ -z "$mount_point" ]]; then
        warning "No mount point specified. Skipping check."
        return 0
    fi
    
    if [[ ! -d "$mount_point" ]]; then
        fail "Mount point $mount_point does not exist."
        return 1
    fi
    
    # Check if we have df command
    if ! command -v df &>/dev/null; then
        fail "Cannot determine filesystem type (df command not found)."
        return 1
    fi
    
    # Check if mount point is actually mounted
    if ! df -T "$mount_point" 2>/dev/null | grep -q "$mount_point"; then
        fail "No filesystem mounted at $mount_point."
        return 1
    fi
    
    # Get filesystem type
    local fs_type
    fs_type=$(df -T "$mount_point" | awk 'NR==2 {print $2}')
    
    info "Detected filesystem type: $fs_type"
    
    # Check filesystem type against allowed list
    if [[ -n "$allowed_filesystems" ]]; then
        if value_in_list "$fs_type" "$allowed_filesystems"; then
            pass "Filesystem type check passed ($fs_type)."
            return 0
        else
            fail "Filesystem type $fs_type is not supported for $mount_point."
            suggest "Supported filesystems: $allowed_filesystems"
            return 1
        fi
    else
        warning "No allowed filesystem types specified. Skipping validation."
        return 0
    fi
}

# Function to check ACL support
check_acl_support() {
    local mount_point="${1:-}"
    
    # Skip if no mount point specified
    if [[ -z "$mount_point" ]]; then
        warning "No mount point specified. Skipping ACL support check."
        return 0
    fi
    
    info "Checking ACL support for $mount_point..."
    
    # First check if we have the necessary commands
    if ! command -v setfacl &>/dev/null || ! command -v getfacl &>/dev/null; then
        fail "ACL commands (setfacl/getfacl) not found. Please install acl package."
        suggest "Install ACL package: yum install acl (RHEL/CentOS) or apt-get install acl (Ubuntu/Debian)"
        return 1
    fi
    
    # Create a temporary test file
    local test_file="${mount_point}/dss_acl_test_$RANDOM"
    if ! touch "$test_file" 2>/dev/null; then
        fail "Unable to create test file for ACL check on $mount_point."
        suggest "Check permissions on the mount point."
        return 1
    fi
    
    # Try to set an ACL
    local current_user
    current_user=$(whoami)
    
    if ! setfacl -m "u:${current_user}:r" "$test_file" 2>/dev/null; then
        rm -f "$test_file" 2>/dev/null
        fail "Failed to set ACL on test file. ACL support may not be enabled."
        suggest "Ensure the filesystem is mounted with the 'acl' option."
        return 1
    fi
    
    # Verify ACL was set
    if ! getfacl "$test_file" 2>/dev/null | grep -q "user:${current_user}:r"; then
        rm -f "$test_file" 2>/dev/null
        fail "ACL was not correctly applied. ACL support may not be functioning correctly."
        suggest "Check if the filesystem supports ACLs and is mounted correctly."
        return 1
    fi
    
    # Clean up
    rm -f "$test_file" 2>/dev/null
    pass "ACL support is enabled and functioning correctly on $mount_point."
    return 0
}

# Function to check file locking support
check_file_locking() {
    local mount_point="${1:-}"
    
    # Skip if no mount point specified
    if [[ -z "$mount_point" ]]; then
        warning "No mount point specified. Skipping file locking check."
        return 0
    fi
    
    info "Checking file locking support for $mount_point..."
    
    # Check if flock is available
    if ! command -v flock &>/dev/null; then
        warning "flock command not found. Cannot verify file locking support."
        suggest "For complete check, install util-linux package."
        return 0
    fi
    
    # Create a temporary lock file
    local lock_file="${mount_point}/dss_lock_test_$RANDOM"
    touch "$lock_file" 2>/dev/null || {
        fail "Unable to create test file for lock check on $mount_point."
        suggest "Check permissions on the mount point."
        return 1
    }
    
    # Try to acquire a lock in background
    (
        flock -w 1 9 || {
            echo "ERROR_ACQUIRING_FIRST_LOCK"
            exit 1
        }
        # Hold the lock for 2 seconds
        sleep 2
        echo "FIRST_LOCK_ACQUIRED" >&9
    ) 9>"$lock_file" &
    local first_lock_pid=$!
    
    # Give time for the first lock to be acquired
    sleep 1
    
    # Try to acquire a second lock with timeout
    local second_lock_result
    second_lock_result=$(
        flock -w 1 9 || {
            echo "SECOND_LOCK_BLOCKED"
            exit 0
        }
        echo "SECOND_LOCK_ACQUIRED"
    ) 9<"$lock_file"
    
    # Wait for the first process to finish
    wait "$first_lock_pid"
    local first_lock_exit=$?
    
    # Clean up
    rm -f "$lock_file" 2>/dev/null
    
    # Evaluate results
    if [[ $first_lock_exit -ne 0 ]]; then
        fail "Failed to acquire first lock. File locking may not be supported."
        return 1
    fi
    
    if [[ "$second_lock_result" == "SECOND_LOCK_BLOCKED" ]]; then
        pass "File locking is supported on $mount_point (locks are blocking correctly)."
        return 0
    else
        warning "Second lock was not blocked as expected. File locking behavior may not be reliable."
        suggest "Verify that the filesystem supports proper file locking."
        return 1
    fi
}

# Function to check symbolic link support
check_symlink_support() {
    local mount_point="${1:-}"
    
    # Skip if no mount point specified
    if [[ -z "$mount_point" ]]; then
        warning "No mount point specified. Skipping symbolic link check."
        return 0
    fi
    
    info "Checking symbolic link support for $mount_point..."
    
    # Create a test file and try to create a symlink to it
    local test_file="${mount_point}/dss_symlink_test_file_$RANDOM"
    local test_link="${mount_point}/dss_symlink_test_link_$RANDOM"
    
    if ! touch "$test_file" 2>/dev/null; then
        fail "Unable to create test file for symlink check on $mount_point."
        suggest "Check permissions on the mount point."
        return 1
    fi
    
    if ! ln -s "$test_file" "$test_link" 2>/dev/null; then
        rm -f "$test_file" 2>/dev/null
        fail "Failed to create symbolic link. Symlink support may not be enabled."
        suggest "Ensure the filesystem supports symbolic links."
        return 1
    fi
    
    # Verify the symlink was created correctly
    if ! [[ -L "$test_link" && -e "$test_link" ]]; then
        rm -f "$test_file" "$test_link" 2>/dev/null
        fail "Symbolic link was not created correctly or doesn't point to the target file."
        suggest "Check if the filesystem supports symbolic links properly."
        return 1
    fi
    
    # Clean up
    rm -f "$test_file" "$test_link" 2>/dev/null
    pass "Symbolic link support is functioning correctly on $mount_point."
    return 0
}

# Function to check case sensitivity
check_case_sensitivity() {
    local mount_point="${1:-}"
    
    # Skip if no mount point specified
    if [[ -z "$mount_point" ]]; then
        warning "No mount point specified. Skipping case sensitivity check."
        return 0
    fi
    
    info "Checking case sensitivity for $mount_point..."
    
    # Create two files with names differing only by case
    local test_file_upper="${mount_point}/DSS_CASE_TEST_$RANDOM"
    local test_file_lower="${mount_point}/dss_case_test_$RANDOM"
    
    # Make sure the filenames are actually different
    test_file_lower=$(echo "$test_file_upper" | tr '[:upper:]' '[:lower:]')
    
    if ! touch "$test_file_upper" 2>/dev/null; then
        fail "Unable to create test file for case sensitivity check on $mount_point."
        suggest "Check permissions on the mount point."
        return 1
    fi
    
    if ! touch "$test_file_lower" 2>/dev/null; then
        rm -f "$test_file_upper" 2>/dev/null
        fail "Unable to create second test file for case sensitivity check."
        return 1
    fi
    
    # Check if both files exist separately
    if [[ ! -f "$test_file_upper" || ! -f "$test_file_lower" ]]; then
        rm -f "$test_file_upper" "$test_file_lower" 2>/dev/null
        fail "Filesystem appears to be case-insensitive. Both test files are not present as separate entities."
        suggest "Dataiku DSS requires a case-sensitive filesystem."
        return 1
    fi
    
    # Check if they are actually different files
    local upper_inode
    local lower_inode
    upper_inode=$(stat -c %i "$test_file_upper" 2>/dev/null)
    lower_inode=$(stat -c %i "$test_file_lower" 2>/dev/null)
    
    if [[ "$upper_inode" == "$lower_inode" ]]; then
        rm -f "$test_file_upper" "$test_file_lower" 2>/dev/null
        fail "Filesystem is case-insensitive (same inode for differently cased files)."
        suggest "Dataiku DSS requires a case-sensitive filesystem."
        return 1
    fi
    
    # Clean up
    rm -f "$test_file_upper" "$test_file_lower" 2>/dev/null
    pass "Filesystem is case-sensitive on $mount_point."
    return 0
}

# Main function to run all filesystem checks
run_filesystem_checks() {
    local root_mount="${1:-/}"
    local data_mount="${2:-}"
    local allowed_filesystems="${3:-ext4,xfs}"
    local filesystem_check_passed=true
    
    section_header "Running Filesystem Checks"
    
    # Check root filesystem type
    info "Checking root filesystem type..."
    if ! check_filesystem_type "$root_mount" "$allowed_filesystems"; then
        filesystem_check_passed=false
    fi
    
    echo ""
    
    # Check data filesystem type if specified
    if [[ -n "$data_mount" ]]; then
        info "Checking data filesystem type and features..."
        if ! check_filesystem_type "$data_mount" "$allowed_filesystems"; then
            filesystem_check_passed=false
        fi
        
        echo ""
        
        # The following checks are only run on the data disk where Dataiku DSS data will be stored
        # These features are critical for proper Dataiku DSS operation
        
        # Check ACL support
        if ! check_acl_support "$data_mount"; then
            filesystem_check_passed=false
        fi
        
        echo ""
        
        # Check file locking support
        if ! check_file_locking "$data_mount"; then
            filesystem_check_passed=false
        fi
        
        echo ""
        
        # Check symbolic link support
        if ! check_symlink_support "$data_mount"; then
            filesystem_check_passed=false
        fi
        
        echo ""
        
        # Check case sensitivity
        if ! check_case_sensitivity "$data_mount"; then
            filesystem_check_passed=false
        fi
        
        echo ""
    else
        warning "No data mount point specified. Only checking root filesystem type."
        warning "Dataiku DSS requires additional filesystem features that are not being checked."
        suggest "Specify a data mount point to run complete filesystem checks."
    fi
    
    # Return final result
    section_footer "$([[ "$filesystem_check_passed" == true ]] && echo 0 || echo 1)" "Filesystem checks"
    
    return "$([[ "$filesystem_check_passed" == true ]] && echo 0 || echo 1)"
} 