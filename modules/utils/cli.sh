#!/bin/bash
# Utility functions for CLI operations

# Exit on error, treat unset variables as errors
set -eu

# Function to display usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Run diagnostic checks for Dataiku DSS installation."
    echo ""
    echo "Options:"
    echo "  -c, --config FILE    Path to configuration file (default: config.ini)"
    echo "  -n, --node TYPE      Node type for reporting purposes only (default: DESIGN)"
    echo "  -l, --log FILE       Path to log file (default: diagnostics.log)"
    echo "  -v, --verbose        Enable verbose output"
    echo "  --auto-fix           Attempt to automatically fix non-sensitive issues"
    echo "  --non-interactive    Run in non-interactive mode, don't prompt for confirmations"
    echo "  -h, --help           Display this help message and exit"
    echo ""
    exit 1
}

# Function to parse command line arguments
parse_args() {
    # Eval-based approach compatible with older Bash versions
    local config_var="$1"
    local log_var="$2"
    local node_var="$3"
    local verbose_var="$4"
    local autofix_var="$5"
    local noninteractive_var="$6"
    shift 6
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--config)
                eval "$config_var=\"$2\""
                shift 2
                ;;
            -n|--node)
                local node_upper
                node_upper=$(echo "$2" | tr '[:lower:]' '[:upper:]') # Convert to uppercase
                eval "$node_var=\"$node_upper\""
                shift 2
                ;;
            -l|--log)
                eval "$log_var=\"$2\""
                shift 2
                ;;
            -v|--verbose)
                eval "$verbose_var=true"
                shift
                ;;
            --auto-fix)
                eval "$autofix_var=true"
                shift
                ;;
            --non-interactive)
                eval "$noninteractive_var=true"
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done
    
    # Get config file value
    local config_file
    eval "config_file=\$$config_var"
    
    # Validate config file
    if [[ ! -f "$config_file" ]]; then
        echo "Error: Config file not found: $config_file"
        exit 1
    fi
}

# Function to initialize the log file
init_log() {
    local log_file="$1"
    local node_type="$2"
    local config_file="$3"
    local auto_fix="$4"
    local non_interactive="$5"
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$log_file")"
    
    # Initialize log file with header
    {
        echo "===========================================" 
        echo "Dataiku DSS VM Diagnostic - $(date '+%Y-%m-%d %H:%M:%S')"
        echo "===========================================" 
        echo "Node Type: $node_type"
        echo "Config File: $config_file"
        echo "Auto-Fix: $auto_fix"
        echo "Non-Interactive: $non_interactive"
        echo "===========================================" 
    } > "$log_file"
    
    # Export log file path for modules
    export LOG_FILE="$log_file"
}

# Function to display banner
show_banner() {
    local node_type="$1"
    local log_file="$2"
    local auto_fix="$3"
    local non_interactive="$4"
    
    echo ""
    echo -e "${BRIGHT_BLUE}${BOLD}DATAIKU DSS VM DIAGNOSTIC TOOL${NC}"
    echo -e "${GRAY}──────────────────────────────────────────${NC}"
    echo ""
    echo -e "${BRIGHT_WHITE}${BOLD}Environment Configuration:${NC}"
    echo -e "${BRIGHT_WHITE}Node Type:${NC}      ${BLUE}${BOLD}$node_type${NC}"
    echo -e "${BRIGHT_WHITE}Run Time:${NC}       ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${BRIGHT_WHITE}Log Path:${NC}       ${GRAY}$log_file${NC}"
    
    # Auto-fix status with colorful indicator
    if [[ "$auto_fix" == true ]]; then
        echo -e "${BRIGHT_WHITE}Auto-Fix:${NC}       ${GREEN}${BOLD}Enabled${NC} ${GREEN}(Will attempt to fix non-sensitive issues)${NC}"
    else
        echo -e "${BRIGHT_WHITE}Auto-Fix:${NC}       ${YELLOW}Disabled${NC}"
    fi
    
    # Interactive mode status
    if [[ "$non_interactive" == true ]]; then
        echo -e "${BRIGHT_WHITE}Mode:${NC}           ${BLUE}Non-Interactive${NC} ${GRAY}(No confirmations will be requested)${NC}"
    else
        echo -e "${BRIGHT_WHITE}Mode:${NC}           ${BLUE}Interactive${NC}"
    fi
    echo -e "${GRAY}──────────────────────────────────────────${NC}"
    echo ""
}

# Function to validate node type
validate_node_type() {
    local node_type="$1"
    
    # Validate node type; allowed values are DESIGN, AUTOMATION, API, GOVERN, DEPLOYER
    case "$node_type" in
        DESIGN|AUTOMATION|API|GOVERN|DEPLOYER) 
            return 0
            ;;
        *) 
            echo "Error: Invalid node type: $node_type. Must be one of: DESIGN, AUTOMATION, API, GOVERN, DEPLOYER" >&2
            return 1
            ;;
    esac
} 