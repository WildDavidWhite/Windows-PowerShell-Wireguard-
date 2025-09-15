# ====================================================================
# WireGuard Configuration & System Setup Script (自动化版本)
# ====================================================================
# 以下为原脚本内容，用于生成 WireGuard 配置文件
# ====================================================================

# 函数：验证IP地址格式
function Test-IPAddress {
    param([string]$IP)
    try {
        $null = [System.Net.IPAddress]::Parse($IP)
        return $true
    } catch {
        return $false
    }
}

# 函数：验证IPv6地址格式
function Test-IPv6Address {
    param([string]$IP)
    try {
        $addr = [System.Net.IPAddress]::Parse($IP)
        return $addr.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6
    } catch {
        return $false
    }
}

# 函数：获取本机IPv6地址
function Get-LocalIPv6Address {
    Write-Host "`n正在获取本机IPv6地址..." -ForegroundColor Yellow
    
    $adapters = Get-NetIPAddress -AddressFamily IPv6 | Where-Object {
        $_.PrefixOrigin -ne 'WellKnown' -and
        $_.AddressState -eq 'Preferred' -and
        $_.IPAddress -notlike 'fe80::*' -and
        $_.IPAddress -notlike '::1*' -and
        $_.IPAddress -notlike 'fd*' -and
        $_.IPAddress -notlike 'fc*'
    }

    $stableAddr = $adapters | Where-Object { $_.SuffixOrigin -ne 'Random' }

    if ($stableAddr) {
        $selectedAddress = $stableAddr[0].IPAddress
        Write-Host "  找到稳定公网IPv6地址: $selectedAddress" -ForegroundColor Green
        return $selectedAddress
    }

    if ($adapters) {
        $selectedAddress = $adapters[0].IPAddress
        Write-Host "  未找到明确的稳定IPv6地址，使用第一个可用地址: $selectedAddress" -ForegroundColor Yellow
        return $selectedAddress
    }
    
    throw "未找到有效的公网IPv6地址，请检查网络配置"
}

# 函数：获取本机IPv4地址和网段
function Get-LocalNetworkInfo {
    Write-Host "正在获取本机网络信息..." -ForegroundColor Yellow
    
    $networkInfo = @{
        IPv4 = $null
        Subnet = $null
    }
    
    $adapters = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
        $_.IPAddress -notlike '127.*' -and
        $_.IPAddress -notlike '169.254.*' -and
        $_.AddressState -eq 'Preferred'
    }
    
    foreach ($adapter in $adapters) {
        if ($adapter.IPAddress -like '192.168.*' -or 
            $adapter.IPAddress -like '10.*' -or 
            $adapter.IPAddress -like '172.16.*' -or
            $adapter.IPAddress -like '172.17.*' -or
            $adapter.IPAddress -like '172.18.*' -or
            $adapter.IPAddress -like '172.19.*' -or
            $adapter.IPAddress -like '172.2*' -or
            $adapter.IPAddress -like '172.30.*' -or
            $adapter.IPAddress -like '172.31.*') {
            
            $networkInfo.IPv4 = $adapter.IPAddress
            
            $prefixLength = $adapter.PrefixLength
            $ip = [System.Net.IPAddress]::Parse($adapter.IPAddress)
            $maskInt = [Convert]::ToInt64(('1' * $prefixLength).PadRight(32, '0'), 2)
            $mask = [System.Net.IPAddress]::Parse([Convert]::ToString($maskInt, 10))
            
            $ipBytes = $ip.GetAddressBytes()
            $maskBytes = $mask.GetAddressBytes()
            $networkBytes = New-Object byte[] 4
            for ($i = 0; $i -lt 4; $i++) {
                $networkBytes[$i] = $ipBytes[$i] -band $maskBytes[$i]
            }
            $networkAddr = [System.Net.IPAddress]::new($networkBytes)
            
            $networkInfo.Subnet = "$($networkAddr.ToString())/$prefixLength"
            Write-Host "  本机IPv4: $($networkInfo.IPv4)" -ForegroundColor Green
            Write-Host "  内网网段: $($networkInfo.Subnet)" -ForegroundColor Green
            break
        }
    }
    
    if (-not $networkInfo.IPv4) {
        if ($adapters.Count -gt 0) {
            $networkInfo.IPv4 = $adapters[0].IPAddress
            $networkInfo.Subnet = "$($adapters[0].IPAddress.Split('.')[0..2] -join '.').0/$($adapters[0].PrefixLength)"
        } else {
            throw "未找到有效的IPv4地址"
        }
    }
    
    return $networkInfo
}

