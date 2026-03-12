#!/bin/bash
# ==============================================================================
# http_functions.sh - Libreria de funciones HTTP para Linux
# Practica 6 | Mageia 9 x86_64
# Uso: source ./http_functions.sh
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

fn_info() { echo -e "${CYAN}[INFO]  $1${NC}"; }
fn_ok()   { echo -e "${GREEN}[OK]    $1${NC}"; }
fn_warn() { echo -e "${YELLOW}[WARN]  $1${NC}"; }
fn_err()  { echo -e "${RED}[ERROR] $1${NC}"; }

fn_section() {
    echo ""
    echo -e "${BLUE}  ==================================================${NC}"
    echo -e "${BLUE}    $1${NC}"
    echo -e "${BLUE}  ==================================================${NC}"
    echo ""
}

PKG_MANAGER=""

fn_check_root() {
    if [ "$EUID" -ne 0 ]; then
        fn_err "Este script debe ejecutarse como root."
        echo "  Usa: sudo ./menu.sh"
        exit 1
    fi
    fn_ok "Ejecutando como root."
}

fn_init_pkg_manager() {
    fn_info "Detectando gestor de paquetes..."
    if command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
        fn_ok "dnf detectado."
    elif command -v urpmi &>/dev/null; then
        PKG_MANAGER="urpmi"
        fn_ok "urpmi detectado."
    else
        fn_err "No se encontro dnf ni urpmi."
        exit 1
    fi
}

fn_update_repos() {
    fn_info "Actualizando cache de repositorios..."
    if [ "$PKG_MANAGER" = "dnf" ]; then
        dnf makecache -q || true
    else
        urpmi.update -a -q || true
    fi
    fn_ok "Repositorios actualizados."
}

fn_install_pkg() {
    local paquete="$1"
    fn_info "Instalando $paquete..."
    if [ "$PKG_MANAGER" = "dnf" ]; then
        dnf install -y "$paquete"
    else
        urpmi --auto "$paquete"
    fi
}

fn_validate_port() {
    local puerto="$1"

    if ! echo "$puerto" | grep -qE '^[0-9]+$'; then
        fn_err "El puerto debe ser numerico."
        return 1
    fi

    if [ "$puerto" -lt 1 ] || [ "$puerto" -gt 65535 ]; then
        fn_err "Puerto fuera de rango valido."
        return 1
    fi

    local reservados="21 22 23 25 53 110 143 389 443 445 3306 5432 5985 6379 8443 27017"
    for r in $reservados; do
        if [ "$puerto" -eq "$r" ]; then
            fn_err "Puerto $puerto reservado."
            return 1
        fi
    done

    if ss -tln 2>/dev/null | awk '{print $4}' | grep -qE "(^|:)$puerto$"; then
        fn_err "Puerto $puerto ya esta en uso."
        return 1
    fi

    return 0
}

fn_solicitar_puerto() {
    local servicio="$1"
    local default="${2:-80}"
    local puerto

    echo "" >&2
    echo "  Configuracion de puerto para: $servicio" >&2
    echo "  Sugeridos: 80, 8080, 8081, 8888" >&2
    echo "  Bloqueados: 22, 53, 443, 3306" >&2
    echo "" >&2

    while true; do
        read -rp "  Puerto deseado [default: $default]: " puerto
        [ -z "$puerto" ] && puerto="$default"
        if fn_validate_port "$puerto"; then
            break
        fi
    done

    printf '%s\n' "$puerto"
}

fn_get_puerto_actual() {
    local servicio="$1"
    case "$servicio" in
        apache|httpd)
            grep -E '^Listen[[:space:]]+[0-9]+' /etc/httpd/conf/httpd.conf 2>/dev/null | awk '{print $2}' | head -1
            ;;
        nginx)
            grep -E 'listen[[:space:]]+[0-9]+' /etc/nginx/conf.d/practica6.conf 2>/dev/null | grep -oE '[0-9]+' | head -1
            ;;
        tomcat)
            find /opt/tomcat /usr/share/tomcat /etc/tomcat -name server.xml 2>/dev/null | \
            xargs grep -oE 'Connector port="[0-9]+"' 2>/dev/null | head -1 | grep -oE '[0-9]+'
            ;;
        *)
            echo ""
            ;;
    esac
}

