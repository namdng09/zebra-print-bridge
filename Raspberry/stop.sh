#!/bin/bash
# ==============================================================================
#  DUNG NHANH ZEBRA PRINT BRIDGE
# ==============================================================================

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${CYAN}================================================================${NC}"
echo -e "${YELLOW}           DUNG TIEN TRINH ZEBRA PRINT BRIDGE (PORT 8021)       ${NC}"
echo -e "${CYAN}================================================================${NC}"

# Dung systemd service neu co
if systemctl is-active --quiet zebra-bridge.service 2>/dev/null; then
    sudo systemctl stop zebra-bridge.service
    echo -e "${GREEN}[OK] Da dung dich vu systemd zebra-bridge.${NC}"
fi

# Goi free_port.sh de giai phong triet de cong 8021 va tien trinh print_bridge.py
if [ -f "$SCRIPT_DIR/free_port.sh" ]; then
    bash "$SCRIPT_DIR/free_port.sh"
else
    PIDS=$(pgrep -f "print_bridge.py")
    if [ -n "$PIDS" ]; then
        sudo kill -9 $PIDS 2>/dev/null
        echo -e "${GREEN}[OK] Da dong cac tien trinh PID: $PIDS.${NC}"
    else
        echo -e "${YELLOW}[INFO] Khong co tien trinh nao dang chiem giu.${NC}"
    fi
fi

echo -e "${GREEN}Da giai phong xong cong 8021.${NC}"
