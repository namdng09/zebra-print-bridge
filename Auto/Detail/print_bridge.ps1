<#
    Zebra USB Print Bridge for PrintAppLine
    Lang nghe tai http://localhost:8021/
    Cung cap API cho trinh duyet web in ZPL truc tiep vao may in USB
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try {
    $Host.UI.RawUI.WindowTitle = "Zebra USB Print Bridge - Port 8021"
} catch {}

# 1. Bien dich class RawPrinterHelper de nap raw ZPL vao Windows Spooler
$winSpoolCode = @"
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public class RawPrinterHelper
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public class DOCINFOW
    {
        [MarshalAs(UnmanagedType.LPWStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile;
        [MarshalAs(UnmanagedType.LPWStr)] public string pDataType;
    }

    [DllImport("winspool.Drv", EntryPoint = "OpenPrinterW", SetLastError = true, CharSet = CharSet.Unicode, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool OpenPrinter([MarshalAs(UnmanagedType.LPWStr)] string szPrinter, out IntPtr hPrinter, IntPtr pd);

    [DllImport("winspool.Drv", EntryPoint = "ClosePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool ClosePrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", EntryPoint = "StartDocPrinterW", SetLastError = true, CharSet = CharSet.Unicode, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool StartDocPrinter(IntPtr hPrinter, int level, [In, MarshalAs(UnmanagedType.LPStruct)] DOCINFOW di);

    [DllImport("winspool.Drv", EntryPoint = "EndDocPrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool EndDocPrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", EntryPoint = "StartPagePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool StartPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", EntryPoint = "EndPagePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool EndPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", EntryPoint = "WritePrinter", SetLastError = true, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    public static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwWritten);

    public static bool SendBytesToPrinter(string szPrinterName, IntPtr pBytes, int dwCount, out string errorMessage)
    {
        errorMessage = string.Empty;
        int dwWritten = 0;
        IntPtr hPrinter = IntPtr.Zero;
        DOCINFOW di = new DOCINFOW();
        di.pDocName = "ZPL Raw Document";
        di.pDataType = "RAW";

        if (!OpenPrinter(szPrinterName, out hPrinter, IntPtr.Zero))
        {
            int err = Marshal.GetLastWin32Error();
            errorMessage = "Khong the mo may in. Ma loi: " + err;
            return false;
        }

        try
        {
            if (!StartDocPrinter(hPrinter, 1, di))
            {
                int err = Marshal.GetLastWin32Error();
                errorMessage = "StartDocPrinter that bai. Ma loi: " + err;
                return false;
            }

            try
            {
                if (!StartPagePrinter(hPrinter))
                {
                    int err = Marshal.GetLastWin32Error();
                    errorMessage = "StartPagePrinter that bai. Ma loi: " + err;
                    return false;
                }

                try
                {
                    if (!WritePrinter(hPrinter, pBytes, dwCount, out dwWritten) || dwWritten != dwCount)
                    {
                        int err = Marshal.GetLastWin32Error();
                        errorMessage = "WritePrinter that bai. Ma loi: " + err + " (Da ghi: " + dwWritten + "/" + dwCount + ")";
                        return false;
                    }
                }
                finally
                {
                    EndPagePrinter(hPrinter);
                }
            }
            finally
            {
                EndDocPrinter(hPrinter);
            }
        }
        finally
        {
            ClosePrinter(hPrinter);
        }

        return true;
    }

    public static bool SendStringToPrinter(string szPrinterName, string szString, out string errorMessage)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(szString);
        IntPtr pUnmanagedBytes = Marshal.AllocCoTaskMem(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, pUnmanagedBytes, bytes.Length);
            return SendBytesToPrinter(szPrinterName, pUnmanagedBytes, bytes.Length, out errorMessage);
        }
        finally
        {
            Marshal.FreeCoTaskMem(pUnmanagedBytes);
        }
    }
}
"@

try {
    Add-Type -TypeDefinition $winSpoolCode -ErrorAction Stop
} catch {
    # Neu da load roi thi tiep tuc
}

Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

# 2. Thiet lap HttpListener
$port = 8021
$listener = New-Object System.Net.HttpListener
$prefix = "http://localhost:$port/"
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
} catch {
    Write-Host "[LOI] Khong the khoi dong tren cong $port. Co the cong dang bi ung dung khac chiem dung." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Read-Host "Nhan Enter de thoat..."
    exit 1
}

try { Clear-Host } catch {}
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "             ZEBRA USB PRINT BRIDGE (PORT $port)               " -ForegroundColor Yellow
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  Dich vu dang chay tai: $prefix" -ForegroundColor Green
Write-Host "  Dang lang nghe ket noi tu trinh duyet web..." -ForegroundColor White
Write-Host "  (De dung dich vu, nhan Ctrl + C hoac dong cua so nay)" -ForegroundColor DarkGray
Write-Host "-----------------------------------------------------------------" -ForegroundColor Cyan

# Ham gui phan hoi HTTP kem CORS
function Send-Response($context, $statusCode, $contentType, $bodyString) {
    try {
        $response = $context.Response
        $response.StatusCode = $statusCode
        if ($contentType) {
            $response.ContentType = $contentType
        }
        
        # Header CORS bat buoc de trinh duyet khong chan
        $response.AddHeader("Access-Control-Allow-Origin", "*")
        $response.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        $response.AddHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, Accept")

        $buffer = if ($bodyString) { [System.Text.Encoding]::UTF8.GetBytes($bodyString) } else { [byte[]]@() }
        $response.ContentLength64 = $buffer.Length
        if ($buffer.Length -gt 0) {
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        $response.OutputStream.Close()
    } catch {
        # Bo qua loi ngat ket noi bat thuong tu client
    }
}

# Vong lap lang nghe request
try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $urlPath = $request.Url.AbsolutePath.ToLower().TrimEnd('/')
        $method = $request.HttpMethod.ToUpper()
        $timeStr = (Get-Date).ToString("HH:mm:ss")

        # 1. CORS Preflight (OPTIONS)
        if ($method -eq "OPTIONS") {
            Send-Response $context 200 "text/plain; charset=utf-8" "OK"
            continue
        }

        # 2. Endpoint: /health
        if ($urlPath -eq "/health" -and $method -eq "GET") {
            $json = '{"status":"ok","service":"ZebraUsbPrintBridge"}'
            Send-Response $context 200 "application/json; charset=utf-8" $json
            continue
        }

        # 3. Endpoint: /usb-printers
        if ($urlPath -eq "/usb-printers" -and $method -eq "GET") {
            try {
                $installedPrinters = [System.Drawing.Printing.PrinterSettings]::InstalledPrinters
                $printerList = [System.Collections.ArrayList]@()
                
                # Uu tien dua may in Zebra len dau danh sach
                foreach ($p in $installedPrinters) {
                    if ($p -match "Zebra|ZDesigner") {
                        [void]$printerList.Add($p)
                    }
                }
                foreach ($p in $installedPrinters) {
                    if (-not ($p -match "Zebra|ZDesigner")) {
                        [void]$printerList.Add($p)
                    }
                }

                $resObj = @{ printers = $printerList }
                $json = $resObj | ConvertTo-Json -Compress
                Send-Response $context 200 "application/json; charset=utf-8" $json
                Write-Host "[$timeStr] [GET /usb-printers] Da gui danh sach $($printerList.Count) may in cho web." -ForegroundColor Green
            } catch {
                $errJson = @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
                Send-Response $context 500 "application/json; charset=utf-8" $errJson
                Write-Host "[$timeStr] [GET /usb-printers LOI] $($_.Exception.Message)" -ForegroundColor Red
            }
            continue
        }

        # 4. Endpoint: /print-usb
        if ($urlPath -eq "/print-usb" -and $method -eq "POST") {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
                $bodyText = $reader.ReadToEnd()
                $bodyData = $bodyText | ConvertFrom-Json

                $printerName = $bodyData.printerName
                $zpl = $bodyData.zpl

                if ([string]::IsNullOrWhiteSpace($printerName)) {
                    throw "Chua chon ten may in USB."
                }
                if ([string]::IsNullOrWhiteSpace($zpl)) {
                    throw "Du lieu ZPL trong."
                }

                $errMsg = ""
                $ok = [RawPrinterHelper]::SendStringToPrinter($printerName, $zpl, [ref]$errMsg)

                $sw.Stop()
                $duration = [math]::Round($sw.Elapsed.TotalMilliseconds)
                $bytesSent = [System.Text.Encoding]::UTF8.GetByteCount($zpl)

                if ($ok) {
                    $resObj = @{
                        success = $true
                        bytesSent = $bytesSent
                        duration = $duration
                    }
                    $json = $resObj | ConvertTo-Json -Compress
                    Send-Response $context 200 "application/json; charset=utf-8" $json
                    Write-Host "[$timeStr] [IN USB THANH CONG] Da gui $bytesSent bytes -> '$printerName' ($duration ms)" -ForegroundColor Green
                } else {
                    throw $errMsg
                }
            } catch {
                $sw.Stop()
                $errRes = @{
                    success = $false
                    error = $_.Exception.Message
                }
                $json = $errRes | ConvertTo-Json -Compress
                Send-Response $context 500 "application/json; charset=utf-8" $json
                Write-Host "[$timeStr] [IN USB THAT BAI] $($_.Exception.Message)" -ForegroundColor Red
            }
            continue
        }

        # 5. Endpoint: /print (TCP neu co dung)
        if ($urlPath -eq "/print" -and $method -eq "POST") {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
                $bodyData = $reader.ReadToEnd() | ConvertFrom-Json

                $ip = $bodyData.printerIp
                $portTcp = if ($bodyData.printerPort) { [int]$bodyData.printerPort } else { 9100 }
                $zpl = $bodyData.zpl

                $client = New-Object System.Net.Sockets.TcpClient
                $client.Connect($ip, $portTcp)
                $stream = $client.GetStream()
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($zpl)
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Flush()
                $client.Close()

                $sw.Stop()
                $duration = [math]::Round($sw.Elapsed.TotalMilliseconds)

                $resObj = @{
                    success = $true
                    bytesSent = $bytes.Length
                    duration = $duration
                }
                $json = $resObj | ConvertTo-Json -Compress
                Send-Response $context 200 "application/json; charset=utf-8" $json
                Write-Host "[$timeStr] [IN TCP THANH CONG] Da gui $($bytes.Length) bytes -> $ip`:$portTcp ($duration ms)" -ForegroundColor Green
            } catch {
                $sw.Stop()
                $errRes = @{ success = $false; error = $_.Exception.Message }
                $json = $errRes | ConvertTo-Json -Compress
                Send-Response $context 500 "application/json; charset=utf-8" $json
                Write-Host "[$timeStr] [IN TCP THAT BAI] $($_.Exception.Message)" -ForegroundColor Red
            }
            continue
        }

        # Mac dinh 404 cho cac route khac
        Send-Response $context 404 "text/plain" "Endpoint not found"
    }
} finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
}
