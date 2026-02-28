#!/bin/bash

# Función para instalar BIND (si no está instalado)
install_bind() {
  if ! command -v named-checkconf &>/dev/null; then
    echo "[INFO] Instalando BIND..."
    sudo dnf install -y bind bind-utils || { echo "[ERROR] No se pudo instalar BIND"; exit 1; }
  else
    echo "[INFO] BIND ya está instalado."
  fi
}

# Configuración del servidor DNS (similar a Windows)
configurar_dns() {
  echo "[INFO] Configurando BIND..."
  # Aquí puedes agregar la configuración de BIND para tus zonas y demás
}

menu_dns() {
  while true; do
    clear
    echo "===================="
    echo "    MENÚ DNS"
    echo "===================="
    echo "1) Verificar instalación de BIND"
    echo "2) Instalar BIND"
    echo "3) Configurar DNS"
    echo "0) Volver"
    read -r -p "Seleccione una opción: " op

    case "$op" in
      1) install_bind; pause ;;
      2) install_bind; pause ;;
      3) configurar_dns; pause ;;
      0) return ;;
      *) echo "Opción inválida"; pause ;;
    esac
  done
}