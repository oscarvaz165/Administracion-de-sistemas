#!/bin/bash

# ==============================================================================
# Practica-06: menu.sh
# Script principal para el aprovisionamiento web en Linux
# ==============================================================================

source "$(dirname "$0")/http_functions.sh"

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Este script debe ejecutarse como root (use sudo).${NC}"
    exit 1
fi

show_menu() {
    clear
    echo ""
    echo -e "${BLUE}  +============================================================+${NC}"
    echo -e "${BLUE}  |      APROVISIONAMIENTO DE SERVIDORES HTTP                  |${NC}"
    echo -e "${BLUE}  |      Practica 6 - Mageia 9 - Bash                          |${NC}"
    echo -e "${BLUE}  +============================================================+${NC}"
    echo ""
    check_services_status
    echo ""
    echo -e "  ${GREEN}1.${NC} Instalar Apache"
    echo -e "  ${GREEN}2.${NC} Instalar Nginx"
    echo -e "  ${GREEN}3.${NC} Instalar Tomcat (v9)"
    echo -e "  ${GREEN}4.${NC} Mostrar estado de los servicios"
    echo -e "  ${GREEN}5.${NC} Bajar un servicio"
    echo -e "  ${GREEN}6.${NC} Eliminar por completo un servicio (Purge)"
    echo -e "  ${RED}7.${NC} Salir"
    echo ""
    echo -e "${BLUE}  +============================================================+${NC}"
    echo ""
    read -p "  Seleccione una opcion [1-7]: " OPTION
}

while true; do
    show_menu

    case $OPTION in
        1)
            service="apache2"
            versions=$(get_versions "$service")
            echo ""
            echo -e "  ${CYAN}Versiones disponibles:${NC}"
            echo "$versions"
            echo ""
            read -p "  Ingrese la version exacta a instalar: " VERSION
            if ! validate_input "$VERSION"; then
                fn_err "Version invalida."
                continue
            fi
            ;;
        2)
            service="nginx"
            versions=$(get_versions "$service")
            echo ""
            echo -e "  ${CYAN}Versiones disponibles:${NC}"
            echo "$versions"
            echo ""
            read -p "  Ingrese la version exacta a instalar: " VERSION
            if ! validate_input "$VERSION"; then
                fn_err "Version invalida."
                continue
            fi
            ;;
        3)
            service="tomcat"
            VERSION="LTS (Repo)"
            ;;
        4)
            check_services_status
            read -p "  Presione Enter para continuar..." dummy
            continue
            ;;
        5)
            echo ""
            echo "  Elija el servicio a bajar:"
            echo -e "  ${GREEN}1.${NC} Apache"
            echo -e "  ${GREEN}2.${NC} Nginx"
            echo -e "  ${GREEN}3.${NC} Tomcat"
            echo ""
            read -p "  Opcion: " STOP_OPT
            case $STOP_OPT in
                1) stop_linux_service "apache2" ;;
                2) stop_linux_service "nginx" ;;
                3) stop_linux_service "tomcat" ;;
                *) fn_warn "Opcion invalida." ;;
            esac
            read -p "  Presione Enter para continuar..." dummy
            continue
            ;;
        6)
            echo ""
            echo "  Elija el servicio a ELIMINAR por completo:"
            echo -e "  ${GREEN}1.${NC} Apache"
            echo -e "  ${GREEN}2.${NC} Nginx"
            echo -e "  ${GREEN}3.${NC} Tomcat"
            echo ""
            read -p "  Opcion: " PURGE_OPT
            case $PURGE_OPT in
                1) purge_services "apache2" ;;
                2) purge_services "nginx" ;;
                3) purge_services "tomcat" ;;
                *) fn_warn "Opcion invalida." ;;
            esac
            read -p "  Presione Enter para continuar..." dummy
            continue
            ;;
        7)
            echo ""
            fn_ok "Hasta luego!"
            echo ""
            exit 0
            ;;
        *)
            fn_warn "Opcion invalida. Ingresa un numero del 1 al 7."
            sleep 2
            continue
            ;;
    esac

    # Solicitar puerto con validacion
    while true; do
        echo ""
        read -p "  Ingrese el puerto de escucha: " PORT

        if [[ ! "$PORT" =~ ^[0-9]+$ ]]; then
            fn_err "El puerto debe ser un numero."
            read -p "  Deseas intentar con otro puerto? (s/n): " RETRY
            if [[ "$RETRY" =~ ^[nN]$ ]]; then continue 2; fi
            continue
        fi

        REASON=""
        if is_reserved_port "$PORT"; then
            REASON="esta FUERA DE RANGO (1-65535)"
        elif ! check_port "$PORT"; then
            REASON="ya esta siendo OCUPADO"
        fi

        if [[ -n "$REASON" ]]; then
            fn_warn "El puerto $PORT $REASON."
            read -p "  Deseas intentar con otro puerto? (s/n): " RETRY
            if [[ "$RETRY" =~ ^[nN]$ ]]; then
                continue 2
            else
                continue
            fi
        fi

        break
    done

    # Proceder con la instalacion
    case $service in
        apache2) install_apache "$VERSION" "$PORT" ;;
        nginx)   install_nginx  "$VERSION" "$PORT" ;;
        tomcat)  install_tomcat "$PORT"             ;;
    esac

    read -p "  Presione Enter para continuar..." dummy
done