#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

#Add some basic function here
function LOGD() {
    echo -e "${yellow}[DEG] $* ${plain}"
}

function LOGE() {
    echo -e "${red}[ERROR] $* ${plain}"
}

function LOGI() {
    echo -e "${green}[INFO] $* ${plain}"
}

# Ayudantes de puertos: detecta si hay un servicio escuchando (mejor esfuerzo)
is_port_in_use() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -ltn 2>/dev/null | awk -v p=":${port}$" '$4 ~ p {exit 0} END {exit 1}'
        return
    fi
    if command -v netstat >/dev/null 2>&1; then
        netstat -lnt 2>/dev/null | awk -v p=":${port} " '$4 ~ p {exit 0} END {exit 1}'
        return
    fi
    if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:${port} -sTCP:LISTEN >/dev/null 2>&1 && return 0
    fi
    return 1
}

# Ayudantes simples para validación de dominio/IP
is_ipv4() {
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && return 0 || return 1
}
is_ipv6() {
    [[ "$1" =~ : ]] && return 0 || return 1
}
is_ip() {
    is_ipv4 "$1" || is_ipv6 "$1"
}
is_domain() {
    [[ "$1" =~ ^([A-Za-z0-9](-*[A-Za-z0-9])*\.)+(xn--[a-z0-9]{2,}|[A-Za-z]{2,})$ ]] && return 0 || return 1
}

# check root
[[ $EUID -ne 0 ]] && LOGE "ERROR: ¡Debes ser root para ejecutar este script! \n" && exit 1

# Check OS and set release variable
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "No se pudo verificar el sistema operativo, ¡comuníquese con el autor!" >&2
    exit 1
fi
echo "La versión del sistema operativo es: $release"

os_version=""
os_version=$(grep "^VERSION_ID" /etc/os-release | cut -d '=' -f2 | tr -d '"' | tr -d '.')

# Declare Variables
xui_folder="${XUI_MAIN_FOLDER:=/usr/local/x-ui}"
xui_service="${XUI_SERVICE:=/etc/systemd/system}"
log_folder="${XUI_LOG_FOLDER:=/var/log/x-ui}"
mkdir -p "${log_folder}"
iplimit_log_path="${log_folder}/3xipl.log"
iplimit_banned_log_path="${log_folder}/3xipl-banned.log"

confirm() {
    # 1️⃣ Revisar si se pasaron más de un argumento a la función
    if [[ $# > 1 ]]; then
        # Muestra un mensaje con un valor por defecto y lee la respuesta del usuario
        echo && read -rp "$1 [Predeterminado $2]: " temp
        # Si el usuario no escribe nada, usar el valor por defecto
        if [[ "${temp}" == "" ]]; then
            temp=$2
        fi
    else
        # Si solo se pasa un argumento, solo muestra [s/n] y lee la respuesta
        read -rp "$1 [s/n]: " temp
    fi

    # 2️⃣ Verificar la respuesta del usuario
    if [[ "${temp}" == "s" || "${temp}" == "S" || "${temp}" == "y" || "${temp}" == "Y" ]]; then
        return 0   # significa "sí" → éxito
    else
        return 1   # significa "no" → cancelación
    fi
}

confirm_restart() {
    confirm "Reiniciar el panel, Atención: Al reiniciar el panel también se reiniciará Xray" "s"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}Presione enter para volver al menú principal... ${plain}" && read -r temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/emirjorge/3x-ui_es/main/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    confirm "Esta función reinstalará forzosamente la última versión y los datos no se perderán. ¿Quieres continuar? (s/n)" "s"
    if [[ $? != 0 ]]; then
        LOGE "Cancelado"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/emirjorge/3x-ui_es/main/update.sh)
    if [[ $? == 0 ]]; then
        LOGI "La actualización está completa, el Panel se ha reiniciado automáticamente"
        before_show_menu
    fi
}

update_menu() {
    echo -e "${yellow}Actualizando menú${plain}"
    confirm "Esta función actualizará el menú con los últimos cambios." "s"
    if [[ $? != 0 ]]; then
        LOGE "Cancelado"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi

    curl -fLRo /usr/bin/x-ui https://raw.githubusercontent.com/emirjorge/3x-ui_es/main/x-ui.sh
    chmod +x ${xui_folder}/x-ui.sh
    chmod +x /usr/bin/x-ui

    if [[ $? == 0 ]]; then
        echo -e "${green}Actualización exitosa. El panel se ha reiniciado automáticamente.${plain}"        
        exit 0
    else
        echo -e "${red}No se pudo actualizar el menú.${plain}"
        return 1
    fi
}

legacy_version() {
    echo -n "Ingrese la versión del Panel (Ejemplo 2.4.0):"
    read -r panel_version

    if [ -z "$panel_version" ]; then
        echo "La versión del Panel no puede estar vacía. Cancelando..."
    exit 1
    fi
    # Use the entered panel version in the download link
    install_command="bash <(curl -Ls "https://raw.githubusercontent.com/emirjorge/3x-ui_es/v$panel_version/install.sh") v$panel_version"

    echo "Descargando e instalando Panel versión $panel_version..."
    eval $install_command
}

# Función para manejar la eliminación del archivo del script
delete_script() {
    rm "$0" # Eliminar el propio archivo del script.
    exit 1
}

uninstall() {
    confirm "¿Está seguro de que desea desinstalar el panel? ¡Xray también se desinstalará! (s/n)" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    
    if [[ $release == "alpine" ]]; then
        rc-service x-ui stop
        rc-update del x-ui
        rm /etc/init.d/x-ui -f
    else
    systemctl stop x-ui
    systemctl disable x-ui
    rm ${xui_service}/x-ui.service -f
    systemctl daemon-reload
    systemctl reset-failed
    fi

    rm /etc/x-ui/ -rf
    rm ${xui_folder}/ -rf

    echo ""
    echo -e "Desinstalado exitosamente.\n"
    echo "Si necesitas instalar este panel nuevamente, puedes utilizar el siguiente comando:"
    echo -e "${green}bash <(curl -Ls https://raw.githubusercontent.com/emirjorge/3x-ui_es/master/install.sh)${plain}"
    echo ""
    # Capturar la señal SIGTERM
    trap delete_script SIGTERM
    delete_script
}

reset_user() {
    confirm "¿Estás seguro de restablecer el nombre de usuario y contraseña del panel? (s/n)" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi

    read -rp "Configure el nombre de usuario de inicio de sesión [el valor predeterminado es un nombre de usuario aleatorio]: " config_account
    [[ -z $config_account ]] && config_account=$(gen_random_string 10)
    read -rp "Establezca la contraseña de inicio de sesión [la contraseña predeterminada es aleatoria]: " config_password
    [[ -z $config_password ]] && config_password=$(gen_random_string 18)

    read -rp "¿Desea desactivar la autenticación de dos factores configurada actualmente? (s/n): " twoFactorConfirm
    if [[ $twoFactorConfirm != "s" && $twoFactorConfirm != "S" ]]; then    
        ${xui_folder}/x-ui setting -username "${config_account}" -password "${config_password}" -resetTwoFactor false >/dev/null 2>&1
    else
        ${xui_folder}/x-ui setting -username "${config_account}" -password "${config_password}" -resetTwoFactor true >/dev/null 2>&1
        echo -e "La autenticación de dos factores ha sido deshabilitada."
    fi    
    
    echo -e "El nombre de usuario de inicio de sesión del panel se ha restablecido a: ${green} ${config_account} ${plain}"
    echo -e "La contraseña de inicio de sesión del panel se ha restablecido a: ${green} ${config_password} ${plain}"
    echo -e "${green} Utilice el nuevo nombre de usuario y contraseña de inicio de sesión para acceder al panel X-UI. ¡Recuérdalos! ${plain}"
    confirm_restart
}

