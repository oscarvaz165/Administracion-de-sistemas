#!/usr/bin/env bash
# =============================================================================
# main_linux.sh — Script principal de aprovisionamiento HTTP
# Práctica 6 | Administración de Servidores
# Distribución: Mageia Linux
# Operación: SSH remota — solo contiene llamadas a funciones
# =============================================================================

# Ruta al archivo de funciones (mismo directorio que este script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/http_functions.sh" || {
    echo "[ERROR] No se encontró http_functions.sh en $SCRIPT_DIR"
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# MENÚ PRINCIPAL
# ─────────────────────────────────────────────────────────────────────────────
fn_menu_principal() {
    clear
    echo -e "${BOLD}${BLUE}"
    cat <<'BANNER'
  ╔══════════════════════════════════════════════════════════╗
  ║     APROVISIONAMIENTO WEB AUTOMÁTICO — PRÁCTICA 6        ║
  ║     Sistema Operativo: Mageia Linux                      ║
  ║     Operación remota vía SSH                             ║
  ╚══════════════════════════════════════════════════════════╝
BANNER
    echo -e "${NC}"
    echo -e "  ${BOLD}Selecciona el servidor HTTP a instalar:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Apache HTTP Server (httpd)"
    echo -e "  ${GREEN}2)${NC} Nginx"
    echo -e "  ${GREEN}3)${NC} Apache Tomcat"
    echo -e "  ${RED}0)${NC} Salir"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# FLUJO: Apache
# ─────────────────────────────────────────────────────────────────────────────
fn_flujo_apache() {
    log_section "Flujo de instalación: Apache"
    fn_update_repos
    fn_menu_versiones "httpd"
    fn_solicitar_puerto "Apache" "80"
    fn_install_apache "$PUERTO_ELEGIDO" "$VERSION_ELEGIDA"
}

# ─────────────────────────────────────────────────────────────────────────────
# FLUJO: Nginx
# ─────────────────────────────────────────────────────────────────────────────
fn_flujo_nginx() {
    log_section "Flujo de instalación: Nginx"
    fn_update_repos
    fn_menu_versiones "nginx"
    fn_solicitar_puerto "Nginx" "80"
    fn_install_nginx "$PUERTO_ELEGIDO" "$VERSION_ELEGIDA"
}

# ─────────────────────────────────────────────────────────────────────────────
# FLUJO: Tomcat
# ─────────────────────────────────────────────────────────────────────────────
fn_flujo_tomcat() {
    log_section "Flujo de instalación: Tomcat"
    fn_update_repos
    fn_menu_versiones_tomcat
    fn_solicitar_puerto "Tomcat" "8080"
    fn_install_tomcat "$PUERTO_ELEGIDO" "$VERSION_ELEGIDA"
}

# Menú de versiones especial para Tomcat (repositorio + binario oficial)
fn_menu_versiones_tomcat() {
    echo ""
    log_section "Versiones disponibles de Tomcat"

    # Versiones desde repositorio Mageia
    local REPO_VER
    REPO_VER=$(dnf repoquery --available --queryformat '%{version}' tomcat 2>/dev/null | sort -Vr | head -1)

    # Versiones desde Apache.org (consulta en línea)
    local ONLINE_V10 ONLINE_V9
    ONLINE_V10=$(curl -s --max-time 8 "https://downloads.apache.org/tomcat/tomcat-10/" \
        | grep -oP 'v\K[\d.]+(?=/)' | sort -Vr | head -1 2>/dev/null)
    ONLINE_V9=$(curl -s --max-time 8 "https://downloads.apache.org/tomcat/tomcat-9/" \
        | grep -oP 'v\K[\d.]+(?=/)' | sort -Vr | head -1 2>/dev/null)

    echo ""
    echo -e "  ${BOLD}Opciones disponibles:${NC}"
    local opciones=()
    local i=1

    if [[ -n "$REPO_VER" ]]; then
        echo -e "  ${GREEN}${i})${NC} ${REPO_VER}  ${GREEN}[Repositorio Mageia — LTS/Estable]${NC}"
        opciones+=("$REPO_VER")
        (( i++ ))
    fi
    if [[ -n "$ONLINE_V10" ]]; then
        echo -e "  ${GREEN}${i})${NC} ${ONLINE_V10}  ${YELLOW}[Binario Apache.org Tomcat 10 — Latest]${NC}"
        opciones+=("$ONLINE_V10")
        (( i++ ))
    fi
    if [[ -n "$ONLINE_V9" ]]; then
        echo -e "  ${GREEN}${i})${NC} ${ONLINE_V9}  ${CYAN}[Binario Apache.org Tomcat 9 — LTS]${NC}"
        opciones+=("$ONLINE_V9")
        (( i++ ))
    fi
    if [[ ${#opciones[@]} -eq 0 ]]; then
        log_warn "No se pudo consultar versiones. Se usará la última disponible."
        opciones=("10-latest")
        echo -e "  ${BOLD}1)${NC} Última disponible en Apache.org"
    fi

    echo ""
    local sel
    while true; do
        read -rp "  Selecciona [1-${#opciones[@]}]: " sel
        if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#opciones[@]} )); then
            VERSION_ELEGIDA="${opciones[$((sel-1))]}"
            log_ok "Versión Tomcat seleccionada: $VERSION_ELEGIDA"
            break
        fi
        log_warn "Opción inválida. Ingresa un número entre 1 y ${#opciones[@]}."
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN — Solo llamadas a funciones
# ─────────────────────────────────────────────────────────────────────────────
main() {
    fn_check_root

    local opcion
    while true; do
        fn_menu_principal
        read -rp "  Tu selección: " opcion

        # Validar entrada del menú
        if ! fn_validate_input "$opcion" "Opción de menú" 2>/dev/null || \
           ! [[ "$opcion" =~ ^[0-3]$ ]]; then
            log_warn "Opción inválida. Ingresa 0, 1, 2 o 3."
            sleep 1
            continue
        fi

        case "$opcion" in
            1) fn_flujo_apache  ;;
            2) fn_flujo_nginx   ;;
            3) fn_flujo_tomcat  ;;
            0)
                echo -e "\n${GREEN}Saliendo del aprovisionador. ¡Hasta luego!${NC}\n"
                exit 0
                ;;
        esac

        echo ""
        read -rp "  Presiona ENTER para volver al menú principal..." _
    done
}

main "$@"
