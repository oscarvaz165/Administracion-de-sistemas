#!/usr/bin/env bash
set -euo pipefail

# =========================
# CONFIG
# =========================
FTP_ROOT="/srv/ftp-practica"
GENERAL_DIR="$FTP_ROOT/general"
GRP_REPRO_DIR="$FTP_ROOT/reprobados"
GRP_RECUR_DIR="$FTP_ROOT/recursadores"
USERS_DIR="$FTP_ROOT/users"

VSFTPD_CONF="/etc/vsftpd/vsftpd.conf"
VSFTPD_USERLIST="/etc/vsftpd/user_list"
VSFTPD_CHROOT_LIST="/etc/vsftpd/chroot_list"
VSFTPD_BANNER="FTP Practica - Acceso controlado por grupos"

die(){ echo "[ERROR] $*" >&2; exit 1; }
ok(){ echo "[OK] $*"; }
pause(){ read -r -p "Enter para continuar..." _; }

require_root(){
  [[ "${EUID}" -eq 0 ]] || die "Ejecuta como root (su -) o con sudo."
}

pkg_install(){
  # Mageia usa urpmi
  if ! command -v urpmi >/dev/null 2>&1; then
    die "No encuentro urpmi. ¿Seguro que esto es Mageia?"
  fi
  urpmi --auto --auto-select "$@"
}

ensure_groups(){
  getent group reprobados >/dev/null 2>&1 || groupadd reprobados
  getent group recursadores >/dev/null 2>&1 || groupadd recursadores
  ok "Grupos reprobados/recursadores listos."
}

ensure_dirs(){
  mkdir -p "$GENERAL_DIR" "$GRP_REPRO_DIR" "$GRP_RECUR_DIR" "$USERS_DIR"

  # Permisos base:
  # - general: lectura para todos, escritura solo para autenticados (via grupo ftpusers)
  # Para no complicarnos con ACLs, creamos un grupo "ftpusers" para dar write en general.
  getent group ftpusers >/dev/null 2>&1 || groupadd ftpusers

  chown root:root "$FTP_ROOT"
  chmod 755 "$FTP_ROOT"

  # general: readable por todos (incluye anonymous), writable por ftpusers
  chown root:ftpusers "$GENERAL_DIR"
  chmod 775 "$GENERAL_DIR"

  # directorios de grupo: solo miembros del grupo escriben
  chown root:reprobados "$GRP_REPRO_DIR"
  chmod 2770 "$GRP_REPRO_DIR"   # setgid para heredar grupo

  chown root:recursadores "$GRP_RECUR_DIR"
  chmod 2770 "$GRP_RECUR_DIR"

  # users dir: solo root puede listar (pero cada usuario entra a su carpeta)
  chown root:root "$USERS_DIR"
  chmod 755 "$USERS_DIR"

  ok "Estructura de carpetas lista en $FTP_ROOT"
}

write_vsftpd_conf(){
  mkdir -p /etc/vsftpd

  # Archivos auxiliares
  touch "$VSFTPD_USERLIST" "$VSFTPD_CHROOT_LIST"
  chmod 600 "$VSFTPD_CHROOT_LIST" || true

  # Configuración vsftpd:
  # - Habilita anonymous pero restringido por permisos del FS
  # - Habilita local users + escritura
  # - Chroot local users para que vean FTP_ROOT como raíz
  #   Usamos local_root dentro de su home, y "secure_chroot_dir" para seguridad.
  #   Para que vean la estructura general/grupo/usuario desde "raíz",
  #   hacemos bind-mounts en cada home (más abajo) hacia FTP_ROOT.
  cat > "$VSFTPD_CONF" <<EOF
listen=YES
listen_ipv6=NO
anonymous_enable=YES
local_enable=YES
write_enable=YES

dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
ftpd_banner=$VSFTPD_BANNER

# Seguridad
pam_service_name=vsftpd
userlist_enable=YES
userlist_file=$VSFTPD_USERLIST
userlist_deny=NO

# Enjaular (chroot) usuarios locales
chroot_local_user=YES
allow_writeable_chroot=YES

# Directorio raíz para anónimo:
anon_root=$FTP_ROOT

# Modo PASV (ajusta rango si tu firewall lo requiere)
pasv_enable=YES
pasv_min_port=30000
pasv_max_port=30100

# Opcional: limitar permisos por umask
local_umask=022

# No permitir comandos peligrosos en anónimo (por FS igual)
anon_mkdir_write_enable=NO
anon_upload_enable=NO
anon_other_write_enable=NO
EOF

  ok "vsftpd.conf escrito en $VSFTPD_CONF"
}

enable_service(){
  # Instala paquete
  if ! rpm -q vsftpd >/dev/null 2>&1; then
    ok "Instalando vsftpd..."
    pkg_install vsftpd
  else
    ok "vsftpd ya instalado."
  fi

  # Habilitar y arrancar
  systemctl enable --now vsftpd
  systemctl restart vsftpd
  systemctl --no-pager status vsftpd || true
  ok "Servicio vsftpd activo."
}

