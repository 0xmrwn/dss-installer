# Dataiku DSS VM Diagnostic Automation Tool

This tool provides a comprehensive set of diagnostic checks to verify that a virtual machine (VM) meets the requirements for installing Dataiku DSS.

## Overview

The Dataiku DSS VM Diagnostic Automation Tool is designed to verify system specifications, configurations, and prerequisites according to infrastructure requirements. It performs the following checks:

- **OS Verification**: Checks OS type/version, kernel version, and locale settings
- **Hardware Validation**: Verifies CPU count, memory size, and disk space requirements
- **System Settings**: Ensures that ulimits, time synchronization, and other system settings are properly configured
- **Software Dependencies**: Confirms the presence of required software (Java, Python, essential packages)
- **Network Connectivity**: Validates hostname resolution, network connectivity, and port availability

## Installation

1. Clone this repository or copy the files to your target VM
2. Ensure the scripts have executable permissions:
   ```bash
   chmod +x run_diagnostic.sh
   chmod +x modules/*.sh
   chmod +x modules/utils/*.sh
   ```

## Configuration

The tool uses a configuration file (`config.ini`) to define expected values and thresholds for various checks. Modify this file to match your specific requirements.

Example configuration:

```ini
[DEFAULT]
# Common settings for all node types
min_root_disk_gb = 50
min_data_disk_gb = 100
filesystem = xfs,ext4
ulimit_files = 65536
ulimit_processes = 65536
locale_required = en_US.utf8
allowed_os_distros = RHEL,CentOS,AlmaLinux,Rocky Linux,Ubuntu
allowed_os_versions = 8,9,20.04,22.04
min_kernel_version = 4.18
java_versions = OpenJDK 11,OpenJDK 17
python_versions = 3.6,3.7,3.9,3.10
required_packages = git,nginx,zip,unzip,acl
required_repos = EPEL

[DESIGN]
node_type = Design
vcpus = 16
memory_gb = 128
data_disk_mount = /mnt/dss_data
port_range = 10000-10010

[AUTO]
node_type = Automation
vcpus = 8
memory_gb = 64
data_disk_mount = /mnt/dss_data
port_range = 11000-11010
```

## Usage

To run the diagnostic tool with default settings:

```bash
./run_diagnostic.sh
```

## Command-line Options

The tool supports the following command-line options:

- `-c, --config FILE`: Path to configuration file (default: `config.ini`)
- `-n, --node TYPE`: Node type: DESIGN, AUTO (default: DESIGN)
- `-l, --log FILE`: Path to log file (default: `diagnostics.log`)
- `-v, --verbose`: Enable verbose output
- `--auto-fix`: Attempt to automatically fix non-sensitive issues
- `--non-interactive`: Run in non-interactive mode without prompting for confirmations
- `-h, --help`: Display help message and exit

### Examples

Run diagnostics for a design node using the default configuration:
```bash
./run_diagnostic.sh
```

Run diagnostics for an automation node with verbose output:
```bash
./run_diagnostic.sh -n AUTO -v
```

Run diagnostics with a custom configuration file:
```bash
./run_diagnostic.sh -c custom_config.ini
```

Run diagnostics with automatic fixes in non-interactive mode:
```bash
./run_diagnostic.sh --auto-fix --non-interactive
```

## Auto-Fix Feature

The tool includes an auto-fix feature that can automatically remediate common issues:

- **Locale Settings**: Installs and configures the required locale
- **Missing Packages**: Installs required packages using the appropriate package manager
- **Time Synchronization**: Installs and configures time synchronization services (chronyd/chrony/ntpd)
- **Repository Configuration**: Configures required repositories (e.g., EPEL)
- **Ulimit Settings**: Updates system limits for open files and processes

When the auto-fix feature makes changes that may require a system reboot to take full effect (like ulimit or locale changes), a notification will be displayed in the summary.

To enable the auto-fix feature, use the `--auto-fix` flag:

```bash
./run_diagnostic.sh --auto-fix
```

For automated deployments, you can combine auto-fix with non-interactive mode:

```bash
./run_diagnostic.sh --auto-fix --non-interactive
```

### Auto-Fix Safety Features

The auto-fix feature includes several safety mechanisms:

1. **Sudo Permission Check**: Verifies that the user has sudo permissions before attempting fixes
2. **User Confirmation**: Prompts for confirmation before making system changes (unless in non-interactive mode)
3. **Reboot Notification**: Alerts when changes may require a system reboot
4. **Verification**: Re-runs checks after fixes to confirm they were successful

### Limitations of Auto-Fix

The auto-fix feature is limited to non-sensitive issues. It **cannot** automatically fix:

- Hardware-related issues (CPU, memory, disk space)
- Network connectivity problems
- Port conflicts
- Core software dependencies like Java versions

These issues require manual intervention.

> **Note**: The auto-fix feature requires sudo privileges to make system-level changes. Make sure the user running the script has appropriate permissions.

## Progress Tracking

The diagnostic tool includes progress tracking that shows which check is currently running and how many checks remain. This makes it easier to follow the diagnostic process and understand where you are in the overall workflow.

## Project Structure

```
dss-installer/
├── modules/
│   ├── auto_fix.sh           # Auto-fix functions for common issues
│   ├── check_hardware.sh     # Hardware verification checks
│   ├── check_limits.sh       # System settings and limits checks
│   ├── check_network.sh      # Network and connectivity checks
│   ├── check_os.sh           # OS verification checks
│   ├── check_software.sh     # Software and dependency checks
│   └── utils/
│       └── common.sh         # Common utility functions
├── config.ini                # Configuration file
├── diagnostics.log           # Log file (created on run)
├── README.md                 # This documentation
└── run_diagnostic.sh         # Main script
```

## Logs

The tool creates a detailed log file (`diagnostics.log` by default) with information about each check performed, including pass/fail status and recommendations for fixing issues. The log file is useful for troubleshooting and provides a record of the diagnostic run.

## Requirements

- Bash shell
- Standard POSIX tools (grep, awk, sed, etc.)
- Sudo privileges (for auto-fix feature)

## Contributing

Contributions to this project are welcome. Please ensure that all scripts are written in portable bash, adhere to POSIX standards, and are tested on the supported Linux distributions. 