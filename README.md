# ADS-B Automated Installer

An automated, Bash-based installer and configurator for the [SDR-Enthusiasts](https://github.com/sdr-enthusiasts) ADS-B Docker stack.

## Overview

This tool simplifies the deployment of a professional-grade ADS-B ground station. It handles hardware probing (RTL-SDR), OS configuration (kernel module blacklisting), dependency management, and generates a modular, healthy Docker Compose environment.

## Features

- **Interactive Wizard**: Step-by-step configuration of coordinates, feeders, and aggregators.
- **Headless Mode**: Supports fully automated deployments via environment variables and the `--yes` flag.
- **Modular Design**: Assembles `docker-compose.yml` from verified templates based on your selected feeders.
- **Strict Mode Production-Grade**: Written with defensive Bash patterns (`set -euo pipefail`) and comprehensive error trapping.
- **Security-First**: Automatic credential masking in logs and secure permission handling for configuration files.

## Prerequisites

- **OS**: Debian-based (Debian, Ubuntu, Raspberry Pi OS).
- **Hardware**: RTL-SDR USB Dongle.
- **Privileges**: Sudo/Root access (for package installation and hardware config).

## Quick Start

1. **Clone the repository**:
   ```bash
   git clone https://github.com/g0Idfinger/adsb.git
   cd adsb
   ```

2. **Run the installer**:
   ```bash
   chmod +x adsb-installer.sh
   ./adsb-installer.sh
   ```

## Repository Structure

- `adsb-installer.sh`: Main entry point and orchestrator.
- `lib/`: Core logic modules (OS config, Docker logic, state management, etc.).
- `templates/`: Docker Compose YAML snippets for baseline services and feeders.

## Contributing

This project follows a strict [Engineering Standards](docs/plans/ENGINEERING-STANDARDS.md) and uses Test-Driven Development.

## License

MIT (See [LICENSE](LICENSE) if provided, or assume MIT for this project)
