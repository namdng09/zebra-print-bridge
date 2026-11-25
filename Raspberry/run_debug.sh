#!/bin/bash
# ==============================================================================
#  CHAY ZEBRA PRINT BRIDGE TRUC TIEP TREN CONSOLE (CHE DO DEBUG / TEST)
# ==============================================================================

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_PY="$SCRIPT_DIR/print_bridge.py"

echo -e "${CYAN}================================================================${NC}"
echo -e "${YELLOW}       ZEBRA USB PRINT BRIDGE - CHE DO DEBUG / KIEM TRA         ${NC}"
echo -e "${CYAN}================================================================${NC}"
echo ""

# Neu dich vu systemd dang chay, tam dung de tranh xung dot cong 8021
WAS_RUNNING=false
if systemctl is-active --quiet zebra-bridge.service 2>/dev/null; then
    echo -e "${YELLOW}[INFO] Dich vu systemd 'zebra-bridge' dang chay. Tam dung de debug...${NC}"
    sudo systemctl stop zebra-bridge.service
    WAS_RUNNING=true
fi

# Dong bat ky tien trinh chay ngam cu nao tren port 8021 neu co
if [ -f "$SCRIPT_DIR/free_port.sh" ]; then
    bash "$SCRIPT_DIR/free_port.sh"
else
    EXISTING_PIDS=$(pgrep -f "print_bridge.py")
    if [ -n "$EXISTING_PIDS" ]; then
        echo -e "${YELLOW}[INFO] Dong tien trinh cu PID: $EXISTING_PIDS${NC}"
        kill -9 $EXISTING_PIDS 2>/dev/null
    fi
fi

echo -e "${GREEN}[OK] Khoi dong bridge o che do console live log...${NC}"
echo -e "${CYAN}----------------------------------------------------------------${NC}"

# Chay Python truc tiep
python3 "$TARGET_PY"

# Khi nguoi dung bam Ctrl+C dung chuong trinh
echo ""
echo -e "${CYAN}----------------------------------------------------------------${NC}"
if [ "$WAS_RUNNING" = true ]; then
    echo -e "${YELLOW}[?] Khoi phuc lai dich vu systemd chay ngam? (Y/n): ${NC}"
    read -r ans
    if [[ "$ans" =~ ^[Nn]$ ]]; then
        echo -e "${GREEN}Dich vu systemd van dang dung.${NC}"
    else
        sudo systemctl start zebra-bridge.service
        echo -e "${GREEN}Da bat lai dich vu zebra-bridge chay ngam.${NC}"
    fi
fi
