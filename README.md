# Dataiku DSS VM Diagnostic Automation

This repository contains shell scripts for automating diagnostics on VMs before installing Dataiku DSS.

## Overview

The diagnostic tool performs various checks to ensure the VM meets the requirements for Dataiku DSS installation:

- OS type/version, locale, and kernel compatibility
- Hardware resources (CPU, memory, disk space)
- Filesystem types, ulimits, and system settings
- Software dependencies (Java, Python, etc.)
- Network connectivity and port configuration

## Directory Structure

```
dss-installer/
├── run_diagnostic.sh   # Main entry point script
├── modules/            # Individual modules for different checks
│   ├── check_os.sh     # OS verification module
│   └── ... (more modules to come)
└── config.ini          # Configuration file with thresholds and requirements
```

## Usage

1. Clone this repository to your VM
2. Review and update the `config.ini` file if needed
3. Make the scripts executable: `chmod +x run_diagnostic.sh modules/*.sh`
4. Run the diagnostic: `./run_diagnostic.sh`

### Command Line Options

```
Usage: ./run_diagnostic.sh [OPTIONS]
Run diagnostic checks for Dataiku DSS installation.

Options:
  -c, --config FILE    Path to configuration file (default: config.ini)
  -n, --node TYPE      Node type: DESIGN, AUTO (default: DESIGN)
  -l, --log FILE       Path to log file (default: diagnostics.log)
  -v, --verbose        Enable verbose output
  -h, --help           Display this help message and exit
```

## Configuration

The `config.ini` file contains thresholds and requirements for different node types:

- `[DEFAULT]` section contains common settings
- `[DESIGN]` and `[AUTO]` sections contain node-specific settings

You can modify parameters according to your specific requirements.

## Output

The diagnostic tool produces:

1. Real-time console output with clear PASS/FAIL for each check
2. A detailed log file (`diagnostics.log`) with timestamps
3. A summary at the end showing overall success or failure

## Development

### Adding New Modules

1. Create a new module file in the `modules/` directory
2. Implement the required check functions
3. Add a main function to run all the checks in the module
4. Update `run_diagnostic.sh` to source and execute the new module

## License

[MIT License](LICENSE) 