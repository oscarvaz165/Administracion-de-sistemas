#!/bin/bash
# =============================================================================
# p7_functions.sh - Libreria de funciones Practica 7
# Sistema Operativo: Mageia 9 x86_64
# Integra: Cliente FTP dinamico + SSL/TLS + Verificacion Hash
# =============================================================================

# -----------------------------------------------------------------------------
# COLORES
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# VARIABLES GLOBALES
# -----------------------------------------------------------------------------
FTP_SERVER="192.168.56.104"
FTP_PORT="21"
FTP_USER="mama"
FTP_PASS="Oscar12345"
FTP_BASE_PATH="/http/Linux"
DOMINIO="reprobados.com"
SSL_DIR="/etc/ssl/practica7"
RESUMEN_INSTALACIONES=""
INSTALL_DIR="/opt/p7_instaladores"

# -----------------------------------------------------------------------------
# FUNCIONES DE UTILIDAD
# -----------------------------------------------------------------------------

fn_header_p7() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "+============================================================+"
    echo "|     SISTEMA DE APROVISIONAMIENTO WEB - MAGEIA 9            |"
    echo "|          Practica 7 - FTP + SSL/TLS + Hash                 |"
    echo "+============================================================+"
    echo -e "${NC}"
}

fn_ok()   { echo -e "${GREEN}  [OK]    $1${NC}"; }
fn_info() { echo -e "${CYAN}  [INFO]  $1${NC}"; }
fn_err()  { echo -e "${RED}  [ERROR] $1${NC}"; }
fn_sec()  { echo -e "${MAGENTA}  [SSL]   $1${NC}"; }
fn_warn() { echo -e "${YELLOW}  [WARN]  $1${NC}"; }

fn_section() {
    echo ""
    echo -e "${BLUE}  ==================================================${NC}"
    echo -e "${BLUE}    $1${NC}"
    echo -e "${BLUE}  ==================================================${NC}"
    echo ""
}

fn_verificar_root_p7() {
    if [ "$(id -u)" -ne 0 ]; then
        fn_err "Este script debe ejecutarse como root."
        exit 1
    fi
}

fn_verificar_dependencias() {
    fn_info "Verificando dependencias..."
    local DEPS="curl wget openssl sha256sum"
    for DEP in $DEPS; do
        if ! command -v "$DEP" &>/dev/null; then
            fn_info "Instalando $DEP..."
            dnf install -y "$DEP" 2>/dev/null || urpmi --auto "$DEP" 2>/dev/null
        fi
    done
    fn_ok "Dependencias verificadas."
}

fn_instalar_pkg() {
    local paquete="$1"
    fn_info "Instalando $paquete..."
    dnf install -y "$paquete" 2>/dev/null || urpmi --auto "$paquete" 2>/dev/null
}

# -----------------------------------------------------------------------------
# BLOQUE 1: CLIENTE FTP DINAMICO
# -----------------------------------------------------------------------------

fn_ftp_listar() {
    local RUTA="$1"
    curl -s --connect-timeout 10 \
        "ftp://${FTP_SERVER}:${FTP_PORT}${RUTA}" \
        --user "${FTP_USER}:${FTP_PASS}" \
        -l 2>/dev/null
}

fn_ftp_descargar() {
    local RUTA_REMOTA="$1"
    local DESTINO="$2"

    fn_info "Descargando desde FTP: ${RUTA_REMOTA}..."
    curl -s --connect-timeout 30 \
        "ftp://${FTP_SERVER}:${FTP_PORT}${RUTA_REMOTA}" \
        --user "${FTP_USER}:${FTP_PASS}" \
        -o "$DESTINO" 2>/dev/null

    if [ $? -eq 0 ] && [ -s "$DESTINO" ]; then
        fn_ok "Archivo descargado: $DESTINO"
        return 0
    else
        fn_err "No se pudo descargar el archivo."
        return 1
    fi
}

