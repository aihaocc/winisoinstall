<#
.SYNOPSIS
    WinISO安装助手 v1.0.0
.DESCRIPTION
    API 获取链接 + aria2 并发下载 + Ventoy 1.1.18 启动盘制作 + WinPE 工具箱
.EXAMPLE
    irm https://aihao.cc/wii | iex
#>

param(
    [string]$AppTitle = "WinISO安装助手",
    [string]$ApiBase  = "https://xiaoai.api.i530.cn/WinISO_Install/v1/api.php",
    [string]$ApiKey   = "ak-7a2f9d4e8c1b3a5f7d9c2e4a6f8b0d1c"
)

# ============================================================
# 0. 管理员自提权
# ============================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "请以管理员身份运行此脚本。" -ForegroundColor Red
    Write-Host "右键点击 Windows 徽标，选择「终端（管理员）」或「命令提示符（管理员）」后重试。"
    Read-Host "按回车退出"
    exit
}

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$ProgressPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'

try {
    $culture = [System.Globalization.CultureInfo]::GetCultureInfo('zh-CN')
    [System.Threading.Thread]::CurrentThread.CurrentUICulture = $culture
    [System.Threading.Thread]::CurrentThread.CurrentCulture = $culture
} catch {}

$script:AppVersion = "1.0.0"

$script:DataDir       = Join-Path $env:TEMP "WinISO_Install"
$script:ConfigPath    = Join-Path $script:DataDir "config.json"
$script:LogPath       = Join-Path $script:DataDir "log.txt"
$script:Aria2Dir      = Join-Path $script:DataDir "aria2"
$script:Aria2Exe      = Join-Path $script:Aria2Dir "aria2c.exe"
$script:VentoyDir     = Join-Path $script:DataDir "ventoy"
$script:VentoyExe     = Join-Path $script:VentoyDir "Ventoy2Disk.exe"
$script:VentoyVersion = "1.1.18"
if (!(Test-Path $script:DataDir)) { New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null }

if ((Test-Path $script:LogPath) -and (Get-Item $script:LogPath).Length -gt 5MB) {
    $bak = "$($script:LogPath).1"
    try {
        if (Test-Path $bak) { Remove-Item $bak -Force }
        Move-Item $script:LogPath $bak -Force
    } catch {}
}

# ============================================================
# 1. 常量
# ============================================================
$script:RpcPort     = 16800
$script:RpcSecret   = "xiaoai_iso_helper"
$script:RpcUrl      = "http://127.0.0.1:$($script:RpcPort)/jsonrpc"

$script:Aria2Urls = @(
    "https://filecdn.aihao.cc/aria2-1.37.0-win-32bit-build1.zip",
    "https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-32bit-build1.zip"
)

$script:VentoyUrls = @(
    "https://mirrors.nju.edu.cn/github-release/ventoy/Ventoy/LatestRelease/ventoy-$($script:VentoyVersion)-windows.zip",
    "https://mirror4.lzu.edu.cn/github-release/ventoy/Ventoy/LatestRelease/ventoy-$($script:VentoyVersion)-windows.zip",
    "https://github.com/ventoy/Ventoy/releases/download/v$($script:VentoyVersion)/ventoy-$($script:VentoyVersion)-windows.zip"
)

$script:WinPEUrl      = "https://api.hotpe.top/API/HotPE/ToLink/?id=iso-down"
$script:WinPEFileName = "HotPE-V2.8.251018.iso"

$script:SystemOptions = @(
    [PSCustomObject]@{ DisplayName = "Windows 11（多版本 ISO）x64"; Win = "Windows 11"; Rel = "26H2 (Build 26300.9457 - 2026.09)"; Ed = "Windows 11（多版本 ISO）"; Arch = "x64"; IsWinPE = $false }
    [PSCustomObject]@{ DisplayName = "Windows 11（多版本 ISO）ARM64"; Win = "Windows 11"; Rel = "26H2 (Build 26300.9457 - 2026.09)"; Ed = "Windows 11（多版本 ISO）"; Arch = "ARM64"; IsWinPE = $false }
    [PSCustomObject]@{ DisplayName = "Windows 10（多版本 ISO）x64"; Win = "Windows 10"; Rel = "22H2 v1 (Build 19045.2965 - 2023.05)"; Ed = "Windows 10（多版本 ISO）"; Arch = "x64"; IsWinPE = $false }
    [PSCustomObject]@{ DisplayName = "Windows 10（多版本 ISO）x86"; Win = "Windows 10"; Rel = "22H2 v1 (Build 19045.2965 - 2023.05)"; Ed = "Windows 10（多版本 ISO）"; Arch = "x86"; IsWinPE = $false }
    [PSCustomObject]@{ DisplayName = "WinPE 工具箱（推荐）"; Win = "WinPE"; Rel = ""; Ed = ""; Arch = "x64"; IsWinPE = $true }
)

$script:CommonLanguages = @(
    [PSCustomObject]@{ DisplayName = "中文 (简体)"; Name = "Chinese (Simplified)" }
    [PSCustomObject]@{ DisplayName = "中文 (繁體)"; Name = "Chinese (Traditional)" }
    [PSCustomObject]@{ DisplayName = "English (US)"; Name = "English (United States)" }
    [PSCustomObject]@{ DisplayName = "English (UK)"; Name = "English (United Kingdom)" }
    [PSCustomObject]@{ DisplayName = "日本語"; Name = "Japanese" }
    [PSCustomObject]@{ DisplayName = "한국어"; Name = "Korean" }
    [PSCustomObject]@{ DisplayName = "Deutsch"; Name = "German" }
    [PSCustomObject]@{ DisplayName = "Français"; Name = "French" }
    [PSCustomObject]@{ DisplayName = "Español"; Name = "Spanish" }
    [PSCustomObject]@{ DisplayName = "Italiano"; Name = "Italian" }
    [PSCustomObject]@{ DisplayName = "Português (BR)"; Name = "Brazilian Portuguese" }
    [PSCustomObject]@{ DisplayName = "Русский"; Name = "Russian" }
)

# ============================================================
# 2. 程序集与全局状态
# ============================================================
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:ClientId      = [guid]::NewGuid().ToString()
$script:DownloadState = "idle"
$script:SelectedSystems = @()
$script:UsbPollTimer = $null
$script:UsbSignature = ""
$script:UsbMultiAckedSignature = ""
$script:WorkerPS = $null
$script:WorkerRS = $null

$script:BtnNormalColor = New-Object Windows.Media.SolidColorBrush([Windows.Media.Color]::FromRgb(0, 103, 192))
$script:BtnStopColor   = New-Object Windows.Media.SolidColorBrush([Windows.Media.Color]::FromRgb(239, 68, 68))
$script:PrgNormalColor = New-Object Windows.Media.SolidColorBrush([Windows.Media.Color]::FromRgb(0, 103, 192))
$script:PrgDoneColor   = New-Object Windows.Media.SolidColorBrush([Windows.Media.Color]::FromRgb(16, 185, 129))
$script:PrgErrorColor  = New-Object Windows.Media.SolidColorBrush([Windows.Media.Color]::FromRgb(239, 68, 68))

# 同步哈希表
$script:Sync = [hashtable]::Synchronized(@{})
$script:Sync.Queue   = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
$script:Sync.Running = $false
$script:Sync.Cancel  = $false

# ===== 启动时清理上次异常退出残留的 aria2c 进程 =====
try {
    Get-Process -Name "aria2c" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            if ($_.Path -like "*WinISO_Install\aria2\*") { $_ | Stop-Process -Force -ErrorAction SilentlyContinue }
        } catch {}
    }
} catch {}

# ============================================================
# 3. UI 工具函数
# ============================================================
function Format-Size { param([long]$Bytes); if ($Bytes -ge 1GB) { "{0:N2} GB" -f ($Bytes/1GB) } elseif ($Bytes -ge 1MB) { "{0:N1} MB" -f ($Bytes/1MB) } elseif ($Bytes -ge 1KB) { "{0:N1} KB" -f ($Bytes/1KB) } else { "$Bytes B" } }
function Format-Speed { param([long]$Bps); if ($Bps -ge 1MB) { "{0:N2} MB/s" -f ($Bps/1MB) } elseif ($Bps -ge 1KB) { "{0:N1} KB/s" -f ($Bps/1KB) } else { "$Bps B/s" } }

function Get-DefaultDownloadDir {
    param([long]$MinFreeSpace = 10GB)
    $sysLetter = $env:SystemDrive.TrimEnd(':').ToUpper()
    $candidates = @()
    try {
        $candidates = [System.IO.DriveInfo]::GetDrives() |
                      Where-Object { $_.IsReady -and $_.DriveType -eq [System.IO.DriveType]::Fixed -and $_.Name -match '^[A-Z]:\\$' } |
                      Sort-Object -Property Name -Descending
    } catch {}
    if (-not $candidates) { return (Join-Path $env:USERPROFILE "Downloads") }
    foreach ($d in $candidates) {
        $letter = $d.Name.Substring(0,1)
        if ($letter -ieq $sysLetter) { continue }
        if ($d.AvailableFreeSpace -ge $MinFreeSpace) { return "$letter`:\WinISO" }
    }
    foreach ($d in $candidates) {
        $letter = $d.Name.Substring(0,1)
        if ($letter -ieq $sysLetter) { continue }
        return "$letter`:\WinISO"
    }
    return (Join-Path $env:USERPROFILE "Downloads")
}

