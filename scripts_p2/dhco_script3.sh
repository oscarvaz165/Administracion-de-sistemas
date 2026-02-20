#!/usr/bin/env bash
set -euo pipefail

# =========================
#  DNS PRO (MAGEIA / BIND)
# =========================

# --- Rutas y archivos ---
ZONES_DIR="/var/named/pro-zones"
MANAGED_ZONES_CONF="/etc/named.d/pro-zones.conf"
NAMED_CONF="/etc/named.conf"

mkdir -p "$ZONES_DIR"
mkdir -p "$(dirname "$MANAGED_ZONES_CONF")"

pause() { echo; read -r -p "Presiona ENTER para continuar..." _; }

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "[ERROR] Ejecuta como root: sudo $0" >&2
    exit 1
  fi
}

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

install_bind_if_needed() {
  if ! cmd_exists named || ! cmd_exists named-checkconf || ! cmd_exists named-checkzone; then
    echo "[i] Instalando BIND (bind, bind-utils)..."
    if cmd_exists urpmi; then
      urpmi --auto bind bind-utils >/dev/null
    else
      echo "[ERROR] No encontré urpmi. Instala bind y bind-utils manualmente." >&2
      exit 1
    fi
  fi
}

enable_named() {
  systemctl enable --now named >/dev/null 2>&1 || true
}

# --- Detectar IP de una interfaz ---
obtener_datos_red() {
  read -r -p "Introduce la interfaz de red (ej. enp0s3, eth0): " INTERFAZ
  INTERFAZ="${INTERFAZ// /}"

  if ! cmd_exists ip; then
    echo "[ERROR] No existe el comando 'ip'. Instala iproute2." >&2
    return 1
  fi

  IP_SUGERIDA="$(ip -4 addr show "$INTERFAZ" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)"

  if [ -z "${IP_SUGERIDA:-}" ]; then
    echo "[!] No se encontró IP en $INTERFAZ. Revisa con: ip a" >&2
    return 1
  fi

  echo "[+] IP detectada en $INTERFAZ: $IP_SUGERIDA"
  return 0
}

# --- Asegurar include en named.conf ---
asegurar_include_named_conf() {
  # Creamos include si no existe. (No reescribimos todo /etc/named.conf)
  if [ ! -f "$NAMED_CONF" ]; then
    echo "[ERROR] No existe $NAMED_CONF. ¿Está instalado BIND?" >&2
    exit 1
  fi

  if ! grep -qF "$MANAGED_ZONES_CONF" "$NAMED_CONF"; then
    echo "[i] Agregando include a $NAMED_CONF -> $MANAGED_ZONES_CONF"
    printf '\n// Zonas administradas por DNS PRO\ninclude "%s";\n' "$MANAGED_ZONES_CONF" >> "$NAMED_CONF"
  fi
}

# --- Reconstruir archivo de zonas administradas ---
actualizar_zonas_conf() {
  # Reescribe el archivo de zonas gestionadas con TODO lo que exista en pro-zones
  : > "$MANAGED_ZONES_CONF"

  shopt -s nullglob
  for archivo_zona in "$ZONES_DIR"/db.*; do
    if [ -f "$archivo_zona" ]; then
      dominio="$(basename "$archivo_zona" | sed 's/^db\.//')"
      cat >> "$MANAGED_ZONES_CONF" <<EOF

zone "$dominio" IN {
  type master;
  file "$archivo_zona";
  allow-update { none; };
};
EOF
    fi
  done
  shopt -u nullglob
}

# --- Validar + recargar named ---
aplicar_y_recargar() {
  # Permisos típicos para que named lea zonas
  chown -R named:named "$ZONES_DIR" 2>/dev/null || true
  chmod 750 "$ZONES_DIR" 2>/dev/null || true
  chmod 640 "$ZONES_DIR"/db.* 2>/dev/null || true
  chmod 640 "$MANAGED_ZONES_CONF" 2>/dev/null || true

  # Validar config
  if ! named-checkconf "$NAMED_CONF" >/dev/null 2>&1; then
    echo "[ERROR] named-checkconf falló. Revisa $NAMED_CONF y $MANAGED_ZONES_CONF" >&2
    named-checkconf "$NAMED_CONF" || true
    return 1
  fi

  # Recargar servicio
  systemctl reload named >/dev/null 2>&1 || systemctl restart named >/dev/null 2>&1

  echo -e "\n[+] Configuración aplicada y named recargado."
  return 0
}

# --- Serial dinámico YYYYMMDDnn ---
serial_hoy() {
  date +"%Y%m%d01"
}

