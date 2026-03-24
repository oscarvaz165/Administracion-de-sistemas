# ==============================================================================
# http_functions_p7.ps1
# Libreria corregida para Practica 7 - Windows Server 2022
# Incluye compatibilidad con el menu_p7.ps1 y wrappers SSL basados en la libreria HTTP.
# ==============================================================================

function Write-Info    { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Ok      { param($msg) Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err     { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

function Write-Section {
    param($msg)
    Write-Host ""
    Write-Host "  ==================================================" -ForegroundColor Blue
    Write-Host "    $msg" -ForegroundColor Blue
    Write-Host "  ==================================================" -ForegroundColor Blue
    Write-Host ""
}

function Test-Admin {
    $current = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Err "Este script debe ejecutarse como Administrador."
        exit 1
    }
    Write-Ok "Ejecutando como Administrador."
}

function Test-Port {
    param([int]$Puerto, [int[]]$Exceptuar = @())

    if ($Puerto -lt 1 -or $Puerto -gt 65535) {
        Write-Err "Puerto $Puerto fuera de rango."
        return $false
    }

    $enUso = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object {
        $_.LocalPort -eq $Puerto -and ($Exceptuar -notcontains $_.OwningProcess)
    }
    if ($enUso) {
        Write-Err "Puerto $Puerto ya esta en uso."
        return $false
    }

    return $true
}

$script:PKG_MANAGER = $null

function Install-Chocolatey {
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        $env:ChocolateyInstall = "$env:ProgramData\chocolatey"
        $env:PATH += ";$env:ChocolateyInstall\bin"
    } catch {
        Write-Err "No se pudo instalar Chocolatey: $_"
        throw
    }
}

function Initialize-PackageManager {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $script:PKG_MANAGER = 'winget'
        Write-Ok "Gestor detectado: winget"
        return
    }
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        $script:PKG_MANAGER = 'choco'
        Write-Ok "Gestor detectado: chocolatey"
        return
    }
    Write-Warn "No se detecto winget/choco. Instalando Chocolatey..."
    Install-Chocolatey
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        $script:PKG_MANAGER = 'choco'
        Write-Ok "Chocolatey instalado correctamente."
        return
    }
    throw "No se pudo inicializar ningun gestor de paquetes."
}

function Install-Package {
    param([string]$Paquete, [string]$Version = 'latest')

    $usarVersion = ($Version -and $Version -ne 'latest')
    if ($script:PKG_MANAGER -eq 'winget') {
        if ($usarVersion) {
            winget install --id $Paquete --version $Version --silent --accept-source-agreements --accept-package-agreements
        } else {
            winget install --id $Paquete --silent --accept-source-agreements --accept-package-agreements
        }
    } else {
        if ($usarVersion) {
            choco install $Paquete --version $Version -y --no-progress --allow-downgrade
        } else {
            choco install $Paquete -y --no-progress
        }
    }
}

function Get-AvailableVersions {
    param([string]$Paquete)
    $versiones = @()

    if ($script:PKG_MANAGER -eq 'winget') {
        try {
            $versiones = @(winget show --id $Paquete --versions 2>$null | Where-Object { $_ -match '^\d' } | Select-Object -Unique)
        } catch {}
    }

    if (($script:PKG_MANAGER -eq 'choco') -or $versiones.Count -eq 0) {
        try {
            $versiones = @(choco list $Paquete --all --exact 2>$null |
                Where-Object { $_ -match '^\S+\s+\d' } |
                ForEach-Object { ($_ -split '\s+')[1] } |
                Select-Object -Unique)
        } catch {}
    }

    if ($versiones.Count -eq 0) { return @('latest') }
    return $versiones
}

