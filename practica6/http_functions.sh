#!/bin/bash
# ==============================================================================
# http_functions.sh - Libreria de funciones HTTP para Linux
# Practica 6 | Mageia 9 x86_64
# Uso: source ./http_functions.sh
# Requiere: ejecutar como root (sudo)
# ==============================================================================

# ------------------------------------------------------------------------------
# COLORES
# ------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

fn_info()    { echo -e "${CYAN}[INFO]  $1${NC}"; }
fn_ok()      { echo -e "${GREEN}[OK]    $1${NC}"; }
fn_warn()    { echo -e "${YELLOW}[WARN]  $1${NC}"; }
fn_err()     { echo -e "${RED}[ERROR] $1${NC}"; }
fn_section() {
    echo ""
    echo -e "${BLUE}  ==================================================${NC}"
    echo -e "${BLUE}    $1${NC}"
    echo -e "${BLUE}  ==================================================${NC}"
    echo ""
}

# ------------------------------------------------------------------------------
# VALIDACIONES
# ------------------------------------------------------------------------------

fn_check_root() {
    if [ "$EUID" -ne 0 ]; then
        fn_err "Este script debe ejecutarse como root."
        echo "  Usa: sudo ./menu.sh"
        exit 1
    fi
    fn_ok "Ejecutando como root en Mageia 9."
}

fn_validate_port() {
    local puerto="$1"

    if ! echo "$puerto" | grep -qE '^[0-9]+$'; then
        fn_err "El puerto debe ser un numero entero."
        return 1
    fi

    if [ "$puerto" -lt 1 ] || [ "$puerto" -gt 65535 ]; then
        fn_err "Puerto $puerto fuera de rango valido (1-65535)."
        return 1
    fi

    local reservados="21 22 23 25 53 110 143 389 443 445 3306 5432 5985 6379 8443 27017"
    for r in $reservados; do
        if [ "$puerto" -eq "$r" ]; then
            fn_err "Puerto $puerto reservado para otro servicio."
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
    echo "  Bloqueados: 22, 53, 443, 3306 (entre otros)" >&2
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

# ------------------------------------------------------------------------------
# GESTOR DE PAQUETES
# ------------------------------------------------------------------------------

PKG_MANAGER=""

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
        dnf makecache -q 2>/dev/null || true
    else
        urpmi.update -a -q 2>/dev/null || true
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

# ------------------------------------------------------------------------------
# CONSULTA DINAMICA DE VERSIONES
# ------------------------------------------------------------------------------

fn_get_versions() {
    local paquete="$1"
    local versiones=""

    if [ "$PKG_MANAGER" = "dnf" ]; then
        versiones=$(dnf repoquery --available --queryformat '%{version}' "$paquete" 2>/dev/null | \
                    grep -E '^[0-9]' | sort -Vr | uniq | head -5)
    elif command -v urpmq &>/dev/null; then
        versiones=$(urpmq --list "$paquete" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -Vr | uniq | head -5)
    fi

    if [ -z "$versiones" ]; then
        echo "latest"
    else
        echo "$versiones"
    fi
}

fn_menu_versiones() {
    local paquete="$1"
    local versiones
    versiones=$(fn_get_versions "$paquete")

    echo ""
    echo "  Versiones disponibles para $paquete:"
    echo "  [1] = Latest/Desarrollo     [ultimo] = LTS/Estable"
    echo ""

    local i=1
    local total
    total=$(echo "$versiones" | wc -l)

    while IFS= read -r ver; do
        if [ "$i" -eq 1 ]; then
            echo "    $i) $ver  [Latest]"
        elif [ "$i" -eq "$total" ] && [ "$total" -gt 1 ]; then
            echo "    $i) $ver  [LTS]"
        else
            echo "    $i) $ver"
        fi
        i=$((i + 1))
    done <<< "$versiones"

    echo ""
    local sel
    while true; do
        read -rp "  Selecciona version [1-$total]: " sel
        if echo "$sel" | grep -qE '^[0-9]+$' && [ "$sel" -ge 1 ] && [ "$sel" -le "$total" ]; then
            break
        fi
        fn_warn "Seleccion invalida."
    done

    local elegida
    elegida=$(echo "$versiones" | sed -n "${sel}p")
    fn_ok "Version seleccionada: $elegida"
    echo "$elegida"
}

# ------------------------------------------------------------------------------
# FIREWALL
# ------------------------------------------------------------------------------

fn_configurar_firewall() {
    local puerto="$1"
    local puerto_anterior="${2:-0}"

    fn_section "Configurando Firewall"

    if command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
        if [ "$puerto_anterior" -gt 0 ] && [ "$puerto_anterior" -ne "$puerto" ]; then
            firewall-cmd --permanent --remove-port="${puerto_anterior}/tcp" &>/dev/null || true
            fn_ok "Puerto anterior $puerto_anterior cerrado."
        fi
        firewall-cmd --permanent --add-port="${puerto}/tcp" &>/dev/null
        firewall-cmd --reload &>/dev/null
        fn_ok "Puerto $puerto abierto en firewalld."
    elif command -v iptables &>/dev/null; then
        if [ "$puerto_anterior" -gt 0 ] && [ "$puerto_anterior" -ne "$puerto" ]; then
            iptables -D INPUT -p tcp --dport "$puerto_anterior" -j ACCEPT 2>/dev/null || true
        fi
        iptables -C INPUT -p tcp --dport "$puerto" -j ACCEPT 2>/dev/null || \
        iptables -A INPUT -p tcp --dport "$puerto" -j ACCEPT
        fn_ok "Puerto $puerto abierto en iptables."
    else
        fn_warn "Sin firewall activo. Puerto $puerto sin restriccion de red."
    fi
}

# ------------------------------------------------------------------------------
# INDEX.HTML PERSONALIZADO
# ------------------------------------------------------------------------------

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
        <h1>$servicio</h1>
        <div>
            <span class="badge">Servidor: $servicio</span>
            <span class="badge">Version: $version</span>
            <span class="badge">Puerto: $puerto</span>
        </div>
        <p class="info">Aprovisionado automaticamente - Practica 6 - Mageia 9</p>
    </div>
</body>
</html>
HTMLEOF

    fn_ok "index.html creado en $webroot"
}

