#!/bin/bash
set -e

# Funciones comunes
pause() { echo; read -r -p "Presiona ENTER para continuar..." _; }

# Verificar instalación de OpenSSH
ssh_verificar() {
  echo "--- Verificación OpenSSH ---"
  if systemctl is-active --quiet sshd; then
    echo "Servicio sshd: ACTIVO"
  else
    echo "Servicio sshd: INACTIVO"
  fi
  if rpm -q openssh-server >/dev/null; then
    echo "OpenSSH ya está instalado."
  else
    echo "OpenSSH no está instalado."
  fi
}

# Instalar OpenSSH
ssh_instalar() {
  echo "--- Instalando OpenSSH Server ---"
  sudo dnf install -y openssh-server || { echo "Error en la instalación."; exit 1; }
  sudo systemctl enable --now sshd
  echo "OpenSSH Server instalado y en ejecución."
}

# Configurar OpenSSH (Habilitar servicio, firewall, shell por defecto)
ssh_configurar() {
  echo "--- Configurando OpenSSH ---"
  sudo systemctl enable sshd
  sudo systemctl start sshd

  # Configuración de firewall
  sudo firewall-cmd --permanent --add-service=ssh
  sudo firewall-cmd --reload
  echo "Firewall configurado para permitir puerto 22 (SSH)."

  # Establecer el shell por defecto (opcional)
  sudo usermod -s /bin/bash $USER
  echo "Shell por defecto configurado a Bash."
}

# Monitoreo SSH (Verificar puerto y servicio)
ssh_monitoreo() {
  echo "--- Monitoreo SSH ---"
  sudo systemctl status sshd
  sudo ss -lntup | grep ":22" || echo "Puerto 22 no escuchando."
}

menu_ssh() {
  while true; do
    clear
    echo "===================="
    echo "   MENÚ SSH"
    echo "===================="
    echo "1) Verificar instalación"
    echo "2) Instalar OpenSSH Server"
    echo "3) Configurar SSH"
    echo "4) Monitorear SSH"
    echo "0) Volver"
    read -r -p "Seleccione una opción: " op

    case "$op" in
      1) ssh_verificar; pause ;;
      2) ssh_instalar; pause ;;
      3) ssh_configurar; pause ;;
      4) ssh_monitoreo; pause ;;
      0) return ;;
      *) echo "Opción inválida"; pause ;;
    esac
  done
}