fn_configurar_firewall() {
    local puerto="$1"
    local puerto_anterior="${2:-0}"

    if command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
        if [ "$puerto_anterior" -gt 0 ] && [ "$puerto_anterior" -ne "$puerto" ]; then
            firewall-cmd --permanent --remove-port="${puerto_anterior}/tcp" &>/dev/null || true
        fi
        firewall-cmd --permanent --add-port="${puerto}/tcp" &>/dev/null || true
        firewall-cmd --reload &>/dev/null || true
        fn_ok "Firewall actualizado para puerto $puerto."
    elif command -v iptables &>/dev/null; then
        if [ "$puerto_anterior" -gt 0 ] && [ "$puerto_anterior" -ne "$puerto" ]; then
            iptables -D INPUT -p tcp --dport "$puerto_anterior" -j ACCEPT 2>/dev/null || true
        fi
        iptables -C INPUT -p tcp --dport "$puerto" -j ACCEPT 2>/dev/null || \
        iptables -A INPUT -p tcp --dport "$puerto" -j ACCEPT
        fn_ok "Regla de iptables aplicada a $puerto."
    else
        fn_warn "No se detecto firewall activo."
    fi
}

fn_crear_index() {
    local servicio="$1"
    local version="$2"
    local puerto="$3"
    local webroot="$4"

    mkdir -p "$webroot"

    cat > "$webroot/index.html" <<HTMLEOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>$servicio - Practica 6</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background: #1a1a2e;
            color: #eee;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
        }
        .card {
            background: #16213e;
            border-radius: 12px;
            padding: 40px 60px;
            text-align: center;
            box-shadow: 0 8px 32px rgba(0,0,0,.4);
        }
        h1 { color: #4fc3f7; }
        .badge {
            display: inline-block;
            background: #e94560;
            padding: 6px 12px;
            border-radius: 6px;
            margin: 4px;
        }
    </style>
</head>
<body>
    <div class="card">
        <h1>$servicio</h1>
        <div class="badge">Version: $version</div>
        <div class="badge">Puerto: $puerto</div>
        <p>Servidor aprovisionado automaticamente.</p>
    </div>
</body>
</html>
HTMLEOF

    chmod 644 "$webroot/index.html"
    fn_ok "index.html creado en $webroot"
}

fn_apache_security() {
    cat > /etc/httpd/conf.d/security.conf <<'EOF'
ServerTokens Prod
ServerSignature Off
TraceEnable Off

<IfModule mod_headers.c>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"
    Header always unset Server
</IfModule>
EOF
    fn_ok "Seguridad Apache aplicada."
}

fn_apache_restrict_methods() {
    cat > /etc/httpd/conf.d/methods.conf <<'EOF'
<Location />
    <LimitExcept GET POST HEAD OPTIONS>
        Require all denied
    </LimitExcept>
</Location>
EOF
    fn_ok "Restriccion de metodos aplicada en Apache."
}

