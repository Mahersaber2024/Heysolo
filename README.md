# HeySolo Manager

**English** | [فارسی](README.fa.md)

HeySolo Manager installs and manages MetaTrader 5 terminals on Debian and Ubuntu Linux servers through Wine and a lightweight desktop environment.

## Features

- Automated server preparation for Debian/Ubuntu
- MetaTrader 5 installation and terminal management
- Wine, VNC, desktop, wallpaper, and taskbar setup
- Start, stop, restart, remove, and recover terminals
- MQL5 asset synchronization for Experts, Include, Indicators, sets, and Templates
- Backup and restore support
- Diagnostics, logs, updates, and clean uninstall
- Support for multiple MT5 terminals on one server

## Minimum system requirements

For running **one MetaTrader 5 terminal** through Wine, the bare minimum is:

- Debian 11+/Ubuntu 22.04+ on x86_64
- 1 vCPU
- 1 GB RAM
- 2 GB swap recommended
- 20 GB free disk space
- Root access or a user with `sudo`
- Network access for package and installer downloads

These are practical minimums for one terminal. More CPU and RAM may be required for heavy Expert Advisors, multiple charts, backtesting, or a desktop/VNC session.

## Installation

Run the main installer as root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mahersaber2024/Heysolo/main/heysolo.sh)
```

After the first installation, open the management panel with:

```bash
sudo heysolo
```

The panel prepares the server, installs or adds MT5 terminals, configures the Linux desktop layer, and provides maintenance and uninstall options. Do not run the helper scripts directly unless you are performing advanced maintenance.

## Manual installation from a local checkout

```bash
git clone https://github.com/Mahersaber2024/HeysoloPublic.git
cd HeysoloPublic
sudo bash heysolo.sh
```

## Connecting with VNC

To see the MT5 desktop, install a VNC viewer on your own computer and connect to `SERVER_IP:5901` (or the port shown in the panel) with the VNC password you set during setup.

- VNC Viewer 7.15.1 (direct download): https://dl2.soft98.ir/soft/u-v/VNC.Connect.Viewer.7.15.1.rar?1791992033
- Official RealVNC download: https://www.realvnc.com/en/connect/download/viewer/

## Installation paths

```text
/opt/heysolo/scripts       Manager scripts
/opt/heysolo/bot           Runtime files and settings
/opt/heysolo/bot/MT5       MQL5 assets
/opt/heysolo/bot/Meta5     MT5 installers and local terminal files
/etc/heysolo-mt5           Terminal state and configuration
```

## Terminal management

Use the panel to prepare the server, install or add terminals, start and stop terminals, toggle desktop visibility, synchronize MQL5 files, run diagnostics, update scripts, and uninstall selected components.

MQL5 assets are preserved during routine updates and are not overwritten unless you explicitly request a forced synchronization. Review every installer prompt before allowing changes to a production server.

## Security

Never commit passwords, access tokens, private keys, certificates, customer data, or live server settings. Use a dedicated server user, restrict VNC and remote administration ports, keep the operating system updated, and review shell scripts before running them as root.

## License

This project is distributed under the **HeySolo Custom Source-Available License** in [`LICENSE`](LICENSE). You may install and use it for personal or internal purposes and fork it for development, but redistribution, resale, public hosting, and commercial use require written permission from the copyright holder.

The license is intentionally source-available, not an OSI-approved open-source license. MetaTrader 5, Wine, Linux distributions, and any third-party assets remain subject to their own licenses.
