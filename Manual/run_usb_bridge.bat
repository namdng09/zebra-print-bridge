@echo off
chcp 65001 >nul
title Zebra USB Print Bridge (Port 8021)
color 0A

echo ================================================================
echo           KHOI CHAY ZEBRA USB PRINT BRIDGE (PORT 8021)
echo ================================================================
echo.
echo Dang kiem tra va khoi dong dich vu cau noi may in USB...
echo Ban hay giu cua so nay mo trong suot qua trinh in tem tren web.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0print_bridge.ps1"

echo.
echo Dich vu da dung.
pause
