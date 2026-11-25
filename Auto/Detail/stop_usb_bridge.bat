@echo off
chcp 65001 >nul
title Dung Zebra USB Print Bridge (Port 8021)
color 0C

echo ================================================================
echo           DUNG TIEN TRINH ZEBRA USB BRIDGE (PORT 8021)
echo ================================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$procs = Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*print_bridge.ps1*' -and $_.ProcessId -ne $PID }; if ($procs) { foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue; Write-Host ('[OK] Da tat tien trinh print_bridge PID: ' + $p.ProcessId) -ForegroundColor Green } } else { Write-Host '[INFO] Khong co tien trinh print_bridge nao dang chay.' -ForegroundColor Yellow }"

echo.
echo Hoan tat.
timeout /t 3 >nul
