# Zebra Print Bridge

Cầu nối giữa trình duyệt web và máy in nhãn Zebra (ZPL) qua USB hoặc TCP/IP, lắng nghe tại `http://localhost:8021/`.

| Thư mục | Dùng cho |
|---|---|
| `Auto/` | Windows: cài tự động, chạy ngầm khi khởi động (`start.bat`, gỡ bằng `uninstall.bat`) |
| `Manual/` | Windows: chạy tay (`run_usb_bridge.bat` / `stop_usb_bridge.bat`) |
| `Raspberry/` | Raspberry Pi OS / Linux (`setup.sh`, Python 3 không cần thư viện ngoài) |

Hướng dẫn chi tiết: file `HuongDanSuDung.txt` trong từng thư mục.

```bash
git clone https://github.com/namdng09/zebra-print-bridge.git
```
