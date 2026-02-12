#!/usr/bin/env bash
set -u

CONF="/etc/dhcpd.conf"
LEASES_PRIMARY="/var/lib/dhcpd/dhcpd.leases"
LEASES_FALLBACK="/var/lib/dhcp/dhcpd.leases"

die(){ echo "[ERROR] $*" >&2; exit 1; }
pause(){ read -r -p "Enter para continuar..." _; }

ip_to_int() {
  local ip="$1" a b c d
  IFS=. read -r a b c d <<<"$ip" || return 1
  echo $(( (a<<24) + (b<<16) + (c<<8) + d ))
}

int_to_ip() {
  local n="$1"
  echo "$(( (n>>24)&255 )).$(( (n>>16)&255 )).$(( (n>>8)&255 )).$(( n&255 ))"
}

ip_add() {
  local ip="$1" delta="$2"
  local n
  n=$(ip_to_int "$ip") || return 1
  n=$(( n + delta ))
  (( n>=0 && n<=4294967295 )) || return 1
  int_to_ip "$n"
}

is_ipv4() {
  local ip="$1" a b c d
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r a b c d <<<"$ip" || return 1
  for o in "$a" "$b" "$c" "$d"; do
    [[ "$o" =~ ^[0-9]+$ ]] || return 1
    (( o>=0 && o<=255 )) || return 1
  done
  [[ "$ip" != "0.0.0.0" && "$ip" != "255.255.255.255" ]] || return 1
  return 0
}

mask_is_valid() {
  local m="$1" mi inv
  is_ipv4 "$m" || return 1
  mi=$(ip_to_int "$m") || return 1
  (( mi != 0 && mi != 4294967295 )) || return 1
  inv=$(( 4294967295 ^ mi ))
  (( (inv & (inv + 1)) == 0 )) || return 1
  return 0
}

same_subnet() {
  local ip1="$1" ip2="$2" mask="$3"
  local i1 i2 m
  i1=$(ip_to_int "$ip1") || return 1
  i2=$(ip_to_int "$ip2") || return 1
  m=$(ip_to_int "$mask") || return 1
  (( (i1 & m) == (i2 & m) ))
}

net_addr() {
  local ip="$1" mask="$2"
  local i m
  i=$(ip_to_int "$ip") || return 1
  m=$(ip_to_int "$mask") || return 1
  int_to_ip $(( i & m ))
}

broadcast_addr() {
  local ip="$1" mask="$2"
  local i m inv
  i=$(ip_to_int "$ip") || return 1
  m=$(ip_to_int "$mask") || return 1
  inv=$(( 4294967295 ^ m ))
  int_to_ip $(( (i & m) | inv ))
}

read_ipv4() {
  local prompt="$1" def="${2:-}" v
  while true; do
    if [[ -n "$def" ]]; then
      read -r -p "$prompt [$def]: " v
      v="${v:-$def}"
    else
      read -r -p "$prompt: " v
    fi
    if is_ipv4 "$v"; then echo "$v"; return 0; fi
    echo "IP invalida. Ej: 103.5.153.9 (no 0.0.0.0 / 255.255.255.255)."
  done
}

read_ipv4_optional() {
  local prompt="$1" def="${2:-}" v
  while true; do
    if [[ -n "$def" ]]; then
      read -r -p "$prompt [$def] (ENTER=usar, -=omitir): " v
      [[ -z "$v" ]] && v="$def"
      [[ "$v" == "-" ]] && echo "" && return 0
    else
      read -r -p "$prompt (ENTER o -=omitir): " v
      [[ -z "$v" || "$v" == "-" ]] && echo "" && return 0
    fi
    if is_ipv4 "$v"; then echo "$v"; return 0; fi
    echo "IP invalida. Ej: 8.8.8.8"
  done
}

read_mask() {
  local prompt="$1" def="${2:-}" v
  while true; do
    read -r -p "$prompt [$def]: " v
    v="${v:-$def}"
    if mask_is_valid "$v"; then echo "$v"; return 0; fi
    echo "Mascara invalida. Ej: 255.255.255.0"
  done
}

pick_leases_file() {
  [[ -f "$LEASES_PRIMARY" ]] && echo "$LEASES_PRIMARY" && return
  [[ -f "$LEASES_FALLBACK" ]] && echo "$LEASES_FALLBACK" && return
  echo "$LEASES_PRIMARY"
}

ensure_root() {
  [[ ${EUID:-999} -eq 0 ]] || die "Ejecuta como root: sudo ./dhcp_script.sh"
}

