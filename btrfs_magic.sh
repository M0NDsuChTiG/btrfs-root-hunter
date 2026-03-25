#!/bin/bash

# =====================================================================
# Btrfs Root Hunter & Rescuer (Professional Edition V3)
# =====================================================================
# Features: Interactive selection, Aggressive recovery, Space check,
#           Compression detection, Recovery logging.
# =====================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check for root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root (sudo).${NC}"
   exit 1
fi

DEVICE="$1"
DEST_DIR="$2"

if [[ -z "$DEVICE" ]]; then
    echo -e "${BLUE}Usage:${NC} sudo $0 <DEVICE> [DEST_DIR]"
    echo -e "Example: sudo $0 /dev/sdb1 /mnt/recovery"
    exit 1
fi

BTRFS_BIN=$(which btrfs)
FIND_ROOT_BIN=$(which btrfs-find-root)

if [[ -z "$BTRFS_BIN" || -z "$FIND_ROOT_BIN" ]]; then
    echo -e "${RED}Error: btrfs-progs (btrfs and btrfs-find-root) not found.${NC}"
    exit 1
fi

# --- Helper: Check Free Space ---
check_space() {
    local target="$1"
    local needed_kb=1048576 # Default 1GB safety margin if unknown
    local available_kb=$(df -Pk "$target" | awk 'NR==2 {print $4}')
    
    if [[ "$available_kb" -lt "$needed_kb" ]]; then
        echo -e "${RED}Warning: Low disk space on $target ($((available_kb/1024)) MB free).${NC}"
        read -p "Continue anyway? (y/n): " confirm
        [[ "$confirm" != "y" ]] && exit 1
    fi
}

# --- Step 1: Analyze Superblock ---
echo -e "${YELLOW}=== Step 1: Analyzing Superblock on $DEVICE ===${NC}"
SUPER_DATA=$($BTRFS_BIN inspect-internal dump-super "$DEVICE" 2>/dev/null)

if [[ -z "$SUPER_DATA" ]]; then
    echo -e "${RED}Failed to read superblock. Device might be heavily corrupted.${NC}"
else
    FSID=$(echo "$SUPER_DATA" | awk '$1 == "fsid" {print $2}')
    INCOMPAT=$(echo "$SUPER_DATA" | grep "incompat_flags" | sed 's/.*(\(.*\))/\1/')
    echo -e "FSID: ${BLUE}$FSID${NC}"
    echo -e "Features: ${BLUE}$INCOMPAT${NC}"
    
    # Check for compression
    if [[ "$INCOMPAT" == *"zstd"* ]]; then COMP="zstd"; 
    elif [[ "$INCOMPAT" == *"lzo"* ]]; then COMP="lzo"; 
    else COMP="none"; fi
    echo -e "Compression detected: ${GREEN}$COMP${NC}"
fi

# --- Step 2: Find Roots ---
echo -e "\n${YELLOW}=== Step 2: Searching for Root Generations ===${NC}"
ROOT_LIST=$(mktemp)

# Current root from super
CUR_ROOT=$(echo "$SUPER_DATA" | awk '$1 == "root" {print $2}')
CUR_GEN=$(echo "$SUPER_DATA" | awk '$1 == "generation" {print $2}')
[[ -n "$CUR_ROOT" ]] && echo "$CUR_ROOT $CUR_GEN [CURRENT]" >> "$ROOT_LIST"

# Historical roots
echo "Scanning for historical roots (this may take a moment)..."
$FIND_ROOT_BIN "$DEVICE" 2>/dev/null | grep "Well block" | awk '{print $3, $5}' | sed 's/(gen://' | sed 's/)$//' >> "$ROOT_LIST"

# Sort by Generation (Newest first) and deduplicate by Address
sort -rn -k2 "$ROOT_LIST" | awk '!seen[$1]++' > "${ROOT_LIST}.tmp" && mv "${ROOT_LIST}.tmp" "$ROOT_LIST"

ROOT_COUNT=$(grep -c "." "$ROOT_LIST")
if [[ "$ROOT_COUNT" -eq 0 ]]; then
    echo -e "${RED}No valid roots found.${NC}"
    rm "$ROOT_LIST"
    exit 1
fi

# --- Step 3: Interactive Selection ---
echo -e "${GREEN}Found $ROOT_COUNT potential recovery points:${NC}"
echo -e "ID\tAddress\t\tGen\tStatus/Preview"
echo "------------------------------------------------------------"

i=1
declare -A ADDR_MAP
declare -A GEN_MAP

while read -r addr gen extra; do
    # Quick preview (top level files)
    PREVIEW=$($BTRFS_BIN restore -l -t "$addr" "$DEVICE" 2>/dev/null | head -n 3 | tr '\n' ' ' | cut -c1-40)
    [[ -z "$PREVIEW" ]] && PREVIEW="${RED}[Empty/Corrupt]${NC}" || PREVIEW="${GREEN}[OK]${NC} $PREVIEW..."
    
    echo -e "$i)\t$addr\t$gen\t$PREVIEW $extra"
    ADDR_MAP[$i]=$addr
    GEN_MAP[$i]=$gen
    ((i++))
done < "$ROOT_LIST"

echo -e "\n${YELLOW}Choose an ID to recover (or 'q' to quit):${NC} "
read -p "> " choice

if [[ "$choice" == "q" ]] || [[ -z "${ADDR_MAP[$choice]}" ]]; then
    echo "Exiting."
    rm "$ROOT_LIST"
    exit 0
fi

SELECTED_ADDR=${ADDR_MAP[$choice]}
SELECTED_GEN=${GEN_MAP[$choice]}

# --- Step 4: Recovery Setup ---
if [[ -z "$DEST_DIR" ]]; then
    echo -e "\n${YELLOW}No destination directory provided. Entering Preview Mode (Dry Run).${NC}"
    echo "Showing file list for Gen $SELECTED_GEN..."
    $BTRFS_BIN restore -l -t "$SELECTED_ADDR" "$DEVICE" | less
    rm "$ROOT_LIST"
    exit 0
fi

mkdir -p "$DEST_DIR"
check_space "$DEST_DIR"

REPORT_FILE="$DEST_DIR/recovery_report_gen_${SELECTED_GEN}.txt"
{
    echo "Btrfs Recovery Report"
    echo "Date: $(date)"
    echo "Source: $DEVICE"
    echo "Selected Gen: $SELECTED_GEN"
    echo "Selected Addr: $SELECTED_ADDR"
    echo "Compression: $COMP"
    echo "-----------------------------------"
} > "$REPORT_FILE"

# --- Step 5: The Actual Recovery ---
echo -e "\n${GREEN}Starting Aggressive Recovery...${NC}"
echo -e "Target: $DEST_DIR"
echo -e "Flags: ${BLUE}-v (verbose), -i (ignore errors), -o (overwrite), -S (symlinks)${NC}"

# Running restore
# -i : ignore errors
# -o : overwrite existing
# -v : verbose
# -S : get symlinks
# -t : tree location (the bytenr we found)
$BTRFS_BIN restore -v -i -o -S -t "$SELECTED_ADDR" "$DEVICE" "$DEST_DIR" 2>&1 | tee -a "$REPORT_FILE"

echo -e "\n${YELLOW}=== Recovery Finished ===${NC}"
echo -e "Report saved to: ${BLUE}$REPORT_FILE${NC}"
echo -e "Check the output above for any missed files."

rm "$ROOT_LIST"
