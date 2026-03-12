#!/bin/bash
# ==============================================================================
# menu.sh - Menu interactivo de aprovisionamiento HTTP
# Practica 6 | Mageia 9 x86_64
# Uso: sudo ./menu.sh
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/http_functions.sh"

show_header() {
    clear
    echo ""
    echo -e "${BLUE}  +============================================================+${NC}"
    echo -e "${BLUE}  |      APROVISIONAMIENTO DE SERVIDORES HTTP                  |${NC}"
    echo -e "${BLUE}  |      Practica 6 - Mageia 9 - Bash                          |${NC}"
    echo -e "${BLUE}  +============================================================+${NC}"
    echo ""
    show_service_status
    echo ""
}

show_service_status() {
    echo "  Estado actual de servicios:"

    local servicios=("httpd:Apache" "nginx:Nginx" "tomcat:Tomcat")
    for entry in "${servicios[@]}"; do
        local svc="${entry%%:*}"
        local nombre="${entry##*:}"
        local puerto
        puerto=$(fn_get_puerto_actual "$svc")
        [ -z "$puerto" ] && puerto="N/D"

        if systemctl is-active "$svc" &>/dev/null; then
            echo -e "    ${GREEN}[+] $nombre   activo   puerto: $puerto${NC}"
        elif systemctl list-unit-files 2>/dev/null | grep -q "^${svc}.service"; then
            echo -e "    ${RED}[-] $nombre   inactivo puerto: $puerto${NC}"
        else
            echo -e "    ${YELLOW}[?] $nombre   no instalado${NC}"
        fi
    done
}

show_main_menu() {
    show_header
    echo -e "  ============  MENU PRINCIPAL  ============"
    echo ""
    echo -e "  ${CYAN}-- Instalacion -----------------------------${NC}"
    echo -e "  ${GREEN} 1)  Instalar Apache (httpd)${NC}"
    echo -e "  ${GREEN} 2)  Instalar Nginx${NC}"
    echo -e "  ${GREEN} 3)  Instalar Tomcat${NC}"
    echo ""
    echo -e "  ${CYAN}-- Gestion de servicios --------------------${NC}"
    echo -e "  ${GREEN} 4)  Iniciar / Detener / Reiniciar servicio${NC}"
    echo -e "  ${GREEN} 5)  Ver puertos activos de cada servicio${NC}"
    echo -e "  ${GREEN} 6)  Ver logs recientes de un servicio${NC}"
    echo ""
    echo -e "  ${CYAN}-- Configuracion ---------------------------${NC}"
    echo -e "  ${GREEN} 7)  Cambiar puerto de un servicio instalado${NC}"
    echo -e "  ${GREEN} 8)  Ver encabezados HTTP (curl -I)${NC}"
    echo -e "  ${GREEN} 9)  Liberar puertos (detener servicios)${NC}"
    echo ""
    echo -e "  ${RED} 0)  Salir${NC}"
    echo ""
    echo -n "  Selecciona una opcion [0-9]: "
}

flow_apache() {
    fn_section "Flujo de instalacion: Apache"
    fn_init_pkg_manager
    local puerto
    puerto=$(fn_solicitar_puerto "Apache" 80)
    fn_install_apache "$puerto"
}

flow_nginx() {
    fn_section "Flujo de instalacion: Nginx"
    fn_init_pkg_manager
    local puerto
    puerto=$(fn_solicitar_puerto "Nginx" 8080)
    fn_install_nginx "$puerto"
}

flow_tomcat() {
    fn_section "Flujo de instalacion: Tomcat"
    fn_init_pkg_manager
    local puerto
    puerto=$(fn_solicitar_puerto "Tomcat" 8081)
    fn_install_tomcat "$puerto"
}

