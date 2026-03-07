#!/bin/bash

# ==============================================================
#                      SERVIDOR FTP - PRACTICA 
# ==============================================================

# --- Definicion de Rutas y Constantes ---
RAIZ_FTP="/srv/ftp"
DIR_GRUPOS="$RAIZ_FTP/grupos"
DIR_ANONIMO="$RAIZ_FTP/anonymous"
DIR_PERSONAL="$RAIZ_FTP/personal"
DIR_HOME_USUARIOS="$RAIZ_FTP/users"

GRP_A="reprobados"
GRP_B="recursadores"
GRP_BASE="ftp_users"

# --- Funciones de Utilidad y Estética ---
info()  { echo -e "\e[34m[INFO]\e[0m $1"; }
exito() { echo -e "\e[32m[OK]\e[0m $1"; }
error() { echo -e "\e[31m[ERROR]\e[0m $1"; }
aviso() { echo -e "\e[33m[AVISO]\e[0m $1"; }

# 0. Privilegios Administrativos
if [[ $(id -u) -ne 0 ]]; then
    error "Se requieren privilegios de superusuario para continuar."
    exit 1
fi

# ================================================================
# FUNCION CENTRAL DE PERMISOS RESTRINGIDOS
# El usuario puede: leer, crear y escribir archivos
# NO puede: eliminar, renombrar carpetas del sistema
# ================================================================
set_permiso_restringido() {
    local path="$1"
    local usuario="$2"
    local grupo="$3"

    # Propietario root, grupo del usuario
    chown root:"$grupo" "$path"

    # rwxrwx--- : grupo puede leer/escribir/ejecutar pero NO sticky bit
    # El sticky bit (+t) en directorios impide que usuarios borren/renombren
    # archivos o carpetas que no les pertenecen
    chmod 1775 "$path"

    # Aplicar sticky bit recursivamente para proteger subcarpetas
    find "$path" -type d -exec chmod +t {} \; 2>/dev/null
}

# ================================================================
# FUNCION PARA CARPETA PERSONAL (control total del dueño)
# ================================================================
set_permiso_personal() {
    local path="$1"
    local usuario="$2"

    chown "$usuario":"$GRP_BASE" "$path"
    # 700 = solo el dueño tiene control total, nadie más entra
    chmod 700 "$path"
}

# ================================================================
# 1. Preparación del Sistema y Binarios
# ================================================================
inicializar_sistema() {
    info "Validando presencia de vsftpd..."
    if ! rpm -qa | grep -q vsftpd; then
        info "Descargando e instalando paquetes necesarios..."
        urpmi.update -a && urpmi vsftpd --auto
        if [ $? -ne 0 ]; then
            error "La instalación ha fallado. Verifique su conexión."
            return 1
        fi
        exito "Software instalado correctamente."
    else
        aviso "vsftpd ya se encuentra en el sistema."
    fi

    # Configurar shell seguro
    if ! grep -q "/sbin/nologin" /etc/shells; then
        echo "/sbin/nologin" >> /etc/shells
        info "Shell /sbin/nologin habilitado."
    fi
}

