#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Zebra USB & Network Print Bridge for PrintAppLine (Raspberry Pi OS / Linux)
Cổng lắng nghe: http://localhost:8021/
Cung cấp API cho trình duyệt web in nhãn ZPL trực tiếp vào máy in USB hoặc TCP/IP.
Không phụ thuộc thư viện ngoài (chỉ dùng standard library Python 3).
"""

import sys
import os
import re
import glob
import json
import time
import socket
import signal
import errno
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

PORT = 8021

def get_usb_printers_info():
    """
    Quét danh sách máy in USB trên Linux:
    1. Kiểm tra các thiết bị /dev/usb/lp*
    2. Lấy thông tin Vendor/Model từ udev hoặc sysfs nếu có
    3. Kiểm tra các máy in cấu hình qua CUPS (lpstat)
    Ưu tiên đưa máy in Zebra lên đầu danh sách.
    """
    printers = []
    seen_devs = set()

    # 1. Quét /dev/usb/lp*
    lp_devices = sorted(glob.glob('/dev/usb/lp*'))
    for dev in lp_devices:
        seen_devs.add(dev)
        name = dev
        friendly_title = ""

        # Thử lấy thông tin từ udevadm
        try:
            p = subprocess.run(
                ['udevadm', 'info', '--query=property', f'--name={dev}'],
                capture_output=True, text=True, timeout=2
            )
            if p.returncode == 0:
                props = {}
                for line in p.stdout.splitlines():
                    if '=' in line:
                        k, v = line.split('=', 1)
                        props[k.strip()] = v.strip()
                vendor = props.get('ID_VENDOR_FROM_DATABASE') or props.get('ID_VENDOR') or ''
                model = props.get('ID_MODEL_FROM_DATABASE') or props.get('ID_MODEL') or ''
                if vendor or model:
                    friendly_title = f"{vendor} {model}".strip()
        except Exception:
            pass

        # Thử đọc qua sysfs nếu udevadm không có thông tin
        if not friendly_title:
            try:
                base = os.path.basename(dev)
                sys_path = f"/sys/class/usbmisc/{base}/device"
                if os.path.exists(sys_path):
                    # Tìm thông tin product ở parent folder
                    prod_file = os.path.join(sys_path, "../product")
                    man_file = os.path.join(sys_path, "../manufacturer")
                    prod = ""
                    man = ""
                    if os.path.isfile(prod_file):
                        with open(prod_file, "r") as f:
                            prod = f.read().strip()
                    if os.path.isfile(man_file):
                        with open(man_file, "r") as f:
                            man = f.read().strip()
                    if man or prod:
                        friendly_title = f"{man} {prod}".strip()
            except Exception:
                pass

        if friendly_title:
            printers.append(f"{friendly_title} ({dev})")
        else:
            printers.append(dev)

    # 2. Quét máy in qua CUPS (nếu có cài CUPS)
    try:
        p = subprocess.run(['lpstat', '-e'], capture_output=True, text=True, timeout=2)
        if p.returncode == 0:
            for line in p.stdout.splitlines():
                cups_name = line.strip()
                if cups_name and cups_name not in printers:
                    printers.append(cups_name)
    except FileNotFoundError:
        pass
    except Exception:
        pass

    # Sắp xếp: Ưu tiên máy in có chứa chữ Zebra / ZDesigner lên đầu
    zebra_list = [p for p in printers if re.search(r'zebra|zdesigner', p, re.IGNORECASE)]
    other_list = [p for p in printers if not re.search(r'zebra|zdesigner', p, re.IGNORECASE)]

    return zebra_list + other_list


def print_to_usb_device(printer_name, zpl_data):
    """
    Gửi dữ liệu ZPL vào máy in USB:
    - Nếu printer_name chứa đường dẫn /dev/usb/lp* -> ghi trực tiếp ra device node
    - Nếu là tên máy in CUPS -> gọi lệnh lp -d <printer> -o raw
    - Fallback: Nếu có /dev/usb/lp0 thì ghi vào đó
    """
    raw_bytes = zpl_data.encode('utf-8')
    
    # 1. Tìm đường dẫn /dev/usb/lp* trong tên máy in
    match = re.search(r'/dev/usb/lp\d+', printer_name)
    dev_path = match.group(0) if match else None

    if dev_path and os.path.exists(dev_path):
        with open(dev_path, 'wb', buffering=0) as f:
            f.write(raw_bytes)
            f.flush()
        return len(raw_bytes)

    # 2. Nếu trực tiếp là đường dẫn file hợp lệ
    if os.path.exists(printer_name):
        with open(printer_name, 'wb', buffering=0) as f:
            f.write(raw_bytes)
            f.flush()
        return len(raw_bytes)

    # 3. Thử in qua lệnh CUPS lp (Raw mode)
    try:
        p = subprocess.run(
            ['lp', '-d', printer_name, '-o', 'raw'],
            input=raw_bytes,
            capture_output=True,
            timeout=10
        )
        if p.returncode == 0:
            return len(raw_bytes)
        cups_err = p.stderr.decode('utf-8', errors='ignore').strip()
    except FileNotFoundError:
        cups_err = "Lệnh lp (CUPS) không tồn tại trên hệ thống"
    except Exception as e:
        cups_err = str(e)

    # 4. Fallback: Nếu hệ thống có bất kỳ /dev/usb/lp* nào, thử ghi vào thiết bị đầu tiên
    fallback_devices = sorted(glob.glob('/dev/usb/lp*'))
    if fallback_devices:
        target = fallback_devices[0]
        try:
            with open(target, 'wb', buffering=0) as f:
                f.write(raw_bytes)
                f.flush()
            return len(raw_bytes)
        except Exception as e:
            raise RuntimeError(f"Không thể ghi vào {target}: {e}. Lỗi CUPS trước đó: {cups_err}")

    raise RuntimeError(
        f"Không tìm thấy cổng in phù hợp cho '{printer_name}'. Lỗi: {cups_err}. "
        "Hãy kiểm tra kết nối USB máy in (kiểm tra /dev/usb/lp0)."
    )


def print_to_tcp_socket(printer_ip, printer_port, zpl_data):
    """
    Gửi dữ liệu ZPL qua TCP Socket đến cổng mạng máy in (mặc định 9100).
    """
    raw_bytes = zpl_data.encode('utf-8')
    with socket.create_connection((printer_ip, int(printer_port)), timeout=8) as s:
        s.sendall(raw_bytes)
    return len(raw_bytes)


class PrintBridgeRequestHandler(BaseHTTPRequestHandler):
    """
    Xử lý các request HTTP từ trình duyệt web.
    Hỗ trợ đầy đủ CORS và các API: /health, /usb-printers, /print-usb, /print.
    """

    def _send_cors_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization, Accept')

    def _send_json_response(self, status_code, data):
        body = json.dumps(data, ensure_ascii=False).encode('utf-8')
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self._send_cors_headers()
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        """Xử lý CORS preflight request từ trình duyệt"""
        self.send_response(200)
        self._send_cors_headers()
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_GET(self):
        url_path = urlparse(self.path).path.rstrip('/')
        time_str = time.strftime("%H:%M:%S")

        # 1. Endpoint: /health
        if url_path == '/health' or url_path == '':
            res = {"status": "ok", "service": "ZebraUsbPrintBridge"}
            self._send_json_response(200, res)
            return

        # 2. Endpoint: /usb-printers
        if url_path == '/usb-printers':
            try:
                printers = get_usb_printers_info()
                self._send_json_response(200, {"printers": printers})
                print(f"[{time_str}] [GET /usb-printers] Đã gửi danh sách {len(printers)} máy in cho web.")
            except Exception as e:
                self._send_json_response(500, {"error": str(e), "printers": []})
                print(f"[{time_str}] [GET /usb-printers LỖI] {e}")
            return

        # 404 cho các đường dẫn khác
        self.send_response(404)
        self._send_cors_headers()
        self.end_headers()
        self.wfile.write(b"Endpoint not found")

    def do_POST(self):
        url_path = urlparse(self.path).path.rstrip('/')
        time_str = time.strftime("%H:%M:%S")

        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length).decode('utf-8', errors='ignore')

        try:
            req_json = json.loads(post_data) if post_data else {}
        except Exception:
            self._send_json_response(400, {"success": False, "error": "Dữ liệu JSON không hợp lệ"})
            return

        # 1. Endpoint: /print-usb
        if url_path == '/print-usb':
            t0 = time.perf_counter()
            printer_name = req_json.get('printerName', '').strip()
            zpl = req_json.get('zpl', '')

            if not printer_name:
                self._send_json_response(400, {"success": False, "error": "Chưa chọn tên máy in USB."})
                return
            if not zpl:
                self._send_json_response(400, {"success": False, "error": "Dữ liệu ZPL rỗng."})
                return

            try:
                bytes_sent = print_to_usb_device(printer_name, zpl)
                duration = round((time.perf_counter() - t0) * 1000)
                res = {
                    "success": True,
                    "bytesSent": bytes_sent,
                    "duration": duration
                }
                self._send_json_response(200, res)
                print(f"[{time_str}] [IN USB THÀNH CÔNG] Đã gửi {bytes_sent} bytes -> '{printer_name}' ({duration} ms)")
            except Exception as e:
                duration = round((time.perf_counter() - t0) * 1000)
                res = {
                    "success": False,
                    "error": str(e),
                    "duration": duration
                }
                self._send_json_response(500, res)
                print(f"[{time_str}] [IN USB THẤT BẠI] {e}")
            return

        # 2. Endpoint: /print (TCP socket)
        if url_path == '/print':
            t0 = time.perf_counter()
            printer_ip = req_json.get('printerIp', '').strip()
            printer_port = int(req_json.get('printerPort', 9100) or 9100)
            zpl = req_json.get('zpl', '')

            if not printer_ip:
                self._send_json_response(400, {"success": False, "error": "Chưa nhập địa chỉ IP máy in."})
                return
            if not zpl:
                self._send_json_response(400, {"success": False, "error": "Dữ liệu ZPL rỗng."})
                return

            try:
                bytes_sent = print_to_tcp_socket(printer_ip, printer_port, zpl)
                duration = round((time.perf_counter() - t0) * 1000)
                res = {
                    "success": True,
                    "bytesSent": bytes_sent,
                    "duration": duration
                }
                self._send_json_response(200, res)
                print(f"[{time_str}] [IN TCP THÀNH CÔNG] Đã gửi {bytes_sent} bytes -> {printer_ip}:{printer_port} ({duration} ms)")
            except Exception as e:
                duration = round((time.perf_counter() - t0) * 1000)
                res = {
                    "success": False,
                    "error": str(e),
                    "duration": duration
                }
                self._send_json_response(500, res)
                print(f"[{time_str}] [IN TCP THẤT BẠI] {e}")
            return

        # 404 cho các route POST khác
        self.send_response(404)
        self._send_cors_headers()
        self.end_headers()
        self.wfile.write(b"Endpoint not found")

    def log_message(self, format, *args):
        # Tắt bớt log mặc định của BaseHTTPRequestHandler để console gọn gàng
        return


class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True


def get_pids_listening_on_port(port):
    """
    Tìm danh sách PID đang lắng nghe (LISTEN) trên cổng chỉ định.
    Ưu tiên đọc /proc (thuần Python không phụ thuộc tool ngoài),
    fallback qua ss, lsof, fuser nếu có.
    """
    pids = set()
    hex_port = f"{port:04X}"
    inodes = set()

    # 1. Quét qua /proc/net/tcp và /proc/net/tcp6
    for proc_file in ['/proc/net/tcp', '/proc/net/tcp6']:
        if not os.path.exists(proc_file):
            continue
        try:
            with open(proc_file, 'r') as f:
                lines = f.readlines()
            for line in lines[1:]:
                parts = line.strip().split()
                if len(parts) >= 10:
                    local_addr = parts[1]
                    state = parts[3]  # 0A là LISTEN
                    inode = parts[9]
                    if ':' in local_addr and state == '0A':
                        _, addr_port = local_addr.split(':')
                        if addr_port.upper() == hex_port:
                            inodes.add(inode)
        except Exception:
            pass

    # Nếu tìm thấy inode, quét /proc/[pid]/fd/* để map sang PID
    if inodes:
        try:
            for pid_dir in glob.glob('/proc/[0-9]*'):
                pid_str = os.path.basename(pid_dir)
                try:
                    pid = int(pid_str)
                    fd_dir = os.path.join(pid_dir, 'fd')
                    if os.path.isdir(fd_dir):
                        for fd in os.listdir(fd_dir):
                            fd_path = os.path.join(fd_dir, fd)
                            try:
                                target = os.readlink(fd_path)
                                for inode in inodes:
                                    if f"socket:[{inode}]" in target:
                                        pids.add(pid)
                            except (OSError, IOError):
                                pass
                except (ValueError, OSError):
                    pass
        except Exception:
            pass

    if pids:
        return list(pids)

    # 2. Fallback qua ss
    try:
        res = subprocess.run(['ss', '-tulpn', f'sport = :{port}'], capture_output=True, text=True, timeout=2)
        if res.returncode == 0:
            for match in re.finditer(r'pid=(\d+)', res.stdout):
                pids.add(int(match.group(1)))
    except Exception:
        pass

    if pids:
        return list(pids)

    # 3. Fallback qua lsof
    try:
        res = subprocess.run(['lsof', '-ti', f':{port}'], capture_output=True, text=True, timeout=2)
        if res.returncode == 0:
            for line in res.stdout.splitlines():
                if line.strip().isdigit():
                    pids.add(int(line.strip()))
    except Exception:
        pass

    if pids:
        return list(pids)

    # 4. Fallback qua fuser
    try:
        res = subprocess.run(['fuser', f'{port}/tcp'], capture_output=True, text=True, timeout=2)
        out = (res.stdout + ' ' + res.stderr).strip()
        for token in out.split():
            if token.isdigit():
                pids.add(int(token))
    except Exception:
        pass

    return list(pids)


def get_process_info(pid):
    """
    Lấy tên ứng dụng và câu lệnh của PID.
    """
    name = ""
    cmdline = ""
    comm_path = f"/proc/{pid}/comm"
    cmd_path = f"/proc/{pid}/cmdline"

    if os.path.exists(comm_path):
        try:
            with open(comm_path, 'r') as f:
                name = f.read().strip()
        except Exception:
            pass

    if os.path.exists(cmd_path):
        try:
            with open(cmd_path, 'rb') as f:
                raw = f.read()
                cmdline = raw.replace(b'\x00', b' ').decode('utf-8', errors='ignore').strip()
        except Exception:
            pass

    if not name or not cmdline:
        try:
            p = subprocess.run(['ps', '-p', str(pid), '-o', 'comm=,args='], capture_output=True, text=True, timeout=2)
            if p.returncode == 0 and p.stdout.strip():
                parts = p.stdout.strip().split(None, 1)
                if not name and len(parts) > 0:
                    name = parts[0]
                if not cmdline and len(parts) > 1:
                    cmdline = parts[1]
        except Exception:
            pass

    return name or "Không rõ", cmdline or "Không rõ"


def is_bridge_process(pid, name, cmdline):
    """
    Kiểm tra xem PID có phải là instance print_bridge.py hay không.
    """
    if pid == os.getpid():
        return False
    search_str = f"{name} {cmdline}".lower()
    return "print_bridge.py" in search_str or "zebra-bridge" in search_str


def get_other_bridge_pids():
    """
    Tìm tất cả các PID đang chạy print_bridge.py khác với PID hiện tại.
    """
    my_pid = os.getpid()
    bridge_pids = set()

    for pid_dir in glob.glob('/proc/[0-9]*'):
        pid_str = os.path.basename(pid_dir)
        try:
            pid = int(pid_str)
            if pid == my_pid:
                continue
            cmd_path = os.path.join(pid_dir, 'cmdline')
            if os.path.exists(cmd_path):
                with open(cmd_path, 'rb') as f:
                    cmd = f.read().decode('utf-8', errors='ignore')
                    if 'print_bridge.py' in cmd:
                        bridge_pids.add(pid)
        except Exception:
            pass

    if not bridge_pids:
        try:
            p = subprocess.run(['pgrep', '-f', 'print_bridge.py'], capture_output=True, text=True, timeout=2)
            if p.returncode == 0:
                for line in p.stdout.splitlines():
                    if line.strip().isdigit():
                        pid = int(line.strip())
                        if pid != my_pid:
                            bridge_pids.add(pid)
        except Exception:
            pass

    return list(bridge_pids)


def terminate_process(pid, timeout=1.5):
    """
    Tắt tiến trình: Thử SIGTERM (15) trước, nếu sau timeout chưa tắt thì dùng SIGKILL (9).
    """
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return True
    except PermissionError:
        try:
            subprocess.run(['kill', '-15', str(pid)], timeout=1)
        except Exception:
            pass

    # Chờ tiến trình kết thúc
    start = time.time()
    while time.time() - start < timeout:
        try:
            os.kill(pid, 0)
            time.sleep(0.1)
        except ProcessLookupError:
            return True
        except PermissionError:
            time.sleep(0.1)

    # Nếu vẫn còn sống, gửi SIGKILL
    try:
        os.kill(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        try:
            subprocess.run(['kill', '-9', str(pid)], timeout=1)
        except Exception:
            pass
    time.sleep(0.2)
    return True


def main():
    server_address = ('0.0.0.0', PORT)
    MAX_BIND_RETRIES = 8
    httpd = None

    for attempt in range(1, MAX_BIND_RETRIES + 1):
        try:
            httpd = ReusableHTTPServer(server_address, PrintBridgeRequestHandler)
            if attempt > 1:
                print(f"[THÀNH CÔNG] Đã chiếm và mở cổng {PORT} thành công ở lần thử thứ {attempt}.")
            break
        except OSError as e:
            time_str = time.strftime("%H:%M:%S")
            print(f"[{time_str}] [CẢNH BÁO] Không thể mở cổng {PORT} (Lần thử {attempt}/{MAX_BIND_RETRIES}): {e}")

            # Tìm danh sách PID đang nghe trên cổng 8021
            listening_pids = get_pids_listening_on_port(PORT)
            other_bridge_pids = get_other_bridge_pids()

            bridge_pids_to_kill = set()
            other_apps = []

            for pid in listening_pids:
                if pid == os.getpid():
                    continue
                name, cmdline = get_process_info(pid)
                if is_bridge_process(pid, name, cmdline):
                    bridge_pids_to_kill.add(pid)
                else:
                    other_apps.append((pid, name, cmdline))

            for pid in other_bridge_pids:
                if pid != os.getpid():
                    bridge_pids_to_kill.add(pid)

            # Trường hợp 1: Có instance bridge cũ giữ cổng -> Tắt instance đó
            if bridge_pids_to_kill:
                for b_pid in sorted(bridge_pids_to_kill):
                    name, cmd = get_process_info(b_pid)
                    print(f"[{time_str}] -> Phát hiện instance print_bridge.py cũ (PID: {b_pid}, {name}). Đang tắt để giải phóng cổng...")
                    terminate_process(b_pid)
                    print(f"[{time_str}] -> Đã giải phóng instance PID: {b_pid}.")
                time.sleep(0.8)
                continue

            # Trường hợp 2: Có ứng dụng khác giữ cổng 8021 -> Log rõ PID và thông tin
            if other_apps:
                print(f"[{time_str}] [LỖI XUNG ĐỘT CỔNG] Cổng {PORT} đang bị ứng dụng khác chiếm giữ:")
                for o_pid, o_name, o_cmd in other_apps:
                    print(f"  + PID      : {o_pid}")
                    print(f"  + Tên App  : {o_name}")
                    print(f"  + Lệnh chạy: {o_cmd}")
                print(f"[{time_str}] Vui lòng tắt ứng dụng trên hoặc giải phóng cổng {PORT} trước khi chạy Zebra Print Bridge.")
                sys.exit(1)

            # Trường hợp 3: Socket đang trong trạng thái chờ giải phóng (TIME_WAIT)
            print(f"[{time_str}] Cổng {PORT} chưa kịp giải phóng (trạng thái TIME_WAIT). Chờ 1 giây rồi thử lại...")
            time.sleep(1.0)

    if httpd is None:
        print(f"[LỖI] Đã thử {MAX_BIND_RETRIES} lần nhưng không thể mở cổng {PORT}. Dừng chương trình.")
        sys.exit(1)

    print("=" * 65)
    print(f"       ZEBRA USB & NETWORK PRINT BRIDGE - RASPBERRY PI OS")
    print(f"                 Cổng lắng nghe: http://localhost:{PORT}/")
    print("=" * 65)
    print(f"  Dịch vụ đang sẵn sàng nhận lệnh in từ trình duyệt web.")
    print(f"  Hỗ trợ các API: /health, /usb-printers, /print-usb, /print")
    print(f"  Nhấn Ctrl + C để dừng dịch vụ.")
    print("-" * 65)

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nĐang dừng Zebra Print Bridge...")
    finally:
        httpd.server_close()
        print("Đã giải phóng cổng và tắt hoàn toàn.")


if __name__ == '__main__':
    main()