crear_zona() {
  obtener_datos_red || return 1
  read -r -p "Nombre del dominio (ej. reprobados.com): " dominio
  dominio="${dominio// /}"

  if [ -z "$dominio" ]; then
    echo "[ERROR] Dominio vacío." >&2
    return 1
  fi

  local zonefile="$ZONES_DIR/db.$dominio"

  # Crear archivo de zona con IP detectada
  cat > "$zonefile" <<EOF
\$TTL 86400
@   IN  SOA ns1.$dominio. root.$dominio. (
        $(serial_hoy) ; Serial
        3600          ; Refresh
        900           ; Retry
        1209600       ; Expire
        86400 )       ; Negative Cache TTL

@    IN  NS  ns1.$dominio.
@    IN  A   $IP_SUGERIDA
ns1  IN  A   $IP_SUGERIDA
www  IN  A   $IP_SUGERIDA
EOF

  # Validar zona
  if ! named-checkzone "$dominio" "$zonefile" >/dev/null 2>&1; then
    echo "[ERROR] named-checkzone falló para $dominio" >&2
    named-checkzone "$dominio" "$zonefile" || true
    return 1
  fi

  asegurar_include_named_conf
  actualizar_zonas_conf
  aplicar_y_recargar

  echo "[OK] Dominio $dominio creado apuntando a $IP_SUGERIDA"
  return 0
}

eliminar_zona() {
  read -r -p "Dominio a eliminar (ej. reprobados.com): " dom_del
  dom_del="${dom_del// /}"

  if [ -z "$dom_del" ]; then
    echo "[ERROR] Dominio vacío." >&2
    return 1
  fi

  rm -f "$ZONES_DIR/db.$dom_del"

  asegurar_include_named_conf
  actualizar_zonas_conf
  aplicar_y_recargar

  echo "[OK] Dominio eliminado: $dom_del"
  return 0
}

enlistar() {
  echo "--- Dominios activos (pro-zones) ---"
  if ls "$ZONES_DIR"/db.* >/dev/null 2>&1; then
    ls "$ZONES_DIR"/db.* | sed 's#.*/db\.##'
  else
    echo "(ninguno)"
  fi
}

probar_resolucion() {
  read -r -p "Dominio a consultar (ej. reprobados.com): " dom_con
  dom_con="${dom_con// /}"
  if [ -z "$dom_con" ]; then
    echo "[ERROR] Dominio vacío." >&2
    return 1
  fi

  echo
  if cmd_exists dig; then
    echo "[dig] @$IP_LOCAL (127.0.0.1) -> A $dom_con"
    dig @"127.0.0.1" +short A "$dom_con" || true
    echo
    echo "[dig] @$IP_LOCAL (127.0.0.1) -> A www.$dom_con"
    dig @"127.0.0.1" +short A "www.$dom_con" || true
  else
    echo "[i] 'dig' no está. Probando con nslookup..."
    nslookup "$dom_con" 127.0.0.1 || true
    nslookup "www.$dom_con" 127.0.0.1 || true
  fi

  return 0
}

monitoreo() {
  echo "=== MONITOREO ==="
  echo
  echo "[Servicio]"
  systemctl --no-pager -l status named | sed -n '1,20p' || true
  echo
  echo "[Puertos escuchando 53]"
  if cmd_exists ss; then
    ss -lntup | awk 'NR==1 || /:53 /' || true
  else
    netstat -lntup 2>/dev/null | awk 'NR==1 || /:53 /' || true
  fi
  echo
  echo "[Config check]"
  named-checkconf "$NAMED_CONF" && echo "[OK] named-checkconf sin errores"
}

main() {
  require_root
  install_bind_if_needed
  enable_named
  asegurar_include_named_conf
  actualizar_zonas_conf
  aplicar_y_recargar >/dev/null 2>&1 || true

  while true; do
    clear
    echo "========================================"
    echo "     ADMINISTRADOR DNS PRO (MAGEIA)     "
    echo "========================================"
    echo "1. Enlistar Dominios"
    echo "2. Agregar Dominio (incluye fijar IP)"
    echo "3. Eliminar Dominio"
    echo "4. Probar Resolución Local"
    echo "5. Monitoreo"
    echo "6. Salir"
    echo "----------------------------------------"
    read -r -p "Selecciona una opción: " opcion

    case "${opcion:-}" in
      1) enlistar; pause ;;
      2) crear_zona; pause ;;
      3) eliminar_zona; pause ;;
      4) probar_resolucion; pause ;;
      5) monitoreo; pause ;;
      6) echo "Saliendo..."; exit 0 ;;
      *) echo "Opción no válida."; sleep 1 ;;
    esac
  done
}

main "$@"