# ================================================================
# 2. Configuración de Almacenamiento y Jerarquías
# ================================================================
preparar_entorno_ftp() {
    info "Generando estructura de directorios en $RAIZ_FTP..."

    # Creación de grupos si no existen
    for g in "$GRP_A" "$GRP_B" "$GRP_BASE"; do
        groupadd -f "$g"
    done

    # Creación de carpetas base
    mkdir -p "$RAIZ_FTP/publica" "$DIR_GRUPOS/$GRP_A" "$DIR_GRUPOS/$GRP_B" "$DIR_PERSONAL" "$DIR_HOME_USUARIOS"

    # Carpeta anónima y sus subdirectorios de espejo
    mkdir -p "$DIR_ANONIMO"/{publica,"$GRP_A","$GRP_B"}

    # Carpeta publica: sticky bit para que nadie borre lo ajeno
    chown root:"$GRP_BASE" "$RAIZ_FTP/publica"
    chmod 1777 "$RAIZ_FTP/publica"

    # Permisos para grupos específicos con sticky bit
    chown root:"$GRP_A" "$DIR_GRUPOS/$GRP_A"
    chmod 3775 "$DIR_GRUPOS/$GRP_A"   # setgid + sticky

    chown root:"$GRP_B" "$DIR_GRUPOS/$GRP_B"
    chmod 3775 "$DIR_GRUPOS/$GRP_B"   # setgid + sticky

    # Configuración de montajes en espejo (Solo Lectura para Anónimos)
    configurar_montaje_ro() {
        if ! mountpoint -q "$1" 2>/dev/null; then
            mount --bind "$2" "$1"
            mount -o remount,ro,bind "$1"
        fi
    }

    configurar_montaje_ro "$DIR_ANONIMO/publica"  "$RAIZ_FTP/publica"
    configurar_montaje_ro "$DIR_ANONIMO/$GRP_A"   "$DIR_GRUPOS/$GRP_A"
    configurar_montaje_ro "$DIR_ANONIMO/$GRP_B"   "$DIR_GRUPOS/$GRP_B"

    chown root:root "$DIR_ANONIMO"
    chmod 555 "$DIR_ANONIMO"

    # Apertura de puertos
    info "Configurando excepciones en el cortafuegos..."
    if hash firewall-cmd 2>/dev/null; then
        firewall-cmd --permanent --add-service=ftp
        firewall-cmd --permanent --add-port=40000-40100/tcp
        firewall-cmd --reload > /dev/null
    else
        iptables -I INPUT -p tcp --dport 21 -j ACCEPT
        iptables -I INPUT -p tcp --dport 40000:40100 -j ACCEPT
    fi
    exito "Infraestructura de red y archivos lista."
}

# ================================================================
# 3. Aplicar Parámetros de vsftpd
# ================================================================
desplegar_configuracion() {
    IP_LOCAL=$(hostname -I | cut -f1 -d' ')
    info "Generando archivo maestro: /etc/vsftpd.conf ($IP_LOCAL)..."

    mkdir -p /usr/share/empty ; chmod 555 /usr/share/empty

    cat > /etc/vsftpd.conf <<CONF_MAESTRA
# CONFIGURACIÓN PERSONALIZADA VSFTPD
listen=YES
listen_ipv6=NO

# --- SEGMENTO ANÓNIMO ---
anonymous_enable=YES
no_anon_password=YES
anon_root=$DIR_ANONIMO
anon_upload_enable=NO
anon_mkdir_write_enable=NO
anon_other_write_enable=NO

# --- SEGMENTO USUARIOS LOCALES ---
local_enable=YES
write_enable=YES
local_umask=002
file_open_mode=0775

# --- SEGURIDAD Y JAULAS (CHROOT) ---
chroot_local_user=YES
allow_writeable_chroot=YES
user_sub_token=\$USER
local_root=$DIR_HOME_USUARIOS/\$USER

# --- PARAMETROS DE SESIÓN ---
pam_service_name=vsftpd
check_shell=NO
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
pasv_address=$IP_LOCAL

# --- LOGS Y VARIOS ---
xferlog_enable=YES
dirmessage_enable=YES
use_localtime=YES
connect_from_port_20=YES
secure_chroot_dir=/usr/share/empty
CONF_MAESTRA

    [ -d "/etc/vsftpd" ] && cp /etc/vsftpd.conf /etc/vsftpd/vsftpd.conf

    systemctl restart vsftpd && systemctl enable vsftpd
    exito "El servicio FTP se ha reiniciado correctamente."
}

