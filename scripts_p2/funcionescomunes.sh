#!/bin/bash

# Función para verificar si el script se está ejecutando como root
require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Ejecuta este script como root." >&2
    exit 1
  fi
}

# Funciones de log
log_info() { echo "[INFO] $1" ; }
log_ok() { echo "[OK] $1" ; }
log_warn() { echo "[WARN] $1" ; }
log_err() { echo "[ERROR] $1" ; }

# Confirmar una opción del usuario (s/n)
confirmar() {
  while true; do
    read -r -p "$1 (s/n): " respuesta
    case "$respuesta" in
      [Ss]) return 0 ;;
      [Nn]) return 1 ;;
      *) echo "Respuesta no válida." ;;
    esac
  done
}

# Leer una opción válida
leer_opcion() {
  while true; do
    read -r -p "$1: " opcion
    if [[ " ${2[@]} " =~ " ${opcion} " ]]; then
      echo "$opcion"
      return 0
    else
      echo "Opción no válida. Validas: ${2[*]}"
    fi
  done
}

# Verificar que un comando exista
assert_command() {
  command -v "$1" >/dev/null 2>&1 || { echo "[ERROR] Comando '$1' no encontrado." >&2; exit 1; }
}