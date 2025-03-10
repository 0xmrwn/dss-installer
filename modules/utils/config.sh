#!/bin/bash
# Utility functions for configuration management

# Exit on error, treat unset variables as errors
set -eu

# Function to read a value from INI file
read_ini() {
    local config_file="$1"
    local key="$2"
    local default="${3:-}"
    
    # Try to get value from NODE section
    local value
    value=$(awk -F "=" -v key="$key" '
        BEGIN { in_section = 0 }
        /^\[NODE\]/ { in_section = 1 }
        /^\[/ && !/^\[NODE\]/ { in_section = 0 }
        in_section && $1 ~ "^[ \t]*"key"[ \t]*$" { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }
    ' "$config_file" | tr -d '\r')
    
    # If not found, use default
    if [[ -z "$value" ]]; then
        value="$default"
    fi
    
    echo "$value"
}

# Function to load all configuration parameters
load_config_parameters() {
    local config_file="$1"
    local prefix="$2"  # Prefix for variable names
    
    # OS check parameters
    eval "${prefix}_allowed_os_distros=\"$(read_ini "$config_file" "allowed_os_distros")\""
    eval "${prefix}_allowed_os_versions=\"$(read_ini "$config_file" "allowed_os_versions")\""
    eval "${prefix}_min_kernel_version=\"$(read_ini "$config_file" "min_kernel_version")\""
    eval "${prefix}_locale_required=\"$(read_ini "$config_file" "locale_required")\""
    
    # Hardware check parameters
    eval "${prefix}_vcpus=\"$(read_ini "$config_file" "vcpus")\""
    eval "${prefix}_memory_gb=\"$(read_ini "$config_file" "memory_gb")\""
    eval "${prefix}_min_root_disk_gb=\"$(read_ini "$config_file" "min_root_disk_gb")\""
    eval "${prefix}_data_disk_mount=\"$(read_ini "$config_file" "data_disk_mount")\""
    eval "${prefix}_min_data_disk_gb=\"$(read_ini "$config_file" "min_data_disk_gb")\""
    eval "${prefix}_filesystem=\"$(read_ini "$config_file" "filesystem")\""
    
    # System limits check parameters
    eval "${prefix}_ulimit_files=\"$(read_ini "$config_file" "ulimit_files")\""
    eval "${prefix}_ulimit_processes=\"$(read_ini "$config_file" "ulimit_processes")\""
    eval "${prefix}_port_range=\"$(read_ini "$config_file" "port_range")\""
    
    # Software check parameters
    eval "${prefix}_java_versions=\"$(read_ini "$config_file" "java_versions")\""
    eval "${prefix}_python_versions=\"$(read_ini "$config_file" "python_versions")\""
    eval "${prefix}_required_packages=\"$(read_ini "$config_file" "required_packages")\""
    eval "${prefix}_required_repos=\"$(read_ini "$config_file" "required_repos")\""
    
    # Get node type if specified in config
    local config_node_type
    config_node_type=$(read_ini "$config_file" "node_type")
    if [[ -n "$config_node_type" ]]; then
        eval "${prefix}_node_type=\"$(echo "$config_node_type" | tr '[:lower:]' '[:upper:]')\""
    fi
}

# Function to display config parameters in verbose mode
display_verbose_config() {
    local prefix="$1"  # Prefix for variable names
    
    echo -e "${BRIGHT_WHITE}${BOLD}Configuration Parameters:${NC}"
    echo -e "${GRAY}──────────────────────────────────────────${NC}"
    
    echo -e "${CYAN}${BOLD}Operating System Requirements:${NC}"
    eval "show_config_property \"Allowed OS Distros\" \"\${${prefix}_allowed_os_distros}\""
    eval "show_config_property \"Allowed OS Versions\" \"\${${prefix}_allowed_os_versions}\""
    eval "show_config_property \"Min Kernel Version\" \"\${${prefix}_min_kernel_version}\""
    eval "show_config_property \"Required Locale\" \"\${${prefix}_locale_required}\""
    echo ""
    
    echo -e "${CYAN}${BOLD}Hardware Requirements:${NC}"
    eval "show_config_property \"Required vCPUs\" \"\${${prefix}_vcpus}\""
    eval "show_config_property \"Required Memory (GB)\" \"\${${prefix}_memory_gb}\""
    eval "show_config_property \"Min Root Disk (GB)\" \"\${${prefix}_min_root_disk_gb}\""
    eval "show_config_property \"Data Disk Mount\" \"\${${prefix}_data_disk_mount}\""
    eval "show_config_property \"Min Data Disk (GB)\" \"\${${prefix}_min_data_disk_gb}\""
    eval "show_config_property \"Allowed Filesystem\" \"\${${prefix}_filesystem}\""
    echo ""
    
    echo -e "${CYAN}${BOLD}System Limits:${NC}"
    eval "show_config_property \"Required Open Files Limit\" \"\${${prefix}_ulimit_files}\""
    eval "show_config_property \"Required User Processes Limit\" \"\${${prefix}_ulimit_processes}\""
    eval "show_config_property \"Port Range to Check\" \"\${${prefix}_port_range}\""
    echo ""
    
    echo -e "${CYAN}${BOLD}Software Requirements:${NC}"
    eval "show_config_property \"Required Java Versions\" \"\${${prefix}_java_versions}\""
    eval "show_config_property \"Required Python Versions\" \"\${${prefix}_python_versions}\""
    eval "show_config_property \"Required Packages\" \"\${${prefix}_required_packages}\""
    eval "show_config_property \"Required Repositories\" \"\${${prefix}_required_repos}\""
    echo -e "${GRAY}──────────────────────────────────────────${NC}"
    echo ""
} 