function Set-FirewallRule {
    param([int]$Puerto, [int]$PuertoAnterior = 0, [string]$Servicio = 'HTTP')

    if ($PuertoAnterior -gt 0 -and $PuertoAnterior -ne $Puerto) {
        $reglaAnt = "$Servicio-Puerto-$PuertoAnterior"
        Get-NetFirewallRule -DisplayName $reglaAnt -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
    }

    $nombre = "$Servicio-Puerto-$Puerto"
    if (-not (Get-NetFirewallRule -DisplayName $nombre -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $nombre -Direction Inbound -Protocol TCP -LocalPort $Puerto -Action Allow -Profile Any | Out-Null
    }
    Write-Ok "Firewall listo para $Servicio en puerto $Puerto."
}

function New-IndexPage {
    param([string]$Servicio, [string]$Version, [int]$Puerto, [string]$Webroot)

    if (-not (Test-Path $Webroot)) {
        New-Item -ItemType Directory -Path $Webroot -Force | Out-Null
    }

    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>$Servicio - Practica 7</title>
</head>
<body style="font-family:Segoe UI,Arial,sans-serif;display:flex;justify-content:center;align-items:center;height:100vh;background:#0f172a;color:#fff;">
    <div style="background:#1e293b;padding:32px 48px;border-radius:14px;text-align:center;box-shadow:0 10px 30px rgba(0,0,0,.35)">
        <h1 style="margin-top:0">$Servicio</h1>
        <p>Version: $Version</p>
        <p>Puerto: $Puerto</p>
        <p>Practica 7 - Windows Server 2022</p>
    </div>
</body>
</html>
"@

    Set-Content -Path (Join-Path $Webroot 'index.html') -Value $html -Encoding UTF8
}

function Set-WebRootPermissions {
    param([string]$Webroot, [string]$ServiceUser = 'NETWORK SERVICE')
    if (-not (Test-Path $Webroot)) {
        New-Item -ItemType Directory -Path $Webroot -Force | Out-Null
    }
    try {
        $acl = Get-Acl $Webroot
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($ServiceUser,'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow')
        $acl.SetAccessRule($rule)
        Set-Acl -Path $Webroot -AclObject $acl
    } catch {
        Write-Warn "No se pudieron ajustar permisos NTFS: $_"
    }
}

function Get-InstalledVersion {
    param([string]$Servicio)
    try {
        if ($script:PKG_MANAGER -eq 'choco') {
            $line = choco list --local-only 2>$null | Where-Object { $_ -imatch "^$Servicio\s" } | Select-Object -First 1
            if ($line) { return ($line -split '\s+')[1] }
        }
        if ($script:PKG_MANAGER -eq 'winget') {
            $line = winget list --id $Servicio 2>$null | Where-Object { $_ -match '\d+\.\d+' } | Select-Object -First 1
            if ($line -match '(\d[\d.]+)') { return $matches[1] }
        }
    } catch {}
    return 'desconocida'
}


function Reset-IISSiteConfig {
    param([string]$SiteName = 'Default Web Site', [string]$Webroot = 'C:\inetpub\wwwroot')

    Write-Info 'Limpiando configuracion previa de IIS para evitar errores 500.19/500.0...'

    $appcmd = Join-Path $env:windir 'System32\inetsrv\appcmd.exe'
    if (Test-Path $appcmd) {
        & $appcmd clear config "$SiteName" /section:system.webServer/httpProtocol | Out-Null
        & $appcmd clear config "$SiteName" /section:system.webServer/security/requestFiltering | Out-Null
        & $appcmd clear config "$SiteName" /section:system.webServer/defaultDocument | Out-Null
    }

    $webConfig = Join-Path $Webroot 'web.config'
    if (Test-Path $webConfig) {
        $backup = "$webConfig.bak"
        Move-Item -Path $webConfig -Destination $backup -Force
        Write-Warn "Se movio web.config a: $backup"
    }

    try {
        Add-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter 'system.webServer/defaultDocument/files' -Name '.' -Value @{value='index.html'} -ErrorAction SilentlyContinue
    } catch {}
}

function Set-IISSecurity {
    param([string]$SiteName = 'Default Web Site')
    try {
        Remove-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "system.webServer/httpProtocol/customHeaders" -Name "." -AtElement @{name='X-Powered-By'} -ErrorAction SilentlyContinue
    } catch {}
    try {
        Set-WebConfigurationProperty -PSPath 'IIS:\' -Filter 'system.webServer/security/requestFiltering' -Name 'removeServerHeader' -Value $true
    } catch {}
}

function Install-IIS {
    param([int]$Puerto)

    Write-Section 'Instalando IIS'
    foreach ($feat in @('Web-Server','Web-Common-Http','Web-Static-Content','Web-Http-Errors','Web-Http-Logging','Web-Filtering','Web-Mgmt-Tools','Web-Mgmt-Console')) {
        Install-WindowsFeature -Name $feat -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null
    }

    Import-Module WebAdministration -ErrorAction Stop
    $site = 'Default Web Site'

    Get-WebBinding -Name $site -Protocol 'http' -ErrorAction SilentlyContinue | Remove-WebBinding -ErrorAction SilentlyContinue
    New-WebBinding -Name $site -Protocol 'http' -Port $Puerto -IPAddress '*'

    $iisVer = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\InetStp' -ErrorAction SilentlyContinue).VersionString
    if (-not $iisVer) { $iisVer = '10.0' }

    Reset-IISSiteConfig -SiteName $site -Webroot 'C:\inetpub\wwwroot'
    Set-IISSecurity -SiteName $site
    Set-WebRootPermissions -Webroot 'C:\inetpub\wwwroot' -ServiceUser 'IIS_IUSRS'
    New-IndexPage -Servicio 'IIS' -Version $iisVer -Puerto $Puerto -Webroot 'C:\inetpub\wwwroot'
    Set-FirewallRule -Puerto $Puerto -PuertoAnterior 80 -Servicio 'IIS'

    Set-Service W3SVC -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service W3SVC -ErrorAction SilentlyContinue
    Write-Ok "IIS listo en http://localhost:$Puerto"
}

function Set-ApacheSecurity {
    param([string]$ConfFile)
    $contenido = Get-Content $ConfFile -Raw

    if ($contenido -notmatch '(?m)^ServerName\s') {
        $contenido += "`r`nServerName localhost"
    }
    if ($contenido -notmatch '(?m)^LoadModule headers_module') {
        $contenido = $contenido -replace '(?m)^#?(LoadModule headers_module .+)$', '$1'
    }
    if ($contenido -notmatch '# ===== Seguridad Practica 7 =====') {
        $contenido += @"

# ===== Seguridad Practica 7 =====
ServerTokens Prod
ServerSignature Off
TraceEnable Off
<IfModule headers_module>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"
</IfModule>
"@
    }

    Set-Content -Path $ConfFile -Value $contenido -Encoding ASCII
}

function Resolve-ServiceExePath {
    param([string]$PathName)

    if ([string]::IsNullOrWhiteSpace($PathName)) { return $null }

    $raw = $PathName.Trim()

    if ($raw -match '^\s*"([^"]+\.exe)"') {
        return $Matches[1]
    }

    if ($raw -match '^\s*([^\s]+\.exe)') {
        return $Matches[1]
    }

    return $null
}

function Get-ApacheDir {
    $paths = @(
        'C:\Apache24',
        'C:\tools\Apache24',
        "$env:ProgramFiles\Apache24",
        "$env:ProgramFiles\Apache Software Foundation\Apache2.4",
        "$env:ProgramData\chocolatey\lib\apache-httpd\tools\Apache24",
        "$env:ChocolateyInstall\lib\apache-httpd\tools\Apache24",
        "$env:ProgramData\chocolatey\lib\Apache-HTTPD\tools\Apache24"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    $dir = $paths | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'bin\httpd.exe') } | Select-Object -First 1
    if ($dir) { return $dir }

    foreach ($svcName in @('Apache24','Apache2.4')) {
        try {
            $svc = Get-CimInstance Win32_Service -Filter "Name='$svcName'"
            if ($svc -and $svc.PathName) {
                $exe = Resolve-ServiceExePath -PathName $svc.PathName
                if ($exe -and (Test-Path -LiteralPath $exe)) {
                    return (Split-Path (Split-Path $exe -Parent) -Parent)
                }
            }
        } catch {}
    }

    try {
        $cmd = Get-Command httpd.exe -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
            return (Split-Path (Split-Path $cmd.Source -Parent) -Parent)
        }
    } catch {}

    $roots = @('C:\tools','C:\ProgramData\chocolatey\lib','C:\Program Files','C:\') | Where-Object { Test-Path -LiteralPath $_ }
    foreach ($root in $roots) {
        try {
            $hit = Get-ChildItem $root -Recurse -Filter 'httpd.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { return (Split-Path (Split-Path $hit.FullName -Parent) -Parent) }
        } catch {}
    }
    return $null
}