gen_random_string() {
    local length="$1"
    local random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

reset_webbasepath() {
    echo -e "${yellow}Restableciendo la Base Path de la Web${plain}"

    read -rp "¿Está seguro de que desea restablecer el Path Base de la web? (s/n): " confirm
    if [[ $confirm != "s" && $confirm != "S" ]]; then
        echo -e "${yellow}Operation canceled.${plain}"
        return
    fi

    config_webBasePath=$(gen_random_string 18)

    # Apply the new web base path setting
    ${xui_folder}/x-ui setting -webBasePath "${config_webBasePath}" >/dev/null 2>&1

    echo -e "Web base path has been reset to: ${green}${config_webBasePath}${plain}"
    echo -e "${green}Please use the new web base path to access the panel.${plain}"
    restart
}

reset_config() {
    confirm "¿Está seguro de que desea restablecer todas las configuraciones del panel? Los datos de la cuenta no se perderán, el nombre de usuario y la contraseña no cambiarán (s/n)" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    ${xui_folder}/x-ui setting -reset
    echo -e "Todas las configuraciones del panel se han restablecido a los valores predeterminados."
    restart
}

check_config() {
    local info=$(${xui_folder}/x-ui setting -show true)
    if [[ $? != 0 ]]; then
        LOGE "Se presenta un error de configuración actual, verifique los registros"
        show_menu
        return
    fi
    LOGI "${info}"
    
    local existing_webBasePath=$(echo "$info" | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(echo "$info" | grep -Eo 'port: .+' | awk '{print $2}')
    local existing_cert=$(${xui_folder}/x-ui setting -getCert true | grep 'cert:' | awk -F': ' '{print $2}' | tr -d '[:space:]')
    local server_ip=$(curl -s --max-time 3 https://api.ipify.org)
    if [ -z "$server_ip" ]; then
        server_ip=$(curl -s --max-time 3 https://4.ident.me)
    fi

    if [[ -n "$existing_cert" ]]; then
        local domain=$(basename "$(dirname "$existing_cert")")

        if [[ "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            echo -e "${green}URL de acceso: https://${domain}:${existing_port}${existing_webBasePath}${plain}"
        else
            echo -e "${green}URL de acceso: https://${server_ip}:${existing_port}${existing_webBasePath}${plain}"
        fi
    else
        echo -e "${red}⚠ ADVERTENCIA: ¡No hay ningún certificado SSL configurado!${plain}"
        echo -e "${yellow}Puede obtener un certificado de Let’s Encrypt para su dirección IP (válido ~6 días, se renueva automáticamente).${plain}"
        read -rp "¿Generar ahora el certificado SSL para la IP? [s/n]: " gen_ssl
        if [[ "$gen_ssl" == "s" || "$gen_ssl" == "S" ]]; then
            stop_auto >/dev/null 2>&1
            ssl_cert_issue_for_ip
            if [[ $? -eq 0 ]]; then
                echo -e "${green}URL de acceso: https://${server_ip}:${existing_port}${existing_webBasePath}${plain}"
                # ssl_cert_issue_for_ip ya reinicia el panel, pero se asegura de que esté en ejecución
                start >/dev/null 2>&1
            else
                LOGE "La instalación del certificado para la IP falló."
                echo -e "${yellow}Puede intentarlo nuevamente mediante la opción 18 (Gestión de certificados SSL).${plain}"
                start >/dev/null 2>&1
            fi
        else
            echo -e "${yellow}URL de acceso: http://${server_ip}:${existing_port}${existing_webBasePath}${plain}"
            echo -e "${yellow}Por seguridad, configure el certificado SSL usando la opción 18 (Gestión de certificados SSL)${plain}"
        fi
    fi
}

set_port() {
    echo -n "Introduzca el número de puerto[1-65535]: "
    read -r port
    if [[ -z "${port}" ]]; then
        LOGD "Cancelado"
        before_show_menu
    else
        ${xui_folder}/x-ui setting -port ${port}
        echo -e "El puerto está configurado. Reinicie el panel ahora y use el nuevo puerto ${green}${port}${plain} para acceder al Panel web"
        confirm_restart
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        LOGI "El panel se está ejecutando. No es necesario iniciar de nuevo. Si necesita reiniciar, seleccione reiniciar"
    else
        if [[ $release == "alpine" ]]; then
            rc-service x-ui start
    else
        systemctl start x-ui
        fi
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            LOGI "x-ui se inició con éxito"
        else
            LOGE "El panel no pudo iniciarse, es probable que tarde más de dos segundos en iniciarse. Verifique la información del registro luego"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop_auto() {
    check_status
    if [[ $? == 1 ]]; then
        echo ""
        LOGI "El panel se detuvo. ¡No es necesario detenerlo nuevamente!"
    else
        if [[ $release == "alpine" ]]; then
            rc-service x-ui stop
        else
            systemctl stop x-ui
        fi
        sleep 2
        check_status
        if [[ $? == 1 ]]; then
            LOGI "x-ui y xray se detuvieron exitosamente"
        else
            LOGE "El panel no pudo detenerse, es probable que tarde más de dos segundos en detenerse. Verifique la información del registro luego"
        fi
    fi

    sleep 2
}

stop() {
    check_status
    if [[ $? == 1 ]]; then
        echo ""
        LOGI "El panel se detuvo. ¡No es necesario detenerlo nuevamente!"
    else
        if [[ $release == "alpine" ]]; then
            rc-service x-ui stop
        else
        systemctl stop x-ui
        fi
        sleep 2
        check_status
        if [[ $? == 1 ]]; then
            LOGI "x-ui y xray se detuvieron exitosamente"
        else
            LOGE "El panel no pudo detenerse, es probable que tarde más de dos segundos en detenerse. Verifique la información del registro luego"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    if [[ $release == "alpine" ]]; then
    rc-service x-ui restart
    else
    systemctl restart x-ui
    fi
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        LOGI "x-ui y xray se reiniciaron correctamente"
    else
        LOGE "Error al reiniciar el panel, es probable que tarde más de dos segundos en reiniciarse. Verifique la información del registro luego"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    if [[ $release == "alpine" ]]; then
        rc-service x-ui status
    else
        systemctl status x-ui -l
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    if [[ $release == "alpine" ]]; then
        rc-update add x-ui
    else
        systemctl enable x-ui
    fi
    if [[ $? == 0 ]]; then
        LOGI "x-ui configurado exitosamente para iniciar automáticamente al encender el VPS"
    else
        LOGE "x-ui falló al configurar el inicio automático"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    if [[ $release == "alpine" ]]; then
        rc-update del x-ui
    else
        systemctl disable x-ui
    fi
    if [[ $? == 0 ]]; then
        LOGI "x-ui se canceló el inicio automatico exitosamente"
    else
        LOGE "x-ui falló al cancelar el inicio automático"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    if [[ $release == "alpine" ]]; then
        echo -e "${green}\t1.${plain} Registro de depuración"
        echo -e "${green}\t0.${plain} Volver al menú principal"
        read -rp "Elija una opción: " choice

        case "$choice" in
        0)
            show_menu
            ;;
        1)
            grep -F 'x-ui[' /var/log/messages
            if [[ $# == 0 ]]; then
                before_show_menu
            fi
            ;;
        *)
            echo -e "${red}Opción inválida. Por favor, seleccione un número válido.${plain}\n"
            show_log
            ;;
        esac
    else
        echo -e "${green}\t1.${plain} Registro de depuración"
        echo -e "${green}\t2.${plain} Limpiar todos los registros"
        echo -e "${green}\t0.${plain} Volver al menú principal"
        read -rp "Elija una opción: " choice

        case "$choice" in
        0)
            show_menu
            ;;
        1)
            journalctl -u x-ui -e --no-pager -f -p debug
            if [[ $# == 0 ]]; then
                before_show_menu
            fi
            ;;
        2)
            sudo journalctl --rotate
            sudo journalctl --vacuum-time=1s
            echo "Todos los registros fueron limpiados."
            restart
            ;;
        *)
            echo -e "${red}Opción inválida. Por favor, seleccione un número válido.${plain}\n"
            show_log
            ;;
        esac
    fi 
}

bbr_menu() {
    echo -e "${green}\t1.${plain} Habilitar BBR"
    echo -e "${green}\t2.${plain} Deshabilitar BBR"
    echo -e "${green}\t0.${plain} Volver al Menú Principal"
    read -rp "Elige una opción: " choice
    case "$choice" in
    0)
        show_menu
        ;;
    1)
        enable_bbr
        bbr_menu
        ;;
    2)
        disable_bbr
        bbr_menu
        ;;
    *)
        echo -e "${red}Opción inválida. Por favor, seleccione un número válido.${plain}\n"
        bbr_menu
        ;;
    esac
}

disable_bbr() {

    if [[ $(sysctl -n net.ipv4.tcp_congestion_control) != "bbr" ]] || [[ ! $(sysctl -n net.core.default_qdisc) =~ ^(fq|cake)$ ]]; then
        echo -e "${yellow}BBR no está actualmente habilitado.${plain}"
        before_show_menu
    fi

    if [ -f "/etc/sysctl.d/99-bbr-x-ui.conf" ]; then
        old_settings=$(head -1 /etc/sysctl.d/99-bbr-x-ui.conf | tr -d '#')
        sysctl -w net.core.default_qdisc="${old_settings%:*}"
        sysctl -w net.ipv4.tcp_congestion_control="${old_settings#*:}"
        rm /etc/sysctl.d/99-bbr-x-ui.conf
        sysctl --system
    else
        # Reemplazar configuraciones de BBR con CUBIC
        if [ -f "/etc/sysctl.conf" ]; then
            sed -i 's/net.core.default_qdisc=fq/net.core.default_qdisc=pfifo_fast/' /etc/sysctl.conf
            sed -i 's/net.ipv4.tcp_congestion_control=bbr/net.ipv4.tcp_congestion_control=cubic/' /etc/sysctl.conf
        # Aplicar cambios
            sysctl -p
        fi
    fi
    # Verificar que BBR se haya reemplazado con CUBIC
    if [[ $(sysctl -n net.ipv4.tcp_congestion_control) != "bbr" ]]; then
        echo -e "${green}BBR se ha reemplazado exitosamente con CUBIC.${plain}"
    else
        echo -e "${red}Error al reemplazar BBR con CUBIC. Por favor, verifica la configuración de tu sistema.${plain}"
    fi
}

enable_bbr() {
    if [[ $(sysctl -n net.ipv4.tcp_congestion_control) == "bbr" ]] && [[ $(sysctl -n net.core.default_qdisc) =~ ^(fq|cake)$ ]]; then
        echo -e "${green}BBR ya está habilitado!${plain}"
        before_show_menu
    fi

    # Hbailitar BBR
    if [ -d "/etc/sysctl.d/" ]; then
        {
            echo "#$(sysctl -n net.core.default_qdisc):$(sysctl -n net.ipv4.tcp_congestion_control)"
            echo "net.core.default_qdisc = fq"
            echo "net.ipv4.tcp_congestion_control = bbr"
        } > "/etc/sysctl.d/99-bbr-x-ui.conf"
        if [ -f "/etc/sysctl.conf" ]; then
            # Backup old settings from sysctl.conf, if any
            sed -i 's/^net.core.default_qdisc/# &/'          /etc/sysctl.conf
            sed -i 's/^net.ipv4.tcp_congestion_control/# &/' /etc/sysctl.conf
        fi
        sysctl --system
    else
        sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
        sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
        echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf
        # Aplicar cambios
        sysctl -p
    fi

    # Verifica que BBR está habilitado
    if [[ $(sysctl -n net.ipv4.tcp_congestion_control) == "bbr" ]]; then
        echo -e "${green}BBR ha sido habilitado exitosamente.${plain}"
    else
        echo -e "${red}No se pudo habilitar BBR. Por favor verifique la configuración de su sistema.${plain}"
    fi
}

