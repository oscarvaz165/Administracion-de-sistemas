# dhcp_menu_windows.ps1
# Menu DHCP para Windows Server - Sin errores de Overflow
# Ejecutar en PowerShell como Administrador

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Pause-Enter { Read-Host "`nPresiona Enter para continuar..." | Out-Null }

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        throw "ERROR: Debes ejecutar este script como ADMINISTRADOR."
    }
}

# ===== HELPERS DE CONVERSION PROFESIONALES (SIN OVERFLOW) =====

function IpToUInt32([string]$ip) {
    $bytes = [System.Net.IPAddress]::Parse($ip.Trim()).GetAddressBytes()
    # Las IPs en red son Big-Endian. Windows es Little-Endian. 
    # Invertimos para que el calculo matematico sea lineal.
    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($bytes) }
    return [BitConverter]::ToUInt32($bytes, 0)
}

function UInt32ToIp([uint32]$n) {
    $bytes = [BitConverter]::GetBytes($n)
    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($bytes) }
    return ([System.Net.IPAddress]::new($bytes)).ToString()
}

function IpAdd([string]$ip, [int]$delta) {
    # Usamos [uint64] para la operacion para que NUNCA haya overflow en la suma
    $n = [uint64](IpToUInt32 $ip)
    $res = $n + $delta
    if ($res -gt [uint32]::MaxValue) { throw "La IP resultante excede el limite de IPv4." }
    return UInt32ToIp([uint32]$res)
}

# ===== HELPERS DE RED =====

function MaskToPrefix([string]$mask) {
    $bytes = [System.Net.IPAddress]::Parse($mask.Trim()).GetAddressBytes()
    $bits = ""
    foreach ($b in $bytes) { $bits += [Convert]::ToString($b, 2).PadLeft(8,'0') }
    return ($bits.ToCharArray() | Where-Object { $_ -eq '1' }).Count
}

function Get-NetAddr([string]$ip, [string]$mask) {
    $i = IpToUInt32 $ip
    $m = IpToUInt32 $mask
    return UInt32ToIp($i -band $m)
}

# ===== LOGICA DE INSTALACION E IDEMPOTENCIA =====

function Dhcp-Install {
    Write-Host "--- Verificando Instalacion ---" -ForegroundColor Cyan
    $feature = Get-WindowsFeature -Name DHCP
    if ($feature.Installed) {
        Write-Host "El rol DHCP ya esta presente (Idempotencia OK)." -ForegroundColor Green
    } else {
        Write-Host "Instalando Rol DHCP de forma desatendida..." -ForegroundColor Yellow
        Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
        Write-Host "Instalacion completada." -ForegroundColor Green
    }
}

# ===== CONFIGURACION DINAMICA =====

function Configure-DhcpScope {
    Assert-Admin
    Import-Module DhcpServer

    Write-Host "`n--- Configuracion de Ambito DHCP ---" -ForegroundColor Cyan
    $name    = Read-Host "Nombre del Ambito [Red-Interna]"
    if ([string]::IsNullOrWhiteSpace($name)) { $name = "Red-Interna" }

    $srvIp   = Read-Host "IP del Servidor (fija) [192.168.100.1]"
    if (-not $srvIp) { $srvIp = "192.168.100.1" }

    $mask    = Read-Host "Mascara de Subred [255.255.255.0]"
    if (-not $mask) { $mask = "255.255.255.0" }

    $endIp   = Read-Host "IP Final del Rango [192.168.100.150]"
    if (-not $endIp) { $endIp = "192.168.100.150" }

    $lease   = Read-Host "Tiempo de concesion (HH:mm:ss) [08:00:00]"
    if (-not $lease) { $lease = "08:00:00" }

    # Calculos automaticos
    $scopeId   = Get-NetAddr $srvIp $mask
    $poolStart = IpAdd $srvIp 1 # El pool empieza despues de la IP del server
    $prefix    = MaskToPrefix $mask

    # Mostrar interfaces para elegir
    Write-Host "`nInterfaces disponibles:" -ForegroundColor Gray
    Get-NetAdapter | Where-Object Status -eq "Up" | Select Name, InterfaceDescription, MacAddress
    $iface = Read-Host "`nNombre de la Interfaz para el servidor"

    # 1. Configurar IP Estatica en el Servidor
    Write-Host "Asignando IP estatica al servidor..." -ForegroundColor Yellow
    New-NetIPAddress -InterfaceAlias $iface -IPAddress $srvIp -PrefixLength $prefix -ErrorAction SilentlyContinue | Out-Null

    # 2. Configurar Scope DHCP
    Write-Host "Configurando Scope en el servicio DHCP..." -ForegroundColor Yellow
    if (Get-DhcpServerv4Scope -ScopeId $scopeId -ErrorAction SilentlyContinue) {
        Remove-DhcpServerv4Scope -ScopeId $scopeId -Force
    }

    Add-DhcpServerv4Scope -Name $name -StartRange $poolStart -EndRange $endIp -SubnetMask $mask -State Active
    Set-DhcpServerv4OptionValue -ScopeId $scopeId -Router $srvIp -DnsServer $srvIp
    Set-DhcpServerv4Scope -ScopeId $scopeId -LeaseDuration ([TimeSpan]::Parse($lease))

    Restart-Service DHCPServer
    Write-Host "¡Servidor DHCP configurado y activo!" -ForegroundColor Green
}

# ===== MONITOREO =====

function Monitor-Dhcp {
    Write-Host "`n=== ESTADO DEL SERVICIO ===" -ForegroundColor Cyan
    Get-Service DHCPServer | Select-Object Name, Status, StartType
    
    Write-Host "`n=== AMBITOS ACTIVOS ===" -ForegroundColor Cyan
    Get-DhcpServerv4Scope | Select-Object ScopeId, Name, State, StartRange, EndRange
    
    Write-Host "`n=== CLIENTES CONECTADOS (LEASES) ===" -ForegroundColor Cyan
    $scopes = Get-DhcpServerv4Scope
    foreach ($s in $scopes) {
        $leases = Get-DhcpServerv4Lease -ScopeId $s.ScopeId
        if ($leases) {
            $leases | Select-Object IPAddress, HostName, ClientId, LeaseExpiryTime | Format-Table
        } else {
            Write-Host "No hay concesiones activas en el ambito $($s.ScopeId)." -ForegroundColor Gray
        }
    }
}

# ===== MENU PRINCIPAL =====

while ($true) {
    Write-Host "`n------------------------------------------"
    Write-Host "   SISTEMA DE GESTION DHCP (WINDOWS)    "
    Write-Host "------------------------------------------"
    Write-Host "1. Verificar/Instalar DHCP (Idempotencia)"
    Write-Host "2. Configurar Nuevo Ambito (Interactivo)"
    Write-Host "3. Monitorear Estado y Leases"
    Write-Host "4. Salir"
    
    $op = Read-Host "Seleccione una opcion"
    switch ($op) {
        "1" { try { Dhcp-Install } catch { Write-Host "Error: $_" -ForegroundColor Red } Pause-Enter }
        "2" { try { Configure-DhcpScope } catch { Write-Host "Error: $_" -ForegroundColor Red } Pause-Enter }
        "3" { Monitor-Dhcp; Pause-Enter }
        "4" { exit }
        default { Write-Host "Opcion no valida." }
    }
}