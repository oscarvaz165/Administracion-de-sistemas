#!/bin/bash

# ==============================================================================
# Practica-06: http_functions.sh
# Libreria de funciones para aprovisionamiento web automatizado en Linux
# ==============================================================================

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

fn_info()    { echo -e "${CYAN}  [INFO]  $1${NC}"; }
fn_ok()      { echo -e "${GREEN}  [OK]    $1${NC}"; }
fn_warn()    { echo -e "${YELLOW}  [WARN]  $1${NC}"; }
fn_err()     { echo -e "${RED}  [ERROR] $1${NC}"; }
fn_section() {
    echo ""
    echo -e "${BLUE}  ==================================================${NC}"
    echo -e "${BLUE}    $1${NC}"
    echo -e "${BLUE}  ==================================================${NC}"
    echo ""
}

# Funcion para validar entrada (evitar caracteres especiales y nulos)
validate_input() {
    local input="$1"
    if [[ -z "$input" || "$input" =~ [^a-zA-Z0-9._-] ]]; then
        return 1
    fi
    return 0
}

# Funcion para verificar si un puerto esta ocupado
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null ; then
        return 1 # Puerto ocupado
    else
        return 0 # Puerto libre
    fi
}

# Funcion para validar que el puerto este en el rango valido
is_reserved_port() {
    local port=$1
    if [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
        return 0 # Fuera de rango (invalido)
    fi
    return 1 # En rango (valido)
}

# Listar versiones dinamicamente (Adaptado para Mageia/DNF o URPMI)
get_versions() {
    local service=$1
    fn_info "Consultando versiones en repositorios de Mageia para $service..."

    if command -v dnf &> /dev/null; then
        dnf --showduplicates list "$service" 2>/dev/null | awk '{print $2}' | grep -E '^[0-9]' | head -n 5
    elif command -v urpmq &> /dev/null; then
        urpmq -m "$service" | head -n 5
    else
        fn_warn "No se detecto dnf ni urpmi. Escriba 'latest'."
    fi
}

# Configuracion de Seguridad General (Mageia/RedHat Paths)
apply_security_config() {
    local service=$1
    local web_root=$2

    fn_section "Hardening de seguridad: $service"

    case $service in
        apache2|httpd)
            local CONF="/etc/httpd/conf/httpd.conf"
            [ ! -f "$CONF" ] && CONF="/etc/apache2/httpd.conf"

            sed -i "s/^ServerTokens .*/ServerTokens Prod/" "$CONF" 2>/dev/null
            grep -q "^ServerTokens Prod" "$CONF" || echo "ServerTokens Prod" >> "$CONF"
            sed -i "s/^ServerSignature .*/ServerSignature Off/" "$CONF" 2>/dev/null
            grep -q "^ServerSignature Off" "$CONF" || echo "ServerSignature Off" >> "$CONF"
            grep -q "^TraceEnable Off" "$CONF" || echo "TraceEnable Off" >> "$CONF"

            fn_info "Validando configuracion de Apache..."
            if apachectl configtest &>/dev/null; then
                systemctl restart httpd 2>/dev/null || systemctl restart apache2 2>/dev/null
                fn_ok "Apache reiniciado correctamente."
            else
                fn_err "Error de sintaxis en httpd.conf:"
                apachectl configtest
            fi
            ;;
        nginx)
            sed -i "s/server_tokens on;/server_tokens off;/" /etc/nginx/nginx.conf
            grep -q "server_tokens off;" /etc/nginx/nginx.conf || \
                sed -i '/http {/a \    server_tokens off;' /etc/nginx/nginx.conf

            if nginx -t &>/dev/null; then
                systemctl restart nginx
                fn_ok "Nginx reiniciado correctamente."
            else
                fn_err "Error de sintaxis en nginx.conf:"
                nginx -t
            fi
            ;;
    esac
}

