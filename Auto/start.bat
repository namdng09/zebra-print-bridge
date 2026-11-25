@echo off
chcp 65001 >nul
title Zebra USB Print Bridge - Khoi Dong
color 0A

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Detail\setup_bridge.ps1"
exit