update_shell() {
    curl -fLRo /usr/bin/x-ui -z /usr/bin/x-ui https://github.com/emirjorge/3x-ui_es/raw/main/x-ui.sh
    if [[ $? != 0 ]]; then
        echo ""
        LOGE "No se pudo descargar el script. Verifique si la máquina puede conectarse a Github"
        before_show_menu
    else
        chmod +x /usr/bin/x-ui
        LOGI "La actualización del script se realizó correctamente. Por favor vuelva a ejecutar el script"
        before_show_menu
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ $release == "alpine" ]]; then
        if [[ ! -f /etc/init.d/x-ui ]]; then
            return 2
        fi
        if [[ $(rc-service x-ui status | grep -F 'status: started' -c) == 1 ]]; then
            return 0
        else
            return 1
        fi
    else
        if [[ ! -f ${xui_service}/x-ui.service ]]; then
        return 2
        fi
        temp=$(systemctl status x-ui | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        if [[ "${temp}" == "running" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

check_enabled() {
    if [[ $release == "alpine" ]]; then
        if [[ $(rc-update show | grep -F 'x-ui' | grep default -c) == 1 ]]; then
            return 0
        else
            return 1
        fi
    else
        temp=$(systemctl is-enabled x-ui)
        if [[ "${temp}" == "enabled" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        LOGE "Panel instalado, por favor no lo reinstale"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        LOGE "Por favor instale el panel primero"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
    0)
        echo -e "Estado del panel: ${green}Iniciado${plain}"
        show_enable_status
        ;;
    1)
        echo -e "Panel state: ${yellow}No iniciado${plain}"
        show_enable_status
        ;;
    2)
        echo -e "Panel state: ${red}No instalado${plain}"
        ;;
    esac
    show_xray_status
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "Iniciar automáticamente: ${green}Si${plain}"
    else
        echo -e "Iniciar automáticamente: ${red}No${plain}"
    fi
}

check_xray_status() {
    count=$(ps -ef | grep "xray-linux" | grep -v "grep" | wc -l)
    if [[ count -ne 0 ]]; then
        return 0
    else
        return 1
    fi
}

show_xray_status() {
    check_xray_status
    if [[ $? == 0 ]]; then
        echo -e "Estado de Xray: ${green}Iniciado${plain}"
    else
        echo -e "Estado de Xray: ${red}No iniciado${plain}"
    fi
}

firewall_menu() {
    echo -e "${green}\t1.${plain} ${green}Instalar${plain} Firewall"
    echo -e "${green}\t2.${plain} Listado de puertos [enumerados]"
    echo -e "${green}\t3.${plain} ${green}Puertos${plain} Abiertos"
    echo -e "${green}\t4.${plain} ${red}Eliminar${plain} Puertos de la Lista"
    echo -e "${green}\t5.${plain} ${green}Habilitar${plain} Firewall"
    echo -e "${green}\t6.${plain} ${red}Desactivar${plain} Firewall"
    echo -e "${green}\t7.${plain} Estado de Firewall"
    echo -e "${green}\t0.${plain} Volver al Menú Principal"
    read -rp "Elige una opción: " choice
    case "$choice" in
    0)
        show_menu
        ;;
    1)
        install_firewall
        firewall_menu
        ;;
    2)
        ufw status numbered
        firewall_menu
        ;;
    3)
        open_ports
        firewall_menu
        ;;
    4)
        delete_ports
        firewall_menu
        ;;
    5)
        ufw enable
        firewall_menu
        ;;
    6)
        ufw disable
        firewall_menu
        ;;
    7)
        ufw status verbose
        firewall_menu
        ;;
    *) 
    echo -e "${red}Opción no válida. Seleccione un número válido.${plain}\n"
    firewall_menu
    ;;
    esac
}

install_firewall() {
    if ! command -v ufw &>/dev/null; then
        echo "El firewall ufw no está instalado. Instalando ahora..."
        apt-get update
        apt-get install -y ufw
    else
        echo "El firewall ufw ya está instalado"
    fi

    # Verificar si el firewall está inactivo
    if ufw status | grep -q "Status: active"; then
        echo "El firewall ya está activo"
    else
        echo "Activando el firewall..."
        # Abrir los puertos necesarios
        ufw allow ssh
        ufw allow http
        ufw allow https
        ufw allow 2053/tcp #webPort
        ufw allow 2096/tcp #subport

        # Habilitar el firewall
        ufw --force enable
    fi
}

open_ports() {
# Solicitar al usuario que ingrese una lista de puertos a abrir
    read -rp "Ingrese los puertos que desea abrir (ejem. 80,443,2053 ó rango 400-500): " ports

    # Verificar si la entrada es válida
    if ! [[ $ports =~ ^([0-9]+|[0-9]+-[0-9]+)(,([0-9]+|[0-9]+-[0-9]+))*$ ]]; then
        echo "Error: entrada no válida. Introduzca una lista de puertos separados por comas o un rango de puertos (ejem. 80,443,2053 ó 400-500)." >&2
        exit 1
    fi

    # Abrir los puertos especificados usando ufw
    IFS=',' read -ra PORT_LIST <<<"$ports"
    for port in "${PORT_LIST[@]}"; do
        if [[ $port == *-* ]]; then
            # Dividir el rango en puerto inicial y final
            start_port=$(echo $port | cut -d'-' -f1)
            end_port=$(echo $port | cut -d'-' -f2)
            # Abrir el rango de puertos
            ufw allow $start_port:$end_port/tcp
            ufw allow $start_port:$end_port/udp
        else
            # Abrir el puerto individual
            ufw allow "$port"
        fi
    done

    # Confirmar que los puertos esten abiertos
    echo "Los siguientes puertos están abiertos:"
    for port in "${PORT_LIST[@]}"; do
        if [[ $port == *-* ]]; then
            start_port=$(echo $port | cut -d'-' -f1)
            end_port=$(echo $port | cut -d'-' -f2)
            # Verificar si el rango de puertos se abrió correctamente
            (ufw status | grep -q "$start_port:$end_port") && echo "$start_port-$end_port"
        else
            # Verificar si el puerto individual se abrió correctamente
            (ufw status | grep -q "$port") && echo "$port"
        fi
    done
}

delete_ports() {
    # Mostrar las reglas actuales con números
    echo "Reglas actuales de UFW:"
    ufw status numbered

    # Preguntar al usuario cómo desea eliminar las reglas
    echo "¿Desea eliminar reglas por:"
    echo "1) Números de regla"
    echo "2) Puertos"
    read -rp "Ingrese su opción (1 o 2): " choice

    if [[ $choice -eq 1 ]]; then
        # Eliminando por números de regla
        read -rp "Ingrese los números de regla que desea eliminar (1, 2, etc.): " rule_numbers

        # Validar la entrada
        if ! [[ $rule_numbers =~ ^([0-9]+)(,[0-9]+)*$ ]]; then
            echo "Error: Entrada inválida. Por favor ingrese una lista de números de regla separados por comas." >&2
            exit 1
        fi

        # Dividir los números en un arreglo
        IFS=',' read -ra RULE_NUMBERS <<<"$rule_numbers"
        for rule_number in "${RULE_NUMBERS[@]}"; do
            # Eliminar la regla por número
            ufw delete "$rule_number" || echo "No se pudo eliminar la regla número $rule_number"
        done

        echo "Las reglas seleccionadas han sido eliminadas."

elif [[ $choice -eq 2 ]]; then
    # Eliminando por puertos
    read -rp "Ingresa los puertos que deseas eliminar (por ejemplo, 80,443,2053 o rango 400-500): " ports

    # Verificar si la entrada es válida
    if ! [[ $ports =~ ^([0-9]+|[0-9]+-[0-9]+)(,([0-9]+|[0-9]+-[0-9]+))*$ ]]; then
        echo "Error: Entrada inválida. Por favor, ingresa una lista de puertos separados por comas o un rango de puertos (por ejemplo, 80,443,2053 o 400-500)." >&2
        exit 1
    fi

    # Eliminar los puertos especificados utilizando ufw
    IFS=',' read -ra PORT_LIST <<<"$ports"
    for port in "${PORT_LIST[@]}"; do
        if [[ $port == *-* ]]; then
            # Dividir el rango en puertos de inicio y fin
            start_port=$(echo $port | cut -d'-' -f1)
            end_port=$(echo $port | cut -d'-' -f2)
            # Eliminar el rango de puertos
            ufw delete allow $start_port:$end_port/tcp
            ufw delete allow $start_port:$end_port/udp
        else
            # Eliminar un solo puerto
            ufw delete allow "$port"
        fi
    done

        # Confirmar que se han eliminado los puertos
        echo "Se han eliminado los siguientes puertos:"
        for port in "${PORT_LIST[@]}"; do
            if [[ $port == *-* ]]; then
                start_port=$(echo $port | cut -d'-' -f1)
                end_port=$(echo $port | cut -d'-' -f2)
                # Comprobar si el rango de puertos se ha eliminado correctamente
                (ufw status | grep -q "$start_port:$end_port") || echo "$start_port-$end_port"
            else
                # Comprobar si el puerto individual se ha eliminado correctamente
                (ufw status | grep -q "$port") || echo "$port"
            fi
        done
    else
        echo "${red}Error:${plain} Opción inválida. Por favor ingrese 1 o 2." >&2
        exit 1
    fi
}

update_all_geofiles() {
    update_geofiles "main"
    update_geofiles "IR"
    update_geofiles "RU"
}

update_geofiles() {
    case "${1}" in
        "main") dat_files=(geoip geosite); dat_source="Loyalsoldier/v2ray-rules-dat";;
        "IR") dat_files=(geoip_IR geosite_IR); dat_source="chocolate4u/Iran-v2ray-rules" ;;
        "RU") dat_files=(geoip_RU geosite_RU); dat_source="runetfreedom/russia-v2ray-rules-dat";;
    esac
    for dat in "${dat_files[@]}"; do
        # Eliminar el sufijo para el nombre de archivo remoto (ej. geoip_IR -> geoip)
        remote_file="${dat%%_*}"
        curl -fLRo ${xui_folder}/bin/${dat}.dat -z ${xui_folder}/bin/${dat}.dat \
            https://github.com/${dat_source}/releases/latest/download/${remote_file}.dat
    done
}

update_geo() {
echo -e "${green}\t1.${plain} Loyalsoldier (geoip.dat, geosite.dat)"
echo -e "${green}\t2.${plain} chocolate4u (geoip_IR.dat, geosite_IR.dat)"
echo -e "${green}\t3.${plain} runetfreedom (geoip_RU.dat, geosite_RU.dat)"
echo -e "${green}\t4.${plain} Todos"
echo -e "${green}\t0.${plain} Volver al menú principal"
read -rp "Elija una opción: " choice

case "$choice" in
0)
    show_menu
    ;;
1)
    update_geofiles "main"
    echo -e "${green}¡Los conjuntos de datos de Loyalsoldier se han actualizado correctamente!${plain}"
    restart
    ;;
2)
    update_geofiles "IR"
    echo -e "${green}¡Los conjuntos de datos de chocolate4u se han actualizado correctamente!${plain}"
    restart
    ;;
3)
    update_geofiles "RU"
    echo -e "${green}¡Los conjuntos de datos de runetfreedom se han actualizado correctamente!${plain}"
    restart
    ;;
4)
    update_all_geofiles
    echo -e "${green}¡Todos los archivos geo se han actualizado correctamente!${plain}"
    restart
    ;;
*)
    echo -e "${red}Opción inválida. Por favor, seleccione un número válido.${plain}\n"
    update_geo
    ;;
esac

    before_show_menu
}

install_acme() {
    # Verificar si acme.sh ya está instalado
    if command -v ~/.acme.sh/acme.sh &>/dev/null; then
        LOGI "acme.sh ya está instalado."
        return 0
    fi

    LOGI "Instalando acme.sh..."
    cd ~ || return 1 # Asegurarse de poder cambiar al directorio home

    curl -s https://get.acme.sh | sh
    if [ $? -ne 0 ]; then
        LOGE "Error al instalar acme.sh"
        return 1
    else
        LOGI "Instalación de acme.sh ha sido exitosa"
    fi

    return 0
}