function Write-Log {
    param([string]$Msg, [ValidateSet("Info","Success","Warning","Error")][string]$Lv = "Info")
    $t = Get-Date -Format "HH:mm:ss"
    $color = switch ($Lv) { "Info" { [Windows.Media.Brushes]::LightGray } "Success" { [Windows.Media.Brushes]::LightGreen } "Warning" { [Windows.Media.Brushes]::Orange } "Error" { [Windows.Media.Brushes]::Tomato } default { [Windows.Media.Brushes]::Gray } }
    if ($script:LogParagraph) {
        $r1 = New-Object System.Windows.Documents.Run("[$t] "); $r1.Foreground = [Windows.Media.Brushes]::Gray
        $r2 = New-Object System.Windows.Documents.Run("$Msg`r`n"); $r2.Foreground = $color
        $script:LogParagraph.Inlines.Add($r1); $script:LogParagraph.Inlines.Add($r2)
        if ($script:LogParagraph.Inlines.Count -gt 3000) {
            $toRemove = $script:LogParagraph.Inlines.Count - 3000
            $first = $script:LogParagraph.Inlines.FirstInline
            for ($i = 0; $i -lt $toRemove -and $first; $i++) {
                $next = $first.NextInline
                $script:LogParagraph.Inlines.Remove($first)
                $first = $next
            }
        }
        if ($script:ChkAutoScroll -and $script:ChkAutoScroll.IsChecked) { $script:TxtLog.ScrollToEnd() }
    }
    try { [System.IO.File]::AppendAllText($script:LogPath, "[$t] [$Lv] $Msg`r`n", [System.Text.Encoding]::UTF8) } catch {}
}

function Write-Status {
    param([string]$Text, [string]$Color = "Gray")
    if (!$script:TxtStatus) { return }
    try { $script:Window.Dispatcher.Invoke([Action]{
        if ($script:TxtStatus.Text -ne $Text) { $script:TxtStatus.Text = $Text }
        switch ($Color) { "Orange" { $script:TxtStatus.Foreground = [Windows.Media.Brushes]::Orange } "Green" { $script:TxtStatus.Foreground = [Windows.Media.Brushes]::Green } "Red" { $script:TxtStatus.Foreground = [Windows.Media.Brushes]::Red } default { $script:TxtStatus.Foreground = [Windows.Media.Brushes]::Gray } }
    }) | Out-Null } catch {}
}