show_manage_menu() {
    show_header
    echo "  ============  GESTION DE SERVICIOS  ============"
    echo ""
    echo -e "  ${GREEN} 1)  Apache (httpd)${NC}"
    echo -e "  ${GREEN} 2)  Nginx${NC}"
    echo -e "  ${GREEN} 3)  Tomcat${NC}"
    echo -e "  ${RED} 0)  Volver${NC}"
    echo ""
    read -rp "  Servicio [0-3]: " sel_svc

    local svc_map=("" "httpd" "nginx" "tomcat")
    local svcname="${svc_map[$sel_svc]}"
    [ -z "$svcname" ] && return

    echo ""
    echo "  Acciones sobre: $svcname"
    echo -e "  ${GREEN} 1)  Iniciar${NC}"
    echo -e "  ${GREEN} 2)  Detener${NC}"
    echo -e "  ${GREEN} 3)  Reiniciar${NC}"
    echo -e "  ${GREEN} 4)  Estado detallado${NC}"
    echo -e "  ${RED} 0)  Volver${NC}"
    echo ""
    read -rp "  Accion [0-4]: " accion

    case "$accion" in
        1)
            if systemctl start "$svcname"; then
                fn_ok "$svcname iniciado."
            else
                fn_err "No se pudo iniciar $svcname."
                systemctl status "$svcname" --no-pager -n 20
            fi
            ;;
        2)
            if systemctl stop "$svcname"; then
                fn_ok "$svcname detenido."
            else
                fn_err "No se pudo detener $svcname."
                systemctl status "$svcname" --no-pager -n 20
            fi
            ;;
        3)
            if systemctl restart "$svcname"; then
                fn_ok "$svcname reiniciado."
            else
                fn_err "No se pudo reiniciar $svcname."
                systemctl status "$svcname" --no-pager -n 20
            fi
            ;;
        4)
            systemctl status "$svcname"
            ;;
        0) return ;;
        *) fn_warn "Opcion invalida." ;;
    esac
}

show_ports_status() {
    show_header
    echo "  ============  PUERTOS ACTIVOS POR SERVICIO  ============"
    echo ""
    echo "  Configuracion en archivos:"
    echo "   Apache : puerto $(fn_get_puerto_actual httpd)"
    echo "   Nginx  : puerto $(fn_get_puerto_actual nginx)"
    echo "   Tomcat : puerto $(fn_get_puerto_actual tomcat)"
    echo ""
    echo "  Puertos realmente en escucha (ss -tlnp):"
    ss -tlnp 2>/dev/null | grep -E 'LISTEN' | awk '{print "   " $4 "\t" $6}' | sort
}

show_logs_menu() {
    show_header
    echo "  ============  LOGS DE SERVICIOS  ============"
    echo ""
    echo -e "  ${GREEN} 1)  Apache  - /var/log/httpd/error_log${NC}"
    echo -e "  ${GREEN} 2)  Nginx   - /var/log/nginx/error.log${NC}"
    echo -e "  ${GREEN} 3)  Tomcat  - journalctl${NC}"
    echo -e "  ${RED} 0)  Volver${NC}"
    echo ""
    read -rp "  Selecciona [0-3]: " sel

    case "$sel" in
        1)
            [ -f /var/log/httpd/error_log ] && tail -30 /var/log/httpd/error_log || fn_warn "No se encontro /var/log/httpd/error_log"
            ;;
        2)
            [ -f /var/log/nginx/error.log ] && tail -30 /var/log/nginx/error.log || fn_warn "No se encontro /var/log/nginx/error.log"
            ;;
        3)
            journalctl -u tomcat -n 30 --no-pager 2>/dev/null || fn_warn "Sin logs de tomcat."
            ;;
        0) return ;;
        *) fn_warn "Opcion invalida." ;;
    esac
}