# Crear pagina index.html personalizada
create_custom_index() {
    local service=$1
    local version=$2
    local port=$3
    local path=$4

    mkdir -p "$path"

    cat > "$path/index.html" << HTMLEOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>$service - Practica 6</title>
    <style>
        body { font-family: sans-serif; background: #1a1a2e; color: #eee;
               display: flex; justify-content: center; align-items: center;
               height: 100vh; margin: 0; }
        .card { background: #16213e; border-radius: 12px; padding: 40px 60px;
                box-shadow: 0 8px 32px rgba(0,0,0,.5); text-align: center; }
        h1 { color: #4fc3f7; font-size: 2.2em; margin-bottom: .3em; }
        .badge { display: inline-block; background: #e94560; color: #fff;
                 border-radius: 6px; padding: 4px 14px; font-size: .9em; margin: 6px 4px; }
        .info { color: #a8b2d8; margin-top: 1em; font-size: .95em; }
    </style>
</head>
<body>
    <div class="card">
        <h1>$service</h1>
        <div>
            <span class="badge">Servidor: $service</span>
            <span class="badge">Version: $version</span>
            <span class="badge">Puerto: $port</span>
        </div>
        <p class="info">Aprovisionado automaticamente - Practica 6 - Mageia 9</p>
    </div>
</body>
</html>
HTMLEOF

    chown -R apache:apache "$path" 2>/dev/null || chown -R www-data:www-data "$path" 2>/dev/null
    fn_ok "index.html creado en $path"
}

# Instalacion de Apache (Mageia: apache)
install_apache() {
    local version=$1
    local port=$2

    fn_section "Instalando Apache en Mageia"
    dnf install -y apache 2>/dev/null || urpmi --auto apache

    fn_info "Forzando cambio de puerto en todos los archivos de Apache..."
    find /etc/httpd -name "*.conf" -exec sed -i "s/^Listen\s\+[0-9]\+/Listen $port/g" {} +
    find /etc/apache2 -name "*.conf" -exec sed -i "s/^Listen\s\+[0-9]\+/Listen $port/g" {} + 2>/dev/null

    local apache_root="/var/www/html/apache"
    mkdir -p "$apache_root"
    sed -i "s|DocumentRoot \"/var/www/html\"|DocumentRoot \"$apache_root\"|g" /etc/httpd/conf/httpd.conf
    sed -i "s|<Directory \"/var/www/html\">|<Directory \"$apache_root\">|g" /etc/httpd/conf/httpd.conf

    apply_security_config "httpd" "$apache_root"
    create_custom_index "Apache" "$version" "$port" "$apache_root"

    iptables -A INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
    firewall-cmd --permanent --add-port=$port/tcp 2>/dev/null
    firewall-cmd --reload 2>/dev/null

    systemctl enable httpd
    systemctl restart httpd
    fn_ok "Apache configurado en el puerto $port."
    echo -e "  ${GREEN}URL     : http://localhost:$port${NC}"
    echo -e "  ${GREEN}Webroot : $apache_root${NC}"
}

# Instalacion de Nginx (Mageia)
install_nginx() {
    local version=$1
    local port=$2

    fn_section "Instalando Nginx en Mageia"
    dnf install -y nginx 2>/dev/null || urpmi --auto nginx

    fn_info "Forzando cambio de puerto en todos los archivos de Nginx..."
    find /etc/nginx -name "*.conf" -exec sed -i "s/listen\s\+[0-9]\+/listen $port/g" {} +
    find /etc/nginx -name "*.conf" -exec sed -i "s/listen\s\+\[::\]:[0-9]\+;/listen [::]:$port;/g" {} +

    local nginx_root="/var/www/html/nginx"
    mkdir -p "$nginx_root"
    sed -i "s|root\s\+/usr/share/nginx/html;|root $nginx_root;|g" /etc/nginx/nginx.conf
    sed -i "s|root\s\+/var/www/html;|root $nginx_root;|g" /etc/nginx/nginx.conf

    apply_security_config "nginx" "$nginx_root"
    create_custom_index "Nginx" "$version" "$port" "$nginx_root"

    iptables -A INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
    firewall-cmd --permanent --add-port=$port/tcp 2>/dev/null
    firewall-cmd --reload 2>/dev/null

    systemctl enable nginx
    systemctl restart nginx
    fn_ok "Nginx configurado en el puerto $port."
    echo -e "  ${GREEN}URL     : http://localhost:$port${NC}"
    echo -e "  ${GREEN}Webroot : $nginx_root${NC}"
}

# Instalacion y configuracion de Tomcat (repositorio Mageia)
install_tomcat() {
    local port=$1

    fn_section "Instalando Tomcat en Mageia"

    if ! command -v java &>/dev/null; then
        fn_info "Instalando Java (OpenJDK)..."
        dnf install -y java-1.8.0-openjdk-devel 2>/dev/null || urpmi --auto java-1.8.0-openjdk-devel
    fi

    fn_info "Instalando Tomcat desde repositorio..."
    dnf install -y tomcat 2>/dev/null || urpmi --auto tomcat

    # Obtener version instalada
    local version
    version=$(rpm -q tomcat 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$version" ] && version="desconocida"
    fn_ok "Tomcat $version instalado."

    # Configurar puerto en ambos server.xml (repositorio usa /usr/share/tomcat/conf)
    for serverxml in "/etc/tomcat/server.xml" "/usr/share/tomcat/conf/server.xml"; do
        if [ -f "$serverxml" ]; then
            # Reemplaza cualquier puerto existente en el Connector HTTP (con o sin address)
            sed -i "s|Connector port=\"[0-9]*\" address=\"[^\"]*\" protocol=\"HTTP/1.1\"|Connector port=\"$port\" address=\"0.0.0.0\" protocol=\"HTTP/1.1\"|g" "$serverxml"
            sed -i "s|Connector port=\"[0-9]*\" protocol=\"HTTP/1.1\"|Connector port=\"$port\" address=\"0.0.0.0\" protocol=\"HTTP/1.1\"|g" "$serverxml"
            fn_ok "Puerto $port configurado en $serverxml."
        fi
    done

    # Configurar servicio para correr como root (permite puertos < 1024)
    local svc_file="/usr/lib/systemd/system/tomcat.service"
    if [ -f "$svc_file" ]; then
        sed -i 's/^User=tomcat/User=root/' "$svc_file"
        fn_ok "Servicio tomcat configurado para correr como root."
    fi
    systemctl daemon-reload

    # Crear index en el webroot correcto del repositorio
    local webroot="/var/lib/tomcat/webapps/ROOT"
    create_custom_index "Tomcat" "$version" "$port" "$webroot"

    iptables -A INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null

    systemctl enable tomcat 2>/dev/null
    systemctl restart tomcat
    sleep 3

    fn_ok "Tomcat $version configurado en el puerto $port."
    echo -e "  ${GREEN}URL     : http://localhost:$port${NC}"
    echo -e "  ${GREEN}Webroot : $webroot${NC}"
}

# Funcion para bajar servicios
stop_linux_service() {
    local service=$1
    fn_info "Deteniendo servicio $service..."
    case $service in
        apache2|httpd)
            systemctl stop httpd 2>/dev/null || systemctl stop apache2 2>/dev/null ;;
        nginx)
            systemctl stop nginx 2>/dev/null ;;
        tomcat)
            systemctl stop tomcat 2>/dev/null ;;
    esac
    fn_ok "Servicio $service detenido."
}

