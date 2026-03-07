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
# El usuario puede: leer y escribir archivos propios
# NO puede: eliminar ni renombrar carpetas del sistema
# ================================================================
set_permiso_restringido() {
    local path="$1"
    local usuario="$2"
    local grupo="$3"

    # Propietario root, grupo del usuario
    chown root:"$grupo" "$path"

    # 3775 = setgid + sticky: 
    # - setgid: archivos nuevos heredan el grupo
    # - sticky: solo el dueño puede borrar/renombrar sus propios archivos
    chmod 3775 "$path"

    # Aplicar sticky bit recursivamente a subdirectorios
    find "$path" -type d -exec chmod +t {} \; 2>/dev/null
}

# ================================================================
# FUNCION PARA CARPETA PERSONAL (control total del dueño)
# ================================================================
set_permiso_personal() {
    local path="$1"
    local usuario="$2"

    chown "$usuario":"$GRP_BASE" "$path"
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
    mkdir -p "$RAIZ_FTP/publica" \
             "$DIR_GRUPOS/$GRP_A" \
             "$DIR_GRUPOS/$GRP_B" \
             "$DIR_PERSONAL" \
             "$DIR_HOME_USUARIOS"

    # Carpeta anonima: propiedad root, sin escritura, SIN contenido visible
    mkdir -p "$DIR_ANONIMO"
    chown root:root "$DIR_ANONIMO"
    chmod 555 "$DIR_ANONIMO"   # Solo lectura, sin escritura para nadie

    # Carpeta publica con sticky bit
    chown root:"$GRP_BASE" "$RAIZ_FTP/publica"
    chmod 3775 "$RAIZ_FTP/publica"

    # Permisos para grupos especificos con sticky + setgid
    chown root:"$GRP_A" "$DIR_GRUPOS/$GRP_A"
    chmod 3775 "$DIR_GRUPOS/$GRP_A"

    chown root:"$GRP_B" "$DIR_GRUPOS/$GRP_B"
    chmod 3775 "$DIR_GRUPOS/$GRP_B"

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

    # Crear lista de usuarios que NO pueden entrar (bloquear ftp y root)
    echo "root" > /etc/vsftpd.user_list
    echo "ftp"  >> /etc/vsftpd.user_list

    cat > /etc/vsftpd.conf <<CONF_MAESTRA
# CONFIGURACION PERSONALIZADA VSFTPD
listen=YES
listen_ipv6=NO

# --- SEGMENTO ANONIMO ---
# Anonymous entra pero ve carpeta vacia (sin contenido)
anonymous_enable=YES
no_anon_password=YES
anon_root=$DIR_ANONIMO
anon_upload_enable=NO
anon_mkdir_write_enable=NO
anon_other_write_enable=NO

# --- SEGMENTO USUARIOS LOCALES ---
local_enable=YES
write_enable=YES
local_umask=022
file_open_mode=0644

# --- SEGURIDAD Y JAULAS (CHROOT) ---
chroot_local_user=YES
allow_writeable_chroot=YES
user_sub_token=\$USER
local_root=$DIR_HOME_USUARIOS/\$USER

# --- LISTA DE USUARIOS BLOQUEADOS ---
userlist_enable=YES
userlist_deny=YES
userlist_file=/etc/vsftpd.user_list

# --- PARAMETROS DE SESION ---
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
    info  "Anonymous: entra sin password, ve carpeta vacia."
    info  "Usuarios: entran con password, ven solo su home."
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

        # Creación del usuario
        if ! getent passwd "$user_id" > /dev/null; then
            useradd -m -g "$GRP_BASE" -G "$perfil_seleccionado" -s /sbin/nologin "$user_id"
            echo "$user_id:$user_key" | chpasswd
            exito "Cuenta $user_id creada."
        else
            aviso "El usuario $user_id ya existe. Actualizando perfil..."
            usermod -a -G "$perfil_seleccionado" "$user_id"
            echo "$user_id:$user_key" | chpasswd
        fi

        # Directorio home virtual
        HOME_VIRTUAL="$DIR_HOME_USUARIOS/$user_id"
        mkdir -p "$HOME_VIRTUAL"/{publica,"$perfil_seleccionado",personal}

        # Root del home: propiedad root, el usuario NO puede modificarlo
        chown root:root "$HOME_VIRTUAL"
        chmod 755 "$HOME_VIRTUAL"

        # Montar carpeta publica con permisos restringidos
        if ! mountpoint -q "$HOME_VIRTUAL/publica" 2>/dev/null; then
            mount --bind "$RAIZ_FTP/publica" "$HOME_VIRTUAL/publica"
        fi
        set_permiso_restringido "$HOME_VIRTUAL/publica" "$user_id" "$GRP_BASE"

        # Montar carpeta de grupo con permisos restringidos
        if ! mountpoint -q "$HOME_VIRTUAL/$perfil_seleccionado" 2>/dev/null; then
            mount --bind "$DIR_GRUPOS/$perfil_seleccionado" "$HOME_VIRTUAL/$perfil_seleccionado"
        fi
        set_permiso_restringido "$HOME_VIRTUAL/$perfil_seleccionado" "$user_id" "$perfil_seleccionado"

        # Carpeta personal: control total solo del dueño
        mkdir -p "$DIR_PERSONAL/$user_id"
        set_permiso_personal "$DIR_PERSONAL/$user_id" "$user_id"
        if ! mountpoint -q "$HOME_VIRTUAL/personal" 2>/dev/null; then
            mount --bind "$DIR_PERSONAL/$user_id" "$HOME_VIRTUAL/personal"
        fi
        chown "$user_id":"$GRP_BASE" "$HOME_VIRTUAL/personal"
        chmod 700 "$HOME_VIRTUAL/personal"

        exito "Usuario '$user_id' listo. Home: $HOME_VIRTUAL"
        info  "Subcarpetas: publica, $perfil_seleccionado, personal"
        info  "Permisos: puede leer/escribir sus archivos. NO puede borrar ni renombrar lo ajeno."
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
    if ! mountpoint -q "$RAIZ_VIRTUAL/$nuevo" 2>/dev/null; then
        mount --bind "$DIR_GRUPOS/$nuevo" "$RAIZ_VIRTUAL/$nuevo"
    fi
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