# ================================================================
# 4. Inserción de Nuevos Integrantes
# ================================================================
registrar_usuarios_ftp() {
    echo -n "Ingrese la cantidad de usuarios a dar de alta: "
    read total

    for (( c=1; c<=total; c++ )); do
        echo "-----------------------------------"
        echo -n "[$c/$total] Alias del usuario: "
        read user_id
        echo -n "Contraseña para $user_id: "
        read -s user_key ; echo ""

        echo "Seleccione perfil de acceso:"
        echo "  A) $GRP_A"
        echo "  B) $GRP_B"
        read -n 1 -p "Opción: " perfil ; echo ""

        perfil_seleccionado="$GRP_A"
        [[ "${perfil,,}" == "b" ]] && perfil_seleccionado="$GRP_B"

        # Creación técnica del usuario
        if ! getent passwd "$user_id" > /dev/null; then
            useradd -m -g "$GRP_BASE" -G "$perfil_seleccionado" -s /sbin/nologin "$user_id"
            echo "$user_id:$user_key" | chpasswd
            exito "Cuenta $user_id creada."
        else
            aviso "El usuario $user_id ya existe. Actualizando perfil..."
            usermod -a -G "$perfil_seleccionado" "$user_id"
            echo "$user_id:$user_key" | chpasswd
        fi

        # Directorio home virtual del usuario
        HOME_VIRTUAL="$DIR_HOME_USUARIOS/$user_id"
        mkdir -p "$HOME_VIRTUAL"/{publica,"$perfil_seleccionado",personal}

        # Root del home: propiedad root, no modificable por el usuario
        chown root:root "$HOME_VIRTUAL"
        chmod 755 "$HOME_VIRTUAL"

        # Montar carpeta publica con sticky bit (no borrar lo ajeno)
        mount --bind "$RAIZ_FTP/publica" "$HOME_VIRTUAL/publica"
        set_permiso_restringido "$HOME_VIRTUAL/publica" "$user_id" "$GRP_BASE"

        # Montar carpeta de grupo con sticky bit
        mount --bind "$DIR_GRUPOS/$perfil_seleccionado" "$HOME_VIRTUAL/$perfil_seleccionado"
        set_permiso_restringido "$HOME_VIRTUAL/$perfil_seleccionado" "$user_id" "$perfil_seleccionado"

        # Carpeta personal: control total solo del dueño
        mkdir -p "$DIR_PERSONAL/$user_id"
        set_permiso_personal "$DIR_PERSONAL/$user_id" "$user_id"
        mount --bind "$DIR_PERSONAL/$user_id" "$HOME_VIRTUAL/personal"

        # La carpeta personal montada hereda permisos del dueño
        chown "$user_id":"$GRP_BASE" "$HOME_VIRTUAL/personal"
        chmod 700 "$HOME_VIRTUAL/personal"

        exito "Usuario '$user_id' listo. Home: $HOME_VIRTUAL"
        info  "Subcarpetas: publica, $perfil_seleccionado, personal"
        info  "Permisos: puede leer/escribir archivos. NO puede borrar ni renombrar lo ajeno."
    done
}

# ================================================================
# 5. Modificación de Perfil de Acceso
# ================================================================
migrar_usuario() {
    echo -n "Identificador del usuario a modificar: "
    read target

    if ! getent passwd "$target" > /dev/null; then
        error "No se encontró el registro para '$target'."
        return
    fi

    echo "Seleccione el nuevo destino:"
    echo "  1) $GRP_A"
    echo "  2) $GRP_B"
    read -p "Opción: " n_opt

    nuevo="$GRP_A" ; previo="$GRP_B"
    if [[ "$n_opt" == "2" ]]; then
        nuevo="$GRP_B" ; previo="$GRP_A"
    fi

    gpasswd -d "$target" "$previo" 2>/dev/null
    usermod -a -G "$nuevo" "$target"

    RAIZ_VIRTUAL="$DIR_HOME_USUARIOS/$target"

    if mountpoint -q "$RAIZ_VIRTUAL/$previo" 2>/dev/null; then
        umount -l "$RAIZ_VIRTUAL/$previo"
    fi
    rmdir "$RAIZ_VIRTUAL/$previo" 2>/dev/null

    mkdir -p "$RAIZ_VIRTUAL/$nuevo"
    mount --bind "$DIR_GRUPOS/$nuevo" "$RAIZ_VIRTUAL/$nuevo"
    set_permiso_restringido "$RAIZ_VIRTUAL/$nuevo" "$target" "$nuevo"

    exito "El usuario $target ha sido migrado a $nuevo."
}