fn_ftp_navegar_y_descargar() {
    local SERVICIO="$1"
    local DESTINO_DIR="$2"

    fn_section "Repositorio FTP - $SERVICIO"
    fn_info "Conectando al servidor FTP ${FTP_SERVER}..."

    local SERVICIOS
    SERVICIOS=$(fn_ftp_listar "${FTP_BASE_PATH}/")

    if [ -z "$SERVICIOS" ]; then
        fn_err "No se pudo conectar al FTP o el repositorio esta vacio."
        return 1
    fi

    fn_ok "Conexion FTP exitosa."
    echo ""
    echo -e "${CYAN}  Servicios disponibles en el repositorio:${NC}"
    local i=1
    local LISTA_SERVICIOS=""
    while IFS= read -r linea; do
        if [ -n "$linea" ]; then
            echo "    [$i] $linea"
            LISTA_SERVICIOS="$LISTA_SERVICIOS $linea"
            i=$((i+1))
        fi
    done <<< "$SERVICIOS"

    local TOTAL=$((i-1))
    local SEL_SVC=0
    while true; do
        echo ""
        read -rp "  Selecciona el servicio [1-${TOTAL}]: " SEL_SVC
        if [[ "$SEL_SVC" =~ ^[0-9]+$ ]] && [ "$SEL_SVC" -ge 1 ] && [ "$SEL_SVC" -le "$TOTAL" ]; then
            break
        fi
        fn_err "Seleccion invalida."
    done

    local SVC_ELEGIDO
    SVC_ELEGIDO=$(echo "$LISTA_SERVICIOS" | awk -v n="$SEL_SVC" '{print $n}')
    fn_ok "Servicio seleccionado: $SVC_ELEGIDO"

    echo ""
    fn_info "Listando versiones disponibles para ${SVC_ELEGIDO}..."
    local ARCHIVOS
    ARCHIVOS=$(fn_ftp_listar "${FTP_BASE_PATH}/${SVC_ELEGIDO}/")

    if [ -z "$ARCHIVOS" ]; then
        fn_err "No hay archivos en el repositorio para ${SVC_ELEGIDO}."
        return 1
    fi

    echo ""
    echo -e "${CYAN}  Versiones disponibles:${NC}"
    local j=1
    local LISTA_ARCHIVOS=""
    while IFS= read -r archivo; do
        if [ -n "$archivo" ] && ! echo "$archivo" | grep -q "\.sha256$"; then
            echo "    [$j] $archivo"
            LISTA_ARCHIVOS="$LISTA_ARCHIVOS $archivo"
            j=$((j+1))
        fi
    done <<< "$ARCHIVOS"

    local TOTAL_ARCH=$((j-1))
    if [ "$TOTAL_ARCH" -eq 0 ]; then
        fn_err "No hay instaladores disponibles."
        return 1
    fi

    local SEL_ARCH=0
    while true; do
        echo ""
        read -rp "  Selecciona la version [1-${TOTAL_ARCH}]: " SEL_ARCH
        if [[ "$SEL_ARCH" =~ ^[0-9]+$ ]] && [ "$SEL_ARCH" -ge 1 ] && [ "$SEL_ARCH" -le "$TOTAL_ARCH" ]; then
            break
        fi
        fn_err "Seleccion invalida."
    done

    local ARCH_ELEGIDO
    ARCH_ELEGIDO=$(echo "$LISTA_ARCHIVOS" | awk -v n="$SEL_ARCH" '{print $n}')
    fn_ok "Version seleccionada: $ARCH_ELEGIDO"

    mkdir -p "$DESTINO_DIR"
    local RUTA_REMOTA="${FTP_BASE_PATH}/${SVC_ELEGIDO}/${ARCH_ELEGIDO}"
    local DESTINO_LOCAL="${DESTINO_DIR}/${ARCH_ELEGIDO}"
    local DESTINO_SHA256="${DESTINO_DIR}/${ARCH_ELEGIDO}.sha256"

    fn_ftp_descargar "$RUTA_REMOTA" "$DESTINO_LOCAL" || return 1
    fn_ftp_descargar "${RUTA_REMOTA}.sha256" "$DESTINO_SHA256" || \
        fn_warn "No se encontro archivo SHA256, omitiendo verificacion."

    FTP_ARCHIVO_DESCARGADO="$DESTINO_LOCAL"
    FTP_SHA256_DESCARGADO="$DESTINO_SHA256"
    FTP_SERVICIO_ELEGIDO="$SVC_ELEGIDO"
    FTP_ARCHIVO_NOMBRE="$ARCH_ELEGIDO"

    return 0
}

# -----------------------------------------------------------------------------
# BLOQUE 2: VERIFICACION DE INTEGRIDAD SHA256
# -----------------------------------------------------------------------------

fn_verificar_hash() {
    local ARCHIVO="$1"
    local ARCHIVO_SHA256="$2"

    fn_section "Verificacion de Integridad SHA256"

    if [ ! -f "$ARCHIVO" ]; then
        fn_err "Archivo no encontrado: $ARCHIVO"
        return 1
    fi

    if [ ! -f "$ARCHIVO_SHA256" ]; then
        fn_warn "No hay archivo SHA256 disponible. Omitiendo verificacion."
        return 0
    fi

    fn_info "Calculando hash SHA256..."
    local HASH_LOCAL
    HASH_LOCAL=$(sha256sum "$ARCHIVO" | awk '{print $1}')
    local HASH_REMOTO
    HASH_REMOTO=$(awk '{print $1}' "$ARCHIVO_SHA256")

    echo "  Hash local : $HASH_LOCAL"
    echo "  Hash remoto: $HASH_REMOTO"

    if [ "$HASH_LOCAL" = "$HASH_REMOTO" ]; then
        fn_ok "Integridad verificada. El archivo no esta corrompido."
        return 0
    else
        fn_err "FALLO DE INTEGRIDAD. Los hashes no coinciden."
        fn_err "El archivo puede estar corrompido. Abortando instalacion."
        return 1
    fi
}

