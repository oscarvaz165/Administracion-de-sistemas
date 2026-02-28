#!/bin/bash

# Instalar DHCP Server (si no está instalado)
install_dhcp() {
  if ! command -v dhcpd &>/dev/null; then
    echo "[INFO] Instalando DHCP Server..."
    sudo dnf install -y dhcp-server || { echo "[ERROR] No se pudo instalar DHCP"; exit 1; }
  else
    echo "[INFO] DHCP Server ya está instalado."
  fi
}

# Configuración de DHCP
configurar_dhcp() {
  echo "[INFO] Configurando DHCP..."
  # Aquí se implementan las configuraciones para el servidor DHCP
}

menu_dhcp() {
  while true; do
    clear
    echo "===================="
    echo "   MENÚ DHCP"
    echo "===================="
    echo "1) Verificar instalación de DHCP"
    echo "2) Instalar DHCP"
    echo "3) Configurar DHCP"
    echo "0) Volver"
    read -r -p "Seleccione una opción: " op

    case "$op" in
      1) install_dhcp; pause ;;
      2) install_dhcp; pause ;;
      3) configurar_dhcp; pause ;;
      0) return ;;
      *) echo "Opción inválida"; pause ;;
    esac
  done
}