# ============================================================
# 4. 配置
# ============================================================
function Load-Config { if (Test-Path $script:ConfigPath) { try { Get-Content $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null } } else { $null } }
function Save-Config {
    try {
        $existing = $null; if (Test-Path $script:ConfigPath) { try { $existing = Get-Content $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }
        $dd = if ($script:TxtDownloadDir) { $script:TxtDownloadDir.Text } else { $null }
        if ([string]::IsNullOrWhiteSpace($dd) -and $existing -and $existing.Selection) { $dd = $existing.Selection.DownloadDir }
        $cfg = [ordered]@{
            ClientId = if ($existing -and $existing.ClientId) { $existing.ClientId } else { $script:ClientId }
            Window = [ordered]@{ Width = if ($script:Window) { $script:Window.Width } else { 1100 }; Height = if ($script:Window) { $script:Window.Height } else { 720 }; Left = if ($script:Window) { $script:Window.Left } else { -1 }; Top = if ($script:Window) { $script:Window.Top } else { -1 }; State = if ($script:Window) { $script:Window.WindowState.ToString() } else { "Normal" } }
            Selection = [ordered]@{ LanguageName = if ($script:CmbLanguage -and $script:CmbLanguage.SelectedItem) { $script:CmbLanguage.SelectedItem.Name } else { $null }; DownloadDir = $dd; UseVentoy = if ($script:ChkVentoy) { $script:ChkVentoy.IsChecked } else { $true }; UsbDiskNumber = if ($script:CmbUsbDisk -and $script:CmbUsbDisk.SelectedItem -and $script:CmbUsbDisk.SelectedItem -isnot [string]) { $script:CmbUsbDisk.SelectedItem.Number } else { -1 }; UsbUniqueId = if ($script:CmbUsbDisk -and $script:CmbUsbDisk.SelectedItem -and $script:CmbUsbDisk.SelectedItem -isnot [string]) { $script:CmbUsbDisk.SelectedItem.UniqueId } else { "" }; SelectedKeys = @($script:SelectedSystems) }
        }
        $cfg | ConvertTo-Json -Depth 10 | Set-Content $script:ConfigPath -Encoding UTF8
    } catch {}
}

# ============================================================
# 5. Worker 脚本
# ============================================================
$workerScript = {
    param($sync)

    $ErrorActionPreference = 'Stop'
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls } catch {}

    $scriptStartTime = Get-Date

    function Send-Msg { param($o) $sync.Queue.Enqueue($o) }
    function Emit-Log {
        param([string]$Text, [string]$Level = 'Info')
        $time = Get-Date -Format 'HH:mm:ss'
        $prefix = switch ($Level) { 'OK' { '[ ✓ ]' }; 'Warn' { '[ ! ]' }; 'Error' { '[ × ]' }; 'Step' { '[ » ]' }; default { '[ · ]' } }
        Send-Msg ([PSCustomObject]@{ Type = 'Log'; Text = "$time $prefix $Text" })
    }
    $script:lastStatus = $null
    function Emit-Status {
        param([string]$Text)
        if ($Text -eq $script:lastStatus) { return }
        $script:lastStatus = $Text
        Send-Msg ([PSCustomObject]@{ Type = 'Status'; Text = $Text })
    }
    $script:lastProgress = -1
    function Emit-Progress {
        param([int]$Value=0,[bool]$Indeterminate=$false)
        if (!$Indeterminate -and $Value -eq $script:lastProgress) { return }
        $script:lastProgress = $Value
        Send-Msg ([PSCustomObject]@{ Type='Progress'; Value=$Value; Indeterminate=$Indeterminate })
    }

    function Format-Size {
        param($bytes)
        if ($null -eq $bytes) { return "0 B" }
        $b = [long]$bytes
        if ($b -le 0) { return "0 B" }
        if ($b -ge 1GB) { return ("{0:N2} GB" -f ($b / 1GB)) }
        if ($b -ge 1MB) { return ("{0:N2} MB" -f ($b / 1MB)) }
        if ($b -ge 1KB) { return ("{0:N2} KB" -f ($b / 1KB)) }
        return "$b B"
    }
    function Format-Speed {
        param($bps)
        $b = [long]$bps
        if ($b -ge 1MB) { return ("{0:N2} MB/s" -f ($b / 1MB)) }
        if ($b -ge 1KB) { return ("{0:N1} KB/s" -f ($b / 1KB)) }
        return "$b B/s"
    }
    function Format-Duration {
        param([TimeSpan]$ts)
        if ($ts.TotalHours -ge 1) { return ("{0} 时 {1} 分" -f [int]$ts.TotalHours, $ts.Minutes) }
        if ($ts.TotalMinutes -ge 1) { return ("{0} 分 {1} 秒" -f $ts.Minutes, $ts.Seconds) }
        return ("{0} 秒" -f $ts.Seconds)
    }
    function Ensure-Dir { param([string]$path) if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null } }

    function Test-DownloadUrl {
        param([string]$Url)
        $resp = $null
        try {
            $req = [System.Net.HttpWebRequest]::Create($Url)
            $req.Method = "GET"
            $req.AddRange(0, 0)
            $req.Timeout = 15000
            $req.ReadWriteTimeout = 15000
            $req.AllowAutoRedirect = $true
            $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
            $resp = $req.GetResponse()
            $status = [int]$resp.StatusCode
            $len = $resp.ContentLength
            $ctype = ""
            try { $ctype = [string]$resp.ContentType } catch {}

            $totalSize = 0L
            try {
                $contentRange = [string]$resp.Headers["Content-Range"]
                if ($contentRange -match '/(\d+)$') { $totalSize = [long]$matches[1] }
            } catch {}
            if ($totalSize -le 0 -and $len -gt 1) { $totalSize = $len }
            $resp.Close(); $resp = $null

            if ($status -eq 416) {
                return [PSCustomObject]@{ Valid = $true; Size = 0; Error = $null }
            }
            if ($status -ne 200 -and $status -ne 206) {
                return [PSCustomObject]@{ Valid = $false; Size = $totalSize; Error = "HTTP $status" }
            }
            if ($ctype -and ($ctype -like "*text/html*" -or $ctype -like "*application/json*" -or $ctype -like "*text/plain*")) {
                return [PSCustomObject]@{ Valid = $false; Size = $totalSize; Error = "Content-Type: $ctype（非文件）" }
            }
            return [PSCustomObject]@{ Valid = $true; Size = $totalSize; Error = $null }
        } catch [System.Net.WebException] {
            $status = 0
            try { if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode } } catch {}
            if ($status -eq 416) {
                return [PSCustomObject]@{ Valid = $true; Size = 0; Error = $null }
            }
            return [PSCustomObject]@{ Valid = $false; Size = 0; Error = $_.Exception.Message }
        } catch {
            return [PSCustomObject]@{ Valid = $false; Size = 0; Error = $_.Exception.Message }
        } finally {
            if ($resp) { try { $resp.Close() } catch {} }
        }
    }

    function Invoke-Rpc {
        param([string]$Method, [array]$Params = @())
        $b = @{ jsonrpc = "2.0"; id = "x"; method = $Method; params = @("token:$($sync.RpcSecret)") + $Params } | ConvertTo-Json -Depth 10
        try { return Invoke-RestMethod -Uri $sync.RpcUrl -Method Post -Body $b -ContentType "application/json" -TimeoutSec 10 }
        catch { return $null }
    }

    function Start-Aria2Rpc {
        if (!(Test-Path $sync.Aria2Exe)) { throw "aria2c.exe 不存在：$($sync.Aria2Exe)" }
        try {
            $c = New-Object System.Net.Sockets.TcpClient
            $c.Connect("127.0.0.1", $sync.RpcPort); $c.Close()
            try { Invoke-Rpc -Method "aria2.shutdown" | Out-Null } catch {}
            Start-Sleep -Seconds 1
            try { $c = New-Object System.Net.Sockets.TcpClient; $c.Connect("127.0.0.1", $sync.RpcPort); $c.Close()
                $sync.RpcPort = 16801
                $sync.RpcUrl = "http://127.0.0.1:$($sync.RpcPort)/jsonrpc"
            } catch {}
        } catch {}
        $dd = if ($sync.DownloadDir) { $sync.DownloadDir } else { $env:TEMP }
        Ensure-Dir $dd
        $ariaArgs = @(
            "--enable-rpc=true", "--rpc-listen-port=$($sync.RpcPort)", "--rpc-secret=$($sync.RpcSecret)",
            "--rpc-listen-all=false", "--rpc-allow-origin-all=true", "--dir=`"$dd`"",
            "--continue=true", "--max-connection-per-server=16", "--split=16",
            "--min-split-size=1M", "--max-concurrent-downloads=3"
        )
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $sync.Aria2Exe; $psi.Arguments = ($ariaArgs -join " ")
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $sync.Aria2Proc = [System.Diagnostics.Process]::Start($psi)
        Emit-Status "启动 aria2 RPC…"
        $ok = $false
        for ($i = 0; $i -lt 10; $i++) {
            Start-Sleep -Milliseconds 500
            $v = Invoke-Rpc -Method "aria2.getVersion"
            if ($v -and $v.result) { $ok = $true; break }
        }
        if (!$ok) { throw "aria2 RPC 启动失败" }
        Emit-Log "aria2 RPC 就绪（并发 3）" 'OK'
    }

    function Download-FileSimple {
        param([string]$Url, [string]$OutFile, [string]$Label = "下载", [int]$TimeoutSec = 60)
        Add-Type -AssemblyName System.Net.Http
        $handler = New-Object System.Net.Http.HttpClientHandler; $handler.AllowAutoRedirect = $true
        $client = New-Object System.Net.Http.HttpClient($handler); $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
        try {
            $resp = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            $resp.EnsureSuccessStatusCode()
            $total = $resp.Content.Headers.ContentLength; if (!$total) { $total = 0 }
            $stream = $resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            $fs = [System.IO.File]::Create($OutFile)
            $buf = New-Object byte[] 81920; $readTotal = 0; $last = [DateTime]::MinValue
            try {
                while (($r = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
                    if ($sync.Cancel) { throw "用户已取消" }
                    $fs.Write($buf, 0, $r); $readTotal += $r
                    $now = Get-Date
                    if (($now - $last).TotalMilliseconds -ge 300) {
                        $last = $now
                        if ($total -gt 0) { $pct = [int][math]::Round($readTotal / $total * 100); Emit-Progress -Value $pct; Emit-Status "$Label | $pct% | $(Format-Size $readTotal) / $(Format-Size $total)" }
                    }
                }
            } finally { $fs.Close(); $fs.Dispose(); $stream.Close(); $stream.Dispose(); $resp.Dispose() }
        } finally { $client.Dispose(); $handler.Dispose() }
    }

    function Ensure-Aria2 {
        if (Test-Path $sync.Aria2Exe) { return $true }
        Emit-Log "未找到 aria2，正在下载…" 'Warn'
        Ensure-Dir $sync.Aria2Dir
        $zip = Join-Path $sync.Aria2Dir "aria2.zip"
        $ok = $false
        foreach ($u in $sync.Aria2Urls) {
            try {
                if (Test-Path $zip) { Remove-Item $zip -Force -ErrorAction SilentlyContinue }
                Emit-Log "尝试：$u"
                Download-FileSimple -Url $u -OutFile $zip -Label "下载 aria2" -TimeoutSec 60
                if (!(Test-Path $zip)) { throw "下载后文件不存在" }
                $sz = (Get-Item $zip).Length
                if ($sz -lt 1MB) { throw "下载的文件太小（$sz 字节）" }
                $fs = [System.IO.File]::OpenRead($zip)
                try {
                    $header = New-Object byte[] 4
                    $null = $fs.Read($header, 0, 4)
                    if ($header[0] -ne 0x50 -or $header[1] -ne 0x4B) { throw "文件头不是 PK" }
                } finally { $fs.Dispose() }
                $null = Expand-Archive -Path $zip -DestinationPath $sync.Aria2Dir -Force
                $exe = Get-ChildItem -Path $sync.Aria2Dir -Filter "aria2c.exe" -Recurse | Select-Object -First 1
                if ($exe -and $exe.FullName -ne $sync.Aria2Exe) { Move-Item $exe.FullName $sync.Aria2Exe -Force }
                Remove-Item $zip -Force -ErrorAction SilentlyContinue
                $ok = $true; break
            } catch { Emit-Log "失败：$($_.Exception.Message)" 'Warn' }
        }
        if (!$ok) { throw "无法下载 aria2" }
        Emit-Log "aria2 就绪" 'OK'
        return $true
    }

    function Ensure-Ventoy {
        if (Test-Path $sync.VentoyExe) { Emit-Log "Ventoy 已存在" 'OK'; return $true }
        Emit-Log "正在下载 Ventoy v$($sync.VentoyVersion)…" 'Warn'
        Ensure-Dir $sync.VentoyDir
        $zip = Join-Path $sync.DataDir "ventoy.zip"
        $ok = $false
        foreach ($u in $sync.VentoyUrls) {
            try {
                if (Test-Path $zip) { Remove-Item $zip -Force -ErrorAction SilentlyContinue }
                Emit-Log "尝试：$u"
                Download-FileSimple -Url $u -OutFile $zip -Label "下载 Ventoy" -TimeoutSec 120
                if (!(Test-Path $zip)) { throw "下载后文件不存在" }
                $sz = (Get-Item $zip).Length
                if ($sz -lt 1MB) { throw "文件太小" }
                $null = Expand-Archive -Path $zip -DestinationPath $sync.VentoyDir -Force
                Remove-Item $zip -Force -ErrorAction SilentlyContinue
                $ok = $true; break
            } catch { Emit-Log "失败：$($_.Exception.Message)" 'Warn' }
        }
        if (!$ok) { throw "无法下载 Ventoy" }
        $found = Get-ChildItem -Path $sync.VentoyDir -Filter "Ventoy2Disk.exe" -Recurse | Select-Object -First 1
        if ($found) { $p = $found.Directory.FullName; if ($p -ne $sync.VentoyDir) { Get-ChildItem $p | Move-Item -Destination $sync.VentoyDir -Force }; Emit-Log "Ventoy 就绪" 'OK'; return $true }
        throw "Ventoy2Disk.exe 未找到"
    }

    function Query-FromApi {
        param([string]$W, [string]$R, [string]$E, [string]$L, [string]$A)
        try {
            $b = @{ action = "query"; api_key = $sync.ApiKey; windows_version = $W; release = $R; edition = $E; language = $L; arch = $A; client_id = $sync.ClientId; client_version = $sync.AppVersion } | ConvertTo-Json -Compress
            $resp = Invoke-RestMethod -Uri $sync.ApiBase -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($b)) -ContentType "application/json; charset=utf-8" -TimeoutSec 10
            if ($resp.success -and $resp.data) { return $resp.data }
        } catch {}
        return $null
    }

    function Install-VentoyAsync {
        param([int]$DiskNumber)
        $argStr = "VTOYCLI /I /PhyDrive:$DiskNumber /FS:exFAT"
        Emit-Log "执行：Ventoy2Disk.exe $argStr" 'Warn'
        $percentFile = Join-Path $sync.VentoyDir "cli_percent.txt"
        $doneFile    = Join-Path $sync.VentoyDir "cli_done.txt"
        $logFile     = Join-Path $sync.VentoyDir "cli_log.txt"
        foreach ($f in @($percentFile, $doneFile)) { if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue } }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $sync.VentoyExe; $psi.Arguments = $argStr
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.WorkingDirectory = $sync.VentoyDir
        $proc = [System.Diagnostics.Process]::Start($psi)
        Emit-Log "Ventoy 进程已启动，PID=$($proc.Id)"

        $startTime = Get-Date
        $installed = $false
        while ($true) {
            if ($sync.Cancel) { try { $proc.Kill() } catch {}; throw "用户已取消" }
            if (((Get-Date) - $startTime).TotalSeconds -gt 180) { try { $proc.Kill() } catch {}; throw "Ventoy 安装超时" }
            if (Test-Path $percentFile) {
                try { $s = (Get-Content $percentFile -Raw -ErrorAction SilentlyContinue).Trim(); $p = 0; if ([int]::TryParse($s, [ref]$p)) { Emit-Progress -Value $p; Emit-Status "Ventoy 安装中… $p%" } } catch {}
            }
            if (Test-Path $doneFile) {
                $result = (Get-Content $doneFile -Raw).Trim()
                Remove-Item $doneFile -Force -ErrorAction SilentlyContinue
                if (Test-Path $logFile) { Get-Content $logFile -Tail 5 -ErrorAction SilentlyContinue | ForEach-Object { Emit-Log "  [ventoy] $_" } }
                if ($result -eq "0") { Emit-Log "Ventoy 安装成功！" 'OK'; $installed = $true; break }
                else { Emit-Log "Ventoy 安装失败（cli_done=$result）" 'Error'; return $false }
            }
            if ($proc.HasExited -and !(Test-Path $doneFile)) {
                Start-Sleep -Seconds 2
                if (Test-Path $doneFile) { continue }
                Emit-Log "Ventoy 进程退出但未生成 cli_done.txt" 'Error'
                return $false
            }
            Start-Sleep -Milliseconds 400
        }

        if ($installed) {
            try {
                Start-Sleep -Seconds 3
                $newDisks = @(Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -eq 'USB' -and -not $_.IsBoot -and -not $_.IsSystem } | Sort-Object Number)
                $targetDisk = $newDisks | Where-Object { $_.Number -eq $DiskNumber } | Select-Object -First 1
                if ($targetDisk) {
                    $vol = Get-Partition -DiskNumber $targetDisk.Number -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | Select-Object -First 1
                    if ($vol) {
                        try {
                            Set-Volume -DriveLetter $vol.DriveLetter -NewFileSystemLabel "WinISO" -ErrorAction Stop
                            Emit-Log "已设置卷标为 WinISO（$($vol.DriveLetter):）" 'OK'
                        } catch {
                            Emit-Log "设置卷标失败（不影响启动盘功能）：$($_.Exception.Message)" 'Warn'
                        }
                    }
                }
            } catch {
                Emit-Log "设置卷标异常（不影响启动盘功能）：$($_.Exception.Message)" 'Warn'
            }
        }
        return $installed
    }

    # ===== U 盘空间预检辅助函数 =====
    function Get-RequiredBytesForIsos {
        param([array]$AllIsos)
        $total = 0L
        foreach ($iso in $AllIsos) {
            if (Test-Path -LiteralPath $iso) {
                try { $total += (Get-Item -LiteralPath $iso).Length } catch {}
            }
        }
        return $total
    }

    function Test-UsbDiskSpace {
        param(
            [long]$RequiredBytes,
            [int]$DiskNumber,
            [bool]$VentoyFresh,
            [string]$DriveLetter = ""
        )

        if ($RequiredBytes -le 0) { return $true }

        $usable = 0L
        $source = ""

        if ($VentoyFresh) {
            $disk = Get-Disk -Number $DiskNumber -ErrorAction SilentlyContinue
            if ($disk) {
                $usable = [long]$disk.Size - 64MB
                $source = "磁盘 $DiskNumber 总容量 $(Format-Size ([long]$disk.Size)) 减去预留"
            }
        } else {
            if ($DriveLetter) {
                try {
                    $di = New-Object System.IO.DriveInfo("$($DriveLetter.TrimEnd('\'))\")
                    if ($di.IsReady) { $usable = [long]$di.AvailableFreeSpace; $source = "$DriveLetter 可用空间" }
                } catch {}
            }
            if ($usable -le 0 -and $DiskNumber -ge 0) {
                $vol = Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | Select-Object -First 1
                if ($vol) {
                    try {
                        $di = New-Object System.IO.DriveInfo("$($vol.DriveLetter):\")
                        if ($di.IsReady) { $usable = [long]$di.AvailableFreeSpace; $source = "$($vol.DriveLetter): 可用空间" }
                    } catch {}
                }
            }
        }

        if ($usable -le 0) {
            Emit-Log "无法获取 U 盘可用空间（$source 为空），跳过空间预检" 'Warn'
            return $true
        }

        if ($RequiredBytes -gt $usable) {
            Emit-Log ("U 盘空间不足：需要 {0}，可用 {1}（相差 {2}）" -f `
                (Format-Size $RequiredBytes), (Format-Size $usable), (Format-Size ($RequiredBytes - $usable))) 'Error'
            return $false
        }

        Emit-Log ("U 盘空间充足：需要 {0}，可用 {1}（来源：{2}）" -f `
            (Format-Size $RequiredBytes), (Format-Size $usable), $source) 'OK'
        return $true
    }

    function Copy-IsosToUsb {
        param([array]$AllIsos, [string]$TargetDrive)
        Emit-Log "开始复制 ISO 到 $TargetDrive" 'Step'

        $totalBytes = 0L
        foreach ($iso in $AllIsos) { if (Test-Path -LiteralPath $iso) { try { $totalBytes += (Get-Item -LiteralPath $iso).Length } catch {} } }

        $copyUsable = 0L
        try {
            $di = New-Object System.IO.DriveInfo("$($TargetDrive.TrimEnd('\'))\")
            if ($di.IsReady) { $copyUsable = [long]$di.AvailableFreeSpace }
        } catch {}
        if ($copyUsable -le 0) {
            Emit-Log "无法读取 $TargetDrive 可用空间，跳过精确预检（继续复制）" 'Warn'
        } elseif ($totalBytes -gt $copyUsable) {
            Emit-Log ("复制前空间不足：需要 {0}，{1} 可用 {2}（相差 {3}）" -f `
                (Format-Size $totalBytes), $TargetDrive, (Format-Size $copyUsable), (Format-Size ($totalBytes - $copyUsable))) 'Error'
            throw "目标盘空间不足，已中止复制"
        } else {
            Emit-Log ("复制前空间检查通过：需要 {0}，可用 {1}" -f (Format-Size $totalBytes), (Format-Size $copyUsable)) 'OK'
        }

        $readBytes = 0L
        $lastEmit = [DateTime]::MinValue
        foreach ($iso in $AllIsos) {
            if ($sync.Cancel) { throw "用户已取消" }
            $fn = Split-Path $iso -Leaf
            $dest = Join-Path "$TargetDrive\" $fn
            Emit-Status "复制 $fn …"
            $src = [System.IO.File]::OpenRead($iso); $dst = [System.IO.File]::Create($dest)
            $buf = [byte[]]::new(4MB); $total = $src.Length
            try {
                while (($r = $src.Read($buf, 0, $buf.Length)) -gt 0) {
                    if ($sync.Cancel) { throw "用户已取消" }
                    $dst.Write($buf, 0, $r); $readBytes += $r
                    $now = Get-Date
                    if (($now - $lastEmit).TotalMilliseconds -ge 300) {
                        $lastEmit = $now
                        $pct = if ($totalBytes -gt 0) { [int][math]::Round($readBytes / $totalBytes * 100) } else { 0 }
                        Emit-Progress -Value $pct
                        Emit-Status "复制 $fn | 总进度 $pct%"
                    }
                }
            } finally { $src.Close(); $src.Dispose(); $dst.Close(); $dst.Dispose() }
            $copiedSize = (Get-Item $dest).Length
            Emit-Log "复制完成：$fn（$(Format-Size $copiedSize)）" 'OK'
        }
    }

    function Get-LinksForTask {
        param($t)
        Emit-Status "正在从 API 获取下载链接…"
        $api = Query-FromApi $t.Win $t.Rel $t.Ed $t.Lang.Name $t.Arch
        if ($api -and $api.links) {
            $links = @()
            foreach ($l in $api.links) { $links += [PSCustomObject]@{ Arch = $l.arch; Url = $l.url } }
            Emit-Log "API 获取成功（$($links.Count) 个链接）" 'OK'
            return $links
        }
        return @()
    }

    try {
        Emit-Log "===== 开始任务 =====" 'OK'
        Emit-Log "系统数量：$($sync.Tasks.Count)"

        # 网络连通性预检
        Emit-Status "检查网络连通性…"
        try {
            $null = Invoke-WebRequest -Uri $sync.ApiBase -Method Head -TimeoutSec 8 -UseBasicParsing -ErrorAction Stop
            Emit-Log "API 连通性检查通过" 'OK'
        } catch {
            Emit-Log "API 连通性检查改成Warn" 'Warn'
        }

        Ensure-Aria2 | Out-Null
        if (!$sync.Aria2Proc -or $sync.Aria2Proc.HasExited) { Start-Aria2Rpc }

        $allIsos = @()
        $skippedFiles = @()
        foreach ($t in $sync.Tasks) {
            if ($sync.Cancel) { throw "用户已取消" }

            if ($t.IsWinPE) {
                Emit-Status "正在验证 WinPE 下载链接…"
                $check = Test-DownloadUrl -Url $sync.WinPEUrl
                if (-not $check.Valid) {
                    Emit-Log "WinPE 链接无效（$($check.Error)），跳过" 'Error'
                    $skippedFiles += [PSCustomObject]@{ Task = $t; Reason = $check.Error }
                    continue
                }
                $sizeText = if ($check.Size -gt 0) { "（$(Format-Size $check.Size)）" } else { "" }
                Emit-Log "WinPE 链接有效：$($sync.WinPEFileName) $sizeText" 'OK'

                Emit-Status "正在提交 WinPE 任务…"
                $opts = @{ "dir" = $sync.DownloadDir; "out" = $sync.WinPEFileName; "split" = "16"; "max-connection-per-server" = "16"; "min-split-size" = "1M"; "user-agent" = "Mozilla/5.0" }
                $r = Invoke-Rpc -Method "aria2.addUri" -Params @(@($sync.WinPEUrl), $opts)
                if ($r -and $r.result) {
                    $sync.ActiveTasks[$r.result] = @{ FileName = $sync.WinPEFileName; DestDir = $sync.DownloadDir; IsWinPE = $true; Task = $t }
                    Emit-Log "WinPE 任务已提交：$($sync.WinPEFileName)" 'OK'
                } else {
                    Emit-Log "WinPE 任务提交失败" 'Error'
                    $skippedFiles += [PSCustomObject]@{ Task = $t; Reason = "aria2 提交失败" }
                }
                continue
            }

            $win = $t.Win; $arch = $t.Arch
            $links = Get-LinksForTask -t $t

            if (!$links -or $links.Count -eq 0) {
                Emit-Log "跳过 $win：API 未返回下载链接" 'Error'
                $skippedFiles += [PSCustomObject]@{ Task = $t; Reason = "API 未返回链接" }
                continue
            }

            $link = $links | Where-Object { $_.Arch -eq $arch } | Select-Object -First 1
            if (!$link) { $link = $links[0] }
            $fileName = [System.IO.Path]::GetFileName(($link.Url -split '\?')[0])

            Emit-Status "正在验证下载链接：$fileName …"
            $check = Test-DownloadUrl -Url $link.Url
            if (-not $check.Valid) {
                Emit-Log "链接无效（$($check.Error)），跳过：$fileName" 'Error'
                $skippedFiles += [PSCustomObject]@{ Task = $t; Reason = "链接无效" }
                continue
            }

            $sizeText = if ($check.Size -gt 0) { "（$(Format-Size $check.Size)）" } else { "" }
            Emit-Log "链接有效：$fileName $sizeText" 'OK'

            $opts = @{ "dir" = $sync.DownloadDir; "out" = $fileName; "split" = "16"; "max-connection-per-server" = "16"; "min-split-size" = "1M"; "user-agent" = "Mozilla/5.0" }
            $r = Invoke-Rpc -Method "aria2.addUri" -Params @(@($link.Url), $opts)
            if ($r -and $r.result) {
                $sync.ActiveTasks[$r.result] = @{ FileName = $fileName; DestDir = $sync.DownloadDir; IsWinPE = $false; Task = $t }
                Emit-Log "任务已提交：$fileName" 'OK'
            } else {
                Emit-Log "任务提交失败：$fileName" 'Error'
                $skippedFiles += [PSCustomObject]@{ Task = $t; Reason = "aria2 提交失败" }
            }
        }

        Emit-Log "等待下载完成…" 'Step'
        while ($sync.ActiveTasks.Count -gt 0) {
            if ($sync.Cancel) { throw "用户已取消" }
            Start-Sleep -Milliseconds 500
            $gids = @($sync.ActiveTasks.Keys)
            $totalSpeed = 0L; $totalDone = 0L; $totalSize = 0L
            foreach ($gid in $gids) {
                $st = Invoke-Rpc -Method "aria2.tellStatus" -Params @($gid, @("status","totalLength","completedLength","downloadSpeed"))
                if (!$st -or !$st.result) { continue }
                $r = $st.result
                $totalSpeed += [long]$r.downloadSpeed; $totalDone += [long]$r.completedLength; $totalSize += [long]$r.totalLength
                $task = $sync.ActiveTasks[$gid]
                if ($r.status -eq "complete") {
                    $isoPath = Join-Path $task.DestDir $task.FileName
                    if (Test-Path $isoPath) {
                        $fileSize = (Get-Item $isoPath).Length
                        $expectedSize = [long]$r.totalLength
                        if ($expectedSize -gt 0 -and [math]::Abs($fileSize - $expectedSize) -gt 1MB) {
                            Emit-Log "文件大小异常：$($task.FileName) 实际 $(Format-Size $fileSize) / 期望 $(Format-Size $expectedSize)" 'Error'
                            try { Remove-Item $isoPath -Force -ErrorAction SilentlyContinue } catch {}
                            $skippedTask = $task.Task
                            if (!$skippedTask) { $skippedTask = [PSCustomObject]@{ IsWinPE = $task.IsWinPE; DisplayName = $task.FileName } }
                            $skippedFiles += [PSCustomObject]@{ Task = $skippedTask; Reason = "文件大小不符" }
                            $sync.ActiveTasks.Remove($gid)
                            continue
                        }
                        $allIsos += $isoPath
                        $ariaFile = "$isoPath.aria2"
                        if (Test-Path $ariaFile) { Remove-Item $ariaFile -Force -ErrorAction SilentlyContinue }
                        Emit-Log "下载完成：$($task.FileName)（$(Format-Size $fileSize)）" 'OK'
                    }
                    $sync.ActiveTasks.Remove($gid)
                } elseif ($r.status -eq "error") {
                    $sync.ActiveTasks.Remove($gid)
                    Emit-Log "下载失败（已跳过）：$($task.FileName)" 'Error'
                    $skippedTask = $task.Task
                    if (!$skippedTask) { $skippedTask = [PSCustomObject]@{ IsWinPE = $task.IsWinPE; DisplayName = $task.FileName } }
                    $skippedFiles += [PSCustomObject]@{ Task = $skippedTask; Reason = "下载失败" }
                } elseif ($r.status -eq "removed") { $sync.ActiveTasks.Remove($gid) }
            }
            if ($totalSize -gt 0) {
                $pct = [int][math]::Round($totalDone / $totalSize * 100)
                Emit-Progress -Value $pct
                Emit-Status "下载中 | $pct% | $(Format-Size $totalDone) / $(Format-Size $totalSize) | $(Format-Speed $totalSpeed)"
            }
        }
        Emit-Log "全部下载完成（$($allIsos.Count) 个 ISO）" 'OK'
        if ($skippedFiles.Count -gt 0) {
            Emit-Log "跳过的文件（$($skippedFiles.Count) 个）：" 'Warn'
            foreach ($sf in $skippedFiles) {
                $name = if ($sf.Task -and $sf.Task.IsWinPE) { "WinPE" } else { $sf.Task.DisplayName }
                Emit-Log "  • $name（$($sf.Reason)）" 'Warn'
            }
        }

        if ($allIsos.Count -eq 0) { throw "没有成功下载任何 ISO" }

        if ($sync.UsbDiskNumber -ge 0) {
            $requiredBytes = Get-RequiredBytesForIsos -AllIsos $allIsos
            if ($requiredBytes -gt 0) {
                $freshMode = [bool]$sync.VentoyEnabled
                if (-not (Test-UsbDiskSpace -RequiredBytes $requiredBytes -DiskNumber $sync.UsbDiskNumber -VentoyFresh $freshMode)) {
                    throw "U 盘空间不足，已中止制盘。请更换更大容量的 U 盘，或减少勾选的系统。"
                }
            } else {
                Emit-Log "ISO 总大小为 0，跳过空间预检" 'Warn'
            }
        }

        $ventoyOk = $true
        if ($sync.VentoyEnabled -and $sync.UsbDiskNumber -ge 0) {
            Emit-Log "===== Ventoy 启动盘制作 =====" 'OK'
            Ensure-Ventoy | Out-Null
            $ventoyOk = Install-VentoyAsync -DiskNumber $sync.UsbDiskNumber
            if (-not $ventoyOk) {
                Emit-Log "Ventoy 安装失败" 'Error'
                $sync.VentoyFailedChoice = $null
                Send-Msg ([PSCustomObject]@{ Type = 'ConfirmVentoyFailed' })
                $waitDeadline = (Get-Date).AddMinutes(5)
                while ($null -eq $sync.VentoyFailedChoice -and (Get-Date) -lt $waitDeadline) {
                    if ($sync.Cancel) { throw "用户已取消" }
                    Start-Sleep -Milliseconds 300
                }
                if ($sync.VentoyFailedChoice -eq $true) {
                    Emit-Log "用户选择跳过 Ventoy，直接复制 ISO 到 U 盘根目录" 'Warn'
                    $ventoyOk = $false
                } else {
                    throw "Ventoy 安装失败，用户取消"
                }
            } else {
                $ventoyOk = $true
            }
        }

        if ($ventoyOk -and $sync.VentoyEnabled -and $sync.UsbDiskNumber -ge 0) {
            Start-Sleep -Seconds 3
            $newDisks = @(Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -eq 'USB' -and -not $_.IsBoot -and -not $_.IsSystem } | Sort-Object Number)
            $targetDisk = $newDisks | Where-Object { $_.Number -eq $sync.UsbDiskNumber } | Select-Object -First 1
            $targetDrive = $null
            if ($targetDisk) {
                $vol = Get-Partition -DiskNumber $targetDisk.Number -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | Select-Object -First 1
                if ($vol) { $targetDrive = "$($vol.DriveLetter):" }
            }
            if ($targetDrive) {
                Copy-IsosToUsb -AllIsos $allIsos -TargetDrive $targetDrive
            } else {
                Emit-Log "Ventoy 格式化后未找到盘符，跳过复制" 'Warn'
            }
        } elseif ($sync.UsbDiskNumber -ge 0) {
            $targetDisk = Get-Disk -Number $sync.UsbDiskNumber -ErrorAction SilentlyContinue
            $targetDrive = $null
            if ($targetDisk) {
                $vol = Get-Partition -DiskNumber $targetDisk.Number -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | Select-Object -First 1
                if ($vol) { $targetDrive = "$($vol.DriveLetter):" }
            }
            if ($targetDrive) {
                Copy-IsosToUsb -AllIsos $allIsos -TargetDrive $targetDrive
            }
        }

        $totalElapsed = (Get-Date) - $scriptStartTime
        Emit-Log "===== 全部完成（总耗时 $(Format-Duration $totalElapsed)）=====" 'OK'
        Send-Msg ([PSCustomObject]@{
            Type = 'Done'
            Success = $true
            SkippedFiles = @($skippedFiles | ForEach-Object {
                if ($_.Task -and $_.Task.IsWinPE) { @{ DisplayName = "WinPE"; Reason = $_.Reason } }
                elseif ($_.Task -and $_.Task.DisplayName) { @{ DisplayName = $_.Task.DisplayName; Reason = $_.Reason } }
                else { @{ DisplayName = "未知任务"; Reason = $_.Reason } }
            })
        })
    }
    catch {
        if ($sync.Cancel) {
            Emit-Log "用户已取消任务" 'Warn'
            Send-Msg ([PSCustomObject]@{ Type = 'Done'; Success = $false; Cancelled = $true })
        } else {
            $errMsg   = $_.Exception.Message
            $errFull  = $_.ToString()
            Emit-Log "任务失败：$errMsg" 'Error'
            Send-Msg ([PSCustomObject]@{
                Type      = 'Done'
                Success   = $false
                Error     = $errMsg
                ErrorFull = $errFull
            })
        }
    }
    finally {
        try { Invoke-Rpc -Method "aria2.shutdown" | Out-Null } catch {}
        try { if ($sync.Aria2Proc -and !$sync.Aria2Proc.HasExited) { $sync.Aria2Proc.WaitForExit(3000) | Out-Null; if (!$sync.Aria2Proc.HasExited) { $sync.Aria2Proc.Kill() } } } catch {}
    }
}

