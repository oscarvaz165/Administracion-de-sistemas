#!/bin/bash
# ==============================================================================
# join_domain.sh - Unir Linux al dominio reprobados.local
# Practica 8 | Mageia 9 / Ubuntu
# Uso: sudo ./join_domain.sh
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

fn_ok()   { echo -e "${GREEN}  [OK]    $1${NC}"; }
fn_info() { echo -e "${CYAN}  [INFO]  $1${NC}"; }
fn_err()  { echo -e "${RED}  [ERROR] $1${NC}"; }
fn_warn() { echo -e "${YELLOW}  [WARN]  $1${NC}"; }

DOMINIO="reprobados.local"
DOMINIO_UPPER="REPROBADOS.LOCAL"
DC_IP="192.168.56.104"
AD_ADMIN="Administrador"

# Verificar root
if [ "$EUID" -ne 0 ]; then
    fn_err "Ejecuta como root: sudo ./join_domain.sh"
    exit 1
fi

fn_info "Iniciando union al dominio $DOMINIO..."

# ------------------------------------------------------------------------------
# 1. Instalar dependencias
# ------------------------------------------------------------------------------
fn_info "Instalando paquetes necesarios..."
if command -v dnf &>/dev/null; then
    dnf install -y realmd sssd sssd-tools adcli krb5-workstation \
        oddjob oddjob-mkhomedir samba-common-tools 2>/dev/null
elif command -v apt-get &>/dev/null; then
    apt-get install -y realmd sssd sssd-tools adcli krb5-user \
        oddjob oddjob-mkhomedir samba-common-bin 2>/dev/null
fi
fn_ok "Paquetes instalados."

# ------------------------------------------------------------------------------
# 2. Configurar DNS para apuntar al DC
# ------------------------------------------------------------------------------
fn_info "Configurando DNS..."
cat > /etc/resolv.conf << EOF
search $DOMINIO
nameserver $DC_IP
EOF
chattr +i /etc/resolv.conf 2>/dev/null || true
fn_ok "DNS configurado -> $DC_IP"

# ------------------------------------------------------------------------------
# 3. Sincronizar hora con el DC (requerido por Kerberos)
# ------------------------------------------------------------------------------
fn_info "Sincronizando hora con el DC..."
if command -v dnf &>/dev/null; then
    dnf install -y chrony 2>/dev/null
    systemctl enable chronyd --now 2>/dev/null
else
    apt-get install -y chrony 2>/dev/null
    systemctl enable chrony --now 2>/dev/null
fi

cat >> /etc/chrony.conf << EOF
server $DC_IP iburst prefer
EOF
systemctl restart chronyd 2>/dev/null || systemctl restart chrony 2>/dev/null
sleep 2
fn_ok "Hora sincronizada."

# ------------------------------------------------------------------------------
# 4. Unir al dominio con realmd
# ------------------------------------------------------------------------------
fn_info "Uniendo al dominio $DOMINIO..."
fn_info "Se solicitara la contrasena del Administrador del dominio."

realm discover $DOMINIO
realm join --user=$AD_ADMIN $DOMINIO

if [ $? -eq 0 ]; then
    fn_ok "Unido al dominio $DOMINIO exitosamente."
else
    fn_err "No se pudo unir al dominio. Verifica conectividad y contrasena."
    exit 1
fi

# ------------------------------------------------------------------------------
# 5. Configurar sssd.conf
# ------------------------------------------------------------------------------
fn_info "Configurando sssd.conf..."
cat > /etc/sssd/sssd.conf << EOF
[sssd]
domains = $DOMINIO
config_file_version = 2
services = nss, pam

[domain/$DOMINIO]
ad_domain = $DOMINIO
krb5_realm = $DOMINIO_UPPER
realmd_tags = manages-system joined-with-adcli
cache_credentials = True
id_provider = ad
krb5_store_password_if_offline = True
default_shell = /bin/bash
ldap_id_mapping = True
use_fully_qualified_names = False
fallback_homedir = /home/%u@%d
access_provider = ad
EOF

chmod 600 /etc/sssd/sssd.conf
systemctl restart sssd
fn_ok "sssd.conf configurado. fallback_homedir = /home/%u@%d"

# ------------------------------------------------------------------------------
# 6. Crear directorios home automaticamente
# ------------------------------------------------------------------------------
fn_info "Habilitando creacion automatica de home..."
if command -v authselect &>/dev/null; then
    authselect select sssd with-mkhomedir --force
elif [ -f /etc/pam.d/common-session ]; then
    echo "session required pam_mkhomedir.so skel=/etc/skel/ umask=0077" >> /etc/pam.d/common-session
fi
systemctl enable --now oddjobd 2>/dev/null || true
fn_ok "Creacion automatica de home habilitada."

# ------------------------------------------------------------------------------
# 7. Permisos sudo para usuarios AD
# ------------------------------------------------------------------------------
fn_info "Configurando sudo para usuarios de AD..."
cat > /etc/sudoers.d/ad-admins << EOF
# Sudo para usuarios del dominio reprobados.local
# Grupo Cuates: sudo completo
%Cuates@$DOMINIO ALL=(ALL) ALL

# Grupo NoCuates: sin sudo
# %NoCuates@$DOMINIO ALL=(ALL) NOPASSWD: /bin/false
EOF
chmod 440 /etc/sudoers.d/ad-admins
fn_ok "Permisos sudo configurados en /etc/sudoers.d/ad-admins"

# ------------------------------------------------------------------------------
# 8. Verificar union al dominio
# ------------------------------------------------------------------------------
fn_info "Verificando configuracion..."
realm list
echo ""
fn_ok "Linux unido al dominio $DOMINIO exitosamente."
fn_info "Prueba con: id jgarcia@$DOMINIO"
fn_info "O inicia sesion con: su - jgarcia@$DOMINIO"