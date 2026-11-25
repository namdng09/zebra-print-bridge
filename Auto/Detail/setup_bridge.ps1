[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "          THIET LAP ZEBRA USB PRINT BRIDGE (PORT 8021)          " -ForegroundColor Yellow
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$vbs = Join-Path $dir 'run_hidden.vbs'
$startup = [System.Environment]::GetFolderPath('Startup')
$lnk = Join-Path $startup 'ZebraPrintBridge.lnk'

# 1. Tao shortcut vao thu muc Startup de tu khoi dong
$ws = New-Object -ComObject WScript.Shell
$s = $ws.CreateShortcut($lnk)
$s.TargetPath = 'wscript.exe'
$s.Arguments = "`"$vbs`""
$s.WorkingDirectory = $dir
$s.Save()

Write-Host "[1/2] Da cai dat vao Startup Windows (Tu dong mo khi bat may)." -ForegroundColor Green

# 2. Kiem tra cong 8021, neu chua chay thi kich hoat ngay
$conn = Get-NetTCPConnection -LocalPort 8021 -ErrorAction SilentlyContinue
if (-not $conn) {
    Start-Process 'wscript.exe' -ArgumentList "`"$vbs`""
    Write-Host "[2/2] Da kich hoat chay ngam cong 8021 (an 100%, khong cua so)." -ForegroundColor Green
} else {
    Write-Host "[2/2] Cong 8021 da dang chay san sang." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " Hoan tat! Tu gio moi khi mo may, dich vu se tu dong chay ngam." -ForegroundColor White
Write-Host " Cua so nay se tu dong tat sau 3 giay..." -ForegroundColor Gray
Write-Host "================================================================" -ForegroundColor Cyan

Start-Sleep -Seconds 3