# ============================================================
# 6. UI
# ============================================================
[xml]$script:Xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$AppTitle" Height="720" Width="1100" WindowStartupLocation="CenterScreen" Background="#F3F3F3" FontFamily="Microsoft YaHei UI, Segoe UI">
    <Window.Resources>
        <Style TargetType="Button"><Setter Property="Background" Value="#0067C0"/><Setter Property="Foreground" Value="White"/><Setter Property="Padding" Value="12,6"/><Setter Property="BorderThickness" Value="0"/><Setter Property="FontSize" Value="13"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border Background="{TemplateBinding Background}" CornerRadius="5" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border></ControlTemplate></Setter.Value></Setter></Style>
        <Style TargetType="ComboBox"><Setter Property="Padding" Value="6,4"/><Setter Property="FontSize" Value="13"/><Setter Property="Background" Value="White"/><Setter Property="BorderBrush" Value="#E0E0E0"/></Style>
        <Style TargetType="TextBox"><Setter Property="Padding" Value="6,4"/><Setter Property="FontSize" Value="13"/><Setter Property="Background" Value="White"/><Setter Property="BorderBrush" Value="#E0E0E0"/><Setter Property="BorderThickness" Value="1"/></Style>
        <Style TargetType="ProgressBar"><Setter Property="Height" Value="8"/><Setter Property="Foreground" Value="#0067C0"/><Setter Property="Background" Value="#E0E0E0"/><Setter Property="BorderThickness" Value="0"/></Style>
    </Window.Resources>
    <Grid Margin="16">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Margin="0,0,0,12">
            <TextBlock Foreground="#1F1F1F">
                <Run Text="WinISO安装助手" FontSize="22" FontWeight="SemiBold"/>
                <Run Text="  ·  一键制作多系统启动盘" FontSize="16" FontWeight="Normal" Foreground="#666666"/>
            </TextBlock>
            <TextBlock Text="Windows ISO Downloader 微软直链镜像 · WinPE 工具箱 · aria2加速下载" FontSize="12" Foreground="#666666" Margin="0,2,0,0"/>
        </StackPanel>
        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions><ColumnDefinition Width="360"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Border Grid.Column="0" Background="White" CornerRadius="10" Padding="14" BorderBrush="#E5E5E5" BorderThickness="1">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="选择系统（可多选）" FontWeight="SemiBold" FontSize="12" Foreground="#666666" Margin="0,0,0,6"/>
                    <Border Grid.Row="1" Background="#FAFBFC" BorderBrush="#E5E7EB" BorderThickness="1" CornerRadius="8" Padding="6">
                        <ListBox Name="LstSystems" Background="Transparent" BorderThickness="0"
                                 ScrollViewer.HorizontalScrollBarVisibility="Disabled"
                                 ScrollViewer.VerticalScrollBarVisibility="Auto">
                            <ListBox.ItemContainerStyle>
                                <Style TargetType="ListBoxItem">
                                    <Setter Property="Margin" Value="0,2"/>
                                    <Setter Property="Padding" Value="0"/>
                                    <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
                                    <Setter Property="Template">
                                        <Setter.Value>
                                            <ControlTemplate TargetType="ListBoxItem">
                                                <Border x:Name="Bd" Background="White" CornerRadius="6" Padding="10,7"
                                                        BorderBrush="#E5E7EB" BorderThickness="1">
                                                    <ContentPresenter/>
                                                </Border>
                                                <ControlTemplate.Triggers>
                                                    <Trigger Property="IsMouseOver" Value="True">
                                                        <Setter TargetName="Bd" Property="Background" Value="#EEF4FF"/>
                                                        <Setter TargetName="Bd" Property="BorderBrush" Value="#BFD3F0"/>
                                                    </Trigger>
                                                    <DataTrigger Binding="{Binding IsSelected}" Value="True">
                                                        <Setter TargetName="Bd" Property="Background" Value="#E6F0FF"/>
                                                        <Setter TargetName="Bd" Property="BorderBrush" Value="#0067C0"/>
                                                    </DataTrigger>
                                                </ControlTemplate.Triggers>
                                            </ControlTemplate>
                                        </Setter.Value>
                                    </Setter>
                                </Style>
                            </ListBox.ItemContainerStyle>
                            <ListBox.ItemTemplate>
                                <DataTemplate>
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="Auto"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <CheckBox Grid.Column="0" IsChecked="{Binding IsSelected, Mode=TwoWay}"
                                                  VerticalAlignment="Center" Margin="0,0,8,0"/>
                                        <TextBlock Grid.Column="1" Text="{Binding DisplayName}" FontSize="12" Foreground="#1F2937"
                                                   VerticalAlignment="Center" TextWrapping="Wrap"/>
                                    </Grid>
                                </DataTemplate>
                            </ListBox.ItemTemplate>
                        </ListBox>
                    </Border>
                    <StackPanel Grid.Row="2" Margin="0,10,0,0">
                        <TextBlock Text="语言" FontWeight="SemiBold" FontSize="13" Margin="0,0,0,4"/><ComboBox Name="CmbLanguage" Margin="0,0,0,10" Height="30"/>
                        <TextBlock Text="下载目录" FontWeight="SemiBold" FontSize="13" Margin="0,0,0,4"/>
                        <Grid Margin="0,0,0,10"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBox Name="TxtDownloadDir" Grid.Column="0" Height="30" VerticalContentAlignment="Center"/><Button Name="BtnBrowse" Grid.Column="1" Content="浏览" Width="56" Height="30" Margin="6,0,0,0" Background="#E0E0E0" Foreground="#333"/></Grid>
                        <TextBlock Text="目标 U 盘" FontWeight="SemiBold" FontSize="13" Margin="0,0,0,4"/>
                        <Grid Margin="0,0,0,10"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><ComboBox Name="CmbUsbDisk" Grid.Column="0" Height="30"/><Button Name="BtnRefreshUsb" Grid.Column="1" Content="刷新" Width="56" Height="30" Margin="6,0,0,0" Background="#E0E0E0" Foreground="#333" FontSize="12"/></Grid>
                        <Separator Margin="0,4,0,10"/><CheckBox Name="ChkVentoy" Content="全新制作（格式化 U 盘）" IsChecked="True" FontSize="12.5" Margin="0,0,0,4"/>
                        <TextBlock Text="勾选：下载完成后先格式化 U 盘装 Ventoy 再拷系统；不勾选：只把系统拷到已装 Ventoy 的 U 盘" FontSize="10.5" Foreground="#888" TextWrapping="Wrap"/>
                    </StackPanel>
                </Grid>
            </Border>
            <Border Grid.Column="2" Background="White" CornerRadius="10" Padding="12" BorderBrush="#E5E5E5" BorderThickness="1">
                <Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
                    <Grid Grid.Row="0" Margin="0,0,0,8"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Grid.Column="0" Text="运行日志" FontWeight="SemiBold" FontSize="13" VerticalAlignment="Center"/><CheckBox Name="ChkAutoScroll" Grid.Column="1" Content="自动滚动" IsChecked="True" FontSize="12" VerticalAlignment="Center" Margin="0,0,8,0"/><Button Name="BtnExportLog" Grid.Column="2" Content="导出日志" Width="76" Height="28" Background="#E0E0E0" Foreground="#333" FontSize="12" Margin="0,0,6,0"/><Button Name="BtnClearLog" Grid.Column="3" Content="清空日志" Width="76" Height="28" Background="#E0E0E0" Foreground="#333" FontSize="12"/></Grid>
                    <Border Grid.Row="1" Background="#1E1E1E" CornerRadius="6" Padding="2"><RichTextBox Name="TxtLog" Background="Transparent" Foreground="#D4D4D4" FontFamily="Consolas, Courier New" FontSize="11" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" BorderThickness="0" IsReadOnly="True" Padding="6"/></Border>
                </Grid>
            </Border>
        </Grid>
        <Grid Grid.Row="2" Margin="0,12,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" VerticalAlignment="Center" Margin="0,0,12,0"><ProgressBar Name="PrgDownload" Value="0" Maximum="100" Margin="0,0,0,6"/><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Name="TxtStatus" Grid.Column="0" FontSize="12" Foreground="#666666" Text="就绪" TextTrimming="CharacterEllipsis"/><TextBlock Name="TxtSpeed" Grid.Column="1" FontSize="12" Foreground="#0067C0" FontWeight="SemiBold" Margin="8,0,0,0"/></Grid></StackPanel>
            <Button Name="BtnDownload" Grid.Column="1" Content="开始安装" Width="140" Height="36" VerticalAlignment="Center"/>
        </Grid>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $script:Xaml