# ------------------------------------------------------------------------------
# OBTENER PUERTO ACTUAL DE UN SERVICIO
# ------------------------------------------------------------------------------

fn_get_puerto_actual() {
    local servicio="$1"
    case "$servicio" in
        apache|httpd)
            grep -E '^Listen[[:space:]]+[0-9]+' /etc/httpd/conf/httpd.conf 2>/dev/null | \
                awk '{print $2}' | head -1
            ;;
        nginx)
            grep -E 'listen[[:space:]]+[0-9]+' /etc/nginx/conf.d/practica6.conf 2>/dev/null | \
                grep -oE '[0-9]+' | head -1
            ;;
        tomcat)
            find /opt/tomcat /usr/share/tomcat /etc/tomcat -name server.xml 2>/dev/null | \
                xargs grep -oE 'Connector port="[0-9]+"' 2>/dev/null | head -1 | grep -oE '[0-9]+'
            ;;
        *)
            echo "?"
            ;;
    esac
}

# ------------------------------------------------------------------------------
# APACHE en Mageia 9
# ------------------------------------------------------------------------------

fn_install_apache() {
    local puerto="$1"

    fn_section "Instalando Apache (httpd) en Mageia 9"
    fn_update_repos
    fn_install_pkg "apache"
    fn_install_pkg "apache-mod_headers"

    local ver_real
    ver_real=$(httpd -v 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$ver_real" ] && ver_real="desconocida"

    local conf="/etc/httpd/conf/httpd.conf"
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
    fn_ok "Puerto $puerto configurado en httpd.conf."

    fn_apache_security
    fn_apache_restrict_methods

    if ! id apache &>/dev/null; then
        useradd -r -s /sbin/nologin -d /var/www apache 2>/dev/null || true
    fi

    local webroot="/var/www/html"
    mkdir -p "$webroot"
    chown -R apache:apache "$webroot"
    chmod 750 "$webroot"

    fn_crear_index "Apache" "$ver_real" "$puerto" "$webroot"
    fn_configurar_firewall "$puerto" 80

    systemctl enable httpd 2>/dev/null
    if httpd -t && systemctl restart httpd; then
        fn_ok "Servicio httpd iniciado."
    else
        fn_err "Apache no pudo iniciar."
        systemctl status httpd --no-pager -n 20
        return 1
    fi

    fn_section "Apache listo"
    echo -e "  ${GREEN}URL     : http://localhost:$puerto${NC}"
    echo -e "  ${GREEN}Webroot : $webroot${NC}"
}

fn_apache_security() {
    cat > "/etc/httpd/conf.d/security.conf" <<'EOF'
# Seguridad Practica 6
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
    cat > "/etc/httpd/conf.d/methods.conf" <<'EOF'
<Location />
    <LimitExcept GET POST HEAD OPTIONS>
        Require all denied
    </LimitExcept>
</Location>
EOF
    fn_ok "Metodos TRACE, TRACK, DELETE restringidos."
}

# ------------------------------------------------------------------------------
# NGINX en Mageia 9
# ------------------------------------------------------------------------------

fn_install_nginx() {
    local puerto="$1"

    fn_section "Instalando Nginx en Mageia 9"
    fn_update_repos
    fn_install_pkg "nginx"

    local ver_real
    ver_real=$(nginx -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$ver_real" ] && ver_real="desconocida"

    local webroot="/var/www/nginx"
    mkdir -p "$webroot"

    [ -f /etc/nginx/conf.d/default.conf ] && \
        mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak 2>/dev/null || true

    cat > "/etc/nginx/conf.d/practica6.conf" <<NGINXEOF
server {
    listen       $puerto;
    server_name  localhost;
    root         $webroot;
    index        index.html;

    server_tokens off;

    add_header X-Frame-Options        "SAMEORIGIN"    always;
    add_header X-Content-Type-Options "nosniff"       always;
    add_header X-XSS-Protection       "1; mode=block" always;

    if (\$request_method !~ ^(GET|POST|HEAD|OPTIONS)\$) {
        return 405;
    }

    location / { try_files \$uri \$uri/ =404; }
    location ~ /\. { deny all; }
}
NGINXEOF
    fn_ok "Configuracion de Nginx generada con puerto $puerto."

    if ! id nginx &>/dev/null; then
        fn_warn "El usuario nginx no existe aun. Se instalaron los archivos, pero valida el paquete."
    fi

    chown -R nginx:nginx "$webroot" 2>/dev/null || true
    chmod 750 "$webroot"

    fn_crear_index "Nginx" "$ver_real" "$puerto" "$webroot"
    fn_configurar_firewall "$puerto" 80

    systemctl enable nginx 2>/dev/null
    if nginx -t && systemctl restart nginx; then
        fn_ok "Servicio nginx iniciado."
    else
        fn_err "Nginx no pudo iniciar."
        systemctl status nginx --no-pager -n 20
        return 1
    fi

    fn_section "Nginx listo"
    echo -e "  ${GREEN}URL     : http://localhost:$puerto${NC}"
    echo -e "  ${GREEN}Webroot : $webroot${NC}"
}

# ------------------------------------------------------------------------------
# TOMCAT en Mageia 9
# ------------------------------------------------------------------------------

fn_install_tomcat() {
    local puerto="$1"

    fn_section "Instalando Tomcat en Mageia 9"
    fn_update_repos
    fn_install_pkg "tomcat"

    if systemctl list-unit-files 2>/dev/null | grep -q '^tomcat'; then
        fn_ok "Tomcat instalado desde repositorio."
        fn_tomcat_usuario
        fn_tomcat_puerto "$puerto" "/etc/tomcat/server.xml"
        fn_tomcat_security "/usr/share/tomcat"

        local ver_real
        ver_real=$(rpm -q tomcat 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        [ -z "$ver_real" ] && ver_real="desconocida"

        fn_crear_index "Tomcat" "$ver_real" "$puerto" "/var/lib/tomcat/webapps/ROOT"
        fn_configurar_firewall "$puerto" 8080

        systemctl enable tomcat 2>/dev/null
        if systemctl restart tomcat; then
            fn_ok "Servicio tomcat iniciado."
        else
            fn_err "Tomcat no pudo iniciar."
            systemctl status tomcat --no-pager -n 20
            return 1
        fi
    else
        fn_warn "Tomcat no en repositorio. Instalando desde binario Apache..."
        fn_tomcat_desde_binario "$puerto" || return 1
    fi

    fn_section "Tomcat listo"
    echo -e "  ${GREEN}URL     : http://localhost:$puerto${NC}"
}

fn_tomcat_desde_binario() {
    local puerto="$1"

    if ! command -v java &>/dev/null; then
        fn_install_pkg "java-11-openjdk"
    fi

    fn_info "Consultando ultima version de Tomcat 10..."
    local ver_tomcat
    ver_tomcat=$(curl -s "https://tomcat.apache.org/download-10.cgi" 2>/dev/null | \
                 grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 | tr -d 'v')
    [ -z "$ver_tomcat" ] && ver_tomcat="10.1.39"
    fn_info "Instalando Tomcat $ver_tomcat..."

    curl -L -o /tmp/tomcat.tar.gz \
        "https://downloads.apache.org/tomcat/tomcat-10/v${ver_tomcat}/bin/apache-tomcat-${ver_tomcat}.tar.gz" || {
        fn_err "No se pudo descargar Tomcat."
        return 1
    }

    local destino="/opt/tomcat"
    mkdir -p "$destino"
    tar -xzf /tmp/tomcat.tar.gz -C "$destino" --strip-components=1 || {
        fn_err "No se pudo extraer Tomcat."
        rm -f /tmp/tomcat.tar.gz
        return 1
    }
    rm -f /tmp/tomcat.tar.gz

    fn_tomcat_usuario
    fn_tomcat_puerto "$puerto" "$destino/conf/server.xml"
    fn_tomcat_security "$destino"

    chown -R tomcat:tomcat "$destino"
    chmod -R 750 "$destino"

    fn_crear_index "Tomcat" "$ver_tomcat" "$puerto" "$destino/webapps/ROOT"
    fn_configurar_firewall "$puerto" 8080

    cat > /etc/systemd/system/tomcat.service <<SVCEOF
[Unit]
Description=Apache Tomcat Web Server
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment=JAVA_HOME=/usr/lib/jvm/java-11-openjdk
Environment=CATALINA_HOME=$destino
ExecStart=$destino/bin/startup.sh
ExecStop=$destino/bin/shutdown.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload
    systemctl enable tomcat 2>/dev/null
    if systemctl restart tomcat; then
        fn_ok "Tomcat $ver_tomcat instalado e iniciado."
    else
        fn_err "Tomcat no pudo iniciar."
        systemctl status tomcat --no-pager -n 20
        return 1
    fi
}

fn_tomcat_usuario() {
    if ! id tomcat &>/dev/null; then
        useradd -r -s /sbin/nologin -d /opt/tomcat tomcat 2>/dev/null || true
        fn_ok "Usuario 'tomcat' creado."
    else
        fn_ok "Usuario 'tomcat' ya existe."
    fi
}

fn_tomcat_puerto() {
    local puerto="$1"
    local serverxml="$2"

    if [ -f "$serverxml" ]; then
        sed -i 's/Connector port="[0-9]*" protocol="HTTP/Connector port="'"$puerto"'" protocol="HTTP/' "$serverxml"
        fn_ok "Puerto $puerto configurado en server.xml."
    else
        fn_warn "No se encontro server.xml en $serverxml"
    fi
}

fn_tomcat_security() {
    local tomcat_home="$1"
    local webxml="$tomcat_home/conf/web.xml"

    if [ -f "$webxml" ] && ! grep -q "httpHeaderSecurity" "$webxml"; then
        sed -i 's|</web-app>|<filter><filter-name>httpHeaderSecurity</filter-name><filter-class>org.apache.catalina.filters.HttpHeaderSecurityFilter</filter-class><init-param><param-name>antiClickJackingOption</param-name><param-value>SAMEORIGIN</param-value></init-param></filter><filter-mapping><filter-name>httpHeaderSecurity</filter-name><url-pattern>/*</url-pattern></filter-mapping></web-app>|' "$webxml"
        fn_ok "Seguridad Tomcat aplicada."
    fi
}

# ------------------------------------------------------------------------------
# CAMBIAR PUERTO DE SERVICIO YA INSTALADO
# ------------------------------------------------------------------------------

fn_cambiar_puerto() {
    local servicio="$1"
    local puerto_nuevo="$2"
    local puerto_ant
    puerto_ant=$(fn_get_puerto_actual "$servicio")

    case "$servicio" in
        apache|httpd)
            sed -i "s/^Listen .*/Listen $puerto_nuevo/" /etc/httpd/conf/httpd.conf
            if grep -qE '^ServerName ' /etc/httpd/conf/httpd.conf; then
                sed -i "s|^ServerName .*|ServerName localhost:$puerto_nuevo|" /etc/httpd/conf/httpd.conf
            else
                echo "ServerName localhost:$puerto_nuevo" >> /etc/httpd/conf/httpd.conf
            fi

            local ver_apache
            ver_apache=$(httpd -v 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            fn_crear_index "Apache" "$ver_apache" "$puerto_nuevo" "/var/www/html"
            fn_configurar_firewall "$puerto_nuevo" "${puerto_ant:-0}"

            if httpd -t && systemctl restart httpd; then
                fn_ok "Puerto Apache cambiado a $puerto_nuevo."
            else
                fn_err "Apache no pudo reiniciar con el nuevo puerto."
                systemctl status httpd --no-pager -n 20
                return 1
            fi
            ;;
        nginx)
            sed -i -E "s/listen[[:space:]]+[0-9]+;/listen       $puerto_nuevo;/" /etc/nginx/conf.d/practica6.conf

            local ver_nginx
            ver_nginx=$(nginx -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            fn_crear_index "Nginx" "$ver_nginx" "$puerto_nuevo" "/var/www/nginx"
            fn_configurar_firewall "$puerto_nuevo" "${puerto_ant:-0}"

            if nginx -t && systemctl restart nginx; then
                fn_ok "Puerto Nginx cambiado a $puerto_nuevo."
            else
                fn_err "No se pudo reiniciar Nginx con el nuevo puerto."
                systemctl status nginx --no-pager -n 20
                return 1
            fi
            ;;
        tomcat)
            local serverxml
            serverxml=$(find /opt/tomcat /usr/share/tomcat /etc/tomcat -name server.xml 2>/dev/null | head -1)

            if [ -f "$serverxml" ]; then
                sed -i 's/Connector port="[0-9]*" protocol="HTTP/Connector port="'"$puerto_nuevo"'" protocol="HTTP/' "$serverxml"
                fn_configurar_firewall "$puerto_nuevo" "${puerto_ant:-0}"

                if systemctl restart tomcat; then
                    fn_ok "Puerto Tomcat cambiado a $puerto_nuevo."
                else
                    fn_err "Tomcat no pudo reiniciar con el nuevo puerto."
                    systemctl status tomcat --no-pager -n 20
                    return 1
                fi
            else
                fn_err "No se encontro server.xml para Tomcat."
                return 1
            fi
            ;;
        *)
            fn_err "Servicio no valido: $servicio"
            return 1
            ;;
    esac
}