show_change_port_menu() {
    show_header
    echo "  ============  CAMBIAR PUERTO  ============"
    echo ""
    echo "   Puerto actual de cada servicio:"
    echo "   Apache : $(fn_get_puerto_actual httpd)"
    echo "   Nginx  : $(fn_get_puerto_actual nginx)"
    echo "   Tomcat : $(fn_get_puerto_actual tomcat)"
    echo ""
    echo -e "  ${GREEN} 1)  Apache${NC}"
    echo -e "  ${GREEN} 2)  Nginx${NC}"
    echo -e "  ${GREEN} 3)  Tomcat${NC}"
    echo -e "  ${RED} 0)  Volver${NC}"
    echo ""
    read -rp "  Servicio [0-3]: " sel

    local svc_map=("" "apache" "nginx" "tomcat")
    local svcname="${svc_map[$sel]}"
    [ -z "$svcname" ] && return

    local default_port
    case "$svcname" in
        apache) default_port=80 ;;
        nginx) default_port=8080 ;;
        tomcat) default_port=8081 ;;
        *) default_port=8080 ;;
    esac

    local puerto_nuevo
    puerto_nuevo=$(fn_solicitar_puerto "$svcname" "$default_port")
    fn_cambiar_puerto "$svcname" "$puerto_nuevo" || return 1

    echo ""
    fn_info "Verificando respuesta del servidor..."
    sleep 1
    if ! curl -sI "http://localhost:$puerto_nuevo" | head -5; then
        fn_err "No hubo respuesta HTTP en el puerto $puerto_nuevo"
    fi
}

show_http_headers() {
    show_header
    echo "  ============  ENCABEZADOS HTTP  ============"
    echo "  Equivalente a: curl -I http://localhost:PUERTO"
    echo ""
    read -rp "  URL o puerto [ej: 80  o  http://localhost:8080]: " user_input

    local url
    if echo "$user_input" | grep -qE '^[0-9]+$'; then
        url="http://localhost:$user_input"
    else
        url="$user_input"
    fi

    echo ""
    echo -e "  ${CYAN}Consultando: $url${NC}"
    echo "  ------------------------------------------"
    if ! curl -I --max-time 5 "$url"; then
        fn_err "No se pudo obtener respuesta HTTP desde $url"
    fi
}

show_free_ports_menu() {
    show_header
    echo "  ============  LIBERAR PUERTOS  ============"
    echo ""
    echo -e "  ${GREEN} 1)  Detener Apache${NC}"
    echo -e "  ${GREEN} 2)  Detener Nginx${NC}"
    echo -e "  ${GREEN} 3)  Detener Tomcat${NC}"
    echo -e "  ${YELLOW} 4)  Detener TODOS${NC}"
    echo -e "  ${CYAN} 5)  Ver puertos en uso ahora${NC}"
    echo -e "  ${RED} 0)  Volver${NC}"
    echo ""
    read -rp "  Selecciona [0-5]: " sel

    case "$sel" in
        1)
            if systemctl stop httpd; then fn_ok "Apache detenido."; else fn_err "No se pudo detener Apache."; fi
            ;;
        2)
            if systemctl stop nginx; then fn_ok "Nginx detenido."; else fn_err "No se pudo detener Nginx."; fi
            ;;
        3)
            if systemctl stop tomcat; then fn_ok "Tomcat detenido."; else fn_err "No se pudo detener Tomcat."; fi
            ;;
        4)
            systemctl stop httpd nginx tomcat 2>/dev/null
            fn_ok "Todos los servicios detenidos."
            ;;
        5)
            echo ""
            echo "  Puertos en escucha actualmente:"
            ss -tlnp 2>/dev/null | grep LISTEN | awk '{print "   " $4}' | sort
            ;;
        0) return ;;
        *) fn_warn "Opcion invalida." ;;
    esac
}

main() {
    fn_check_root

    while true; do
        show_main_menu
        read -r opcion

        case "$opcion" in
            1) flow_apache ;;
            2) flow_nginx ;;
            3) flow_tomcat ;;
            4) show_manage_menu ;;
            5) show_ports_status ;;
            6) show_logs_menu ;;
            7) show_change_port_menu ;;
            8) show_http_headers ;;
            9) show_free_ports_menu ;;
            0)
                echo ""
                fn_ok "Hasta luego!"
                echo ""
                exit 0
                ;;
            *)
                fn_warn "Opcion invalida. Ingresa un numero del 0 al 9."
                sleep 1
                ;;
        esac

        echo ""
        read -rp "  Presiona ENTER para volver al menu..."
    done
}

main