$script:Window = [Windows.Markup.XamlReader]::Load($reader)

$script:LstSystems = $script:Window.FindName("LstSystems"); $script:CmbLanguage = $script:Window.FindName("CmbLanguage"); $script:TxtDownloadDir = $script:Window.FindName("TxtDownloadDir"); $script:BtnBrowse = $script:Window.FindName("BtnBrowse"); $script:ChkVentoy = $script:Window.FindName("ChkVentoy"); $script:CmbUsbDisk = $script:Window.FindName("CmbUsbDisk"); $script:BtnRefreshUsb = $script:Window.FindName("BtnRefreshUsb"); $script:BtnDownload = $script:Window.FindName("BtnDownload"); $script:TxtStatus = $script:Window.FindName("TxtStatus"); $script:TxtSpeed = $script:Window.FindName("TxtSpeed"); $script:PrgDownload = $script:Window.FindName("PrgDownload"); $script:TxtLog = $script:Window.FindName("TxtLog"); $script:ChkAutoScroll = $script:Window.FindName("ChkAutoScroll"); $script:BtnClearLog = $script:Window.FindName("BtnClearLog"); $script:BtnExportLog = $script:Window.FindName("BtnExportLog")

$script:LogParagraph = New-Object System.Windows.Documents.Paragraph; $script:LogParagraph.Margin = New-Object System.Windows.Thickness(0)
$script:LogDoc = New-Object System.Windows.Documents.FlowDocument; $script:LogDoc.FontFamily = "Consolas, Courier New"; $script:LogDoc.FontSize = 11; $script:LogDoc.PagePadding = New-Object System.Windows.Thickness(0)
$script:TxtLog.Document = $script:LogDoc; $script:LogDoc.Blocks.Add($script:LogParagraph)