# -----------------------------------------------------------------------------
# BLOQUE 3: GENERACION DE CERTIFICADOS SSL/TLS
# -----------------------------------------------------------------------------

fn_generar_certificado_ssl() {
    local SERVICIO="$1"
    local CERT_DIR="${SSL_DIR}/${SERVICIO}"

    mkdir -p "$CERT_DIR"
    fn_sec "Generando certificado SSL autofirmado para ${DOMINIO}..."

    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout "${CERT_DIR}/server.key" \
        -out "${CERT_DIR}/server.crt" \
        -subj "/C=MX/ST=Sinaloa/L=Los_Mochis/O=Reprobados/OU=Sistemas/CN=${DOMINIO}" \
        2>/dev/null

    if [ $? -eq 0 ]; then
        chmod 600 "${CERT_DIR}/server.key"
        chmod 644 "${CERT_DIR}/server.crt"
        fn_sec "Certificado: ${CERT_DIR}/server.crt"
        fn_sec "Llave      : ${CERT_DIR}/server.key"
        fn_sec "Dominio    : ${DOMINIO} | Validez: 365 dias"
        return 0
    else
        fn_err "No se pudo generar el certificado SSL."
        return 1
    fi
}

fn_preguntar_ssl() {
    echo ""
    read -rp "  Desea activar SSL/TLS en este servicio? [s/n]: " RESP_SSL
    if echo "$RESP_SSL" | grep -qi "^s"; then
        return 0
    else
        return 1
    fi
}

# -----------------------------------------------------------------------------
# BLOQUE 4: INSTALACION APACHE
# -----------------------------------------------------------------------------