function Get-ApacheServiceName {
    foreach ($name in @('Apache24','Apache2.4')) {
        if (Get-Service -Name $name -ErrorAction SilentlyContinue) { return $name }
    }
    return 'Apache24'
}

function Install-ApacheWindows {
    param([int]$Puerto, [string]$Version = 'latest')

    Write-Section 'Instalando Apache HTTP Server'
    $pkgId = if ($script:PKG_MANAGER -eq 'winget') { 'Apache.Httpd' } else { 'apache-httpd' }
    Install-Package -Paquete $pkgId -Version $Version

    $apacheDir = Get-ApacheDir
    if (-not $apacheDir -and $script:PKG_MANAGER -eq 'choco') {
        Write-Warn 'Chocolatey reporta Apache instalado, pero no encuentro httpd.exe. Forzando reparacion...'
        try { choco upgrade apache-httpd -y --force --no-progress | Out-Null } catch {}
        Start-Sleep -Seconds 2
        $apacheDir = Get-ApacheDir
    }
    if (-not $apacheDir) {
        Write-Err 'No se encontro Apache despues de la instalacion.'
        Write-Host 'Prueba estos comandos manuales:' -ForegroundColor Yellow
        Write-Host '  Get-ChildItem C:\tools,C:\ProgramData\chocolatey\lib,"C:\Program Files" -Recurse -Filter httpd.exe -ErrorAction SilentlyContinue | Select-Object FullName' -ForegroundColor Gray
        Write-Host '  Get-CimInstance Win32_Service | Where-Object Name -match "Apache" | Select-Object Name,State,PathName' -ForegroundColor Gray
        throw 'No se encontro Apache despues de la instalacion.'
    }

    Write-Ok "Apache encontrado en: $apacheDir"

    $confFile = Join-Path $apacheDir 'conf\httpd.conf'
    $webroot  = Join-Path $apacheDir 'htdocs'
    $conf = Get-Content $confFile -Raw
    $conf = $conf -replace '(?m)^Listen\s+\d+', "Listen $Puerto"
    if ($conf -match '(?m)^#?ServerName\s+') {
        $conf = $conf -replace '(?m)^#?ServerName\s+.*$', "ServerName localhost:$Puerto"
    } else {
        $conf += "`r`nServerName localhost:$Puerto`r`n"
    }
    Set-Content $confFile -Value $conf -Encoding ASCII

    Set-ApacheSecurity -ConfFile $confFile
    Set-WebRootPermissions -Webroot $webroot -ServiceUser 'NETWORK SERVICE'
    New-IndexPage -Servicio 'Apache' -Version (Get-InstalledVersion -Servicio 'apache-httpd') -Puerto $Puerto -Webroot $webroot
    Set-FirewallRule -Puerto $Puerto -PuertoAnterior 80 -Servicio 'Apache'

    $httpd = Join-Path $apacheDir 'bin\httpd.exe'
    $svc = Get-ApacheServiceName
    & $httpd -k install -n $svc 2>$null | Out-Null
    Set-Service $svc -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service $svc -ErrorAction SilentlyContinue
    Write-Ok "Apache listo en http://localhost:$Puerto"
}