ssl_cert_issue_main() {
    echo -e "${green}\t1.${plain} Obtener SSL (Dominio)"
    echo -e "${green}\t2.${plain} Revocar"
    echo -e "${green}\t3.${plain} Renovar forzadamente"
    echo -e "${green}\t4.${plain} Mostrar dominios existentes"
    echo -e "${green}\t5.${plain} Configurar rutas de certificados para el panel"
    echo -e "${green}\t6.${plain} Obtener SSL para dirección IP (certificado de 6 días, se renueva automáticamente)"
    echo -e "${green}\t0.${plain} Volver al menú principal"

    read -rp "Elija una opción: " choice
    case "$choice" in
    0) 
        show_menu 
        ;;
    1) 
        ssl_cert_issue
        ssl_cert_issue_main
        ;;
    2) 
        local domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
        if [ -z "$domains" ]; then
            echo "No se encontraron certificados para revocar."
        else
            echo "Dominios existentes:"
            echo "$domains"
            read -rp "Por favor, ingrese un dominio de la lista para revocar el certificado: " domain
            if echo "$domains" | grep -qw "$domain"; then
                ~/.acme.sh/acme.sh --revoke -d ${domain}
                LOGI "Certificado revocado para el dominio: $domain"
            else
                echo "Dominio ingresado inválido."
            fi
        fi
        ssl_cert_issue_main
        ;;
    3)
        local domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
        # Opción 3: Renovar certificado existente
        if [ -z "$domains" ]; then
            echo "No se encontraron certificados para renovar."
        else
            echo "Dominios existentes:"
            echo "$domains"
            read -rp "Por favor ingresa un dominio de la lista para renovar el certificado SSL: " domain
            if echo "$domains" | grep -qw "$domain"; then
                ~/.acme.sh/acme.sh --renew -d ${domain} --force
                LOGI "Certificado renovado forzosamente para el dominio: $domain"
            else
                echo "Dominio ingresado inválido."
            fi
        fi
        ssl_cert_issue_main
        ;;
    4)
        # Opción 4: Mostrar rutas de los certificados
        local domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
        if [ -z "$domains" ]; then
            echo "No se encontraron certificados."
        else
            echo "Dominios existentes y sus rutas:"
            for domain in $domains; do
                local cert_path="/root/cert/${domain}/fullchain.pem"
                local key_path="/root/cert/${domain}/privkey.pem"
                if [[ -f "${cert_path}" && -f "${key_path}" ]]; then
                    echo -e "Dominio: ${domain}"
                    echo -e "\tRuta del certificado: ${cert_path}"
                    echo -e "\tRuta de la clave privada: ${key_path}"
                else
                    echo -e "Dominio: ${domain} - Falta certificado o clave privada."
                fi
            done
        fi
        ssl_cert_issue_main
        ;;
    5)
        # Opción 5: Configurar rutas de certificados para el panel
        local domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
        if [ -z "$domains" ]; then
            echo "No se encontraron certificados."
        else
            echo "Dominios disponibles:"
            echo "$domains"
            read -rp "Por favor elige un dominio para configurar las rutas del panel: " domain

            if echo "$domains" | grep -qw "$domain"; then
                local webCertFile="/root/cert/${domain}/fullchain.pem"
                local webKeyFile="/root/cert/${domain}/privkey.pem"

                if [[ -f "${webCertFile}" && -f "${webKeyFile}" ]]; then
                    ${xui_folder}/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile"
                    echo "Paths del panel configuradas para el dominio: $domain"
                    echo "  - Archivo de certificado: $webCertFile"
                    echo "  - Archivo de clave privada: $webKeyFile"
                    restart
                else
                    echo "No se encontró el certificado o la clave privada para el dominio: $domain."
                fi
            else
                echo "Dominio ingresado inválido."
            fi
        fi
        ssl_cert_issue_main
        ;;
    6)
        # Opción 6: Emitir certificado SSL para la IP del servidor
        echo -e "${yellow}Certificado SSL de Let's Encrypt para la dirección IP${plain}"
        echo -e "Esto obtendrá un certificado para la IP de tu servidor usando el perfil de corta duración."
        echo -e "${yellow}Certificado válido por ~6 días, se renueva automáticamente mediante acme.sh cron job.${plain}"
        echo -e "${yellow}El puerto 80 debe estar abierto y accesible desde internet.${plain}"
        confirm "¿Deseas continuar?" "s"
        if [[ $? == 0 ]]; then
            ssl_cert_issue_for_ip
        fi
        ssl_cert_issue_main
        ;;

    *)
        # Opción inválida
        echo -e "${red}Opción inválida. Por favor selecciona un número válido.${plain}\n"
        ssl_cert_issue_main
        ;;
    esac
}

ssl_cert_issue_for_ip() {
    LOGI "Iniciando la generación automática de certificado SSL para la IP del servidor..."
    LOGI "Usando el perfil de Let's Encrypt de corta duración (~6 días de validez, se renueva automáticamente)"
    
    local existing_webBasePath=$(${xui_folder}/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(${xui_folder}/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    
    # Obtener la IP del servidor
    local server_ip=$(curl -s --max-time 3 https://api.ipify.org)
    if [ -z "$server_ip" ]; then
        server_ip=$(curl -s --max-time 3 https://4.ident.me)
    fi
    
    if [ -z "$server_ip" ]; then
        LOGE "No se pudo obtener la dirección IP del servidor"
        return 1
    fi
    
    LOGI "IP del servidor detectada: ${server_ip}"
    
    # Preguntar por IPv6 opcional
    local ipv6_addr=""
    read -rp "¿Tienes una dirección IPv6 para incluir? (dejar vacío para omitir): " ipv6_addr
    ipv6_addr="${ipv6_addr// /}"  # Eliminar espacios en blanco
    
    # Verificar primero acme.sh
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
        LOGI "acme.sh no encontrado, instalando..."
        install_acme
        if [ $? -ne 0 ]; then
            LOGE "Error al instalar acme.sh"
            return 1
        fi
    fi
    
    # Instalar socat según el sistema operativo
    case "${release}" in
    ubuntu | debian | armbian)
        apt-get update >/dev/null 2>&1 && apt-get install socat -y >/dev/null 2>&1
        ;;
    fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol)
        dnf -y update >/dev/null 2>&1 && dnf -y install socat >/dev/null 2>&1
        ;;
    centos)
        if [[ "${VERSION_ID}" =~ ^7 ]]; then
            yum -y update >/dev/null 2>&1 && yum -y install socat >/dev/null 2>&1
        else
            dnf -y update >/dev/null 2>&1 && dnf -y install socat >/dev/null 2>&1
        fi
        ;;
    arch | manjaro | parch)
        pacman -Sy --noconfirm socat >/dev/null 2>&1
        ;;
    opensuse-tumbleweed | opensuse-leap)
        zypper refresh >/dev/null 2>&1 && zypper -q install -y socat >/dev/null 2>&1
        ;;
    alpine)
        apk add socat curl openssl >/dev/null 2>&1
        ;;
    *)
        LOGW "Sistema Operativo no soportado para instalación automática de socat"
        ;;
    esac
    
    # Crear directorio para certificados
    certPath="/root/cert/ip"
    mkdir -p "$certPath"
    
    # Construir argumentos de dominio
    local domain_args="-d ${server_ip}"
    if [[ -n "$ipv6_addr" ]] && is_ipv6 "$ipv6_addr"; then
        domain_args="${domain_args} -d ${ipv6_addr}"
        LOGI "Incluyendo dirección IPv6: ${ipv6_addr}"
    fi
    
    # Elegir puerto para el listener HTTP-01 (por defecto 80, se permite cambiar)
    local WebPort=""
    read -rp "Puerto a usar para el listener ACME HTTP-01 (por defecto 80): " WebPort
    WebPort="${WebPort:-80}"
    if ! [[ "${WebPort}" =~ ^[0-9]+$ ]] || ((WebPort < 1 || WebPort > 65535)); then
        LOGE "Puerto inválido. Usando 80 por defecto."
        WebPort=80
    fi
    LOGI "Usando puerto ${WebPort} para emitir certificado para IP: ${server_ip}"
    if [[ "${WebPort}" -ne 80 ]]; then
        LOGI "Recordatorio: Let's Encrypt sigue accediendo al puerto 80; redirige el puerto externo 80 a ${WebPort} para validación."
    fi

    # Comprobar si el puerto está en uso
    while true; do
        if is_port_in_use "${WebPort}"; then
            LOGI "El puerto ${WebPort} está actualmente en uso."

            local alt_port=""
            read -rp "Ingresa otro puerto para el listener independiente de acme.sh (dejar vacío para cancelar): " alt_port
            alt_port="${alt_port// /}"
            if [[ -z "${alt_port}" ]]; then
                LOGE "El puerto ${WebPort} está ocupado; no se puede continuar con la emisión."
                return 1
            fi
            if ! [[ "${alt_port}" =~ ^[0-9]+$ ]] || ((alt_port < 1 || alt_port > 65535)); then
                LOGE "Puerto proporcionado inválido."
                return 1
            fi
            WebPort="${alt_port}"
            continue
        else
            LOGI "Puerto ${WebPort} libre y listo para validación independiente."
            break
        fi
    done
    
    # Comando de recarga - reinicia el panel después de la renovación
    local reloadCmd="systemctl restart x-ui 2>/dev/null || rc-service x-ui restart 2>/dev/null"
    
    # Emitir certificado para IP con perfil de corta duración
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force
    ~/.acme.sh/acme.sh --issue \
        ${domain_args} \
        --standalone \
        --server letsencrypt \
        --certificate-profile shortlived \
        --days 6 \
        --httpport ${WebPort} \
        --force
    
    if [ $? -ne 0 ]; then
        LOGE "Error al emitir certificado para IP: ${server_ip}"
        LOGE "Asegúrate de que el puerto ${WebPort} esté abierto y el servidor sea accesible desde internet"
        # Limpiar datos de acme.sh para IPv4 e IPv6 si se especifica
        rm -rf ~/.acme.sh/${server_ip} 2>/dev/null
        [[ -n "$ipv6_addr" ]] && rm -rf ~/.acme.sh/${ipv6_addr} 2>/dev/null
        rm -rf ${certPath} 2>/dev/null
        return 1
    else
        LOGI "Certificado emitido exitosamente para IP: ${server_ip}"
    fi
    
    # Instalar el certificado
    # Nota: acme.sh puede reportar "Reload error" y salir con código distinto de cero si reloadcmd falla,
    # pero los archivos del certificado aún se instalan. Verificamos los archivos en lugar del código de salida.
    ~/.acme.sh/acme.sh --installcert -d ${server_ip} \
        --key-file "${certPath}/privkey.pem" \
        --fullchain-file "${certPath}/fullchain.pem" \
        --reloadcmd "${reloadCmd}" 2>&1 || true
    
    # Verificar que existan los archivos del certificado (no confiar en código de salida)
    if [[ ! -f "${certPath}/fullchain.pem" || ! -f "${certPath}/privkey.pem" ]]; then
        LOGE "Archivos del certificado no encontrados después de la instalación"
        # Limpiar los datos de acme.sh tanto para IPv4 como IPv6 si se especifica
        rm -rf ~/.acme.sh/${server_ip} 2>/dev/null
        [[ -n "$ipv6_addr" ]] && rm -rf ~/.acme.sh/${ipv6_addr} 2>/dev/null
        rm -rf ${certPath} 2>/dev/null
        return 1
    fi
    
    LOGI "Archivos del certificado instalados correctamente"
    
    # Habilitar auto-renovación
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade >/dev/null 2>&1
    chmod 600 $certPath/privkey.pem 2>/dev/null
    chmod 644 $certPath/fullchain.pem 2>/dev/null
    
    # Configurar rutas del certificado para el panel
    local webCertFile="${certPath}/fullchain.pem"
    local webKeyFile="${certPath}/privkey.pem"
    
    if [[ -f "$webCertFile" && -f "$webKeyFile" ]]; then
        ${xui_folder}/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile"
        LOGI "Certificado configurado para el panel"
        LOGI "  - Archivo de Certificado: $webCertFile"
        LOGI "  - Archivo de Clave Privada: $webKeyFile"
        LOGI "  - Validez: ~6 días (renovación automática vía cron de acme.sh)"
        echo -e "${green}URL de acceso: https://${server_ip}:${existing_port}${existing_webBasePath}${plain}"
        LOGI "El panel se reiniciará para aplicar el certificado SSL..."
        restart
        return 0
    else
        LOGE "Archivos del certificado no encontrados después de la instalación"
        return 1
    fi
}

