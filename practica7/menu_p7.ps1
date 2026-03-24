# ==============================================================================
# Practica 7 - menu_p7.ps1 (corregido)
# Orquestador de instalacion - Windows Server 2022
# ==============================================================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\http_functions_p7.ps1"

function Draw-Box {
    param([string[]]$Lineas, [ConsoleColor]$Color = 'Cyan')
    $maxLen = ($Lineas | Measure-Object -Property Length -Maximum).Maximum
    $borde = '+' + ('-' * ($maxLen + 2)) + '+'
    Write-Host "  $borde" -ForegroundColor $Color
    foreach ($l in $Lineas) {
        $pad = $l.PadRight($maxLen)
        Write-Host "  | $pad |" -ForegroundColor $Color
    }
    Write-Host "  $borde" -ForegroundColor $Color
}

function Get-SslPort {
    param([string]$Servicio)
    switch ($Servicio) {
        'IIS'    { 443 }
        'Apache' { 8443 }
        'Nginx'  { 8444 }
        'FTP'    { 21 }
        default  { 0 }
    }
}

function Get-HttpPort {
    param([string]$Servicio)
    switch ($Servicio) {
        'IIS'    { 80 }
        'Apache' { 8080 }
        'Nginx'  { 8081 }
        default  { 0 }
    }
}

function Get-SvcStatus {
    param([string[]]$SvcNames)
    foreach ($name in $SvcNames) {
        $s = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($s) {
            if ($s.Status -eq 'Running') { return 'activo' }
            return 'inactivo'
        }
    }
    return 'no instalado'
}

function Get-SslStatus {
    param([string]$Servicio)
    $puerto = Get-SslPort -Servicio $Servicio
    if ($puerto -le 0) { return 'N/D' }
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ar  = $tcp.BeginConnect('localhost', $puerto, $null, $null)
        $ok  = $ar.AsyncWaitHandle.WaitOne(600)
        $tcp.Close()
        if ($ok) { return "HTTPS:$puerto [ON]" }
    } catch {}
    return "HTTPS:$puerto [--]"
}

function Show-Header {
    Clear-Host
    Write-Host ''
    Draw-Box -Color Blue -Lineas @(
        '  ORQUESTADOR DE INSTALACION  ',
        '      reprobados.com          ',
        '  Windows Server 2022         '
    )

    $iisStatus    = Get-SvcStatus -SvcNames @('W3SVC')
    $apacheStatus = Get-SvcStatus -SvcNames @('Apache24','Apache2.4')
    $nginxStatus  = Get-SvcStatus -SvcNames @('Nginx')
    $ftpStatus    = Get-SvcStatus -SvcNames @('FTPSVC','W3SVC')

    Draw-Box -Color Cyan -Lineas @(
        ' Servicio   Estado        SSL               ',
        ' ----------------------------------------- ',
        " IIS        $($iisStatus.PadRight(13)) $(Get-SslStatus -Servicio 'IIS')    ",
        " Apache     $($apacheStatus.PadRight(13)) $(Get-SslStatus -Servicio 'Apache') ",
        " Nginx      $($nginxStatus.PadRight(13)) $(Get-SslStatus -Servicio 'Nginx')  ",
        " IIS-FTP    $($ftpStatus.PadRight(13)) $(Get-SslStatus -Servicio 'FTP')      "
    )
    Write-Host ''
}

function Show-MainMenu {
    Show-Header
    Draw-Box -Color Blue -Lineas @(
        ' 1) IIS       -> HTTPS puerto :443  ',
        ' 2) Apache    -> HTTP  puerto :8080 ',
        ' 3) Nginx     -> HTTP  puerto :8081 ',
        ' 4) IIS-FTP   -> FTPS  puerto :21   ',
        ' 5) Ver resumen de instalaciones    ',
        ' 6) Salir                           '
    )
    Write-Host ''
    Write-Host -NoNewline '  Selecciona servicio: ' -ForegroundColor White
}

function Show-OriginMenu {
    param([string]$Servicio)
    Write-Host ''
    Draw-Box -Color Cyan -Lineas @(
        (" Origen de instalacion para {0}:" -f $Servicio),
        ' 1) WEB (gestor de paquetes)         ',
        ' 2) FTP (repositorio privado)        '
    )
    Write-Host ''
    Write-Host -NoNewline '  Selecciona origen: ' -ForegroundColor White
    return (Read-Host)
}

function Run-IIS {
    $origen = Show-OriginMenu -Servicio 'IIS'
    $puerto = Get-HttpPort -Servicio 'IIS'
    if ($origen -eq '2') {
        Write-Section 'Origen FTP seleccionado'
        Select-FtpServicio | Out-Null
    }
    Install-IISWithSsl -Puerto $puerto
}

function Run-Apache {
    $origen = Show-OriginMenu -Servicio 'Apache'
    $puerto = Get-HttpPort -Servicio 'Apache'
    Install-ApacheWithSsl -Puerto $puerto -Origen $origen
}

function Run-Nginx {
    $origen = Show-OriginMenu -Servicio 'Nginx'
    $puerto = Get-HttpPort -Servicio 'Nginx'
    Install-NginxWithSsl -Puerto $puerto -Origen $origen
}

function Run-FTP {
    Write-Host ''
    Write-Section 'Configurando FTPS en IIS-FTP'
    Enable-SslFTP
}

function Main {
    Test-Admin
    Test-Deps

    while ($true) {
        Show-MainMenu
        $opcion = Read-Host
        Write-Host ''

        switch ($opcion) {
            '1' { Run-IIS }
            '2' { Run-Apache }
            '3' { Run-Nginx }
            '4' { Run-FTP }
            '5' { Show-Resumen }
            '6' {
                Write-Ok 'Hasta luego!'
                break
            }
            default {
                Write-Warn 'Opcion invalida.'
                Start-Sleep -Seconds 1
            }
        }

        if ($opcion -ne '6') {
            Write-Host ''
            Read-Host '  Presiona ENTER para continuar'
        }
    }
}

Main
