@echo off
chcp 65001 >nul
title Zebra USB Print Bridge - Go Cai Dat
color 0C

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Detail\uninstall_bridge.ps1"
exit