fn_instalar_apache_ftp() {
    local ARCHIVO="$1"
    local PUERTO="$2"
    local SSL="$3"

    fn_section "Instalacion Apache desde FTP - Mageia 9"

    fn_info "Instalando dependencias..."
    fn_instalar_pkg "apache"
    fn_instalar_pkg "apache-mod_ssl"
    fn_instalar_pkg "apache-mod_headers"

    local CONF="/etc/httpd/conf/httpd.conf"

    # Deshabilitar ssl.conf para evitar conflicto de puertos
    for sslf in /etc/httpd/conf/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf; do
        [ -f "$sslf" ] && mv "$sslf" "${sslf}.bak" && fn_info "ssl.conf deshabilitado."
    done

    # Configurar puerto
    sed -i "s/^Listen .*/Listen ${PUERTO}/" "$CONF"
    sed -i "s/^#\?ServerName.*/ServerName ${DOMINIO}:${PUERTO}/" "$CONF"

    # Seguridad
    cat >> "$CONF" << APACHEEOF

# Seguridad - Practica 7
ServerTokens Prod
ServerSignature Off
TraceEnable Off
APACHEEOF

    # Configurar SSL
    local SSL_LABEL="No"
    if [ "$SSL" = "si" ]; then
        fn_generar_certificado_ssl "apache"
        local CERT_DIR="${SSL_DIR}/apache"
        SSL_LABEL="Si (puerto 443)"

        cat > /etc/httpd/conf.d/ssl_p7.conf << SSLEOF
Listen 443
<VirtualHost *:443>
    ServerName ${DOMINIO}
    DocumentRoot "/var/www/html/apache"
    SSLEngine on
    SSLCertificateFile    ${CERT_DIR}/server.crt
    SSLCertificateKeyFile ${CERT_DIR}/server.key
    Header always set Strict-Transport-Security "max-age=31536000"
    Header always set X-Frame-Options SAMEORIGIN
    Header always set X-Content-Type-Options nosniff
</VirtualHost>
<VirtualHost *:${PUERTO}>
    ServerName ${DOMINIO}
    Redirect permanent / https://${DOMINIO}/
</VirtualHost>
SSLEOF
        fn_sec "SSL configurado en Apache (443 + redireccion desde ${PUERTO})"
        iptables -A INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null
    fi

    # Crear webroot y pagina
    local WEBROOT="/var/www/html/apache"
    mkdir -p "$WEBROOT"
    local VER
    VER=$(httpd -v 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$VER" ] && VER="2.4.x"
    fn_crear_index "Apache" "$VER" "$PUERTO" "$SSL_LABEL" "$WEBROOT"
    chown -R apache:apache "$WEBROOT"

    # Firewall
    iptables -A INPUT -p tcp --dport "$PUERTO" -j ACCEPT 2>/dev/null

    systemctl enable httpd 2>/dev/null
    systemctl restart httpd
    fn_ok "Apache iniciado en puerto ${PUERTO}."

    RESUMEN_INSTALACIONES="${RESUMEN_INSTALACIONES}\n  [Apache] Puerto: ${PUERTO} | SSL: ${SSL_LABEL} | Origen: FTP"
}

fn_instalar_apache_web() {
    local PUERTO="$1"
    local SSL="$2"

    fn_section "Instalacion Apache via DNF - Mageia 9"
    fn_instalar_pkg "apache"
    fn_instalar_pkg "apache-mod_ssl"
    fn_instalar_pkg "apache-mod_headers"

    local CONF="/etc/httpd/conf/httpd.conf"

    for sslf in /etc/httpd/conf/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf; do
        [ -f "$sslf" ] && mv "$sslf" "${sslf}.bak" 2>/dev/null
    done

    sed -i "s/^Listen .*/Listen ${PUERTO}/" "$CONF"
    sed -i "s/^#\?ServerName.*/ServerName ${DOMINIO}:${PUERTO}/" "$CONF"

    cat >> "$CONF" << APACHEEOF

# Seguridad - Practica 7
ServerTokens Prod
ServerSignature Off
TraceEnable Off
APACHEEOF

    local SSL_LABEL="No"
    if [ "$SSL" = "si" ]; then
        fn_generar_certificado_ssl "apache"
        local CERT_DIR="${SSL_DIR}/apache"
        SSL_LABEL="Si (puerto 443)"

        cat > /etc/httpd/conf.d/ssl_p7.conf << SSLEOF
Listen 443
<VirtualHost *:443>
    ServerName ${DOMINIO}
    DocumentRoot "/var/www/html/apache"
    SSLEngine on
    SSLCertificateFile    ${CERT_DIR}/server.crt
    SSLCertificateKeyFile ${CERT_DIR}/server.key
    Header always set Strict-Transport-Security "max-age=31536000"
</VirtualHost>
<VirtualHost *:${PUERTO}>
    ServerName ${DOMINIO}
    Redirect permanent / https://${DOMINIO}/
</VirtualHost>
SSLEOF
        iptables -A INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null
    fi

    local WEBROOT="/var/www/html/apache"
    mkdir -p "$WEBROOT"
    local VER
    VER=$(httpd -v 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$VER" ] && VER="2.4.x"
    fn_crear_index "Apache" "$VER" "$PUERTO" "$SSL_LABEL" "$WEBROOT"
    chown -R apache:apache "$WEBROOT"

    iptables -A INPUT -p tcp --dport "$PUERTO" -j ACCEPT 2>/dev/null
    systemctl enable httpd 2>/dev/null
    systemctl restart httpd
    fn_ok "Apache instalado via DNF en puerto ${PUERTO}."
    RESUMEN_INSTALACIONES="${RESUMEN_INSTALACIONES}\n  [Apache] Puerto: ${PUERTO} | SSL: ${SSL_LABEL} | Origen: WEB"
}

# -----------------------------------------------------------------------------
# BLOQUE 5: INSTALACION NGINX
# -----------------------------------------------------------------------------

fn_instalar_nginx_ftp() {
    local ARCHIVO="$1"
    local PUERTO="$2"
    local SSL="$3"

    fn_section "Instalacion Nginx desde FTP - Mageia 9"

    fn_info "Instalando dependencias de compilacion..."
    for pkg in gcc make pcre-dev openssl-dev zlib-dev; do
        fn_instalar_pkg "$pkg"
    done

    local EXTRACT_DIR="${INSTALL_DIR}/nginx_src"
    mkdir -p "$EXTRACT_DIR"
    fn_info "Extrayendo ${ARCHIVO}..."
    tar -xzf "$ARCHIVO" -C "$EXTRACT_DIR" 2>/dev/null
    local SRC_DIR
    SRC_DIR=$(find "$EXTRACT_DIR" -maxdepth 1 -type d -name "nginx-*" | head -1)

    if [ -z "$SRC_DIR" ]; then
        fn_err "No se pudo extraer Nginx."
        return 1
    fi

    fn_info "Compilando Nginx..."
    cd "$SRC_DIR" || return 1
    ./configure \
        --prefix=/usr/local/nginx \
        --with-http_ssl_module \
        --with-http_rewrite_module \
        >/tmp/nginx_configure.log 2>&1
    make -j2 >/tmp/nginx_make.log 2>&1
    make install >/tmp/nginx_install.log 2>&1

    if [ ! -f "/usr/local/nginx/sbin/nginx" ]; then
        fn_err "La compilacion de Nginx fallo."
        return 1
    fi
    fn_ok "Nginx compilado en /usr/local/nginx"

    local VER
    VER=$(basename "$SRC_DIR" | sed 's/nginx-//')
    fn_configurar_nginx "/usr/local/nginx" "$PUERTO" "$SSL" "$VER"

    # Registrar como servicio systemd
    cat > /etc/systemd/system/nginx_p7.service << SVCEOF
[Unit]
Description=Nginx P7
After=network.target
[Service]
Type=forking
ExecStart=/usr/local/nginx/sbin/nginx
ExecStop=/usr/local/nginx/sbin/nginx -s stop
ExecReload=/usr/local/nginx/sbin/nginx -s reload
[Install]
WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload
    systemctl enable nginx_p7 2>/dev/null
    systemctl restart nginx_p7
    fn_ok "Nginx iniciado en puerto ${PUERTO}."

    local SSL_LABEL="No"
    [ "$SSL" = "si" ] && SSL_LABEL="Si (puerto 443)"
    RESUMEN_INSTALACIONES="${RESUMEN_INSTALACIONES}\n  [Nginx] Puerto: ${PUERTO} | SSL: ${SSL_LABEL} | Origen: FTP"
}

fn_instalar_nginx_web() {
    local PUERTO="$1"
    local SSL="$2"

    fn_section "Instalacion Nginx via DNF - Mageia 9"
    fn_instalar_pkg "nginx"

    local VER
    VER=$(nginx -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$VER" ] && VER="desconocida"

    fn_configurar_nginx "/etc/nginx" "$PUERTO" "$SSL" "$VER"

    # Deshabilitar default
    [ -f /etc/nginx/conf.d/default.conf ] && \
        mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak 2>/dev/null

    systemctl enable nginx 2>/dev/null
    systemctl restart nginx
    fn_ok "Nginx instalado via DNF en puerto ${PUERTO}."

    local SSL_LABEL="No"
    [ "$SSL" = "si" ] && SSL_LABEL="Si (puerto 443)"
    RESUMEN_INSTALACIONES="${RESUMEN_INSTALACIONES}\n  [Nginx] Puerto: ${PUERTO} | SSL: ${SSL_LABEL} | Origen: WEB"
}

fn_configurar_nginx() {
    local NGINX_BASE="$1"
    local PUERTO="$2"
    local SSL="$3"
    local VER="$4"

    local WEBROOT="/var/www/nginx"
    mkdir -p "$WEBROOT"
    local CONF_DIR="$NGINX_BASE/conf"
    [ -d "$NGINX_BASE/conf.d" ] && CONF_DIR="$NGINX_BASE/conf.d"

    local SSL_LABEL="No"
    local SSL_BLOCK=""
    if [ "$SSL" = "si" ]; then
        fn_generar_certificado_ssl "nginx"
        local CERT_DIR="${SSL_DIR}/nginx"
        SSL_LABEL="Si (puerto 443)"
        SSL_BLOCK="
server {
    listen 443 ssl;
    server_name ${DOMINIO};
    ssl_certificate     ${CERT_DIR}/server.crt;
    ssl_certificate_key ${CERT_DIR}/server.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    add_header Strict-Transport-Security \"max-age=31536000\" always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;
    root ${WEBROOT};
    index index.html;
    server_tokens off;
}"
        iptables -A INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null
    fi

    # Generar config sin BOM
    cat > "${CONF_DIR}/practica7.conf" << NGINXEOF
server {
    listen ${PUERTO};
    server_name ${DOMINIO};
    root ${WEBROOT};
    index index.html;
    server_tokens off;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    $([ "$SSL" = "si" ] && echo "return 301 https://\$host\$request_uri;")
}
${SSL_BLOCK}
NGINXEOF

    fn_crear_index "Nginx" "$VER" "$PUERTO" "$SSL_LABEL" "$WEBROOT"
    chown -R nginx:nginx "$WEBROOT" 2>/dev/null || true
    iptables -A INPUT -p tcp --dport "$PUERTO" -j ACCEPT 2>/dev/null
}

# -----------------------------------------------------------------------------
# BLOQUE 6: INSTALACION TOMCAT
# -----------------------------------------------------------------------------

fn_instalar_tomcat_ftp() {
    local ARCHIVO="$1"
    local PUERTO="$2"
    local SSL="$3"

    fn_section "Instalacion Tomcat desde FTP - Mageia 9"

    if ! command -v java &>/dev/null; then
        fn_info "Instalando Java OpenJDK..."
        fn_instalar_pkg "java-11-openjdk"
    fi
    fn_ok "Java: $(java -version 2>&1 | head -1)"

    local TOMCAT_BASE="/opt/tomcat_p7"
    mkdir -p "$TOMCAT_BASE"
    fn_info "Extrayendo ${ARCHIVO}..."
    tar -xzf "$ARCHIVO" -C "$TOMCAT_BASE" --strip-components=1 2>/dev/null

    if [ ! -f "${TOMCAT_BASE}/bin/catalina.sh" ]; then
        fn_err "No se pudo extraer Tomcat."
        return 1
    fi
    fn_ok "Tomcat extraido en ${TOMCAT_BASE}"

    fn_configurar_tomcat "$TOMCAT_BASE" "$PUERTO" "$SSL"
    RESUMEN_INSTALACIONES="${RESUMEN_INSTALACIONES}\n  [Tomcat] Puerto: ${PUERTO} | SSL: $([ "$SSL" = "si" ] && echo "Si (443)" || echo "No") | Origen: FTP"
}

fn_instalar_tomcat_web() {
    local PUERTO="$1"
    local SSL="$2"

    fn_section "Instalacion Tomcat via DNF - Mageia 9"
    fn_instalar_pkg "tomcat"

    # Configurar como root para puertos < 1024
    local SVC_FILE="/usr/lib/systemd/system/tomcat.service"
    [ -f "$SVC_FILE" ] && sed -i 's/^User=tomcat/User=root/' "$SVC_FILE"

    # Configurar puerto en ambos server.xml
    for xmlf in "/etc/tomcat/server.xml" "/usr/share/tomcat/conf/server.xml"; do
        [ -f "$xmlf" ] && \
            sed -i "s|Connector port=\"[0-9]*\" address=\"[^\"]*\" protocol=\"HTTP/1.1\"|Connector port=\"${PUERTO}\" address=\"0.0.0.0\" protocol=\"HTTP/1.1\"|g" "$xmlf" && \
            sed -i "s|Connector port=\"[0-9]*\" protocol=\"HTTP/1.1\"|Connector port=\"${PUERTO}\" address=\"0.0.0.0\" protocol=\"HTTP/1.1\"|g" "$xmlf"
    done

    local VER
    VER=$(rpm -q tomcat 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$VER" ] && VER="9.x"

    local SSL_LABEL="No"
    [ "$SSL" = "si" ] && SSL_LABEL="Si (443)"

    fn_crear_index "Tomcat" "$VER" "$PUERTO" "$SSL_LABEL" "/var/lib/tomcat/webapps/ROOT"

    iptables -A INPUT -p tcp --dport "$PUERTO" -j ACCEPT 2>/dev/null
    systemctl daemon-reload
    systemctl enable tomcat 2>/dev/null
    systemctl restart tomcat
    fn_ok "Tomcat instalado via DNF en puerto ${PUERTO}."
    RESUMEN_INSTALACIONES="${RESUMEN_INSTALACIONES}\n  [Tomcat] Puerto: ${PUERTO} | SSL: ${SSL_LABEL} | Origen: WEB"
}

fn_configurar_tomcat() {
    local TOMCAT_BASE="$1"
    local PUERTO="$2"
    local SSL="$3"

    sed -i "s/port=\"8080\"/port=\"${PUERTO}\"/" "${TOMCAT_BASE}/conf/server.xml"
    fn_ok "Puerto Tomcat: ${PUERTO}"

    local SSL_LABEL="No"
    if [ "$SSL" = "si" ]; then
        fn_generar_certificado_ssl "tomcat"
        SSL_LABEL="Si (443)"
        iptables -A INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null
        fn_sec "SSL configurado en Tomcat puerto 443"
    fi

    # Usuario tomcat
    if ! id tomcat &>/dev/null; then
        useradd -r -s /sbin/nologin -d "$TOMCAT_BASE" tomcat 2>/dev/null
    fi
    chown -R tomcat:tomcat "$TOMCAT_BASE"
    chmod +x "${TOMCAT_BASE}/bin/"*.sh

    local VER
    VER=$(find "$TOMCAT_BASE" -name "catalina.jar" 2>/dev/null | head -1 | xargs -I{} unzip -p {} META-INF/MANIFEST.MF 2>/dev/null | grep "Implementation-Version" | awk -F': ' '{print $2}' | tr -d '\r')
    [ -z "$VER" ] && VER="9.x"

    fn_crear_index "Tomcat" "$VER" "$PUERTO" "$SSL_LABEL" "${TOMCAT_BASE}/webapps/ROOT"

    # Servicio systemd
    local JAVA_HOME
    JAVA_HOME=$(readlink -f $(which java) | sed 's|/bin/java||')
    cat > /etc/systemd/system/tomcat_p7.service << SVCEOF
[Unit]
Description=Tomcat P7
After=network.target
[Service]
Type=forking
User=root
Environment=JAVA_HOME=${JAVA_HOME}
Environment=CATALINA_HOME=${TOMCAT_BASE}
ExecStart=${TOMCAT_BASE}/bin/startup.sh
ExecStop=${TOMCAT_BASE}/bin/shutdown.sh
Restart=on-failure
[Install]
WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload
    systemctl enable tomcat_p7 2>/dev/null
    systemctl restart tomcat_p7
    fn_ok "Tomcat iniciado en puerto ${PUERTO}."
}

# -----------------------------------------------------------------------------
# BLOQUE 7: FTPS (SSL en vsftpd)
# -----------------------------------------------------------------------------

fn_configurar_ftps() {
    fn_section "Configuracion FTPS - vsftpd - Mageia 9"

    if ! command -v vsftpd &>/dev/null; then
        fn_info "Instalando vsftpd..."
        fn_instalar_pkg "vsftpd"
    fi

    mkdir -p "${SSL_DIR}/vsftpd"
    fn_sec "Generando certificado SSL para vsftpd..."

    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout "${SSL_DIR}/vsftpd/vsftpd.key" \
        -out "${SSL_DIR}/vsftpd/vsftpd.crt" \
        -subj "/C=MX/ST=Sinaloa/L=Los_Mochis/O=Reprobados/OU=FTP/CN=${DOMINIO}" \
        2>/dev/null

    chmod 600 "${SSL_DIR}/vsftpd/vsftpd.key"
    fn_sec "Certificado FTPS generado."

    # Detectar vsftpd.conf
    local VSFTPD_CONF="/etc/vsftpd/vsftpd.conf"
    [ ! -f "$VSFTPD_CONF" ] && VSFTPD_CONF="/etc/vsftpd.conf"

    # Limpiar configuracion SSL anterior
    for param in ssl_enable rsa_cert_file rsa_private_key_file ssl_tlsv1 \
                 force_local_data_ssl force_local_logins_ssl require_ssl_reuse ssl_ciphers; do
        sed -i "/^${param}/d" "$VSFTPD_CONF"
    done

    cat >> "$VSFTPD_CONF" << FTPSEOF

# FTPS - SSL/TLS - Practica 7
ssl_enable=YES
rsa_cert_file=${SSL_DIR}/vsftpd/vsftpd.crt
rsa_private_key_file=${SSL_DIR}/vsftpd/vsftpd.key
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
force_local_data_ssl=YES
force_local_logins_ssl=YES
require_ssl_reuse=NO
ssl_ciphers=HIGH
FTPSEOF

    iptables -A INPUT -p tcp --dport 21 -j ACCEPT 2>/dev/null
    systemctl restart vsftpd
    fn_ok "FTPS activado en vsftpd."
    RESUMEN_INSTALACIONES="${RESUMEN_INSTALACIONES}\n  [vsftpd] FTPS activado | Cert: ${SSL_DIR}/vsftpd/vsftpd.crt"
}

# -----------------------------------------------------------------------------
# BLOQUE 8: INDEX.HTML PERSONALIZADO
# -----------------------------------------------------------------------------

fn_crear_index() {
    local SERVICIO="$1"
    local VERSION="$2"
    local PUERTO="$3"
    local SSL_LABEL="$4"
    local WEBROOT="$5"

    mkdir -p "$WEBROOT"
    cat > "$WEBROOT/index.html" << HTMLEOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>$SERVICIO - Practica 7</title>
    <style>
        body { font-family: sans-serif; background: #1a1a2e; color: #eee;
               display: flex; justify-content: center; align-items: center;
               height: 100vh; margin: 0; }
        .card { background: #16213e; border-radius: 12px; padding: 40px 60px;
                box-shadow: 0 8px 32px rgba(0,0,0,.5); text-align: center; }
        h1 { color: #4fc3f7; font-size: 2.2em; margin-bottom: .3em; }
        .badge { display: inline-block; background: #e94560; color: #fff;
                 border-radius: 6px; padding: 4px 14px; margin: 6px 4px; }
        .info { color: #a8b2d8; margin-top: 1em; font-size: .9em; }
    </style>
</head>
<body>
    <div class="card">
        <h1>$SERVICIO</h1>
        <span class="badge">Version: $VERSION</span>
        <span class="badge">Puerto: $PUERTO</span>
        <span class="badge">SSL: $SSL_LABEL</span>
        <p class="info">Practica 7 - Mageia 9 | $DOMINIO</p>
    </div>
</body>
</html>
HTMLEOF
    fn_ok "index.html creado en $WEBROOT"
}

# -----------------------------------------------------------------------------
# BLOQUE 9: INSTALACION HIBRIDA
# -----------------------------------------------------------------------------

fn_instalar_servicio_hibrido() {
    local SERVICIO="$1"
    local NOMBRE_DISPLAY="$2"

    fn_section "Instalacion de ${NOMBRE_DISPLAY}"

    # Origen
    echo ""
    echo -e "${CYAN}+-------------------------------+"
    echo -e "| Origen de instalacion:        |"
    echo -e "| 1) WEB (DNF/repositorio)      |"
    echo -e "| 2) FTP (repositorio privado)  |"
    echo -e "+-------------------------------+${NC}"
    echo ""
    local ORIGEN=""
    while true; do
        read -rp "  Selecciona origen: " ORIGEN
        case "$ORIGEN" in 1|2) break ;; *) fn_err "Elige 1 o 2." ;; esac
    done

    # Puerto
    echo ""
    local PUERTO=""
    while true; do
        read -rp "  Puerto para ${NOMBRE_DISPLAY}: " PUERTO
        if [[ "$PUERTO" =~ ^[0-9]+$ ]] && [ "$PUERTO" -ge 1 ] && [ "$PUERTO" -le 65535 ]; then
            if ss -tlnp 2>/dev/null | grep -q ":${PUERTO} "; then
                fn_err "Puerto ${PUERTO} ya esta en uso."
            else
                fn_ok "Puerto ${PUERTO} disponible."
                break
            fi
        else
            fn_err "Puerto invalido."
        fi
    done

    # SSL
    local SSL="no"
    fn_preguntar_ssl && SSL="si"

    # Instalar
    if [ "$ORIGEN" = "1" ]; then
        case "$SERVICIO" in
            apache) fn_instalar_apache_web "$PUERTO" "$SSL" ;;
            nginx)  fn_instalar_nginx_web  "$PUERTO" "$SSL" ;;
            tomcat) fn_instalar_tomcat_web "$PUERTO" "$SSL" ;;
        esac
    else
        fn_ftp_navegar_y_descargar "$NOMBRE_DISPLAY" "$INSTALL_DIR" || return 1
        fn_verificar_hash "$FTP_ARCHIVO_DESCARGADO" "$FTP_SHA256_DESCARGADO" || return 1
        case "$SERVICIO" in
            apache) fn_instalar_apache_ftp "$FTP_ARCHIVO_DESCARGADO" "$PUERTO" "$SSL" ;;
            nginx)  fn_instalar_nginx_ftp  "$FTP_ARCHIVO_DESCARGADO" "$PUERTO" "$SSL" ;;
            tomcat) fn_instalar_tomcat_ftp "$FTP_ARCHIVO_DESCARGADO" "$PUERTO" "$SSL" ;;
        esac
    fi

    # Verificar
    sleep 2
    fn_verificar_servicio_http "$NOMBRE_DISPLAY" "$PUERTO" "$SSL"
}

