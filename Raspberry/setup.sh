#!/bin/bash
# ==============================================================================
#  THIET LAP ZEBRA USB & NETWORK PRINT BRIDGE (PORT 8021) CHO RASPBERRY PI OS
# ==============================================================================

# Mau sac hien thi
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${CYAN}================================================================${NC}"
echo -e "${YELLOW}       THIET LAP ZEBRA PRINT BRIDGE CHO RASPBERRY PI OS (PORT 8021)       ${NC}"
echo -e "${CYAN}================================================================${NC}"
echo ""

# Kiem tra quyen sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}[CHU Y] Dang chay voi quyen user thuong. He thong se hoi mat khau sudo de cai dat.${NC}"
    SUDO="sudo"
else
    SUDO=""
fi

# Xac dinh thu muc chua script va user chay
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_PY="$SCRIPT_DIR/print_bridge.py"

# Xac dinh user thuc su (neu chay bang sudo thi lay SUDO_USER)
REAL_USER="${SUDO_USER:-$USER}"
if [ "$REAL_USER" = "root" ]; then
    REAL_USER="pi"
    # Neu khong co user pi thi lay user dau tien co UID >= 1000
    if ! id "$REAL_USER" &>/dev/null; then
        REAL_USER="$(id -un 1000 2>/dev/null || echo 'root')"
    fi
fi

# Kiem tra Python 3
if ! command -v python3 &>/dev/null; then
    echo -e "${RED}[LOI] He thong chua cai dat python3. Dang tien hanh cai dat...${NC}"
    $SUDO apt-get update && $SUDO apt-get install -y python3
fi

PYTHON_BIN="$(which python3 2>/dev/null || echo '/usr/bin/python3')"
BASH_BIN="$(which bash 2>/dev/null || echo '/bin/bash')"

# Tam dung va reset dich vu cu neu dang chay hoac bi lap restart loop
if systemctl is-active --quiet zebra-bridge.service 2>/dev/null || systemctl is-failed --quiet zebra-bridge.service 2>/dev/null; then
    echo -e "${YELLOW}[CHU Y] Dang tam dung va reset dich vu zebra-bridge cu...${NC}"
    $SUDO systemctl stop zebra-bridge.service 2>/dev/null
    $SUDO systemctl reset-failed zebra-bridge.service 2>/dev/null
fi

# Cap quyen thuc thi cho cac script trong thu muc
chmod +x "$SCRIPT_DIR"/*.sh "$TARGET_PY" 2>/dev/null

echo -e "${CYAN}[1/4] Cau hinh phan quyen thiet bi USB (udev rules)...${NC}"
# Tao file udev rule de cap quyen doc/ghi vao /dev/usb/lp* cho moi user khong can root
UDEV_RULE_FILE="/etc/udev/rules.d/99-zebra-printer.rules"
$SUDO bash -c "cat << 'EOF' > $UDEV_RULE_FILE
# Quyen truy cap cong in USB khong can root
SUBSYSTEM==\"usbmisc\", KERNEL==\"lp*\", MODE=\"0666\", GROUP=\"lp\"
SUBSYSTEM==\"usb\", ATTRS{idVendor}==\"0a5f\", MODE=\"0666\", GROUP=\"lp\"
EOF"

$SUDO udevadm control --reload-rules 2>/dev/null
$SUDO udevadm trigger 2>/dev/null

# Them user vao group lp va dialout
$SUDO usermod -a -G lp,dialout "$REAL_USER" 2>/dev/null
echo -e "${GREEN}    -> Da cau hinh udev rules va them user '$REAL_USER' vao group lp.${NC}"

echo -e "${CYAN}[2/4] Tao dich vu tu khoi dong systemd (zebra-bridge.service)...${NC}"
SERVICE_FILE="/etc/systemd/system/zebra-bridge.service"

$SUDO bash -c "cat << EOF > $SERVICE_FILE
[Unit]
Description=Zebra USB & Network Print Bridge (Port 8021)
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=$REAL_USER
WorkingDirectory=$SCRIPT_DIR
PermissionsStartOnly=true
ExecStartPre=-$BASH_BIN $SCRIPT_DIR/free_port.sh
ExecStart=$PYTHON_BIN $TARGET_PY
Restart=always
RestartSec=2
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF"

echo -e "${GREEN}    -> Da tao file dich vu tai $SERVICE_FILE${NC}"

echo -e "${CYAN}[3/4] Kich hoat va khoi chay dich vu...${NC}"
# Giai phong cong truoc khi systemctl start/restart
if [ -f "$SCRIPT_DIR/free_port.sh" ]; then
    echo -e "${YELLOW}    -> Dang don sach cong 8021 truoc khi khoi dong...${NC}"
    $SUDO bash "$SCRIPT_DIR/free_port.sh"
fi

$SUDO systemctl daemon-reload
$SUDO systemctl reset-failed zebra-bridge.service 2>/dev/null
$SUDO systemctl enable zebra-bridge.service
$SUDO systemctl restart zebra-bridge.service

sleep 2

echo -e "${CYAN}[4/4] Kiem tra trang thai hoat dong...${NC}"
if systemctl is-active --quiet zebra-bridge.service; then
    echo -e "${GREEN}    -> Dich vu zebra-bridge dang CHAY (Active: running).${NC}"
    HEALTH_RESP=$(curl -s --max-time 2 http://127.0.0.1:8021/health 2>/dev/null)
    if [[ "$HEALTH_RESP" == *"ZebraUsbPrintBridge"* ]] || [[ "$HEALTH_RESP" == *"ok"* ]]; then
        echo -e "${GREEN}    -> Kiem tra http://127.0.0.1:8021/health: PHAN HOI TOT.${NC}"
        echo -e "${GREEN}    -> Cong 8021 da san sang phuc vu!${NC}"
    else
        echo -e "${YELLOW}    -> Dich vu da chay, cong 8021 dang khoi tao.${NC}"
    fi
else
    echo -e "${RED}    -> Canh bao: Dich vu chua running. Chi tiet loi:${NC}"
    $SUDO journalctl -u zebra-bridge.service -n 15 --no-pager
fi

echo ""
echo -e "${CYAN}================================================================${NC}"
echo -e "${GREEN}  HOAN TAT CAI DAT! Tu gio moi khi bat Raspberry Pi:${NC}"
echo -e "  - Dich vu Print Bridge se tu dong chay ngam tai cong 8021."
echo -e "  - Trinh duyet tren Raspberry Pi se tu ket noi http://localhost:8021."
echo -e "  - De kiem tra trang thai:  systemctl status zebra-bridge"
echo -e "  - De xem log chay truc tiep: bash run_debug.sh"
echo -e "${CYAN}================================================================${NC}"
