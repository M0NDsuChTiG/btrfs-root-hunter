#!/bin/bash

# =====================================================================
# 🛡️ Btrfs Magic Rescuer (Forensic Edition v3.1)
# =====================================================================
# Integrated with CDS Host Guardian ecosystem.
# Features: 
#   - Generation Discovery & Selection
#   - Non-destructive Forensic Scanning
#   - Aggressive Metadata Recovery
#   - Detailed Audit Reporting
# =====================================================================

set -e # Exit on error (except for piped commands)

# Colors for professional output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_header() { echo -e "\n${CYAN}>>> $1${NC}"; }
log_info()   { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success(){ echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()  { echo -e "${RED}[ERROR]${NC} $1"; }

# Check for root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (sudo)."
   exit 1
fi

DEVICE="$1"
DEST_DIR="$2"

if [[ -z "$DEVICE" ]]; then
    echo -e "${CYAN}------------------------------------------------------------${NC}"
    echo -e "  ${GREEN}Btrfs Magic Rescuer${NC} - Part of CDS Host Guardian"
    echo -e "${CYAN}------------------------------------------------------------${NC}"
    echo -e "${BLUE}Usage:${NC} sudo $0 <DEVICE> [DEST_DIR]"
    echo -e "Example: sudo $0 /dev/sdb1 /mnt/recovery"
    echo -e "\n${YELLOW}Note:${NC} If DEST_DIR is omitted, script runs in ${BLUE}Preview Mode${NC}."
    exit 1
fi

# Verify dependencies
BTRFS_BIN=$(which btrfs)
FIND_ROOT_BIN=$(which btrfs-find-root)

if [[ -z "$BTRFS_BIN" || -z "$FIND_ROOT_BIN" ]]; then
    log_error "btrfs-progs (btrfs and btrfs-find-root) not found. Please install them."
    exit 1
fi

# --- Helper: Check Free Space ---
check_space() {
    local target="$1"
    local needed_kb=2097152 # 2GB safety margin for recovery
    local available_kb=$(df -Pk "$target" | awk 'NR==2 {print $4}')
    
    if [[ "$available_kb" -lt "$needed_kb" ]]; then
        log_warn "Low disk space on $target ($((available_kb/1024)) MB free)."
        read -p "Continue anyway? (y/n): " confirm
        [[ "$confirm" != "y" ]] && exit 1
    fi
}

# --- Step 1: Device Audit ---
log_header "Step 1: Auditing Block Device $DEVICE"
if [[ ! -b "$DEVICE" ]]; then
    log_error "$DEVICE is not a valid block device."
    exit 1
fi

SUPER_DATA=$($BTRFS_BIN inspect-internal dump-super "$DEVICE" 2>/dev/null)

if [[ -z "$SUPER_DATA" ]]; then
    log_error "Failed to read Btrfs superblock. Device might be heavily corrupted or not Btrfs."
    exit 1
fi

FSID=$(echo "$SUPER_DATA" | awk '$1 == "fsid" {print $2}')
LABEL=$(echo "$SUPER_DATA" | awk '$1 == "label" {print $2}')
[[ -z "$LABEL" || "$LABEL" == "<none>" ]] && LABEL="Untitled"

log_info "Label: ${GREEN}$LABEL${NC}"
log_info "FSID:  ${GREEN}$FSID${NC}"

# Incompat flags detection
INCOMPAT=$(echo "$SUPER_DATA" | grep "incompat_flags" | sed 's/.*(\(.*\))/\1/')
log_info "Hardware Features: ${BLUE}$INCOMPAT${NC}"

# --- Step 2: Generation Discovery ---
log_header "Step 2: Searching for Forensic Recovery Points"
ROOT_LIST=$(mktemp)

# Current root from super
CUR_ROOT=$(echo "$SUPER_DATA" | awk '$1 == "root" {print $2}')
CUR_GEN=$(echo "$SUPER_DATA" | awk '$1 == "generation" {print $2}')
[[ -n "$CUR_ROOT" ]] && echo "$CUR_ROOT $CUR_GEN [CURRENT_ACTIVE]" >> "$ROOT_LIST"

log_info "Scanning for historical tree roots (Aggressive Scan)..."
$FIND_ROOT_BIN "$DEVICE" 2>/dev/null | grep "Well block" | awk '{print $3, $5}' | sed 's/(gen://' | sed 's/)$//' >> "$ROOT_LIST"

# Sort by Generation (Newest first) and deduplicate
sort -rn -k2 "$ROOT_LIST" | awk '!seen[$1]++' > "${ROOT_LIST}.tmp" && mv "${ROOT_LIST}.tmp" "$ROOT_LIST"

ROOT_COUNT=$(grep -c "." "$ROOT_LIST")
if [[ "$ROOT_COUNT" -eq 0 ]]; then
    log_error "No valid tree roots found. Recovery impossible via this method."
    rm "$ROOT_LIST"
    exit 1
fi

# --- Step 3: Selection ---
log_success "Found $ROOT_COUNT valid generations."
echo -e "\nID\tRoot Address\tGen\t\tStatus / Preview"
echo -e "${CYAN}----------------------------------------------------------------------${NC}"

i=1
declare -A ADDR_MAP
declare -A GEN_MAP

while read -r addr gen extra; do
    # Quick metadata preview
    PREVIEW=$($BTRFS_BIN restore -l -t "$addr" "$DEVICE" 2>/dev/null | head -n 3 | tr '\n' ' ' | cut -c1-50)
    if [[ -z "$PREVIEW" ]]; then
        PREVIEW_STAT="${RED}[CORRUPT/EMPTY]${NC}"
    else
        PREVIEW_STAT="${GREEN}[READABLE]${NC} ${BLUE}$PREVIEW...${NC}"
    fi
    
    echo -e "$i)\t$addr\t$gen\t$PREVIEW_STAT $extra"
    ADDR_MAP[$i]=$addr
    GEN_MAP[$i]=$gen
    ((i++))
done < "$ROOT_LIST"

echo -e "\n${YELLOW}Select Recovery Point ID (or 'q' to quit):${NC} "
read -p "> " choice

if [[ "$choice" == "q" ]] || [[ -z "${ADDR_MAP[$choice]}" ]]; then
    log_info "Operation cancelled by user."
    rm "$ROOT_LIST"
    exit 0
fi

SELECTED_ADDR=${ADDR_MAP[$choice]}
SELECTED_GEN=${GEN_MAP[$choice]}

# --- Step 4: Execution Logic ---
if [[ -z "$DEST_DIR" ]]; then
    log_header "Preview Mode: Listing files for Gen $SELECTED_GEN"
    $BTRFS_BIN restore -l -t "$SELECTED_ADDR" "$DEVICE" | less
    rm "$ROOT_LIST"
    exit 0
fi

# Ensure safety: destination should not be on the same partition
if mount | grep -q "$DEVICE" && [[ "$DEST_DIR" == "$(mount | grep "$DEVICE" | awk '{print $3}')"* ]]; then
    log_error "Safety violation: Target directory is on the source device!"
    exit 1
fi

mkdir -p "$DEST_DIR"
check_space "$DEST_DIR"

REPORT_FILE="$DEST_DIR/recovery_audit_gen_${SELECTED_GEN}.log"
{
    echo "========================================="
    echo "🛡️ CDS BTRFS MAGIC RECOVERY AUDIT"
    echo "========================================="
    echo "Timestamp:   $(date)"
    echo "Device:      $DEVICE"
    echo "FSID:        $FSID"
    echo "Gen Target:  $SELECTED_GEN"
    echo "Root Addr:   $SELECTED_ADDR"
    echo "Target Path: $DEST_DIR"
    echo "========================================="
} > "$REPORT_FILE"

# --- Step 5: Aggressive Metadata Restore ---
log_header "Step 5: Executing Forensic Recovery to $DEST_DIR"
log_info "Flags enabled: Verbose, Ignore Errors, Overwrite, Symlink preservation."

# -i : ignore errors (critical for forensics)
# -o : overwrite
# -v : verbose
# -S : symlinks
# -t : tree address
$BTRFS_BIN restore -v -i -o -S -t "$SELECTED_ADDR" "$DEVICE" "$DEST_DIR" 2>&1 | tee -a "$REPORT_FILE"

log_success "Recovery completed for Generation $SELECTED_GEN."
log_info "Audit report saved to: ${CYAN}$REPORT_FILE${NC}"
log_warn "Please verify recovered files manually before use."

rm "$ROOT_LIST"