# Bind mounts para que el usuario vea desde su chroot:
# /home/usuario/general -> /srv/ftp-practica/general
# /home/usuario/reprobados|recursadores -> carpeta de grupo
# /home/usuario/usuario -> carpeta personal /srv/ftp-practica/users/usuario
ensure_bind_mounts(){
  # Para que persistan, lo anotamos en /etc/fstab con líneas idempotentes
  local user="$1" group="$2"
  local home
  home="$(getent passwd "$user" | cut -d: -f6)"
  [[ -n "$home" ]] || die "No pude determinar home de $user"

  mkdir -p "$home/general" "$home/$group" "$home/$user"

  # bind general
  add_fstab_bind "$GENERAL_DIR" "$home/general"
  mountpoint -q "$home/general" || mount --bind "$GENERAL_DIR" "$home/general"

  # bind grupo
  local grpdir="$FTP_ROOT/$group"
  add_fstab_bind "$grpdir" "$home/$group"
  mountpoint -q "$home/$group" || mount --bind "$grpdir" "$home/$group"

  # bind personal
  local pdir="$USERS_DIR/$user"
  add_fstab_bind "$pdir" "$home/$user"
  mountpoint -q "$home/$user" || mount --bind "$pdir" "$home/$user"

  ok "Bind mounts listos para $user"
}

add_fstab_bind(){
  local src="$1" dst="$2"
  local line="$src $dst none bind 0 0"
  grep -Fq "$line" /etc/fstab || echo "$line" >> /etc/fstab
}

create_user_one(){
  local user="$1" pass="$2" grp="$3"

  # Validación grupo
  [[ "$grp" == "reprobados" || "$grp" == "recursadores" ]] || die "Grupo inválido: $grp"

  # Crear usuario si no existe
  if id "$user" >/dev/null 2>&1; then
    ok "Usuario $user ya existe, ajustando grupo/recursos..."
  else
    useradd -m -s /sbin/nologin "$user"
    echo "$user:$pass" | chpasswd
    ok "Usuario $user creado."
  fi

  # Grupo principal: el del alumno
  usermod -g "$grp" "$user"

  # También lo metemos a ftpusers para escritura en general
  usermod -aG ftpusers "$user"

  # Carpeta personal real dentro de FTP_ROOT
  mkdir -p "$USERS_DIR/$user"
  chown "$user:$grp" "$USERS_DIR/$user"
  chmod 770 "$USERS_DIR/$user"

  # Ajustar permisos en su home para chroot + bind mounts
  local home
  home="$(getent passwd "$user" | cut -d: -f6)"
  chown root:root "$home"
  chmod 755 "$home"

  ensure_bind_mounts "$user" "$grp"

  ok "Usuario $user listo (grupo $grp)."
}

bulk_create_users(){
  read -r -p "¿Cuántos usuarios deseas crear? (n): " n
  [[ "$n" =~ ^[0-9]+$ ]] || die "n debe ser numérico."

  for ((i=1; i<=n; i++)); do
    echo "----- Usuario $i de $n -----"
    read -r -p "Nombre de usuario: " u
    [[ -n "$u" ]] || die "Usuario vacío."

    read -r -s -p "Contraseña: " p; echo
    [[ -n "$p" ]] || die "Contraseña vacía."

    read -r -p "Grupo (reprobados/recursadores): " g
    create_user_one "$u" "$p" "$g"
  done
}

change_user_group(){
  read -r -p "Usuario a cambiar de grupo: " u
  id "$u" >/dev/null 2>&1 || die "No existe el usuario: $u"

  local current
  current="$(id -gn "$u")"
  echo "Grupo actual: $current"
  local newg
  if [[ "$current" == "reprobados" ]]; then newg="recursadores"; else newg="reprobados"; fi
  echo "Cambiando a: $newg"

  usermod -g "$newg" "$u"

  # Ajustar carpeta personal ownership al nuevo grupo
  chown "$u:$newg" "$USERS_DIR/$u"

  # Actualizar bind mount de grupo en home: desmontar anterior y montar nuevo
  local home
  home="$(getent passwd "$u" | cut -d: -f6)"
  mkdir -p "$home/$newg"

  # desmontar posible mount viejo
  if mountpoint -q "$home/reprobados"; then umount "$home/reprobados" || true; fi
  if mountpoint -q "$home/recursadores"; then umount "$home/recursadores" || true; fi

  # limpiar entradas fstab viejas del grupo (simple: dejamos ambas si existen; montamos solo la actual)
  ensure_bind_mounts "$u" "$newg"

  ok "Grupo de $u cambiado a $newg."
}

show_status(){
  echo "==== Estado vsftpd ===="
  systemctl --no-pager status vsftpd || true
  echo
  echo "==== Puertos escuchando (21 / pasv) ===="
  ss -lntp | grep -E ':(21|30000|30100)\b' || true
  echo
  echo "==== Estructura FTP ===="
  ls -la "$FTP_ROOT"
  echo
  echo "==== Permisos ===="
  ls -ld "$FTP_ROOT" "$GENERAL_DIR" "$GRP_REPRO_DIR" "$GRP_RECUR_DIR" "$USERS_DIR"
}

menu(){
  while true; do
    echo
    echo "=============================="
    echo " FTP Practica - Mageia (vsftpd)"
    echo "=============================="
    echo "1) Instalar/Configurar vsftpd (idempotente)"
    echo "2) Crear estructura de carpetas + permisos"
    echo "3) Crear usuarios (alta masiva)"
    echo "4) Cambiar usuario de grupo (toggle)"
    echo "5) Ver estado"
    echo "0) Salir"
    read -r -p "Opción: " op
    case "$op" in
      1) ensure_groups; write_vsftpd_conf; enable_service ;;
      2) ensure_groups; ensure_dirs ;;
      3) ensure_groups; ensure_dirs; bulk_create_users; systemctl restart vsftpd ;;
      4) change_user_group; systemctl restart vsftpd ;;
      5) show_status ;;
      0) exit 0 ;;
      *) echo "Opción inválida" ;;
    esac
  done
}

main(){
  require_root
  menu
}

main "$@"