# 🌲 Btrfs Root Hunter & Integrity Guard

**Advanced filesystem forensics, subvolume management, and integrity monitoring for Btrfs.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: Linux](https://img.shields.io/badge/Platform-Linux-lightgrey.svg)](https://www.linux.org/)

---

## 🔍 Overview

**Btrfs Root Hunter** is a specialized tool designed for systems engineers, forensic analysts, and security professionals working with the Btrfs filesystem. It provides a robust, interactive interface to discover, monitor, and restore Btrfs subvolumes across any block device.

As a core component of the **[CDS Host Guardian](https://github.com/M0NDsuChTiG/cds-host-guardian)** ecosystem, it serves as the first line of defense for host filesystem integrity.

### Why Btrfs Root Hunter?
In a Zero-Trust environment, you cannot trust the host OS if the underlying filesystem is compromised. This tool ensures that:
- **Stealth subvolumes** are detected.
- **Rootfs integrity** is verified through checksum-aware subvolume scanning.
- **Rapid recovery** paths are available via automated snapshot mounting.

---

## ✨ Key Features

- **🛡️ Automated Discovery:** Scans all block devices (`/dev/sd*`, `/dev/nvme*`) using `lsblk` and `blkid` to reliably identify Btrfs structures.
- **🧩 Interactive Subvolume Manager:** A clean, menu-driven interface for mounting, unmounting, and managing snapshots.
- **📸 Snapshot Forensics:** Instantly create snapshots of any subvolume for backup or post-compromise analysis.
- **🧹 Atomic Cleanup:** Guaranteed removal of temporary mount points even if the script is interrupted.
- **⚙️ Integrated Security:** Seamlessly works with `cds-authz-system` to provide full-stack host protection.

---

## 🛠️ Installation & Usage

### Prerequisites
- `btrfs-progs`
- `util-linux` (`lsblk`, `blkid`, `mount`)

### Quick Start
1.  **Clone the repository:**
    ```bash
    git clone https://github.com/M0NDsuChTiG/btrfs-root-hunter.git
    cd btrfs-root-hunter
    ```
2.  **Set permissions:**
    ```bash
    chmod +x btrfs-root-hunter.sh
    ```
3.  **Run with root privileges:**
    ```bash
    sudo ./btrfs-root-hunter.sh
    ```

---

## 🚀 Advanced Capabilities

### Forensic Mode
Use Btrfs Root Hunter to identify unauthorized subvolumes that may be hiding persistent malware or rootkits outside the standard directory tree.

### Recovery Workflows
If your main rootfs is damaged, use the hunter to find and mount recent snapshots to restore system functionality in minutes.

---

## 📄 License

Distributed under the **MIT License**. See `LICENSE` for more information.

---
*Part of the [CDS Host Guardian](https://github.com/M0NDsuChTiG/cds-host-guardian) security suite.*