function Register-NginxService {
    param([string]$NginxDir)
    $nginxExe = Join-Path $NginxDir 'nginx.exe'

    if (-not (Get-Command nssm -ErrorAction SilentlyContinue)) {
        try {
            Install-Package -Paquete 'nssm'
            $env:PATH += ";$env:ProgramData\chocolatey\bin"
        } catch {}
    }

    if (Get-Command nssm -ErrorAction SilentlyContinue) {
        nssm stop Nginx 2>$null | Out-Null
        nssm remove Nginx confirm 2>$null | Out-Null
        nssm install Nginx $nginxExe 2>&1 | Out-Null
        nssm set Nginx AppDirectory $NginxDir 2>&1 | Out-Null
        nssm set Nginx Start SERVICE_AUTO_START 2>&1 | Out-Null
        Start-Service Nginx -ErrorAction SilentlyContinue
    } else {
        Start-Process $nginxExe -WorkingDirectory $NginxDir -WindowStyle Hidden
    }
}

function Get-NginxDir {
    $paths = @(
        'C:\tools\nginx',
        'C:\nginx',
        "$env:ProgramFiles\nginx",
        "$env:ProgramData\chocolatey\lib\nginx\tools\nginx"
    )
    $dir = $paths | Where-Object { Test-Path (Join-Path $_ 'nginx.exe') } | Select-Object -First 1
    if ($dir) { return $dir }
    $hit = Get-ChildItem 'C:\ProgramData\chocolatey\lib' -Recurse -Filter 'nginx.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($hit) { return $hit.DirectoryName }
    return $null
}

