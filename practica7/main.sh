#!/bin/bash
# =============================================================================
# p7_main.sh - Script Principal Practica 7
# Sistema Operativo: Mageia 9 x86_64
# Uso: sudo ./p7_main.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUNCTIONS_FILE="${SCRIPT_DIR}/p7_functions.sh"

if [ ! -f "$FUNCTIONS_FILE" ]; then
    echo "[ERROR] No se encontro p7_functions.sh en: $FUNCTIONS_FILE"
    exit 1
fi
source "$FUNCTIONS_FILE"

# =============================================================================
# ESTADO DE SERVICIOS EN CABECERA
# =============================================================================

fn_estado_servicios() {
    echo -e "${CYAN}+----------------------------------------------------+"
    echo -e "| Servicio   Estado        SSL                      |"
    echo -e "+----------------------------------------------------+${NC}"

    local svcs=("httpd:Apache" "nginx:Nginx" "tomcat:Tomcat" "vsftpd:FTP")
    for entry in "${svcs[@]}"; do
        local svc="${entry%%:*}"
        local nombre="${entry##*:}"
        local estado ssl_estado

        if systemctl is-active "$svc" &>/dev/null; then
            estado="${GREEN}activo${NC}"
        elif systemctl list-unit-files 2>/dev/null | grep -q "^${svc}.service"; then
            estado="${RED}inactivo${NC}"
        else
            estado="${YELLOW}no instalado${NC}"
        fi

        # Verificar SSL
        local puerto=443
        [ "$svc" = "vsftpd" ] && puerto=21
        if ss -tlnp 2>/dev/null | grep -q ":${puerto} "; then
            ssl_estado="${GREEN}SSL:${puerto} [ON]${NC}"
        else
            ssl_estado="${RED}SSL:${puerto} [--]${NC}"
        fi

        printf "  ${CYAN}%-10s${NC} " "$nombre"
        echo -ne "$estado"
        printf "       "
        echo -e "$ssl_estado"
    done
    echo -e "${CYAN}+----------------------------------------------------+${NC}"
}

# =============================================================================
# MENU PRINCIPAL
# =============================================================================

fn_menu_principal_p7() {
    while true; do
        fn_header_p7
        fn_estado_servicios

        echo ""
        echo -e "${BLUE}+----------------------------------------------------+"
        echo -e "| 1) Apache  -> HTTPS puerto :443                   |"
        echo -e "| 2) Nginx   -> HTTPS puerto :8443                  |"
        echo -e "| 3) Tomcat  -> HTTPS puerto :8444                  |"
        echo -e "| 4) FTP (vsftpd) -> FTPS puerto :21               |"
        echo -e "| 5) Ver estado de servicios                        |"
        echo -e "| 6) Resumen de instalaciones                       |"
        echo -e "| 0) Salir                                          |"
        echo -e "+----------------------------------------------------+${NC}"
        echo ""
        read -rp "  Selecciona servicio: " OPCION

        case "$OPCION" in
            1)
                fn_verificar_root_p7
                fn_verificar_dependencias
                fn_instalar_servicio_hibrido "apache" "Apache"
                echo ""
                read -rp "  Presiona ENTER para continuar..."
                ;;
            2)
                fn_verificar_root_p7
                fn_verificar_dependencias
                fn_instalar_servicio_hibrido "nginx" "Nginx"
                echo ""
                read -rp "  Presiona ENTER para continuar..."
                ;;
            3)
                fn_verificar_root_p7
                fn_verificar_dependencias
                fn_instalar_servicio_hibrido "tomcat" "Tomcat"
                echo ""
                read -rp "  Presiona ENTER para continuar..."
                ;;
            4)
                fn_verificar_root_p7
                fn_configurar_ftps
                echo ""
                read -rp "  Presiona ENTER para continuar..."
                ;;
            5)
                fn_section "Estado de Servicios"
                echo -e "${CYAN}  Puertos en escucha:${NC}"
                ss -tlnp 2>/dev/null | grep LISTEN | awk '{print "    " $4}' | sort
                echo ""
                echo -e "${CYAN}  Procesos activos:${NC}"
                ps aux 2>/dev/null | grep -E "httpd|nginx|tomcat|java|vsftpd" | grep -v grep || \
                    echo "  (ninguno)"
                echo ""
                read -rp "  Presiona ENTER para continuar..."
                ;;
            6)
                fn_mostrar_resumen
                read -rp "  Presiona ENTER para continuar..."
                ;;
            0)
                echo ""
                fn_ok "Hasta luego!"
                echo ""
                exit 0
                ;;
            *)
                fn_err "Opcion invalida. Elige entre 0 y 6."
                sleep 1
                ;;
        esac
    done
}

# =============================================================================
# PUNTO DE ENTRADA
# =============================================================================
fn_verificar_root_p7
fn_menu_principal_p7