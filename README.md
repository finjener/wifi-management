# WiFi Manager

A comprehensive Bash CLI tool and Rust GUI application for synchronizing WiFi networks between Android devices and Linux (NetworkManager).

## Overview

WiFi Manager provides two interfaces:
- **CLI** (`wifi-manager.sh`) - A feature-rich Bash script for all WiFi management operations
- **GUI** (`wifi-manager-gui/`) - A native desktop application built with Rust and Iced framework

## Features

### Core Functionality
- **Import from Android** – Parse `WifiConfigStore.xml` and create `.nmconnection` files
- **ADB Integration** – Pull/push WiFi config via USB (requires root on device)
- **System Sync** – Install networks to system or backup existing ones
- **Report Generation** – Markdown report with all saved networks
- **Bidirectional Sync** – Keep report and local files in sync

### GUI Features
- Dark theme interface with status bar
- Network list with search and password visibility toggle
- Add new networks via dialog
- Terminal output panel showing command results
- Execute all CLI commands via toolbar buttons

## Requirements

### CLI
- `bash`, `grep`, `sed`, `awk`, `md5sum`, `uuidgen`
- `nmcli` (NetworkManager)
- `adb` (optional, for Android device operations)

### GUI
- Rust toolchain (1.70+)
- Linux with X11/Wayland

## Installation

```bash
git clone <repo-url>
cd wifi-management
chmod +x wifi-manager.sh
```

### Building the GUI

```bash
cd wifi-manager-gui
cargo build --release
```

The binary will be available at `target/release/wifi-manager-gui`.

## Usage

### CLI Commands

```bash
# Import from local XML file (place WifiConfigStore.xml in data/)
./wifi-manager.sh import-android

# Pull config from Android device via ADB (requires root)
./wifi-manager.sh pull-android

# Push config to Android device (WARNING: overwrites device config)
./wifi-manager.sh push-android

# Install networks to system (requires sudo)
sudo ./wifi-manager.sh install

# Backup system networks to local
sudo ./wifi-manager.sh backup

# Sync report and local connection files
./wifi-manager.sh sync-local

# Preview changes without executing
./wifi-manager.sh import-android --dry-run
./wifi-manager.sh --help
```

### GUI Application

```bash
# Run from project root
cd wifi-manager-gui
cargo run --release

# Or run the built binary
./target/release/wifi-manager-gui
```

**Toolbar Actions:**
| Button | Command | Description |
|--------|---------|-------------|
| Import XML | `import-android` | Import networks from Android XML |
| Pull ADB | `pull-android` | Pull XML from device via ADB |
| Push ADB | `push-android` | Push XML to device via ADB |
| Install | `install` | Install networks to system (sudo) |
| Backup | `backup` | Backup system networks (sudo) |
| Sync Report-Local | `sync-local` | Sync report and local files |

## Project Structure

```
wifi-management/
├── wifi-manager.sh           # Main CLI tool (Bash)
├── data/
│   ├── WifiConfigStore.xml     # Android WiFi config (input)
│   ├── network_connections/    # Generated .nmconnection files
│   ├── networks_report.md      # Markdown report
│   └── examples/               # Sample XML files
└── wifi-manager-gui/           # Rust GUI application
    ├── Cargo.toml
    └── src/
        ├── main.rs             # Application entry point
        ├── backend/            # Script execution & file parsing
        ├── models/             # Data structures
        └── ui/                 # UI components (toolbar, dialogs, etc.)
```

## How It Works

1. **Android Export**: Android stores WiFi credentials in `WifiConfigStore.xml`
2. **Import**: The tool parses XML and creates NetworkManager-compatible `.nmconnection` files
3. **System Install**: Connection files are copied to `/etc/NetworkManager/system-connections/`
4. **Report**: A markdown report is generated with all network details
5. **Bidirectional Sync**: Changes in report or files are synchronized

## Security Notice

⚠️ **Warning**: Network connection files contain plaintext passwords.
- Keep the `data/` directory secure
- Do not commit `network_connections/` or `networks_report.md` to public repositories
- The `.nmconnection` files in system directories require root access

## Development

### Project History
This project was refactored from Python to pure Bash for portability and reduced dependencies. The GUI was added later using Rust and the Iced framework for a native desktop experience.

### Tech Stack
- **CLI**: Pure Bash with standard Unix utilities
- **GUI**: Rust + Iced 0.13 + Tokio (async runtime)
- **Parsing**: awk/sed for XML in CLI, quick-xml for Rust

## License

MIT License - Copyright (c) 2025 finjener
