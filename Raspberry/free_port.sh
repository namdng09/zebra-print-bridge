#!/bin/bash
# ==============================================================================
#  GIAI PHONG CONG 8021 TRUOC KHI KHOI DONG PRINT BRIDGE
#  (Goi boi systemd ExecStartPre hoac chay thu cong truoc khi start service)
# ==============================================================================

PORT=8021
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Kiem tra quyen sudo neu can
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
else
    SUDO=""
fi

echo "[free_port.sh] Bat dau kiem tra va giai phong cong $PORT..."

CURRENT_PID=$$

# 1. Tim va dong cac tien trinh print_bridge.py cu con sot
BRIDGE_PIDS=$(pgrep -f "print_bridge.py" 2>/dev/null | grep -v "^$CURRENT_PID$")
if [ -n "$BRIDGE_PIDS" ]; then
    echo "[free_port.sh] Tim thay instance print_bridge.py cu (PID: $BRIDGE_PIDS). Dang gui SIGTERM..."
    $SUDO kill -15 $BRIDGE_PIDS 2>/dev/null
    sleep 0.5
    # Kiem tra lai, neu con song thi cuong che kill -9
    REMAINING_BRIDGE=$(pgrep -f "print_bridge.py" 2>/dev/null | grep -v "^$CURRENT_PID$")
    if [ -n "$REMAINING_BRIDGE" ]; then
        echo "[free_port.sh] Cuong che dung instance print_bridge.py (PID: $REMAINING_BRIDGE)..."
        $SUDO kill -9 $REMAINING_BRIDGE 2>/dev/null
    fi
fi

# 2. Giai phong bat ky tien trinh nao dang chiem giu cong 8021
# Phuong phap 1: fuser
if command -v fuser &>/dev/null; then
    FUSER_PIDS=$($SUDO fuser $PORT/tcp 2>/dev/null)
    if [ -n "$FUSER_PIDS" ]; then
        echo "[free_port.sh] fuser: Giai phong cong $PORT (PID: $FUSER_PIDS)..."
        $SUDO fuser -k -9 $PORT/tcp 2>/dev/null
    fi
fi

# Phuong phap 2: lsof
if command -v lsof &>/dev/null; then
    LSOF_PIDS=$($SUDO lsof -ti :$PORT 2>/dev/null)
    if [ -n "$LSOF_PIDS" ]; then
        echo "[free_port.sh] lsof: Giai phong cong $PORT (PID: $LSOF_PIDS)..."
        $SUDO kill -9 $LSOF_PIDS 2>/dev/null
    fi
fi

# Phuong phap 3: ss
if command -v ss &>/dev/null; then
    SS_PIDS=$($SUDO ss -tulpn "sport = :$PORT" 2>/dev/null | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u)
    if [ -n "$SS_PIDS" ]; then
        echo "[free_port.sh] ss: Giai phong cong $PORT (PID: $SS_PIDS)..."
        $SUDO kill -9 $SS_PIDS 2>/dev/null
    fi
fi

# 3. Cho cong duoc giai phong hoan toan (toi da 2s, moi lan 200ms)
for i in {1..10}; do
    OCCUPIED=0
    if command -v ss &>/dev/null; then
        if $SUDO ss -tuln "sport = :$PORT" 2>/dev/null | grep -q ":$PORT "; then
            OCCUPIED=1
        fi
    elif command -v netstat &>/dev/null; then
        if $SUDO netstat -tuln 2>/dev/null | grep -q ":$PORT "; then
            OCCUPIED=1
        fi
    elif command -v lsof &>/dev/null; then
        if $SUDO lsof -ti :$PORT &>/dev/null; then
            OCCUPIED=1
        fi
    fi

    if [ "$OCCUPIED" -eq 0 ]; then
        echo "[free_port.sh] Cong $PORT da san sang."
        exit 0
    fi
    sleep 0.2
done

echo "[free_port.sh] Da hoan tat don cong $PORT."
exit 0