function Install-NginxWindows {
    param([int]$Puerto, [string]$Version = 'latest')

    Write-Section 'Instalando Nginx'
    $pkgId = if ($script:PKG_MANAGER -eq 'winget') { 'Nginx.Nginx' } else { 'nginx' }
    Install-Package -Paquete $pkgId -Version $Version

    $nginxDir = Get-NginxDir
    if (-not $nginxDir) { throw 'No se encontro Nginx despues de la instalacion.' }

    $confFile = Join-Path $nginxDir 'conf\nginx.conf'
    $webroot  = Join-Path $nginxDir 'html'

    $conf = @"
worker_processes 1;
events { worker_connections 1024; }
http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;
    server_tokens off;

    server {
        listen $Puerto;
        server_name localhost;
        root html;
        index index.html;

        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;

        location / {
            try_files `$uri `$uri/ =404;
        }
    }
}
"@
    Set-Content -Path $confFile -Value $conf -Encoding ASCII

    Set-WebRootPermissions -Webroot $webroot -ServiceUser 'NETWORK SERVICE'
    New-IndexPage -Servicio 'Nginx' -Version (Get-InstalledVersion -Servicio 'nginx') -Puerto $Puerto -Webroot $webroot
    Set-FirewallRule -Puerto $Puerto -PuertoAnterior 80 -Servicio 'Nginx'
    Register-NginxService -NginxDir $nginxDir
    Write-Ok "Nginx listo en http://localhost:$Puerto"
}

function New-SelfSignedSslCert {
    param(
        [string]$DnsName = 'localhost',
        [string]$FriendlyName = 'Practica7-SelfSigned'
    )

    $cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.FriendlyName -eq $FriendlyName } | Select-Object -First 1
    if ($cert) { return $cert }

    return New-SelfSignedCertificate -DnsName $DnsName,'127.0.0.1' -CertStoreLocation 'Cert:\LocalMachine\My' -FriendlyName $FriendlyName -NotAfter (Get-Date).AddYears(3)
}