# 函数：生成WireGuard密钥对
function New-WireGuardKeyPair {
    param([string]$Name)
    
    Write-Host "`n正在为 $Name 生成密钥对..." -ForegroundColor Yellow
    
    $wgPath = Get-Command wg.exe -ErrorAction SilentlyContinue
    if (-not $wgPath) {
        Write-Host "警告：未找到wg.exe，尝试使用默认路径" -ForegroundColor Yellow
        $wgPath = "C:\Program Files\WireGuard\wg.exe"
        if (-not (Test-Path $wgPath)) {
            throw "未找到WireGuard工具，请先安装WireGuard"
        }
    } else {
        $wgPath = $wgPath.Source
    }
    
    $privateKey = & $wgPath genkey
    if (-not $privateKey) {
        throw "生成私钥失败"
    }
    
    $publicKey = $privateKey | & $wgPath pubkey
    if (-not $publicKey) {
        throw "生成公钥失败"
    }
    
    Write-Host "  私钥: $privateKey" -ForegroundColor Gray
    Write-Host "  公钥: $publicKey" -ForegroundColor Gray
    
    return @{
        PrivateKey = $privateKey
        PublicKey = $publicKey
    }
}

# 函数：保存配置文件（无BOM的UTF-8）
function Save-ConfigFile {
    param(
        [string]$Path,
        [string]$Content
    )
    
    Write-Host "正在保存配置文件: $Path" -ForegroundColor Yellow
    
    $directory = [System.IO.Path]::GetDirectoryName($Path)
    if (-not (Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        Write-Host "  创建目录: $directory" -ForegroundColor Gray
    }
    
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
    
    if (Test-Path $Path) {
        Write-Host "  配置文件已保存" -ForegroundColor Green
    } else {
        throw "保存配置文件失败"
    }
}

# 主函数
function New-WireGuardConfig {
    Write-Host "`n=== WireGuard 自动配置生成器 ===" -ForegroundColor Cyan
    Write-Host "此脚本将自动生成服务器端和客户端配置文件" -ForegroundColor White
    
    $serverPort = "51820"
    $vpnSubnet = "10.0.0.0/24"
    $serverVpnIP = "10.0.0.1"
    $clientVpnIP = "10.0.0.2"
    
    $vpnIPv6Subnet = "fd00::/64"
    $serverVpnIPv6 = "fd00::1/64"
    $clientVpnIPv6 = "fd00::2/128"
    
    Write-Host "`n使用默认配置：" -ForegroundColor Yellow
    Write-Host "  WireGuard端口: $serverPort" -ForegroundColor Gray
    Write-Host "  VPN IPv4网段: $vpnSubnet" -ForegroundColor Gray
    Write-Host "  服务器VPN IPv4: $serverVpnIP" -ForegroundColor Gray
    Write-Host "  客户端VPN IPv4: $clientVpnIP" -ForegroundColor Gray
    Write-Host "  VPN IPv6网段: $vpnIPv6Subnet" -ForegroundColor Gray
    Write-Host "  服务器VPN IPv6: $serverVpnIPv6" -ForegroundColor Gray
    Write-Host "  客户端VPN IPv6: $clientVpnIPv6" -ForegroundColor Gray
    
    $serverPublicIPv6 = Get-LocalIPv6Address
    
    $localNetwork = Get-LocalNetworkInfo
    $localSubnet = $localNetwork.Subnet
    
    $serverKeys = New-WireGuardKeyPair -Name "服务器"
    $clientKeys = New-WireGuardKeyPair -Name "客户端"
    
    $serverConfig = @"
[Interface]
# 服务器端配置
PrivateKey = $($serverKeys.PrivateKey)
Address = $serverVpnIP/24
Address = $serverVpnIPv6
ListenPort = $serverPort
MTU = 1380

[Peer]
# 客户端
PublicKey = $($clientKeys.PublicKey)
# 这里的AllowedIPs只应包含客户端的虚拟IP
AllowedIPs = $clientVpnIP/32, $clientVpnIPv6
"@

    $clientConfig = @"
[Interface]
# 客户端配置
PrivateKey = $($clientKeys.PrivateKey)
Address = $clientVpnIP/32
Address = $clientVpnIPv6
MTU = 1380

# DNS服务器（自动获取）
# DNS = 8.8.8.8, 1.1.1.1

[Peer]
# 服务器
PublicKey = $($serverKeys.PublicKey)
# 使用IPv6地址连接服务器
Endpoint = [$serverPublicIPv6]:$serverPort

# 关键改动：所有流量都走隧道
AllowedIPs = 0.0.0.0/0, ::/0

# 保持连接活跃
PersistentKeepalive = 25
"@

    $outputPath = "D:\wireguard files"
    $serverConfigPath = Join-Path $outputPath "wg_server.conf"
    $clientConfigPath = Join-Path $outputPath "wg_client.conf"
    
    Save-ConfigFile -Path $serverConfigPath -Content $serverConfig
    Save-ConfigFile -Path $clientConfigPath -Content $clientConfig
    
    Write-Host "`n=== 配置生成完成 ===" -ForegroundColor Green
    Write-Host "`n配置摘要：" -ForegroundColor Cyan
    Write-Host "`n服务器端信息：" -ForegroundColor Yellow
    Write-Host "  配置文件: $serverConfigPath"
    Write-Host "  VPN IPv4: $serverVpnIP"
    Write-Host "  VPN IPv6: $serverVpnIPv6"
    Write-Host "  公网IPv6: $serverPublicIPv6"
    Write-Host "  监听端口: $serverPort"
    Write-Host "  公钥: $($serverKeys.PublicKey)"
    
    Write-Host "`n客户端信息：" -ForegroundColor Yellow
    Write-Host "  配置文件: $clientConfigPath"
    Write-Host "  VPN IPv4: $clientVpnIP"
    Write-Host "  VPN IPv6: $clientVpnIPv6"
    Write-Host "  服务器地址: [$serverPublicIPv6]:$serverPort"
    Write-Host "  公钥: $($clientKeys.PublicKey)"
    
    Write-Host "`n路由配置：" -ForegroundColor Yellow
    Write-Host "  VPN IPv4网段: $vpnSubnet"
    Write-Host "  VPN IPv6网段: $vpnIPv6Subnet"
    Write-Host "  内网网段: $localSubnet"
    Write-Host "  客户端现在会通过VPN访问所有互联网流量。"
    
    Write-Host "`n===== 重要提示 =====" -ForegroundColor Red
    Write-Host ""
    Write-Host "服务器端（Windows PC）设置：" -ForegroundColor Cyan
    Write-Host "1. 打开WireGuard，点击'添加隧道' -> '从文件导入...'"
    Write-Host "    选择: $serverConfigPath"
    Write-Host ""
    Write-Host "2. 客户端（手机/其他设备）设置：" -ForegroundColor Cyan
    Write-Host "3. 安装WireGuard应用"
    Write-Host "4. 扫描二维码或导入配置文件: $clientConfigPath"
    Write-Host "5. 连接后即可实现全流量代理"
    Write-Host ""
    Write-Host "注意事项：" -ForegroundColor Yellow
    Write-Host "- 此配置会把你的所有流量都通过VPN发送，请确认你已经手动配置了NAT。"
    Write-Host "- 任何拥有客户端配置文件的设备都可以连接"
    Write-Host "- 请妥善保管配置文件，特别是私钥信息"

    return $outputPath
}

$finalOutputPath = $null
try {
    $finalOutputPath = New-WireGuardConfig
    Write-Host "`n脚本执行成功！配置文件已保存到 $finalOutputPath\" -ForegroundColor Green
} catch {
    Write-Host "`n错误: $_" -ForegroundColor Red
    Write-Host "配置生成失败，请检查：" -ForegroundColor Red
    Write-Host "1. 是否已安装WireGuard" -ForegroundColor Yellow
    Write-Host "2. 是否有IPv6网络连接" -ForegroundColor Yellow
    Write-Host "3. 是否以管理员权限运行此脚本" -ForegroundColor Yellow
    exit 1
}