function Set-ControlsEnabled { param([bool]$E); $script:LstSystems.IsEnabled = $E; $script:CmbLanguage.IsEnabled = $E; $script:TxtDownloadDir.IsEnabled = $E; $script:BtnBrowse.IsEnabled = $E; $script:ChkVentoy.IsEnabled = $E; $script:CmbUsbDisk.IsEnabled = $E; $script:BtnRefreshUsb.IsEnabled = $E }

function Get-BtnIdleText {
    if ($script:ChkVentoy -and $script:ChkVentoy.IsChecked) { return "开始安装" }
    return "开始下载"
}
function Update-BtnIdleText {
    if (!$script:BtnDownload) { return }
    if ($script:DownloadState -eq "idle") {
        $script:BtnDownload.Content = Get-BtnIdleText
    }
}

function Get-UsbDisks {
    $list = @()
    try {
        $disks = Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -eq 'USB' -and -not $_.IsBoot -and -not $_.IsSystem } | Sort-Object Number
        foreach ($d in $disks) {
            $sizeGB = [math]::Round($d.Size / 1GB, 1)
            $label = "磁盘 $($d.Number)  |  $($d.FriendlyName)  |  $($sizeGB) GB"
            $vol = Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | Select-Object -First 1
            if ($vol) {
                $label += "  |  盘符 $($vol.DriveLetter):"
                try {
                    $di = New-Object System.IO.DriveInfo("$($vol.DriveLetter):\")
                    if ($di.IsReady) { $label += "  可用 {0:N1} GB" -f ($di.AvailableFreeSpace / 1GB) }
                } catch {}
            }
            $list += [PSCustomObject]@{ Label = $label; Number = $d.Number; SizeGB = $sizeGB; UniqueId = [string]$d.UniqueId; Model = [string]$d.FriendlyName }
        }
    } catch {}
    return $list
}

