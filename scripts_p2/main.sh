#!/bin/bash
set -e

# Cargar las funciones de SSH, DNS, y DHCP
source ./funciones_ssh.sh
source ./funciones_dns.sh
source ./funciones_dhcp.sh

# Validar que se esté ejecutando como root
require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Ejecuta este script como root." >&2
    exit 1
  fi
}

# Menú Principal
menu_principal() {
  while true; do
    clear
    echo "==========================="
    echo " SISTEMA DE ADMINISTRACIÓN"
    echo "==========================="
    echo "1) SSH"
    echo "2) DNS"
    echo "3) DHCP"
    echo "4) Salir"
    echo "==========================="
    read -r -p "Seleccione una opción: " opcion

    case "$opcion" in
      1) menu_ssh ;;
      2) menu_dns ;;
      3) menu_dhcp ;;
      4) echo "Saliendo..."; exit 0 ;;
      *) echo "Opción no válida"; sleep 1 ;;
    esac
  done
}

# Ejecutar la validación y el menú
require_root
menu_principal