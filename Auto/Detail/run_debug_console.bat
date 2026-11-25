@echo off
chcp 65001 >nul
title Zebra USB Print Bridge - Che Do Debug (Port 8021)
color 0A

echo ================================================================
echo      KHOI CHAY ZEBRA USB PRINT BRIDGE (CHE DO HIEN LOG CONSOLE)
echo ================================================================
echo.
echo Cua so nay dung de kiem tra log in tem khi can debug.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0print_bridge.ps1"

echo.
echo Dich vu da dung.
pause
