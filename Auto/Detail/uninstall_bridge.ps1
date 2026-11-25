[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "================================================================" -ForegroundColor Red
Write-Host "       HUY TU KHOI DONG VA DUNG ZEBRA USB PRINT BRIDGE          " -ForegroundColor Yellow
Write-Host "================================================================" -ForegroundColor Red
Write-Host ""

# 1. Xoa shortcut khoi Startup
$startup = [System.Environment]::GetFolderPath('Startup')
$lnk = Join-Path $startup 'ZebraPrintBridge.lnk'
if (Test-Path $lnk) {
    Remove-Item $lnk -Force
    Write-Host "[OK] Da xoa shortcut khoi Startup Windows." -ForegroundColor Green
} else {
    Write-Host "[INFO] Khong tim thay trong Startup Windows." -ForegroundColor Yellow
}

# 2. Dong cong 8021 bang cach tat tien trinh PowerShell dang chay print_bridge.ps1
$killed = $false
$procs = Get-CimInstance Win32_Process | Where-Object { 
    $_.Name -eq "powershell.exe" -and 
    $_.CommandLine -like "*print_bridge.ps1*" -and 
    $_.ProcessId -ne $PID 
}
if ($procs) {
    foreach ($p in $procs) {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host ("[OK] Da dong cong 8021 (Tat tien trinh PID: " + $p.ProcessId + ")") -ForegroundColor Green
        $killed = $true
    }
}

# 3. Tat tien trinh wscript phu tro neu co
$wscripts = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -like "*wscript*" -and
    $_.CommandLine -like "*run_hidden.vbs*" -and
    $_.ProcessId -ne $PID
}
if ($wscripts) {
    foreach ($w in $wscripts) {
        Stop-Process -Id $w.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

# 4. Kiem tra them cac tien trinh khac co the dang chiem cong 8021
$conn = Get-NetTCPConnection -LocalPort 8021 -ErrorAction SilentlyContinue
if ($conn) {
    foreach ($c in $conn) {
        if ($c.OwningProcess -gt 4) {
            Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
            Write-Host ("[OK] Da giai phong cong 8021 tu PID: " + $c.OwningProcess) -ForegroundColor Green
            $killed = $true
        }
    }
}

if (-not $killed) {
    Write-Host "[INFO] Cong 8021 hien khong co tien trinh nao chay." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Hoan tat! Cua so se tu dong tat sau 3 giay..." -ForegroundColor Gray
Start-Sleep -Seconds 3