fn_install_apache() {
    local puerto="$1"
    local conf="/etc/httpd/conf/httpd.conf"
    local webroot="/var/www/html"

    fn_section "Instalando Apache"
    fn_update_repos
    fn_install_pkg "apache"
    fn_install_pkg "apache-mod_headers"

    mkdir -p "$webroot"

    if grep -qE '^Listen ' "$conf"; then
        sed -i "s/^Listen .*/Listen $puerto/" "$conf"
    else
        echo "Listen $puerto" >> "$conf"
    fi

    if grep -qE '^#?ServerName' "$conf"; then
        sed -i "s|^#\?ServerName.*|ServerName localhost:$puerto|" "$conf"
    else
        echo "ServerName localhost:$puerto" >> "$conf"
    fi

    fn_apache_security
    fn_apache_restrict_methods

    chown -R root:root "$webroot"
    chmod 755 "$webroot"

    local ver_real
    ver_real=$(httpd -v 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$ver_real" ] && ver_real="desconocida"

    fn_crear_index "Apache" "$ver_real" "$puerto" "$webroot"
    fn_configurar_firewall "$puerto"

    systemctl enable httpd &>/dev/null
    if httpd -t && systemctl restart httpd; then
        fn_ok "Apache iniciado en puerto $puerto."
    else
        fn_err "Apache no pudo iniciar."
        systemctl status httpd --no-pager -n 20
        return 1
    fi
}

fn_install_nginx() {
    local puerto="$1"
    local webroot="/var/www/nginx"
    local conf="/etc/nginx/conf.d/practica6.conf"

    fn_section "Instalando Nginx"
    fn_update_repos
    fn_install_pkg "nginx"

    mkdir -p "$webroot"
    chown -R root:root "$webroot"
    chmod 755 "$webroot"

    [ -f /etc/nginx/conf.d/default.conf ] && mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak 2>/dev/null || true

    local ver_real
    ver_real=$(nginx -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$ver_real" ] && ver_real="desconocida"

    fn_crear_index "Nginx" "$ver_real" "$puerto" "$webroot"

    cat > "$conf" <<NGINXEOF
server {
    listen $puerto;
    server_name _;
    root $webroot;
    index index.html;

    server_tokens off;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location ~ /\. {
        deny all;
    }
}
NGINXEOF

    chmod 644 "$conf"
    fn_configurar_firewall "$puerto"

    systemctl enable nginx &>/dev/null
    if nginx -t && systemctl restart nginx; then
        fn_ok "Nginx iniciado en puerto $puerto."
    else
        fn_err "Nginx no pudo iniciar."
        systemctl status nginx --no-pager -n 20
        return 1
    fi
}

fn_tomcat_usuario() {
    if ! id tomcat &>/dev/null; then
        useradd -r -s /sbin/nologin -d /opt/tomcat tomcat 2>/dev/null || true
        fn_ok "Usuario tomcat creado."
    fi
}

fn_tomcat_puerto() {
    local puerto="$1"
    local serverxml="$2"

    if [ -f "$serverxml" ]; then
        sed -i 's/Connector port="[0-9]*" protocol="HTTP/Connector port="'"$puerto"'" protocol="HTTP/' "$serverxml"
        fn_ok "Puerto Tomcat configurado a $puerto."
    fi
}

fn_install_tomcat() {
    local puerto="$1"

    fn_section "Instalando Tomcat"
    fn_update_repos
    fn_install_pkg "tomcat"

    if ! systemctl list-unit-files | grep -q '^tomcat'; then
        fn_err "No se encontro servicio tomcat instalado desde repositorios."
        return 1
    fi

    fn_tomcat_usuario
    fn_tomcat_puerto "$puerto" "/etc/tomcat/server.xml"

    mkdir -p /var/lib/tomcat/webapps/ROOT
    chown -R root:root /var/lib/tomcat/webapps/ROOT
    chmod 755 /var/lib/tomcat/webapps/ROOT

    local ver_real
    ver_real=$(rpm -q tomcat 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$ver_real" ] && ver_real="desconocida"

    fn_crear_index "Tomcat" "$ver_real" "$puerto" "/var/lib/tomcat/webapps/ROOT"
    fn_configurar_firewall "$puerto"

    systemctl enable tomcat &>/dev/null
    if systemctl restart tomcat; then
        fn_ok "Tomcat iniciado en puerto $puerto."
    else
        fn_err "Tomcat no pudo iniciar."
        systemctl status tomcat --no-pager -n 20
        return 1
    fi
}

fn_cambiar_puerto() {
    local servicio="$1"
    local puerto_nuevo="$2"

    case "$servicio" in
        apache|httpd)
            sed -i "s/^Listen .*/Listen $puerto_nuevo/" /etc/httpd/conf/httpd.conf
            if grep -qE '^ServerName ' /etc/httpd/conf/httpd.conf; then
                sed -i "s|^ServerName .*|ServerName localhost:$puerto_nuevo|" /etc/httpd/conf/httpd.conf
            else
                echo "ServerName localhost:$puerto_nuevo" >> /etc/httpd/conf/httpd.conf
            fi

            if httpd -t && systemctl restart httpd; then
                fn_ok "Puerto Apache cambiado a $puerto_nuevo."
            else
                fn_err "Apache no pudo reiniciar."
                systemctl status httpd --no-pager -n 20
                return 1
            fi
            ;;
        nginx)
            sed -i -E "s/listen[[:space:]]+[0-9]+;/listen $puerto_nuevo;/" /etc/nginx/conf.d/practica6.conf
            if nginx -t && systemctl restart nginx; then
                fn_ok "Puerto Nginx cambiado a $puerto_nuevo."
            else
                fn_err "Nginx no pudo reiniciar."
                systemctl status nginx --no-pager -n 20
                return 1
            fi
            ;;
        tomcat)
            local serverxml
            serverxml=$(find /opt/tomcat /usr/share/tomcat /etc/tomcat -name server.xml 2>/dev/null | head -1)

            if [ ! -f "$serverxml" ]; then
                fn_err "No se encontro server.xml de Tomcat."
                return 1
            fi

            sed -i 's/Connector port="[0-9]*" protocol="HTTP/Connector port="'"$puerto_nuevo"'" protocol="HTTP/' "$serverxml"
            if systemctl restart tomcat; then
                fn_ok "Puerto Tomcat cambiado a $puerto_nuevo."
            else
                fn_err "Tomcat no pudo reiniciar."
                systemctl status tomcat --no-pager -n 20
                return 1
            fi
            ;;
        *)
            fn_err "Servicio invalido: $servicio"
            return 1
            ;;
    esac
}