function Refresh-UsbList {
    try {
        $prevUniqueId = $null
        if ($script:CmbUsbDisk.SelectedItem -and $script:CmbUsbDisk.SelectedItem -isnot [string]) { $prevUniqueId = $script:CmbUsbDisk.SelectedItem.UniqueId }
        $script:CmbUsbDisk.Items.Clear(); $script:CmbUsbDisk.SelectedIndex = -1; $script:CmbUsbDisk.Text = ""
        $disks = @(Get-UsbDisks)
        if ($disks.Count -eq 0) {
            $script:CmbUsbDisk.Items.Add("（未检测到 USB 磁盘）") | Out-Null; $script:CmbUsbDisk.SelectedIndex = 0
            $script:UsbSignature = ""; Write-Log "未检测到可用 U 盘" "Warning"; return
        }
        $newSig = (($disks | ForEach-Object { "$($_.Number):$($_.UniqueId)" }) -join '|')
        if ($disks.Count -gt 1 -and $newSig -ne $script:UsbMultiAckedSignature) {
            try {
                $listText = ($disks | ForEach-Object { "  • $($_.Label)" }) -join [Environment]::NewLine
                $msg = "检测到 $($disks.Count) 个 USB 磁盘：`n`n$listText`n`n请确认只操作目标 U 盘，其他 U 盘不会被动。`n`n是否继续？"
                $ans = [System.Windows.Forms.MessageBox]::Show($msg, "多个 U 盘", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
                if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
                    $script:CmbUsbDisk.Items.Clear(); $script:CmbUsbDisk.SelectedIndex = -1; $script:CmbUsbDisk.Text = ""
                    $script:UsbSignature = $newSig
                    $script:UsbMultiAckedSignature = $newSig
                    Write-Log "检测到多个 U 盘，用户选择暂不继续（再次刷新前不再提示）" "Warning"; return
                }
                $script:UsbMultiAckedSignature = $newSig
                Write-Log "检测到多个 U 盘，用户确认继续" "Warning"
            } catch {}
        }
        foreach ($d in $disks) { $script:CmbUsbDisk.Items.Add($d) | Out-Null }
        $script:UsbSignature = $newSig
        if ($prevUniqueId) { for ($i = 0; $i -lt $disks.Count; $i++) { if ($disks[$i].UniqueId -eq $prevUniqueId) { $script:CmbUsbDisk.SelectedIndex = $i; break } } }
        if ($script:CmbUsbDisk.SelectedIndex -lt 0) { $script:CmbUsbDisk.SelectedIndex = 0 }
        Write-Log ("U 盘列表已刷新（{0} 个）" -f $disks.Count) "Success"
    } catch { Write-Log ("刷新失败：{0}" -f $_.Exception.Message) "Warning" }
}

function Start-UsbPolling {
    $script:UsbPollTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:UsbPollTimer.Interval = [TimeSpan]::FromSeconds(3)
    $script:UsbPollTimer.Add_Tick({
        if ($script:DownloadState -ne "idle") { return }
        try {
            $disks = @(Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -eq 'USB' -and -not $_.IsBoot -and -not $_.IsSystem } | Sort-Object Number)
            $sig = (($disks | ForEach-Object { "$($_.Number):$($_.UniqueId)" }) -join '|')
            if ($sig -ne $script:UsbSignature) { Refresh-UsbList }
        } catch {}
    })
    $script:UsbPollTimer.Start()
    Write-Log "已启动 U 盘轮询监听（3 秒间隔）" "Info"
}

# 加载配置
$cfg = Load-Config; if ($cfg -and $cfg.ClientId) { $script:ClientId = $cfg.ClientId }

# 系统列表
$systemList = [System.Collections.ArrayList]::new()
$savedKeys = if ($cfg -and $cfg.Selection -and $cfg.Selection.SelectedKeys) { @($cfg.Selection.SelectedKeys) } else { @() }
for ($i = 0; $i -lt $script:SystemOptions.Count; $i++) {
    $o = $script:SystemOptions[$i]
    $def = ($i -eq 0 -or $i -eq 2 -or $o.IsWinPE)
    $sel = if ($savedKeys.Count -gt 0) { $savedKeys -contains $o.DisplayName } else { $def }
    $null = $systemList.Add([PSCustomObject]@{ DisplayName = $o.DisplayName; Key = $o.DisplayName; Win = $o.Win; Rel = $o.Rel; Ed = $o.Ed; Arch = $o.Arch; IsWinPE = $o.IsWinPE; IsSelected = $sel })
}
$script:LstSystems.ItemsSource = $systemList

$script:CmbLanguage.ItemsSource = $script:CommonLanguages; $script:CmbLanguage.DisplayMemberPath = "DisplayName"; $script:CmbLanguage.SelectedIndex = 0
$script:CmbUsbDisk.DisplayMemberPath = "Label"
if ($cfg -and $cfg.Selection -and $cfg.Selection.LanguageName) { for ($i = 0; $i -lt $script:CommonLanguages.Count; $i++) { if ($script:CommonLanguages[$i].Name -eq $cfg.Selection.LanguageName) { $script:CmbLanguage.SelectedIndex = $i; break } } }
$script:TxtDownloadDir.Text = Get-DefaultDownloadDir -MinFreeSpace 10GB
if ($cfg -and $cfg.Selection -and $cfg.Selection.DownloadDir) { $script:TxtDownloadDir.Text = $cfg.Selection.DownloadDir }
if ($cfg -and $cfg.Selection -and $null -ne $cfg.Selection.UseVentoy) { $script:ChkVentoy.IsChecked = $cfg.Selection.UseVentoy }
if ($cfg -and $cfg.Selection -and $cfg.Selection.UsbUniqueId) {
    for ($i = 0; $i -lt $script:CmbUsbDisk.Items.Count; $i++) {
        $it = $script:CmbUsbDisk.Items[$i]
        if ($it -isnot [string] -and $it.UniqueId -eq $cfg.Selection.UsbUniqueId) { $script:CmbUsbDisk.SelectedIndex = $i; break }
    }
}

$script:BtnBrowse.add_Click({
    try {
        $d = New-Object System.Windows.Forms.FolderBrowserDialog
        $d.Description = "选择 ISO 保存目录"
        $initial = $script:TxtDownloadDir.Text
        if ([string]::IsNullOrWhiteSpace($initial) -or -not (Test-Path $initial -PathType Container)) { $initial = [Environment]::GetFolderPath("MyDocuments") }
        if (-not [string]::IsNullOrWhiteSpace($initial) -and (Test-Path $initial -PathType Container)) { $d.SelectedPath = $initial }
        if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { if (-not [string]::IsNullOrWhiteSpace($d.SelectedPath)) { $script:TxtDownloadDir.Text = $d.SelectedPath; Save-Config } }
    } catch { Write-Log "选择目录失败：$($_.Exception.Message)" "Error" }
})
$script:BtnRefreshUsb.add_Click({ $script:UsbMultiAckedSignature = ""; Refresh-UsbList })

$script:ChkVentoy.add_Checked({ Update-BtnIdleText })
$script:ChkVentoy.add_Unchecked({ Update-BtnIdleText })

$script:BtnClearLog.add_Click({
    try {
        $script:LogDoc = New-Object System.Windows.Documents.FlowDocument
        $script:LogDoc.FontFamily = "Consolas, Courier New"
        $script:LogDoc.FontSize = 11
        $script:LogDoc.PagePadding = New-Object System.Windows.Thickness(0)
        $script:LogParagraph = New-Object System.Windows.Documents.Paragraph
        $script:LogParagraph.Margin = New-Object System.Windows.Thickness(0)
        $script:LogDoc.Blocks.Add($script:LogParagraph)
        $script:TxtLog.Document = $script:LogDoc
    } catch {}
})

$script:BtnExportLog.add_Click({
    try {
        $d = New-Object System.Windows.Forms.SaveFileDialog
        $d.Filter = "日志文件|*.txt"; $d.FileName = "WinISO_日志_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { if ($d.FileName -and (Test-Path $script:LogPath)) { Copy-Item $script:LogPath $d.FileName -Force; Write-Log "日志已导出" "Success" } }
    } catch { Write-Log "导出日志失败：$($_.Exception.Message)" "Warning" }
})