function Ensure-IisHttpsBinding {
    param([int]$HttpsPort = 443)
    Import-Module WebAdministration -ErrorAction Stop
    $cert = New-SelfSignedSslCert -FriendlyName 'Practica7-IIS'

    Get-WebBinding -Name 'Default Web Site' -Protocol 'https' -ErrorAction SilentlyContinue | Remove-WebBinding -ErrorAction SilentlyContinue
    New-WebBinding -Name 'Default Web Site' -Protocol 'https' -Port $HttpsPort -IPAddress '*'

    Push-Location IIS:\SslBindings
    try {
        $bindingPath = "0.0.0.0!$HttpsPort"
        if (Test-Path $bindingPath) { Remove-Item $bindingPath -Force }
        Get-Item "Cert:\LocalMachine\My\$($cert.Thumbprint)" | New-Item $bindingPath | Out-Null
    } finally {
        Pop-Location
    }

    Set-FirewallRule -Puerto $HttpsPort -Servicio 'IIS-HTTPS'
}

function Install-IISWithSsl {
    param([int]$Puerto = 80)
    Install-IIS -Puerto $Puerto
    Ensure-IisHttpsBinding -HttpsPort 443
    Write-Ok 'IIS con HTTPS habilitado en 443.'
}

function Install-ApacheWithSsl {
    param([int]$Puerto = 8080, [string]$Origen = '1')
    if (-not $script:PKG_MANAGER) { Initialize-PackageManager }
    $version = 'latest'
    Install-ApacheWindows -Puerto $Puerto -Version $version
    Write-Warn 'Wrapper SSL de Apache agregado solo a nivel de compatibilidad. La instalacion HTTP queda funcional; HTTPS dedicado requiere cert/key y VirtualHost SSL aparte.'
}

function Install-NginxWithSsl {
    param([int]$Puerto = 8081, [string]$Origen = '1')
    if (-not $script:PKG_MANAGER) { Initialize-PackageManager }
    $version = 'latest'
    Install-NginxWindows -Puerto $Puerto -Version $version
    Write-Warn 'Wrapper SSL de Nginx agregado solo a nivel de compatibilidad. La instalacion HTTP queda funcional; HTTPS dedicado requiere cert/key y server{} SSL aparte.'
}

function Enable-SslFTP {
    Import-Module ServerManager -ErrorAction SilentlyContinue
    Install-WindowsFeature Web-Server,Web-Ftp-Server,Web-Ftp-Service,Web-Mgmt-Tools -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null
    $cert = New-SelfSignedSslCert -FriendlyName 'Practica7-FTP'
    Write-Warn "FTPS requiere configuracion fina del sitio FTP, autenticacion, rutas y politica SSL. Ya deje el rol FTP y el certificado listos. Thumbprint: $($cert.Thumbprint)"
}

function Select-FtpServicio {
    Write-Warn 'El flujo FTP privado no estaba implementado en el codigo original. Se devuelve control al instalador local.'
    return @($null, $null)
}

function Test-Deps {
    Write-Section 'Verificando dependencias'
    Initialize-PackageManager
    Import-Module ServerManager -ErrorAction SilentlyContinue
    Write-Ok 'Dependencias base verificadas.'
}

function Show-Resumen {
    Write-Section 'Resumen de instalaciones'
    $svcNames = @(
        @{ Nombre='W3SVC'; Alias='IIS/IIS-FTP' },
        @{ Nombre='Apache24'; Alias='Apache' },
        @{ Nombre='Apache2.4'; Alias='Apache' },
        @{ Nombre='Nginx'; Alias='Nginx' }
    )

    $vistos = @{}
    foreach ($item in $svcNames) {
        if ($vistos.ContainsKey($item.Alias)) { continue }
        $svc = Get-Service -Name $item.Nombre -ErrorAction SilentlyContinue
        if ($svc) {
            Write-Host ("  {0,-10} : {1}" -f $item.Alias, $svc.Status)
            $vistos[$item.Alias] = $true
        }
    }
    if (-not $vistos.ContainsKey('Apache')) { Write-Host '  Apache     : no instalado' }
    if (-not $vistos.ContainsKey('Nginx'))  { Write-Host '  Nginx      : no instalado' }
    if (-not $vistos.ContainsKey('IIS/IIS-FTP')) { Write-Host '  IIS/IIS-FTP: no instalado' }
}