ssl_cert_issue() {
    local existing_webBasePath=$(${xui_folder}/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(${xui_folder}/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    # check for acme.sh first
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
        echo "No se encontró acme.sh, lo instalaremos"
        install_acme
        if [ $? -ne 0 ]; then
            LOGE "La instalación de acme falló, verifique los registros"
            exit 1
        fi
    fi

    # Instalar socat según el sistema operativo
    case "${release}" in
    ubuntu | debian | armbian)
        # En Ubuntu, Debian o Armbian: actualizar repositorios e instalar socat (silencioso)
        apt-get update >/dev/null 2>&1 && apt-get install socat -y >/dev/null 2>&1
        ;;
    fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol)
        # En Fedora, Amazon Linux, Virtuozzo, RHEL, AlmaLinux, Rocky o Oracle Linux: actualizar e instalar socat (silencioso)
        dnf -y update >/dev/null 2>&1 && dnf -y install socat >/dev/null 2>&1
        ;;
    centos)
        # En CentOS:
        if [[ "${VERSION_ID}" =~ ^7 ]]; then
            # Para CentOS 7: usar yum
            yum -y update >/dev/null 2>&1 && yum -y install socat >/dev/null 2>&1
        else
            # Para CentOS 8+ usar dnf
            dnf -y update >/dev/null 2>&1 && dnf -y install socat >/dev/null 2>&1
        fi
        ;;
    arch | manjaro | parch)
        # En Arch, Manjaro o Parch Linux: sincronizar repositorios e instalar socat sin confirmación
        pacman -Sy --noconfirm socat >/dev/null 2>&1
        ;;
    opensuse-tumbleweed | opensuse-leap)
        # En openSUSE (Tumbleweed o Leap): actualizar repositorios e instalar socat de forma silenciosa
        zypper refresh >/dev/null 2>&1 && zypper -q install -y socat >/dev/null 2>&1
        ;;
    alpine)
        # En Alpine Linux: instalar socat, curl y openssl
        apk add socat curl openssl >/dev/null 2>&1
        ;;
    *)
        # Cualquier otro sistema operativo: mostrar advertencia de que no es soportado
        LOGW "Sistema operativo no soportado para instalación automática de socat"
        ;;
    esac
    if [ $? -ne 0 ]; then
        LOGE "La instalación de socat falló, verifique los registros"
        exit 1
    else
        LOGI "socat instalado correctamente..."
    fi

    # Obtener el dominio aquí y necesitamos verificarlo
    local domain=""
    while true; do
        # Solicitar al usuario que ingrese el nombre de dominio
        read -rp "Por favor ingresa tu nombre de dominio: " domain
        domain="${domain// /}"  # Eliminar espacios en blanco

        # Verificar que no esté vacío
        if [[ -z "$domain" ]]; then
            LOGE "El nombre de dominio no puede estar vacío. Inténtalo de nuevo."
            continue
        fi

        # Verificar que tenga formato válido de dominio
        if ! is_domain "$domain"; then
            LOGE "Formato de dominio inválido: ${domain}. Por favor ingresa un nombre de dominio válido."
            continue
        fi

        # Si pasa las validaciones, salir del bucle
        break
    done
    LOGD "Tu dominio es: ${domain}, verificándolo..."

    # Verificar si ya existe un certificado
    local currentCert=$(~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}')
    if [ "${currentCert}" == "${domain}" ]; then
        local certInfo=$(~/.acme.sh/acme.sh --list)
        LOGE "El sistema ya tiene certificados, no se puede volver a emitir. Detalles de los certificados actuales:"
        LOGI "$certInfo"
        exit 1
    else
        LOGI "Su dominio está listo para emitir el certificado ahora..."
    fi

    # create a directory for install cert
    certPath="/root/cert/${domain}"
    if [ ! -d "$certPath" ]; then
        mkdir -p "$certPath"
    else
        rm -rf "$certPath"
        mkdir -p "$certPath"
    fi

    # Obtener el número de puerto para el servidor independiente (standalone)
    local WebPort=80
    read -rp "Por favor elige qué puerto usar (por defecto es 80): " WebPort

    # Validar que el puerto esté dentro del rango válido
    if [[ ${WebPort} -gt 65535 || ${WebPort} -lt 1 ]]; then
        LOGE "El puerto ${WebPort} es inválido, se usará el puerto 80 por defecto."
        WebPort=80
    fi
    LOGI "Se usará el puerto: ${WebPort} para emitir certificados. Por favor asegúrate de que este puerto esté abierto."

    # Emitir el certificado
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force
    ~/.acme.sh/acme.sh --issue -d ${domain} --listen-v6 --standalone --httpport ${WebPort} --force

    # Verificar si la emisión fue exitosa
    if [ $? -ne 0 ]; then
        LOGE "Fallo al emitir el certificado, por favor revisa los registros."
        rm -rf ~/.acme.sh/${domain}  # Limpiar datos temporales de acme.sh para este dominio
        exit 1
    else
        LOGI "Certificados emitidos exitosamente, instalando certificados..."
    fi

    # Comando de recarga por defecto
    reloadCmd="x-ui restart"

    LOGI "El --reloadcmd por defecto para ACME es: ${yellow}x-ui restart"
    LOGI "Este comando se ejecutará en cada emisión o renovación de certificado."

    # Preguntar si desea modificar el --reloadcmd
    read -rp "¿Deseas modificar el --reloadcmd para ACME? (s/n): " setReloadcmd
    if [[ "$setReloadcmd" == "s" || "$setReloadcmd" == "S" ]]; then
        echo -e "\n${green}\t1.${plain} Predefinido: systemctl reload nginx ; x-ui restart"
        echo -e "${green}\t2.${plain} Ingresa tu propio comando"
        echo -e "${green}\t0.${plain} Mantener reloadcmd por defecto"
        read -rp "Elige una opción: " choice
        case "$choice" in
        1)
            LOGI "Reloadcmd será: systemctl reload nginx ; x-ui restart"
            reloadCmd="systemctl reload nginx ; x-ui restart"
            ;;
        2)  
            LOGD "Se recomienda colocar 'x-ui restart' al final para evitar errores si otros servicios fallan."
            read -rp "Por favor ingresa tu reloadcmd (ejemplo: systemctl reload nginx ; x-ui restart): " reloadCmd
            LOGI "Tu reloadcmd es: ${reloadCmd}"
            ;;
        *)
            LOGI "Se mantiene el reloadcmd por defecto"
            ;;
        esac
    fi

    # instalar el certificado
    ~/.acme.sh/acme.sh --installcert -d ${domain} \
        --key-file /root/cert/${domain}/privkey.pem \
        --fullchain-file /root/cert/${domain}/fullchain.pem --reloadcmd "${reloadCmd}"

    if [ $? -ne 0 ]; then
        LOGE "Error al instalar los certificados, saliendo..."
        rm -rf ~/.acme.sh/${domain}
        exit 1
    else
        LOGI "Certificados instalados correctamente, habilitando la renovación automática..."
    fi

    # habilitar la renovación automática
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    if [ $? -ne 0 ]; then
        LOGE "La renovación automática falló, detalles de los certificados:"
        ls -lah cert/*
        chmod 600 $certPath/privkey.pem
        chmod 644 $certPath/fullchain.pem
        exit 1
    else
        LOGI "Renovación automática exitosa, detalles de certificados:"
        ls -lah cert/*
        chmod 600 $certPath/privkey.pem   # Establecer permisos seguros para la clave privada
        chmod 644 $certPath/fullchain.pem # Establecer permisos para el certificado
    fi

    # Preguntar al usuario si desea configurar este certificado para el panel
    read -rp "¿Deseas configurar este certificado para el panel? (s/n): " setPanel
    if [[ "$setPanel" == "s" || "$setPanel" == "S" ]]; then
        local webCertFile="/root/cert/${domain}/fullchain.pem"
        local webKeyFile="/root/cert/${domain}/privkey.pem"

        if [[ -f "$webCertFile" && -f "$webKeyFile" ]]; then
            # Configurar las rutas del certificado en el panel X-UI
            ${xui_folder}/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile"
            LOGI "Rutas del panel configuradas para el dominio: $domain"
            LOGI "  - Archivo de certificado: $webCertFile"
            LOGI "  - Archivo de clave privada: $webKeyFile"
            echo -e "${green}URL de acceso: https://${domain}:${existing_port}${existing_webBasePath}${plain}"
            restart  # Reiniciar el panel para aplicar los cambios
        else
            LOGE "Error: No se encontró el archivo de certificado o clave privada para el dominio: $domain."
        fi
    else
        LOGI "Se omitió la configuración de rutas del panel."
    fi
}

ssl_cert_issue_CF() {
    local existing_webBasePath=$(${xui_folder}/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(${xui_folder}/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    LOGD "******Instrucciones de uso******"
    LOGI "Sigue los pasos a continuación para completar el proceso:"
    LOGI "1. Correo electrónico registrado en Cloudflare"
    LOGI "2. Cloudflare Global API Key"
    LOGI "3. El nombre de dominio."
    LOGI "4. Una vez emitido el certificado, se te pedirá configurar el certificado para el panel (opcional)."
    LOGI "5. El script también soporta la renovación automática del certificado SSL después de la instalación."
    
    confirm "¿Confirmas la información y deseas continuar? [s/n]" "s"

    if [ $? -eq 0 ]; then
        # Verificar acme.sh primero
        if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
            echo "acme.sh no pudo ser encontrado. Lo instalaremos"
            install_acme
            if [ $? -ne 0 ]; then
                LOGE "La instalación de acme falló, verifique los registros."
                exit 1
            fi
        fi

        CF_Domain=""

        LOGD "Por favor, ingresa un nombre de dominio:"
        read -rp "Ingresa tu dominio aquí: " CF_Domain
        LOGD "Tu nombre de dominio se ha configurado como: ${CF_Domain}"

        # Configurar los detalles de la API de Cloudflare
        CF_GlobalKey=""
        CF_AccountEmail=""
        LOGD "Por favor configure el API key:"
        read -rp "Introduzca su key aqui:" CF_GlobalKey
        LOGD "Su API key es: ${CF_GlobalKey}"

        LOGD "Por favor configure el correo electrónico registrado:"
        read -rp "Introduce tu correo electrónico aquí:" CF_AccountEmail
        LOGD "Su dirección de correo electrónico registrada es: ${CF_AccountEmail}"

        # Establecer la CA por defecto en Let's Encrypt  
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force
        if [ $? -ne 0 ]; then
            LOGE "CA predeterminada, Lets'Encrypt falló, saliendo del script..."
            exit 1
        fi

        export CF_Key="${CF_GlobalKey}"
        export CF_Email="${CF_AccountEmail}"

        # Emitir el certificado usando DNS de Cloudflare
        ~/.acme.sh/acme.sh --issue --dns dns_cf -d ${CF_Domain} -d *.${CF_Domain} --log --force
        if [ $? -ne 0 ]; then
            LOGE "La emisión del certificado falló, saliendo del script..."
            exit 1
        else
            LOGI "Certificado emitido exitosamente, Instalando..."
        fi

        # Instalar el certificado
        certPath="/root/cert/${CF_Domain}"
        if [ -d "$certPath" ]; then
            rm -rf ${certPath}  # Eliminar carpeta existente si ya existe
        fi

        # Crear el directorio para el certificado
        mkdir -p ${certPath}
        if [ $? -ne 0 ]; then
            LOGE "Error al crear el directorio: ${certPath}"
            exit 1
        fi

        # Comando de recarga por defecto
        reloadCmd="x-ui restart"

        LOGI "El --reloadcmd por defecto para ACME es: ${yellow}x-ui restart"
        LOGI "Este comando se ejecutará en cada emisión o renovación del certificado."

        # Preguntar si desea modificar el --reloadcmd
        read -rp "¿Deseas modificar el --reloadcmd para ACME? (s/n): " setReloadcmd
        if [[ "$setReloadcmd" == "s" || "$setReloadcmd" == "S" ]]; then
            echo -e "\n${green}\t1.${plain} Predefinido: systemctl reload nginx ; x-ui restart"
            echo -e "${green}\t2.${plain} Ingresa tu propio comando"
            echo -e "${green}\t0.${plain} Mantener reloadcmd por defecto"
            read -rp "Elige una opción: " choice
            case "$choice" in
            1)
                LOGI "Reloadcmd será: systemctl reload nginx ; x-ui restart"
                reloadCmd="systemctl reload nginx ; x-ui restart"
                ;;
            2)  
                LOGD "Se recomienda colocar 'x-ui restart' al final para evitar errores si otros servicios fallan."
                read -rp "Por favor ingresa tu reloadcmd (ejemplo: systemctl reload nginx ; x-ui restart): " reloadCmd
                LOGI "Tu reloadcmd es: ${reloadCmd}"
                ;;
            *)
                LOGI "Se mantiene el reloadcmd por defecto"
                ;;
            esac
        fi

        # Ejecutar la instalación del certificado con acme.sh para el dominio y subdominios
        ~/.acme.sh/acme.sh --installcert -d ${CF_Domain} -d *.${CF_Domain} \
            --key-file ${certPath}/privkey.pem \
            --fullchain-file ${certPath}/fullchain.pem --reloadcmd "${reloadCmd}"

        # Verificar si la instalación fue exitosa
        if [ $? -ne 0 ]; then
            LOGE "Fallo al instalar el certificado, el script se cerrará..."
            exit 1
        else
            LOGI "Certificado instalado correctamente, activando actualizaciones automáticas..."
        fi

        # Habilitar actualización automática
        ~/.acme.sh/acme.sh --upgrade --auto-upgrade
        if [ $? -ne 0 ]; then
            LOGE "Fallo al configurar la actualización automática, el script se cerrará..."
            exit 1
        else
            LOGI "El certificado está instalado y la renovación automática está activada. La información específica es la siguiente:"
            ls -lah ${certPath}/*
            chmod 600 ${certPath}/privkey.pem   # Permisos seguros para la clave privada
            chmod 644 ${certPath}/fullchain.pem # Permisos para el certificado
        fi

        # Preguntar al usuario si desea configurar este certificado para el panel
        read -rp "¿Deseas configurar este certificado para el panel? (s/n): " setPanel
        if [[ "$setPanel" == "s" || "$setPanel" == "S" ]]; then
            local webCertFile="${certPath}/fullchain.pem"
            local webKeyFile="${certPath}/privkey.pem"

            if [[ -f "$webCertFile" && -f "$webKeyFile" ]]; then
                # Configurar las rutas del certificado en el panel X-UI
                ${xui_folder}/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile"
                LOGI "Rutas del panel configuradas para el dominio: $CF_Domain"
                LOGI "  - Archivo de certificado: $webCertFile"
                LOGI "  - Archivo de clave privada: $webKeyFile"
                echo -e "${green}URL de acceso: https://${CF_Domain}:${existing_port}${existing_webBasePath}${plain}"
                restart  # Reiniciar el panel para aplicar los cambios
            else
                LOGE "Error: No se encontró el archivo de certificado o clave privada para el dominio: $CF_Domain."
            fi
        else
            LOGI "Se omitió la configuración de rutas de directorio del panel."
        fi
    else
        show_menu
    fi
}


run_speedtest() {
    # Verificar si Speedtest ya está instalado
    if ! command -v speedtest &>/dev/null; then
        # Si no está instalado, determinar el método de instalación
        if command -v snap &>/dev/null; then
            # Usar snap para instalar Speedtest
            echo "Instalando Speedtest usando snap..."
            snap install speedtest
        else
            # Alternativa usando los gestores de paquetes
            local pkg_manager=""
            local speedtest_install_script=""
        
            if command -v dnf &>/dev/null; then
                pkg_manager="dnf"
                speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh"
            elif command -v yum &>/dev/null; then
                pkg_manager="yum"
                speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh"
            elif command -v apt-get &>/dev/null; then
                pkg_manager="apt-get"
                speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh"
            elif command -v apt &>/dev/null; then
                pkg_manager="apt"
                speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh"
            fi
            
            if [[ -z $pkg_manager ]]; then
                echo "Error: Administrador de paquetes no encontrado. Es posible que necesites instalar Speedtest manualmente."
                return 1
            else
                echo "Instalando Speedtest usando $pkg_manager..."
                curl -s $speedtest_install_script | bash
                $pkg_manager install -y speedtest
            fi
        fi
    fi

    # Ejecutar Speedtest
    speedtest
}



ip_validation() {
    ipv6_regex="^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$"
    ipv4_regex="^((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)$"
}

iplimit_main() {
    echo -e "\n${green}\t1.${plain} Instalar Fail2ban y configurar límite de IP"
    echo -e "${green}\t2.${plain} Cambiar la duración del Ban"
    echo -e "${green}\t3.${plain} Desbanear a todos"
    echo -e "${green}\t4.${plain} Registros de Ban"
    echo -e "${green}\t5.${plain} Bloquear una dirección IP"
    echo -e "${green}\t6.${plain} Desbloquear una dirección IP"
    echo -e "${green}\t7.${plain} Registros en tiempo real"
    echo -e "${green}\t8.${plain} Estado del servicio"
    echo -e "${green}\t9.${plain} Reiniciar el servicio"
    echo -e "${green}\t10.${plain} Desinstalar Fail2ban y límite de IP"
    echo -e "${green}\t0.${plain} Volver al menú principal"
    read -rp "Elige una opción: " choice
    case "$choice" in
    0)
        show_menu 
        ;;
    1)
        confirm "¿Continuar con la instalación de Fail2ban y IP Limiter?" "s"
        if [[ $? == 0 ]]; then
            install_iplimit
        else
            iplimit_main
        fi 
        ;;
    2)
        read -rp "Ingrese la nueva duración del Ban en minutos [predeterminado 30]: " NUM
        if [[ $NUM =~ ^[0-9]+$ ]]; then
            create_iplimit_jails ${NUM}
            if [[ $release == "alpine" ]]; then
                rc-service fail2ban restart
            else
                systemctl restart fail2ban
            fi
        else
            echo -e "${red}${NUM} no es un número! Por favor, inténtalo de nuevo.${plain}"
        fi
        iplimit_main 
        ;;
    3)
        confirm "¿Continuar con el desbaneo de los regitros de IP Limiter para todos?" "s"
        if [[ $? == 0 ]]; then
            fail2ban-client reload --restart --unban 3x-ipl
            truncate -s 0 "${iplimit_banned_log_path}"
            echo -e "${green}Todos los usuarios se desbanearon con éxito.${plain}"
            iplimit_main
        else
            echo -e "${yellow}Cancelado.${plain}"
        fi
        iplimit_main 
        ;;
    4)
        show_banlog
        iplimit_main
        ;;
    5)
        read -rp "Ingresa la dirección IP que deseas bloquear: " ban_ip
        ip_validation
        if [[ $ban_ip =~ $ipv4_regex || $ban_ip =~ $ipv6_regex ]]; then
            fail2ban-client set 3x-ipl banip "$ban_ip"
            echo -e "${green}La dirección IP ${ban_ip} ha sido bloqueada exitosamente.${plain}"
        else
            echo -e "${red}¡Formato de dirección IP inválido! Por favor intenta nuevamente.${plain}"
        fi
        iplimit_main
        ;;
    6)
        read -rp "Ingresa la dirección IP que deseas desbloquear: " unban_ip
        ip_validation
        if [[ $unban_ip =~ $ipv4_regex || $unban_ip =~ $ipv6_regex ]]; then
            fail2ban-client set 3x-ipl unbanip "$unban_ip"
            echo -e "${green}La dirección IP ${unban_ip} ha sido desbloqueada exitosamente.${plain}"
        else
            echo -e "${red}¡Formato de dirección IP inválido! Por favor intenta nuevamente.${plain}"
        fi
        iplimit_main
        ;;
    7)
        # Mostrar registros en tiempo real
        tail -f /var/log/fail2ban.log
        iplimit_main
        ;;
    8)
        service fail2ban status
        iplimit_main
        ;;
    9)
        # Reiniciar Fail2ban según la distribución
        if [[ $release == "alpine" ]]; then
            rc-service fail2ban restart
        else
            systemctl restart fail2ban
        fi
        iplimit_main
        ;;
    10)
        # Desinstalar Fail2ban y límite de IP
        remove_iplimit
        iplimit_main
        ;;
    *)
        # Opción inválida
        echo -e "${red}Opción inválida. Por favor, selecciona un número válido.${plain}\n"
        iplimit_main
        ;;
    esac
}

install_iplimit() {
    if ! command -v fail2ban-client &>/dev/null; then
        echo -e "${green}Fail2ban no está instalado. Instalando ahora...!${plain}\n"

        # Verificar el sistema operativo e instalar los paquetes necesarios
        case "${release}" in
        ubuntu)
            apt-get update
            if [[ "${os_version}" -ge 24 ]]; then
                apt-get install python3-pip -y
                python3 -m pip install pyasynchat --break-system-packages
            fi
            apt-get install fail2ban -y
            ;;
        debian)
            apt-get update
            if [ "$os_version" -ge 12 ]; then
                apt-get install -y python3-systemd
            fi
            apt-get install -y fail2ban
            ;;
        armbian)
            apt-get update && apt-get install fail2ban -y
            ;;
        fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol)
            dnf -y update && dnf -y install fail2ban
            ;;
        centos)
            if [[ "${VERSION_ID}" =~ ^7 ]]; then
                yum update -y && yum install epel-release -y
                yum -y install fail2ban
            else
                dnf -y update && dnf -y install fail2ban
            fi
            ;;
        arch | manjaro | parch)
            pacman -Syu --noconfirm fail2ban
            ;;
        alpine)
            apk add fail2ban
            ;;
        *)
            echo -e "${red}Sistema operativo no compatible. Verifique el script e instale los paquetes necesarios manualmente.${plain}\n"
            exit 1 
            ;;
        esac

                if ! command -v fail2ban-client &>/dev/null; then
            echo -e "${red}Fail2ban installation failed.${plain}\n"
            exit 1
        fi

        echo -e "${green}Fail2ban instalado exitosamente!${plain}\n"
    else
        echo -e "${yellow}Fail2ban ya está instalado.${plain}\n"
    fi

    echo -e "${green}Configurando limitador de IP...${plain}\n"

    # Asegurarse de que no haya conflictos con los archivos de registros Cautivos (Jail)
    iplimit_remove_conflicts

    # Verificar si el archivo de registro de IPs bloqueadas existe
    if ! test -f "${iplimit_banned_log_path}"; then
        touch ${iplimit_banned_log_path}
    fi

    # Verificar si el archivo de registro del servicio existe para que fail2ban no devuelva errores
    if ! test -f "${iplimit_log_path}"; then
        touch ${iplimit_log_path}
    fi

    # Crear los archivos de jail para iplimit
    # No pasamos el bantime aquí para usar el valor predeterminado
    create_iplimit_jails

    # Iniciar Fail2ban
    if [[ $release == "alpine" ]]; then
        if [[ $(rc-service fail2ban status | grep -F 'status: started' -c) == 0 ]]; then
            rc-service fail2ban start
        else
            rc-service fail2ban restart
        fi
        rc-update add fail2ban
    else
        if ! systemctl is-active --quiet fail2ban; then
            systemctl start fail2ban
        else
            systemctl restart fail2ban
        fi
        systemctl enable fail2ban
    fi

    echo -e "${green}IP Limit instalado y configurado con éxito!${plain}\n"
    before_show_menu
}

remove_iplimit() {
    echo -e "${green}\t1.${plain} Remover solo las configuraciones de IP Limit"
    echo -e "${green}\t2.${plain} Desinstalar Fail2ban e IP Limiter"
    echo -e "${green}\t0.${plain} Volver al menú principal"
    read -rp "Elige una opción: " num
    case "$num" in
    1) 
        rm -f /etc/fail2ban/filter.d/3x-ipl.conf
        rm -f /etc/fail2ban/action.d/3x-ipl.conf
        rm -f /etc/fail2ban/jail.d/3x-ipl.conf
        if [[ $release == "alpine" ]]; then
            rc-service fail2ban restart
        else
        systemctl restart fail2ban
        fi
        echo -e "${green}IP Limiter removido exitosamente!${plain}\n"
        before_show_menu 
        ;;
    2)  
        rm -rf /etc/fail2ban
        if [[ $release == "alpine" ]]; then
            rc-service fail2ban stop
        else
        systemctl stop fail2ban
        fi
        case "${release}" in
        ubuntu | debian | armbian)
            apt-get remove -y fail2ban
            apt-get purge -y fail2ban -y
            apt-get autoremove -y
            ;;
        fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol)
            dnf remove fail2ban -y
            dnf autoremove -y
            ;;
        centos)
            if [[ "${VERSION_ID}" =~ ^7 ]]; then
                yum remove fail2ban -y
                yum autoremove -y
            else
                dnf remove fail2ban -y
                dnf autoremove -y
            fi
            ;;
        arch | manjaro | parch)
            pacman -Rns --noconfirm fail2ban
            ;;
        alpine)
            apk del fail2ban
            ;;
        *)
            echo -e "${red}Sistema operativo no compatible. Desinstale Fail2ban manualmente.${plain}\n"
            exit 1 
            ;;
        esac
        echo -e "${green}Fail2ban e IP Limiter removido exitosamente!${plain}\n"
        before_show_menu 
        ;;
    0) 
        show_menu
        ;;
    *) 
        echo -e "${red}Opción inválida. Por favor seleccione un número válido.${plain}\n"
        remove_iplimit 
        ;;
    esac
}

show_banlog() {
    local system_log="/var/log/fail2ban.log"

    echo -e "${green}Verificando registros de bloqueos(Ban)...${plain}\n"

    if [[ $release == "alpine" ]]; then
        if [[ $(rc-service fail2ban status | grep -F 'status: started' -c) == 0 ]]; then
            echo -e "${red}¡El servicio Fail2ban no está en ejecución!${plain}\n"
            return 1
        fi
    else
        if ! systemctl is-active --quiet fail2ban; then
            echo -e "${red}¡El servicio Fail2ban no está en ejecución!${plain}\n"
            return 1
        fi
    fi

    if [[ -f "$system_log" ]]; then
        echo -e "${green}Últimas actividades de bloqueo(Ban) en fail2ban.log:${plain}"
        grep "3x-ipl" "$system_log" | grep -E "Ban|Unban" | tail -n 10 || echo -e "${yellow}No se encontraron actividades recientes${plain}"
        echo ""
    fi

    if [[ -f "${iplimit_banned_log_path}" ]]; then
        echo -e "${green}Entradas y registros de bloqueos Ban de 3X-IPL:${plain}"
        if [[ -s "${iplimit_banned_log_path}" ]]; then
            grep -v "INIT" "${iplimit_banned_log_path}" | tail -n 10 || echo -e "${yellow}No se encontraron entradas de bloqueo(Ban)${plain}"
        else
            echo -e "${yellow}El archivo de registro de bloqueos está vacío${plain}"
        fi
    else
        echo -e "${red}Archivo log de bloqueos no encontrado en: ${iplimit_banned_log_path}${plain}"
    fi

    echo -e "\n${green}Estado actual de cautivos(jail):${plain}"
    fail2ban-client status 3x-ipl || echo -e "${yellow}No se pudo obtener el estado de la jail${plain}"
}

create_iplimit_jails() {
    # Usar bantime predeterminado si no se pasa => 30 minutos
    local bantime="${1:-30}"

    # Descomentar 'allowipv6 = auto' en fail2ban.conf
    sed -i 's/#allowipv6 = auto/allowipv6 = auto/g' /etc/fail2ban/fail2ban.conf

    # En Debian 12+ se recomienda cambiar backend por systemd
    if [[  "${release}" == "debian" && ${os_version} -ge 12 ]]; then
        sed -i '0,/action =/s/backend = auto/backend = systemd/' /etc/fail2ban/jail.conf
    fi

    cat << EOF > /etc/fail2ban/jail.d/3x-ipl.conf
[3x-ipl]
enabled=true
backend=auto
filter=3x-ipl
action=3x-ipl
logpath=${iplimit_log_path}
maxretry=2
findtime=32
bantime=${bantime}m
EOF

    cat << EOF > /etc/fail2ban/filter.d/3x-ipl.conf
[Definition]
datepattern = ^%%Y/%%m/%%d %%H:%%M:%%S
failregex   = \[LIMIT_IP\]\s*Email\s*=\s*<F-USER>.+</F-USER>\s*\|\|\s*SRC\s*=\s*<ADDR>
ignoreregex =
EOF

    cat << EOF > /etc/fail2ban/action.d/3x-ipl.conf
[INCLUDES]
before = iptables-allports.conf

[Definition]
actionstart = <iptables> -N f2b-<name>
              <iptables> -A f2b-<name> -j <returntype>
              <iptables> -I <chain> -p <protocol> -j f2b-<name>

actionstop = <iptables> -D <chain> -p <protocol> -j f2b-<name>
             <actionflush>
             <iptables> -X f2b-<name>

actioncheck = <iptables> -n -L <chain> | grep -q 'f2b-<name>[ \t]'

actionban = <iptables> -I f2b-<name> 1 -s <ip> -j <blocktype>
            echo "\$(date +"%%Y/%%m/%%d %%H:%%M:%%S")   BLOQUEO   [Email] = <F-USER> [IP] = <ip> bloqueada por <bantime> segundos." >> ${iplimit_banned_log_path}

actionunban = <iptables> -D f2b-<name> -s <ip> -j <blocktype>
              echo "\$(date +"%%Y/%%m/%%d %%H:%%M:%%S")   DESBLOQUEO   [Email] = <F-USER> [IP] = <ip> desbloqueada." >> ${iplimit_banned_log_path}

[Init]
name = default
protocol = tcp
chain = INPUT
EOF

    echo -e "${green}Archivos cautivos(jail) de Ip Limiter creados con un tiempo de bloqueo de ${bantime} minutos.${plain}"
}

iplimit_remove_conflicts() {
    local jail_files=(
        /etc/fail2ban/jail.conf
        /etc/fail2ban/jail.local
    )

    for file in "${jail_files[@]}"; do
        # Verificar si existe configuración de [3x-ipl] en el archivo y eliminarla
        if test -f "${file}" && grep -qw '3x-ipl' ${file}; then
            sed -i "/\[3x-ipl\]/,/^$/d" ${file}
            echo -e "${yellow}Eliminando conflictos de [3x-ipl] en el jail (${file})!${plain}\n"
        fi
    done
}

SSH_port_forwarding() {
    local URL_lists=(
        "https://api4.ipify.org"
		"https://ipv4.icanhazip.com"
		"https://v4.api.ipinfo.io/ip"
		"https://ipv4.myexternalip.com/raw"
		"https://4.ident.me"
		"https://check-host.net/ip"
    )
    local server_ip=""
    for ip_address in "${URL_lists[@]}"; do
        server_ip=$(curl -s --max-time 3 "${ip_address}" 2>/dev/null | tr -d '[:space:]')
        if [[ -n "${server_ip}" ]]; then
            break
        fi
    done
    local existing_webBasePath=$(${xui_folder}/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(${xui_folder}/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    local existing_listenIP=$(${xui_folder}/x-ui setting -getListen true | grep -Eo 'listenIP: .+' | awk '{print $2}')
    local existing_cert=$(${xui_folder}/x-ui setting -getCert true | grep -Eo 'cert: .+' | awk '{print $2}')
    local existing_key=$(${xui_folder}/x-ui setting -getCert true | grep -Eo 'key: .+' | awk '{print $2}')

    local config_listenIP=""
    local listen_choice=""

    if [[ -n "$existing_cert" && -n "$existing_key" ]]; then
        echo -e "${green}El panel está seguro con SSL.${plain}"
        before_show_menu
    fi
    if [[ -z "$existing_cert" && -z "$existing_key" && (-z "$existing_listenIP" || "$existing_listenIP" == "0.0.0.0") ]]; then
        echo -e "\n${red}Advertencia: No se encontró Certificado ni Key! El panel no está seguro.${plain}"
        echo "Por favor, obtén un certificado o configura el reenvío de puerto SSH."
    fi

    if [[ -n "$existing_listenIP" && "$existing_listenIP" != "0.0.0.0" && (-z "$existing_cert" && -z "$existing_key") ]]; then
        echo -e "\n${green}Configuración actual de reenvío de puerto SSH:${plain}"
        echo -e "Comando SSH estándar:"
        echo -e "${yellow}ssh -L 2222:${existing_listenIP}:${existing_port} root@${server_ip}${plain}"
        echo -e "\nSi usas clave SSH:"
        echo -e "${yellow}ssh -i <ruta_de_clave_ssh> -L 2222:${existing_listenIP}:${existing_port} root@${server_ip}${plain}"
        echo -e "\nDespués de conectarte, accede al panel en:"
        echo -e "${yellow}http://localhost:2222${existing_webBasePath}${plain}"
    fi

    echo -e "\nElige una opción:"
    echo -e "${green}1.${plain} Configurar listen IP"
    echo -e "${green}2.${plain} Limpiar listen IP"
    echo -e "${green}0.${plain} Volver al menú principal"
    read -rp "Elige una opción: " num

    case "$num" in
    1)
        if [[ -z "$existing_listenIP" || "$existing_listenIP" == "0.0.0.0" ]]; then
            echo -e "\nNo hay listenIP configurada. Elige una opción:"
            echo -e "1. Usar IP predeterminada (127.0.0.1)"
            echo -e "2. Configurar una IP personalizada"
            read -rp "Selecciona una opción (1 o 2): " listen_choice

            config_listenIP="127.0.0.1"
            [[ "$listen_choice" == "2" ]] && read -rp "Ingresa la IP personalizada para escuchar: " config_listenIP

            ${xui_folder}/x-ui setting -listenIP "${config_listenIP}" >/dev/null 2>&1
            echo -e "${green}La listen IP se ha configurado a ${config_listenIP}.${plain}"
            echo -e "\n${green}Configuración de reenvío de puerto SSH:${plain}"
            echo -e "Comando SSH estándar:"
            echo -e "${yellow}ssh -L 2222:${config_listenIP}:${existing_port} root@${server_ip}${plain}"
            echo -e "\nSi usas clave SSH:"
            echo -e "${yellow}ssh -i <ruta_de_clave_ssh> -L 2222:${config_listenIP}:${existing_port} root@${server_ip}${plain}"
            echo -e "\nDespués de conectarte, accede al panel en:"
            echo -e "${yellow}http://localhost:2222${existing_webBasePath}${plain}"
            restart
        else
            config_listenIP="${existing_listenIP}"
            echo -e "${green}La listen IP actual ya está configurada a ${config_listenIP}.${plain}"
        fi
        ;;
    2)
        ${xui_folder}/x-ui setting -listenIP 0.0.0.0 >/dev/null 2>&1
        echo -e "${green}La IP de escucha ha sido limpiada.${plain}"
        restart
        ;;
    0)
        show_menu
        ;;
    *)
        echo -e "${red}Opción inválida. Por favor, selecciona un número válido.${plain}\n"
        SSH_port_forwarding
        ;;
    esac
}

show_usage() {
    echo -e "┌──────────────────────────────────────────────────────┐
│  ${blue}Uso del menú de control x-ui (subcomandos):${plain}         │
│                                                      │
│ ${blue}x-ui${plain}                     - Script de administración  │
│ ${blue}x-ui start${plain}               - Iniciar                   │
│ ${blue}x-ui stop${plain}                - Detener                   │
│ ${blue}x-ui restart${plain}             - Reiniciar                 │
│ ${blue}x-ui status${plain}              - Estado actual             │
│ ${blue}x-ui settings${plain}            - Configuración actual      │
│ ${blue}x-ui enable${plain}              - Activar autoinicio del SO │
│ ${blue}x-ui disable${plain}             - Apagar autoinicio del SO  │
│ ${blue}x-ui log${plain}                 - Revisar registros         │
│ ${blue}x-ui banlog${plain}              - Revisar logs de Fail2ban  │
│ ${blue}x-ui update${plain}              - Actualizar                │
│ ${blue}x-ui update-all-geofiles${plain} - Actualizar archivos geo   │
│ ${blue}x-ui legacy${plain}              - Versión heredada          │
│ ${blue}x-ui install${plain}             - Instalar                  │
│ ${blue}x-ui uninstall${plain}           - Desinstalar               │
└──────────────────────────────────────────────────────┘"
}

show_menu() {
    echo -e "
╔────────────────────────────────────────────────╗
│   ${green}Script de Gestión del Panel 3X-UI${plain}            │
│   ${green}0.${plain} Salir del Script                          │
│────────────────────────────────────────────────│
│   ${green}1.${plain} Instalar                                  │
│   ${green}2.${plain} Actualizar                                │
│   ${green}3.${plain} Actualizar Menú                           │
│   ${green}4.${plain} Versión Personalizada                     │
│   ${green}5.${plain} Desinstalar                               │
│────────────────────────────────────────────────│
│   ${green}6.${plain} Restablecer Usuario y Contraseña          │
│   ${green}7.${plain} Restablecer Ruta Base Web                 │
│   ${green}8.${plain} Restablecer Configuración                 │
│   ${green}9.${plain} Cambiar Puerto                            │
│  ${green}10.${plain} Ver Configuración Actual                  │
│────────────────────────────────────────────────│
│  ${green}11.${plain} Iniciar                                   │
│  ${green}12.${plain} Detener                                   │
│  ${green}13.${plain} Reiniciar                                 │
│  ${green}14.${plain} Ver Estado                                │
│  ${green}15.${plain} Gestión de Registros                      │
│────────────────────────────────────────────────│
│  ${green}16.${plain} Activar Inicio Automático                 │
│  ${green}17.${plain} Desactivar Inicio Automático              │
│────────────────────────────────────────────────│
│  ${green}18.${plain} Gestión de Certificados SSL               │
│  ${green}19.${plain} Certificado SSL Cloudflare                │
│  ${green}20.${plain} Gestión de Límite de IP                   │
│  ${green}21.${plain} Gestión de Firewall                       │
│  ${green}22.${plain} Gestión de Redirección de Puerto SSH      │
│────────────────────────────────────────────────│
│  ${green}23.${plain} Activar BBR                               │
│  ${green}24.${plain} Actualizar Archivos Geo                   │
│  ${green}25.${plain} Speedtest por Ookla                       │
╚────────────────────────────────────────────────╝
"
    show_status
    echo && read -rp "Por favor ingrese una opción [0-25]: " num

    case "${num}" in
    0)
        exit 0
        ;;
    1)
        check_uninstall && install
        ;;
    2)
        check_install && update
        ;;
    3)
        check_install && update_menu
        ;;
    4)
        check_install && legacy_version
        ;;
    5)
        check_install && uninstall
        ;;
    6)
        check_install && reset_user
        ;;
    7)
        check_install && reset_webbasepath
        ;;
    8)
        check_install && reset_config
        ;;
    9)
        check_install && set_port
        ;;
    10)
        check_install && check_config
        ;;
    11)
        check_install && start
        ;;
    12)
        check_install && stop
        ;;
    13)
        check_install && restart
        ;;
    14)
        check_install && status
        ;;
    15)
        check_install && show_log
        ;;
    16)
        check_install && enable
        ;;
    17)
        check_install && disable
        ;;
    18)
        ssl_cert_issue_main
        ;;
    19)
        ssl_cert_issue_CF
        ;;
    20)
        iplimit_main
        ;;
    21)
        firewall_menu
        ;;
    22)
        SSH_port_forwarding
        ;;
    23)
        bbr_menu
        ;;
    24)
        update_geo
        ;;
    25)
        run_speedtest
        ;;
    *)
        LOGE "Por favor ingrese el número correcto [0-25]"
        ;;
    esac
}

if [[ $# > 0 ]]; then
    case $1 in
    "start")
        check_install 0 && start 0
        ;;
    "stop")
        check_install 0 && stop 0
        ;;
    "restart")
        check_install 0 && restart 0
        ;;
    "status")
        check_install 0 && status 0
        ;;
    "settings")
        check_install 0 && check_config 0
        ;;
    "enable")
        check_install 0 && enable 0
        ;;
    "disable")
        check_install 0 && disable 0
        ;;
    "log")
        check_install 0 && show_log 0
        ;;
    "banlog")
        check_install 0 && show_banlog 0
        ;;
    "update")
        check_install 0 && update 0
        ;;
    "legacy")
        check_install 0 && legacy_version 0
        ;;
    "install")
        check_uninstall 0 && install 0
        ;;
    "uninstall")
        check_install 0 && uninstall 0
        ;;
    "update-all-geofiles")
        check_install 0 && update_all_geofiles 0 && restart 0
        ;;
    *) show_usage ;;
    esac
else
    show_menu
fi