# Funcion para verificar estado y puertos de los servicios
check_services_status() {
    fn_section "Estado de los servicios web"
    printf "  ${CYAN}%-15s | %-12s | %-10s${NC}\n" "SERVICIO" "ESTADO" "PUERTO(S)"
    echo "  ------------------------------------------"

    local services=("httpd" "nginx" "tomcat")

    for srv in "${services[@]}"; do
        local status=$(systemctl is-active "$srv" 2>/dev/null)
        if [[ "$status" == "active" ]]; then
            local search_pattern="$srv"
            [[ "$srv" == "tomcat" ]] && search_pattern="java"
            local ports=$(ss -tulpn 2>/dev/null | grep -i "$search_pattern" | \
                awk '{print $5}' | cut -d':' -f2 | sort -u | tr '\n' ',' | sed 's/,$//')
            [[ -z "$ports" ]] && ports="Iniciando..."
            printf "  %-15s | " "$srv"
            echo -ne "${GREEN}%-12s${NC}" "Corriendo"
            printf " | %-10s\n" "$ports"
        else
            printf "  %-15s | " "$srv"
            echo -ne "${RED}%-12s${NC}" "Detenido"
            printf " | %-10s\n" "-"
        fi
    done
    echo "  ------------------------------------------"
}

# Funcion para eliminacion total de servicios (Purge)
purge_services() {
    local service=$1
    fn_warn "Eliminando por completo $service (registros, configs y binarios)..."

    case $service in
        apache2|httpd)
            systemctl stop httpd 2>/dev/null
            dnf remove -y apache 2>/dev/null || urpme apache 2>/dev/null
            rm -rf /etc/httpd /var/www/html /var/log/httpd
            ;;
        nginx)
            systemctl stop nginx 2>/dev/null
            dnf remove -y nginx 2>/dev/null || urpme nginx 2>/dev/null
            rm -rf /etc/nginx /var/www/html /var/log/nginx /usr/share/nginx
            ;;
        tomcat)
            systemctl stop tomcat 2>/dev/null
            dnf remove -y tomcat 2>/dev/null || urpme tomcat 2>/dev/null
            rm -rf /var/lib/tomcat /etc/tomcat /var/log/tomcat
            ;;
    esac
    fn_ok "Limpieza de $service completada."
}