$script:BtnDownload.add_Click({
    switch ($script:DownloadState) {
        "idle" {
            $sel = @(); foreach ($it in $script:LstSystems.ItemsSource) { if ($it.IsSelected) { $sel += $it } }
            if ($sel.Count -eq 0) { Write-Log "请至少勾选一个系统" "Warning"; return }
            if (!$script:CmbLanguage.SelectedItem) { Write-Log "请选择语言" "Warning"; return }
            $destDir = $script:TxtDownloadDir.Text; if ([string]::IsNullOrWhiteSpace($destDir)) { Write-Log "请选择下载目录" "Warning"; return }
            $script:SelectedSystems = @($sel | ForEach-Object { $_.Key })
            $useVentoy = [bool]$script:ChkVentoy.IsChecked
            $usbDisk = $null
            if ($script:CmbUsbDisk.SelectedItem -and $script:CmbUsbDisk.SelectedItem -isnot [string]) { $usbDisk = $script:CmbUsbDisk.SelectedItem }
            if ($useVentoy -and !$usbDisk) { Write-Log "已勾选「全新制作」但未选择 U 盘" "Warning"; return }

            $tasks = @()
            foreach ($s in $sel) {
                $tasks += @{ DisplayName = $s.DisplayName; Win = $s.Win; Rel = $s.Rel; Ed = $s.Ed; Lang = $script:CmbLanguage.SelectedItem; Arch = $s.Arch; IsWinPE = $s.IsWinPE }
            }

            $script:Sync.Tasks          = $tasks
            $script:Sync.DownloadDir    = $destDir
            $script:Sync.VentoyEnabled  = $useVentoy
            $script:Sync.UsbDiskNumber  = if ($usbDisk) { $usbDisk.Number } else { -1 }
            $script:Sync.WinPEUrl       = $script:WinPEUrl
            $script:Sync.WinPEFileName  = $script:WinPEFileName
            $script:Sync.Aria2Exe       = $script:Aria2Exe
            $script:Sync.Aria2Dir       = $script:Aria2Dir
            $script:Sync.Aria2Urls      = $script:Aria2Urls
            $script:Sync.VentoyExe      = $script:VentoyExe
            $script:Sync.VentoyDir      = $script:VentoyDir
            $script:Sync.VentoyUrls     = $script:VentoyUrls
            $script:Sync.VentoyVersion  = $script:VentoyVersion
            $script:Sync.DataDir        = $script:DataDir
            $script:Sync.RpcPort        = $script:RpcPort
            $script:Sync.RpcUrl         = $script:RpcUrl
            $script:Sync.RpcSecret      = $script:RpcSecret
            $script:Sync.ApiBase        = $ApiBase
            $script:Sync.ApiKey         = $ApiKey
            $script:Sync.AppVersion     = $script:AppVersion
            $script:Sync.ClientId       = $script:ClientId
            $script:Sync.ActiveTasks    = @{}
            $script:Sync.Aria2Proc      = $null
            $script:Sync.Cancel         = $false
            $script:Sync.VentoyFailedChoice = $null

            Write-Log "===== 开始下载 $($sel.Count) 个系统 =====" "Success"
            $script:DownloadState = "downloading"
            $script:BtnDownload.Content = "停止下载"
            $script:BtnDownload.Background = $script:BtnStopColor
            Set-ControlsEnabled $false
            $script:PrgDownload.Foreground = $script:PrgNormalColor
            $script:PrgDownload.Value = 0
            Save-Config

            $rs = [runspacefactory]::CreateRunspace()
            $rs.ApartmentState = 'MTA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
            $rs.SessionStateProxy.SetVariable('sync', $script:Sync)
            $ps = [powershell]::Create(); $ps.Runspace = $rs
            $ps.AddScript($workerScript).AddArgument($script:Sync) | Out-Null
            $script:Sync.Running = $true
            $ps.BeginInvoke() | Out-Null
            $script:WorkerPS = $ps
            $script:WorkerRS = $rs
        }
        "downloading" {
            $script:Sync.Cancel = $true
            Write-Log "正在取消…" "Warning"
            Write-Status "正在取消…" "Orange"
            $script:BtnDownload.Content = "取消中…"
            $script:BtnDownload.IsEnabled = $false
        }
    }
})

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(120)
$timer.Add_Tick({
    $item = $null; $limit = 200
    while ($limit-- -gt 0 -and $script:Sync.Queue.TryDequeue([ref]$item)) {
        switch ($item.Type) {
            'Log' {
                $text = [string]$item.Text
                $color = [Windows.Media.Brushes]::LightGray
                if     ($text -match '\[ ✓ \]') { $color = [Windows.Media.Brushes]::LightGreen }
                elseif ($text -match '\[ × \]') { $color = [Windows.Media.Brushes]::Tomato }
                elseif ($text -match '\[ ! \]') { $color = [Windows.Media.Brushes]::Orange }
                elseif ($text -match '\[ » \]') { $color = [Windows.Media.Brushes]::DeepSkyBlue }
                $run = New-Object System.Windows.Documents.Run("$text`r`n")
                $run.Foreground = $color
                $script:LogParagraph.Inlines.Add($run)
                if ($script:LogParagraph.Inlines.Count -gt 3000) {
                    $toRemove = $script:LogParagraph.Inlines.Count - 3000
                    $first = $script:LogParagraph.Inlines.FirstInline
                    for ($i = 0; $i -lt $toRemove -and $first; $i++) {
                        $next = $first.NextInline
                        $script:LogParagraph.Inlines.Remove($first)
                        $first = $next
                    }
                }
                try { [System.IO.File]::AppendAllText($script:LogPath, "$text`r`n", [System.Text.Encoding]::UTF8) } catch {}
            }
            'Progress' {
                if ($item.Indeterminate) {
                    if (!$script:PrgDownload.IsIndeterminate) { $script:PrgDownload.IsIndeterminate = $true }
                } else {
                    if ($script:PrgDownload.IsIndeterminate) { $script:PrgDownload.IsIndeterminate = $false }
                    if ($script:PrgDownload.Value -ne [double]$item.Value) { $script:PrgDownload.Value = [double]$item.Value }
                }
            }
            'Status' {
                if ($script:TxtStatus.Text -ne $item.Text) { $script:TxtStatus.Text = $item.Text }
            }
            'ConfirmVentoyFailed' {
                try {
                    $ans = [System.Windows.Forms.MessageBox]::Show(
                        "Ventoy 安装失败。`n`n是否跳过 Ventoy，直接把 ISO 复制到 U 盘根目录？`n`n（仅当 U 盘已手动安装 Ventoy 时才有意义）",
                        "Ventoy 安装失败",
                        [System.Windows.Forms.MessageBoxButtons]::YesNo,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    )
                    $script:Sync.VentoyFailedChoice = ($ans -eq [System.Windows.Forms.DialogResult]::Yes)
                } catch { $script:Sync.VentoyFailedChoice = $false }
            }
            'Done' {
                $script:TxtLog.ScrollToEnd()
                $script:Sync.Running = $false
                $script:DownloadState = "idle"
                $script:BtnDownload.Content = Get-BtnIdleText
                $script:BtnDownload.Background = $script:BtnNormalColor
                $script:BtnDownload.IsEnabled = $true
                Set-ControlsEnabled $true
                $script:TxtSpeed.Text = ""
                if ($script:WorkerPS) { try { $script:WorkerPS.Dispose() } catch {}; $script:WorkerPS = $null }
                if ($script:WorkerRS) { try { $script:WorkerRS.Dispose() } catch {}; $script:WorkerRS = $null }

                if ($item.Cancelled) {
                    $script:TxtStatus.Text = "已取消"
                    $script:TxtStatus.Foreground = [Windows.Media.Brushes]::Orange
                    try { $script:TxtStatus.ToolTip = "任务已被用户取消" } catch {}
                    $script:PrgDownload.Foreground = $script:PrgNormalColor
                }
                elseif ($item.Success) {
                    $script:TxtStatus.Text = "全部完成"
                    $script:TxtStatus.Foreground = [Windows.Media.Brushes]::Green
                    try { $script:TxtStatus.ToolTip = "全部任务已完成" } catch {}
                    $script:PrgDownload.Value = 100
                    $script:PrgDownload.Foreground = $script:PrgDoneColor
                    if ($item.SkippedFiles -and $item.SkippedFiles.Count -gt 0) {
                        $names = ($item.SkippedFiles | ForEach-Object { "  • $($_.DisplayName)（$($_.Reason)）" }) -join "`n"
                        try {
                            $ans = [System.Windows.Forms.MessageBox]::Show(
                                "以下 $($item.SkippedFiles.Count) 个任务未完成：`n`n$names`n`n是否重新勾选这些任务以便重试？",
                                "部分任务失败",
                                [System.Windows.Forms.MessageBoxButton]::YesNo,
                                [System.Windows.Forms.MessageBoxImage]::Warning
                            )
                            if ($ans -eq [System.Windows.Forms.MessageBoxResult]::Yes) {
                                foreach ($it in $script:LstSystems.ItemsSource) {
                                    foreach ($sf in $item.SkippedFiles) {
                                        if ($it.DisplayName -eq $sf.DisplayName) { $it.IsSelected = $true; break }
                                    }
                                }
                            }
                        } catch {}
                    }
                }
                else {
                    $errMsg = if ($item.Error) { [string]$item.Error } else { "未知错误" }
                    $fullStatus = "任务失败：$errMsg"
                    $script:TxtStatus.Text = $fullStatus
                    $script:TxtStatus.Foreground = [Windows.Media.Brushes]::Red
                    try { $script:TxtStatus.ToolTip = $fullStatus } catch {}
                    $script:PrgDownload.Foreground = $script:PrgErrorColor
                    if ($item.ErrorFull -and ([string]$item.ErrorFull) -ne $errMsg) {
                        try { [System.IO.File]::AppendAllText($script:LogPath, "[Stack] $($item.ErrorFull)`r`n", [System.Text.Encoding]::UTF8) } catch {}
                    }
                }
            }
        }
    }
    if ($script:ChkAutoScroll -and $script:ChkAutoScroll.IsChecked) { $script:TxtLog.ScrollToEnd() }
})
$timer.Start()

$script:Window.Add_Closed({
    $timer.Stop()
    if ($script:UsbPollTimer) { try { $script:UsbPollTimer.Stop() } catch {} }
    if ($script:Sync.Running) { $script:Sync.Cancel = $true }
    if ($script:WorkerPS) { try { $script:WorkerPS.Dispose() } catch {} }
    if ($script:WorkerRS) { try { $script:WorkerRS.Dispose() } catch {} }
    try { if ($script:Sync.Aria2Proc -and !$script:Sync.Aria2Proc.HasExited) { $script:Sync.Aria2Proc.Kill() } } catch {}
    Save-Config
})

$script:Window.Add_Loaded({
    if ($cfg -and $cfg.Window) { try { if ($cfg.Window.Width -gt 0) { $script:Window.Width = $cfg.Window.Width }; if ($cfg.Window.Height -gt 0) { $script:Window.Height = $cfg.Window.Height }; if ($cfg.Window.Left -ge 0 -and $cfg.Window.Top -ge 0) { $script:Window.WindowStartupLocation = "Manual"; $script:Window.Left = $cfg.Window.Left; $script:Window.Top = $cfg.Window.Top }; if ($cfg.Window.State -eq "Maximized") { $script:Window.WindowState = "Maximized" } } catch {} }
    Write-Log "程序启动（v$($script:AppVersion)）" "Success"
    Write-Log "多版本 ISO 内含：家庭版│家庭单语言版│教育版│专业版│专业教育版│专业工作站" "Info"
    Write-Log "WinPE 工具箱（推荐）：一个纯净、开源的Win11PE，支持上网、声音、远程、下载。" "Info"
    Write-Log "数据目录：$($script:DataDir)" "Info"
    Write-Status "就绪" "Gray"
    Refresh-UsbList
    Start-UsbPolling
    Update-BtnIdleText
})

try { [void]$script:Window.ShowDialog() } catch {
    try { [System.IO.File]::AppendAllText($script:LogPath, "[Fatal] $($_.Exception.Message)`r`n$($_.ScriptStackTrace)`r`n", [System.Text.Encoding]::UTF8) } catch {}
}