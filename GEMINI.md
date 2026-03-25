# Btrfs Root Hunter & Rescuer: Gemini Mandates

This file contains project-specific instructions for Gemini CLI when working on `btrfs-root-hunter`.

## Project Context
- **Tool Type:** Btrfs forensic and recovery tool.
- **Primary Language:** Bash 4.0+.
- **Dependencies:** `btrfs-progs` (specifically `btrfs` and `btrfs-find-root`).
- **Core Script:** `btrfs_magic.sh`.

## Safety Mandates
- **CRITICAL:** Always prioritize `read-only` operations on source block devices.
- **CRITICAL:** Never suggest or perform recovery/extraction to the same physical disk as the source.
- **CRITICAL:** Use `sudo` or root privileges only when absolutely necessary for raw disk access or specific `btrfs` commands.
- **Dry Runs:** Always suggest or implement "Scanner Mode" (dry run) before executing full recovery.

## Development Rules
- **Bash Shell:** Use idiomatic Bash 4.0+ features.
- **Error Handling:** Ensure all `btrfs` commands are checked for exit codes.
- **Documentation:** Keep the README updated with any new features or modes.
- **Licensing:** All new code must comply with the MIT License as stated in `LICENSE`.

## User Interaction
- Always warn about the risks of working with corrupted Btrfs structures.
- Confirm target directory existence and safety before suggesting extraction commands.