# -----------------------------------------------------------------------------
# BLOQUE 10: VERIFICACION AUTOMATIZADA
# -----------------------------------------------------------------------------

fn_verificar_servicio_http() {
    local NOMBRE="$1"
    local PUERTO="$2"
    local SSL="$3"

    fn_section "Verificacion: $NOMBRE"

    # Puerto activo
    if ss -tlnp 2>/dev/null | grep -q ":${PUERTO} "; then
        fn_ok "${NOMBRE} escuchando en puerto ${PUERTO}"
    else
        fn_err "${NOMBRE} NO escucha en puerto ${PUERTO}"
        return 1
    fi

    # Respuesta HTTP
    local RESP
    RESP=$(curl -sk --connect-timeout 5 "http://127.0.0.1:${PUERTO}" \
           -o /dev/null -w "%{http_code}" 2>/dev/null)
    fn_ok "${NOMBRE} responde HTTP con codigo: ${RESP}"

    # SSL
    if [ "$SSL" = "si" ]; then
        local RESP_SSL
        RESP_SSL=$(curl -sk --connect-timeout 5 "https://127.0.0.1:443" \
                   -o /dev/null -w "%{http_code}" 2>/dev/null)
        fn_sec "${NOMBRE} responde HTTPS con codigo: ${RESP_SSL}"

        local CERT_INFO
        CERT_INFO=$(echo | openssl s_client -connect "127.0.0.1:443" \
                    -servername "${DOMINIO}" 2>/dev/null | \
                    openssl x509 -noout -subject -dates 2>/dev/null)
        if [ -n "$CERT_INFO" ]; then
            fn_sec "Certificado SSL verificado:"
            echo "$CERT_INFO" | while read -r linea; do echo "    $linea"; done
        fi
    fi
}

# -----------------------------------------------------------------------------
# BLOQUE 11: RESUMEN FINAL
# -----------------------------------------------------------------------------

fn_mostrar_resumen() {
    fn_section "Resumen de Instalaciones - Practica 7"

    if [ -z "$RESUMEN_INSTALACIONES" ]; then
        fn_warn "No hay instalaciones registradas en esta sesion."
    else
        echo -e "${GREEN}  Servicios instalados/configurados:${NC}"
        echo -e "$RESUMEN_INSTALACIONES"
    fi

    echo ""
    echo -e "${CYAN}  Puertos en escucha:${NC}"
    ss -tlnp 2>/dev/null | grep LISTEN | awk '{print "    " $4}' | sort

    echo ""
    echo -e "${CYAN}  Certificados SSL generados:${NC}"
    if [ -d "$SSL_DIR" ]; then
        find "$SSL_DIR" -name "*.crt" 2>/dev/null | while read -r cert; do
            echo "  Archivo: $cert"
            openssl x509 -noout -subject -enddate -in "$cert" 2>/dev/null | \
                while read -r l; do echo "    $l"; done
        done
    else
        echo "  (ninguno generado aun)"
    fi
    echo ""
}