# ================================================================
# 6. Remoción de Integrante
# ================================================================
baja_usuario() {
    echo -n "Nombre del usuario a dar de baja: "
    read alias_del

    if ! id "$alias_del" &>/dev/null; then
        error "Usuario inexistente."
        return
    fi

    aviso "Iniciando proceso de limpieza para $alias_del..."
    H_VIR="$DIR_HOME_USUARIOS/$alias_del"

    for mnt in publica "$GRP_A" "$GRP_B" personal; do
        umount -l "$H_VIR/$mnt" 2>/dev/null
    done

    userdel -r "$alias_del" 2>/dev/null
    rm -rf "$H_VIR"
    rm -rf "$DIR_PERSONAL/$alias_del"

    exito "El usuario $alias_del y sus datos han sido eliminados."
}

# ================================================================
# 7. Auditoría de Usuarios
# ================================================================
visor_usuarios() {
    echo -e "\n\e[1;36m>> LISTADO DE CUENTAS POR PERFIL <<\e[0m"
    echo "=========================================="

    hay_datos=0
    for g in "$GRP_A" "$GRP_B"; do
        lista=$(getent group "$g" | cut -d: -f4 | sed 's/,/  /g')
        if [[ ! -z "$lista" ]]; then
            [[ $hay_datos -eq 0 ]] && printf "%-18s | %-15s\n" "NOMBRE" "PERFIL" && echo "-------------------|----------------"
            for u in $lista; do
                printf "%-18s | %-15s\n" "$u" "$g"
                hay_datos=1
            done
        fi
    done

    [[ $hay_datos -eq 0 ]] && aviso "No se encontraron usuarios en los grupos administrados."
    echo "=========================================="
    read -p "Pulse [Enter] para retornar..."
}

# ================================================================
# 8. Verificación de Inicio de Sesión
# ================================================================
validar_login() {
    echo -e "\n--- MONITOR DE ACCESO ---"
    echo -n "Ingrese su identificación: "
    read u_name

    if getent passwd "$u_name" > /dev/null; then
        if ! groups "$u_name" | grep -qE "$GRP_A|$GRP_B"; then
            error "Acceso denegado: El usuario no tiene perfil FTP asignado."
            return
        fi

        echo -n "Ingrese PIN / Pass: "
        read -s u_pin ; echo ""
        exito "¡Sesión iniciada! Hola de nuevo, $u_name."
        info "Puntos de montaje visibles:"
        ls -F "$DIR_HOME_USUARIOS/$u_name" 2>/dev/null || error "Falla al localizar raíz virtual."
    else
        error "Usuario no reconocido en la base de datos."
    fi
    read -p "...Enter para continuar..."
}

# ================================================================
#                   PANEL DE CONTROL PRINCIPAL
# ================================================================
opc_menu=0
while [[ $opc_menu -ne 7 ]]; do
    clear
    echo -e "\e[1;35m╔══════════════════════════════════════════════╗\e[0m"
    echo -e "\e[1;35m║  CONSOLA DE CONTROL - SERVIDOR FTP (LINUX)   ║\e[0m"
    echo -e "\e[1;35m╚══════════════════════════════════════════════╝\e[0m"
    echo "  1) Despliegue: Instalar y Configurar vsftpd"
    echo "  2) Usuarios: Registro Masivo de Cuentas"
    echo "  3) Auditoría: Ver Usuarios en Sistema"
    echo "  4) Gestión: Modificar Perfil de Usuario"
    echo "  5) Seguridad: Eliminar Cuenta de Usuario"
    echo "  6) Simulación: Prueba de Inicio de Sesión"
    echo "  7) Finalizar Aplicación"
    echo "------------------------------------------------"
    echo -n "Seleccione una acción [1-7]: "
    read opc_menu

    case $opc_menu in
        1) inicializar_sistema ; preparar_entorno_ftp ; desplegar_configuracion ;;
        2) registrar_usuarios_ftp ;;
        3) visor_usuarios ;;
        4) migrar_usuario ;;
        5) baja_usuario ;;
        6) validar_login ;;
        7) exito "Cerrando consola de administración." ;;
        *) aviso "Opción fuera de rango." ; sleep 1 ;;
    esac

    [[ $opc_menu -ne 7 && $opc_menu -ne 3 && $opc_menu -ne 6 ]] && echo "" && read -p "Acción completada. Pulse Enter..."
done