pkg_install() {
  if rpm -q dhcp-server >/dev/null 2>&1; then
    echo "dhcp-server ya esta instalado."
    return 0
  fi
  echo "Instalando dhcp-server (Mageia)..."
  if command -v dnf >/dev/null 2>&1; then
    dnf -y install dhcp-server || die "Fallo dnf install dhcp-server"
  elif command -v urpmi >/dev/null 2>&1; then
    urpmi --auto dhcp-server || die "Fallo urpmi dhcp-server"
  else
    die "No encontre dnf ni urpmi. Instala dhcp-server manualmente."
  fi
}

svc_restart() {
  systemctl enable --now dhcpd >/dev/null 2>&1 || true
  systemctl restart dhcpd || die "No pude reiniciar dhcpd. Revisa: journalctl -u dhcpd -n 50 --no-pager"
}

svc_status() {
  echo "== Servicio dhcpd =="
  systemctl --no-pager -l status dhcpd || true
  echo
  echo "== Ultimos logs (dhcpd) =="
  journalctl -u dhcpd -n 40 --no-pager || true
}

leases_active() {
  local lf
  lf="$(pick_leases_file)"
  [[ -f "$lf" ]] || { echo "No existe lease file aun: $lf"; return 0; }

  echo "== Leases activas ($lf) =="
  awk '
    $1=="lease" {ip=$2; inlease=1; state=""; mac=""; host=""; next}
    inlease && $1=="binding" && $2=="state" {state=$3}
    inlease && $1=="hardware" && $2=="ethernet" {mac=$3; gsub(";","",mac)}
    inlease && $1=="client-hostname" {host=$2; gsub(/[";]/,"",host)}
    inlease && $1=="}" {
      if (state=="active") {
        printf "%-15s  %-17s  %s\n", ip, mac, host
      }
      inlease=0
    }
  ' "$lf" | sort -V
}

set_server_static_ip() {
  local iface="$1" ip="$2" mask="$3"
  # calcula prefijo desde mascara
  local m bits=0 i
  m=$(ip_to_int "$mask") || return 1
  for ((i=31;i>=0;i--)); do
    (( (m>>i)&1 )) && ((bits++))
  done

  echo "Asignando IP estatica al servidor: $ip/$bits en $iface"
  # runtime (sin depender de NetworkManager)
  ip addr flush dev "$iface" >/dev/null 2>&1 || true
  ip addr add "$ip/$bits" dev "$iface" || die "No pude asignar IP al iface $iface"
  ip link set "$iface" up || true

  # persistencia en distros tipo Mageia/RHEL (si existen ifcfg)
  if [[ -d /etc/sysconfig/network-scripts ]]; then
    cat >"/etc/sysconfig/network-scripts/ifcfg-${iface}" <<EOF
DEVICE=${iface}
BOOTPROTO=static
ONBOOT=yes
IPADDR=${ip}
NETMASK=${mask}
EOF
  fi
}

configure_dhcp() {
  local scopeName srv_ip end mask gw dns1 dns2 iface leaseSec net bc pool_start
  read -r -p "Nombre descriptivo del ambito [Scope-1]: " scopeName
  scopeName="${scopeName:-Scope-1}"

  echo
  echo "Captura asi:"
  echo " - La PRIMERA IP se reserva y se pone ESTATICA al servidor."
  echo " - El DHCP empezara a dar desde la SIGUIENTE IP (start+1)."
  echo

  srv_ip=$(read_ipv4 "IP inicial (reservada para el servidor)" "103.5.153.9")
  end=$(read_ipv4 "IP final (ultima para clientes)" "103.5.153.115")
  mask=$(read_mask "Mascara" "255.255.255.0")

  # Validaciones de subred y orden
  same_subnet "$srv_ip" "$end" "$mask" || die "srv_ip y end NO estan en la misma subred segun $mask"
  local si ei
  si=$(ip_to_int "$srv_ip"); ei=$(ip_to_int "$end")
  (( si < ei )) || die "La IP inicial (server) debe ser MENOR a la final."

  pool_start=$(ip_add "$srv_ip" 1) || die "No pude calcular start+1"
  local pi
  pi=$(ip_to_int "$pool_start")
  (( pi <= ei )) || die "No hay espacio: start+1 ($pool_start) se pasa del final ($end)"

  gw=$(read_ipv4_optional "PE / Puerta de enlace (opcional)" "")
  if [[ -n "$gw" ]]; then
    same_subnet "$gw" "$srv_ip" "$mask" || die "Gateway $gw NO pertenece a la subred del server"
  fi

  dns1=$(read_ipv4_optional "DNS Primario (opcional)" "")
  if [[ -n "$dns1" ]]; then
    same_subnet "$dns1" "$srv_ip" "$mask" || true # DNS puede estar fuera; no lo forzamos
  fi
  dns2=$(read_ipv4_optional "DNS Secundario (opcional)" "")
  # dns2 puede estar fuera; no forzamos

  read -r -p "Lease Time en segundos [500]: " leaseSec
  leaseSec="${leaseSec:-500}"
  [[ "$leaseSec" =~ ^[0-9]+$ ]] || die "Lease seconds debe ser entero."
  (( leaseSec >= 60 && leaseSec <= 604800 )) || die "Lease seconds fuera de rango razonable (60..604800)."

  echo
  echo "Interfaces disponibles:"
  ip -o link show | awk -F': ' '{print " - " $2}' | sed 's/@.*//' | grep -v '^ - lo$' || true
  read -r -p "Interfaz de la red interna [eth0]: " iface
  iface="${iface:-eth0}"

  net=$(net_addr "$srv_ip" "$mask") || die "No pude calcular network"
  bc=$(broadcast_addr "$srv_ip" "$mask") || die "No pude calcular broadcast"

  # Poner IP estatica al servidor (requisito)
  set_server_static_ip "$iface" "$srv_ip" "$mask"

  # Backup config
  if [[ -f "$CONF" ]]; then
    cp -a "$CONF" "${CONF}.bak.$(date +%F_%H%M%S)" || true
  fi

  # Construir opciones DHCP segun lo que si se capturo
  local opt_routers="" opt_dns=""
  if [[ -n "$gw" ]]; then
    opt_routers="option routers ${gw};"
  fi

  if [[ -n "$dns1" && -n "$dns2" ]]; then
    opt_dns="option domain-name-servers ${dns1}, ${dns2};"
  elif [[ -n "$dns1" ]]; then
    opt_dns="option domain-name-servers ${dns1};"
  elif [[ -n "$dns2" ]]; then
    opt_dns="option domain-name-servers ${dns2};"
  else
    opt_dns=""  # ninguno
  fi

  cat >"$CONF" <<EOF
authoritative;
ddns-update-style none;

default-lease-time ${leaseSec};
max-lease-time ${leaseSec};

option subnet-mask ${mask};
option broadcast-address ${bc};
${opt_routers}
${opt_dns}

subnet ${net} netmask ${mask} {
  range ${pool_start} ${end};
}
EOF

  # Lease file
  local lf
  lf="$(pick_leases_file)"
  mkdir -p "$(dirname "$lf")" || true
  touch "$lf" || true

  # Limitar interfaz (comun en RHEL/Mageia)
  mkdir -p /etc/sysconfig || true
  cat >/etc/sysconfig/dhcpd <<EOF
DHCPD_INTERFACE="${iface}"
DHCPDARGS="${iface}"
EOF

  echo "Validando sintaxis..."
  dhcpd -t -cf "$CONF" || die "Error en la configuracion. Corrige $CONF"

  if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-service=dhcp >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
  fi

  echo "Reiniciando dhcpd..."
  svc_restart

  echo
  echo "Listo:"
  echo " - Server (IP estatica): ${srv_ip}"
  echo " - Network: ${net} / ${mask}"
  echo " - Pool: ${pool_start}  ->  ${end}"
  echo " - Lease: ${leaseSec}s"
  [[ -n "$gw" ]] && echo " - Gateway: ${gw}" || echo " - Gateway: (omitido)"
  [[ -n "$opt_dns" ]] && echo " - DNS: ${dns1:-}${dns2:+, ${dns2}}" || echo " - DNS: (omitido)"
  echo "Config en: $CONF"
}

menu() {
  while true; do
    echo
    echo "-------------Servidor DHCP --------------------"
    echo "1) Verificar / Instalar dhcp-server"
    echo "2) Configurar DHCP (reservar 1a IP al server)"
    echo "3) Monitoreo (status + leases)"
    echo "4) Restart Servicio"
    echo "5) Salir"
    read -r -p "Opcion: " op

    case "$op" in
      1) ensure_root; pkg_install; pause ;;
      2) ensure_root; pkg_install; configure_dhcp; pause ;;
      3) svc_status; leases_active; pause ;;
      4) ensure_root; svc_restart; echo "Reiniciado."; pause ;;
      5) exit 0 ;;
      *) echo "Opcion invalida." ;;
    esac
  done
}

menu
