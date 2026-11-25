#!/bin/bash
# ==============================================================================
#  GO CAI DAT ZEBRA PRINT BRIDGE TREN RASPBERRY PI OS
# ==============================================================================

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}================================================================${NC}"
echo -e "${YELLOW}           GO CAI DAT ZEBRA PRINT BRIDGE (PORT 8021)            ${NC}"
echo -e "${CYAN}================================================================${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
else
    SUDO=""
fi

echo -e "${CYAN}[1/3] Dung va go bo dich vu systemd...${NC}"
$SUDO systemctl stop zebra-bridge.service 2>/dev/null
$SUDO systemctl disable zebra-bridge.service 2>/dev/null

SERVICE_FILE="/etc/systemd/system/zebra-bridge.service"
if [ -f "$SERVICE_FILE" ]; then
    $SUDO rm -f "$SERVICE_FILE"
    $SUDO systemctl daemon-reload
    echo -e "${GREEN}    -> Da xoa file service: $SERVICE_FILE${NC}"
fi

echo -e "${CYAN}[2/3] Kiem tra va giai phong cong 8021...${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/free_port.sh" ]; then
    $SUDO bash "$SCRIPT_DIR/free_port.sh"
else
    PIDS=$(pgrep -f "print_bridge.py")
    if [ -n "$PIDS" ]; then
        echo -e "${YELLOW}    -> Dang dong cac tien trinh PID: $PIDS${NC}"
        $SUDO kill -9 $PIDS 2>/dev/null
        echo -e "${GREEN}    -> Da dong cac tien trinh thanh cong.${NC}"
    else
        echo -e "${GREEN}    -> Khong con tien trinh print_bridge nao chay.${NC}"
    fi

    # Dam bao dong port 8021 neu co tien trinh ngam khac chiem giu
    if command -v fuser &>/dev/null; then
        $SUDO fuser -k 8021/tcp 2>/dev/null
    fi
fi

echo -e "${CYAN}[3/3] Xoa udev rule khoi he thong...${NC}"
UDEV_RULE_FILE="/etc/udev/rules.d/99-zebra-printer.rules"
if [ -f "$UDEV_RULE_FILE" ]; then
    $SUDO rm -f "$UDEV_RULE_FILE"
    $SUDO udevadm control --reload-rules 2>/dev/null
    echo -e "${GREEN}    -> Da xoa udev rule: $UDEV_RULE_FILE${NC}"
fi

echo ""
echo -e "${CYAN}================================================================${NC}"
echo -e "${GREEN}  DA GO CAI DAT HOAN TAT. Cong 8021 da duoc giai phong hoan toan.${NC}"
echo -e "${CYAN}================================================================${NC}"
