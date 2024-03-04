#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

#Add some basic function here
function LOGD() {
    echo -e "${yellow}[DEG] $* ${plain}"
}

function LOGE() {
    echo -e "${red}[ERR] $* ${plain}"
}

function LOGI() {
    echo -e "${green}[INF] $* ${plain}"
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
os_version=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)

if [[ "${release}" == "centos" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red} Por favor utilice CentOS 8 o una versión superior ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "ubuntu" ]]; then
    if [[ ${os_version} -lt 20 ]]; then
        echo -e "${red} Por favor utilice Ubuntu 20 o una versión superior! ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "fedora" ]]; then
    if [[ ${os_version} -lt 36 ]]; then
        echo -e "${red} Por favor utilice Fedora 36 o una versión superior! ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "debian" ]]; then
    if [[ ${os_version} -lt 11 ]]; then
        echo -e "${red} Por favor utilice Debian 11 o una versión superior ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "almalinux" ]]; then
    if [[ ${os_version} -lt 9 ]]; then
        echo -e "${red} Por favor utilice Almalinux 9 o una versión superior ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "rocky" ]]; then
    if [[ ${os_version} -lt 9 ]]; then
        echo -e "${red} Por favor utilice Rockylinux 9 o una versión superior ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "arch" ]]; then
    echo "El sistema operativo es ArchLinux"
    elif [[ "${release}" == "manjaro" ]]; then
    echo "El sistema operativo es Manjaro"
elif [[ "${release}" == "armbian" ]]; then
    echo "El sistema operativo es Armbian"
fi

# Declare Variables
log_folder="${XUI_LOG_FOLDER:=/var/log}"
iplimit_log_path="${log_folder}/3xipl.log"
iplimit_banned_log_path="${log_folder}/3xipl-banned.log"

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -p "$1 [Default $2]: " temp
        if [[ "${temp}" == "" ]]; then
            temp=$2
        fi
    else
        read -p "$1 [y/n]: " temp
    fi
    if [[ "${temp}" == "y" || "${temp}" == "Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "Reiniciar el panel, Atención: Al reiniciar el panel también se reiniciará Xray" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}Presione enter para volver al menú principal... ${plain}" && read temp
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
    confirm "Esta función reinstalará forzosamente la última versión y los datos no se perderán. ¿Quieres continuar? (y/n)" "n"
    if [[ $? != 0 ]]; then
        LOGE "Cancelado"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/emirjorge/3x-ui_es/main/install.sh)
    if [[ $? == 0 ]]; then
        LOGI "La actualización está completa, el Panel se ha reiniciado automáticamente"
        exit 0
    fi
}

custom_version() {
    echo "Ingrese la versión del Panel (Ejemplo 2.0.0):"
    read panel_version

    if [ -z "$panel_version" ]; then
        echo "La versión del Panel no puede estar vacía. Cancelando..."
    exit 1
    fi

    download_link="https://raw.githubusercontent.com/emirjorge/3x-ui_es/main/install.sh"

    # Use the entered panel version in the download link
    install_command="bash <(curl -Ls $download_link) v$panel_version"

    echo "Descargando e instalando Panel versión $panel_version..."
    eval $install_command
}

# Function to handle the deletion of the script file
delete_script() {
    rm "$0"  # Remove the script file itself
    exit 1
}

uninstall() {
    confirm "¿Está seguro de que desea desinstalar el panel? ¡Xray también se desinstalará! (y/n)" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    systemctl stop x-ui
    systemctl disable x-ui
    rm /etc/systemd/system/x-ui.service -f
    systemctl daemon-reload
    systemctl reset-failed
    rm /etc/x-ui/ -rf
    rm /usr/local/x-ui/ -rf

    echo ""
    echo -e "Desinstalado exitosamente.\n"
    echo "Si necesitas instalar este panel nuevamente, puedes utilizar el siguiente comando:"
    echo -e "${green}bash <(curl -Ls https://raw.githubusercontent.com/emirjorge/3x-ui_es/main/install.sh)${plain}"
    echo ""
    # Capturar la señal SIGTERM
    trap delete_script SIGTERM
    delete_script
}

reset_user() {
    confirm "¿Estás seguro de restablecer el nombre de usuario y contraseña del panel? (y/n)" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    read -rp "Configure el nombre de usuario de inicio de sesión [el valor predeterminado es un nombre de usuario aleatorio]: " config_account
    [[ -z $config_account ]] && config_account=$(date +%s%N | md5sum | cut -c 1-8)
    read -rp "Establezca la contraseña de inicio de sesión [la contraseña predeterminada es aleatoria]: " config_password
    [[ -z $config_password ]] && config_password=$(date +%s%N | md5sum | cut -c 1-8)
    /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password} >/dev/null 2>&1
    /usr/local/x-ui/x-ui setting -remove_secret >/dev/null 2>&1
    echo -e "El nombre de usuario de inicio de sesión del panel se ha restablecido a: ${green} ${config_account} ${plain}"
    echo -e "La contraseña de inicio de sesión del panel se ha restablecido a: ${green} ${config_password} ${plain}"
    echo -e "${yellow} Token secreto de inicio de sesión del panel deshabilitado ${plain}"
    echo -e "${green} Utilice el nuevo nombre de usuario y contraseña de inicio de sesión para acceder al panel X-UI. ¡Recuérdalos! ${plain}"
    confirm_restart
}

reset_config() {
    confirm "¿Está seguro de que desea restablecer todas las configuraciones del panel? Los datos de la cuenta no se perderán, el nombre de usuario y la contraseña no cambiarán (y/n)" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/x-ui/x-ui setting -reset
    echo -e "Todas las configuraciones del panel se han restablecido a los valores predeterminados. Reinicie el panel ahora y use el puerto predeterminado ${green}2053${plain} para acceder al Panel web"
    confirm_restart
}

check_config() {
    info=$(/usr/local/x-ui/x-ui setting -show true)
    if [[ $? != 0 ]]; then
        LOGE "Se presenta un error de configuración actual, verifique los registros"
        show_menu
    fi
    LOGI "${info}"
}

set_port() {
    echo && echo -n -e "Introduzca el número de puerto[1-65535]: " && read port
    if [[ -z "${port}" ]]; then
        LOGD "Cancelado"
        before_show_menu
    else
        /usr/local/x-ui/x-ui setting -port ${port}
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
        systemctl start x-ui
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

stop() {
    check_status
    if [[ $? == 1 ]]; then
        echo ""
        LOGI "El panel se detuvo. ¡No es necesario detenerlo nuevamente!"
    else
        systemctl stop x-ui
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
    systemctl restart x-ui
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
    systemctl status x-ui -l
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    systemctl enable x-ui
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
    systemctl disable x-ui
    if [[ $? == 0 ]]; then
        LOGI "x-ui canceló el inicio automatico exitosamente"
    else
        LOGE "x-ui falló al cancelar el inicio automático"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    journalctl -u x-ui.service -e --no-pager -f
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_banlog() {
if test -f "${iplimit_banned_log_path}"; then
                if [[ -s "${iplimit_banned_log_path}" ]]; then
                    cat ${iplimit_banned_log_path}
                else
                    echo -e "${red}El archivo de registro está vacío.${plain}\n"
                fi
            else
                echo -e "${red}Archivo de registro no encontrado. Instale primero Fail2ban e IP Limit.${plain}\n"
            fi 
}

bbr_menu() {
    echo -e "${green}\t1.${plain} Habilitar BBR"
    echo -e "${green}\t2.${plain} Deshabilitar BBR"
    echo -e "${green}\t0.${plain} Volver al Menú Principal"
    read -p "Elige una opción: " choice
    case "$choice" in
    0)
        show_menu
        ;;
    1)
        enable_bbr
        ;;
    2)
        disable_bbr
        ;;
    *) echo "Opción inválida" ;;
    esac
}

disable_bbr() {

    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo -e "${yellow}BBR no está actualmente habilitado.${plain}"
        exit 0
    fi

    # Reemplazar configuraciones de BBR con CUBIC
    sed -i 's/net.core.default_qdisc=fq/net.core.default_qdisc=pfifo_fast/' /etc/sysctl.conf
    sed -i 's/net.ipv4.tcp_congestion_control=bbr/net.ipv4.tcp_congestion_control=cubic/' /etc/sysctl.conf

    # Aplicar cambios
    sysctl -p

    # Verificar que BBR se haya reemplazado con CUBIC
    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "cubic" ]]; then
        echo -e "${green}BBR se ha reemplazado exitosamente con CUBIC.${plain}"
    else
        echo -e "${red}Error al reemplazar BBR con CUBIC. Por favor, verifica la configuración de tu sistema.${plain}"
    fi
}

enable_bbr() {
    if grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf && grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo -e "${green}BBR ya está habilitado!${plain}"
        exit 0
    fi

    # Verifica el Sistema Operativo e instala paquetes necesarios
    case "${release}" in
        ubuntu|debian)
            apt-get update && apt-get install -yqq --no-install-recommends ca-certificates
            ;;
        centos|almalinux|rocky)
            yum -y update && yum -y install ca-certificates
            ;;
        fedora)
            dnf -y update && dnf -y install ca-certificates
            ;;
        *)
            echo -e "${red}Sistema Operativo no compatible. Verifique el script e instale los paquetes necesarios manualmente.${plain}\n"
            exit 1
            ;;
    esac

    # Habilitar BBR
    echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf

    # Aplicar cambios
    sysctl -p

    # Verifica que BBR está habilitado
    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "bbr" ]]; then
        echo -e "${green}BBR ha sido habilitado exitosamente.${plain}"
    else
        echo -e "${red}No se pudo habilitar BBR. Por favor verifique la configuración de su sistema.${plain}"
    fi
}

update_shell() {
    wget -O /usr/bin/x-ui -N --no-check-certificate https://github.com/emirjorge/3x-ui_es/raw/main/x-ui.sh
    if [[ $? != 0 ]]; then
        echo ""
        LOGE "No se pudo descargar el script. Verifique si la máquina puede conectarse a Github"
        before_show_menu
    else
        chmod +x /usr/bin/x-ui
        LOGI "La actualización del script se realizó correctamente. Por favor vuelva a ejecutar el script" && exit 0
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/x-ui.service ]]; then
        return 2
    fi
    temp=$(systemctl status x-ui | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ "${temp}" == "running" ]]; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    temp=$(systemctl is-enabled x-ui)
    if [[ "${temp}" == "enabled" ]]; then
        return 0
    else
        return 1
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
    echo -e "${green}\t1.${plain} Instalar Firewall y abrir puertos"
    echo -e "${green}\t2.${plain} Lista de Permitidos"
    echo -e "${green}\t3.${plain} Eliminar Puertos de la Lista"
    echo -e "${green}\t4.${plain} Desactivar Firewall"
    echo -e "${green}\t0.${plain} Volver al Menú Principal"
    read -p "Elige una opción: " choice
    case "$choice" in
    0)
        show_menu
        ;;
    1)
        open_ports
        ;;
    2)
        sudo ufw status
        ;;
    3)
        delete_ports
        ;;
    4)
        sudo ufw disable
        ;;
    *) echo "Opción inválida" ;;
    esac
}

open_ports() {
    if ! command -v ufw &>/dev/null; then
        echo "ufw firewall no está instalado. Instalando ahora..."
        apt-get update
        apt-get install -y ufw
    else
        echo "ufw firewall ya está instalado"
    fi

    # Check if the firewall is inactive
    if ufw status | grep -q "Status: active"; then
        echo "firewall ya está activo"
    else
        # Open the necessary ports
        ufw allow ssh
        ufw allow http
        ufw allow https
        ufw allow 2053/tcp

        # Enable the firewall
        ufw --force enable
    fi

    # Prompt the user to enter a list of ports
    read -p "Ingrese los puertos que desea abrir (ejem. 80,443,2053 ó rango 400-500): " ports

    # Check if the input is valid
    if ! [[ $ports =~ ^([0-9]+|[0-9]+-[0-9]+)(,([0-9]+|[0-9]+-[0-9]+))*$ ]]; then
        echo "Error: entrada no válida. Introduzca una lista de puertos separados por comas o un rango de puertos (ejem. 80,443,2053 ó 400-500)." >&2
        exit 1
    fi

    # Open the specified ports using ufw
    IFS=',' read -ra PORT_LIST <<<"$ports"
    for port in "${PORT_LIST[@]}"; do
        if [[ $port == *-* ]]; then
            # Split the range into start and end ports
            start_port=$(echo $port | cut -d'-' -f1)
            end_port=$(echo $port | cut -d'-' -f2)
            # Loop through the range and open each port
            for ((i = start_port; i <= end_port; i++)); do
                ufw allow $i
            done
        else
            ufw allow "$port"
        fi
    done

    # Confirm that the ports are open
    ufw status | grep $ports
}

delete_ports() {
    # Solicitar al usuario que ingrese los puertos que desea eliminar
    read -p "Ingresa los puertos que deseas eliminar (por ejemplo, 80,443,2053 o rango 400-500): " ports

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
            # Recorrer el rango y eliminar cada puerto
            for ((i = start_port; i <= end_port; i++)); do
                ufw delete allow $i
            done
        else
            ufw delete allow "$port"
        fi
    done

    # Confirmar que se han eliminado los puertos
    echo "Se eliminaron los puertos especificados:"
    ufw status | grep $ports
}

update_geo() {
    local defaultBinFolder="/usr/local/x-ui/bin"
    read -p "Ingrese la ruta de la carpeta x-ui bin. Dejar en blanco usará la ruta predeterminada. (Predeterminado: '${defaultBinFolder}')" binFolder
    binFolder=${binFolder:-${defaultBinFolder}}
    if [[ ! -d ${binFolder} ]]; then
        LOGE "La carpeta ${binFolder} no existe!"
        LOGI "creando carpeta bin: ${binFolder}..."
        mkdir -p ${binFolder}
    fi

    systemctl stop x-ui
    cd ${binFolder}
    rm -f geoip.dat geosite.dat geoip_IR.dat geosite_IR.dat geoip_VN.dat geosite_VN.dat
    wget -N https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
    wget -N https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
    wget -O geoip_IR.dat -N https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geoip.dat
    wget -O geosite_IR.dat -N https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geosite.dat
    wget -O geoip_VN.dat https://github.com/vuong2023/vn-v2ray-rules/releases/latest/download/geoip.dat
    wget -O geosite_VN.dat https://github.com/vuong2023/vn-v2ray-rules/releases/latest/download/geosite.dat
    systemctl start x-ui
    echo -e "${green}Geosite.dat + Geoip.dat + geoip_IR.dat + geosite_IR.dat have been updated successfully in bin folder '${binfolder}'!${plain}"
    before_show_menu
}

install_acme() {
    cd ~
    LOGI "instalando acme..."
    curl https://get.acme.sh | sh
    if [ $? -ne 0 ]; then
        LOGE "Error al instalar acme"
        return 1
    else
        LOGI "Instalación de acme exitosa"
    fi
    return 0
}

ssl_cert_issue_main() {
    echo -e "${green}\t1.${plain} Obtener certificado SSL"
    echo -e "${green}\t2.${plain} Revocar"
    echo -e "${green}\t3.${plain} Forzar renovación de certificado"
    echo -e "${green}\t0.${plain} Regresar al menú prncipal"
    read -p "Elige una opcion: " choice
    case "$choice" in
        0) 
            show_menu 
            ;;
        1) 
            ssl_cert_issue 
            ;;
        2) 
            local domain=""
            read -p "Por favor ingrese su nombre de dominio para revocar el certificado: " domain
            ~/.acme.sh/acme.sh --revoke -d ${domain}
            LOGI "Certificate revoked"
            ;;
        3)
            local domain=""
            read -p "Ingrese su nombre de dominio para renovar forzosamente un certificado SSL: " domain
            ~/.acme.sh/acme.sh --renew -d ${domain} --force 
            ;;
        *) echo "Opción Inválida" ;;
    esac
}

ssl_cert_issue() {
    # check for acme.sh first
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
        echo "No se encontró acme.sh, lo instalaremos"
        install_acme
        if [ $? -ne 0 ]; then
            LOGE "La instalación de acme falló, verifique los registros"
            exit 1
        fi
    fi
    # install socat second
    case "${release}" in
        ubuntu|debian|armbian)
            apt update && apt install socat -y 
            ;;
        centos|almalinux|rocky)
            yum -y update && yum -y install socat 
            ;;
        fedora)
            dnf -y update && dnf -y install socat 
            ;;
        *)
            echo -e "${red}Sistema operativo no compatible. Verifique el script e instale los paquetes necesarios manualmente.${plain}\n"
            exit 1 
            ;;
    esac
    if [ $? -ne 0 ]; then
        LOGE "La instalación de socat falló, verifique los registros"
        exit 1
    else
        LOGI "socat instalado correctamente..."
    fi

    # get the domain here,and we need verify it
    local domain=""
    read -p "Por favor ingrese su nombre de dominio:" domain
    LOGD "tu dominio es:${domain},revisalo..."
    # here we need to judge whether there exists cert already
    local currentCert=$(~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}')

    if [ ${currentCert} == ${domain} ]; then
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

    # get needed port here
    local WebPort=80
    read -p "Elija qué puerto utilizará, el puerto predeterminado será 80:" WebPort
    if [[ ${WebPort} -gt 65535 || ${WebPort} -lt 1 ]]; then
        LOGE "Su entrada ${WebPort} no es válida, se usará el puerto predeterminado"
    fi
    LOGI "Se utilizará el puerto:${WebPort} para emitir certificados; asegúrese de que este puerto esté abierto..."
    # NOTE:This should be handled by user
    # open the port and kill the occupied progress
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d ${domain} --standalone --httpport ${WebPort}
    if [ $? -ne 0 ]; then
        LOGE "Error al emitir certificados; verifique los registros"
        rm -rf ~/.acme.sh/${domain}
        exit 1
    else
        LOGE "Certificados emitidos exitosamente, instalando certificados..."
    fi
    # install cert
    ~/.acme.sh/acme.sh --installcert -d ${domain} \
        --key-file /root/cert/${domain}/privkey.pem \
        --fullchain-file /root/cert/${domain}/fullchain.pem

    if [ $? -ne 0 ]; then
        LOGE "Error al instalar los certificados, saliendo..."
        rm -rf ~/.acme.sh/${domain}
        exit 1
    else
        LOGI "Certificados instalados correctamente, habilitando la renovación automática..."
    fi

    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    if [ $? -ne 0 ]; then
        LOGE "La renovación automática falló, detalles de los certificados:"
        ls -lah cert/*
        chmod 755 $certPath/*
        exit 1
    else
        LOGI "Renovación automática exitosa, detalles de certificados:"
        ls -lah cert/*
        chmod 755 $certPath/*
    fi
}

ssl_cert_issue_CF() {
    echo -E ""
    LOGD "******Instrucciones de uso******"
    LOGI "Este script de Acme requiere los siguientes datos:"
    LOGI "1.Correo electrónico registrado en Cloudflare"
    LOGI "2.Cloudflare Global API Key"
    LOGI "3.El nombre de dominio y el DNS resuelto por Cloudflare"
    LOGI "4.El script solicita un certificado. La ruta de instalación predeterminada es /root/cert "
    confirm "¿Confirmado?[y/n]" "y"
    if [ $? -eq 0 ]; then
        # check for acme.sh first
        if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
            echo "acme.sh no pudo ser encontrado. Lo instalaremos"
            install_acme
            if [ $? -ne 0 ]; then
                LOGE "La instalación de acme falló, verifique los registros."
                exit 1
            fi
        fi
        CF_Domain=""
        CF_GlobalKey=""
        CF_AccountEmail=""
        certPath=/root/cert
        if [ ! -d "$certPath" ]; then
            mkdir $certPath
        else
            rm -rf $certPath
            mkdir $certPath
        fi
        LOGD "Por favor establezca un nombre de dominio:"
        read -p "Introduce tu dominio aquí:" CF_Domain
        LOGD "Su nombre de dominio está configurado en:${CF_Domain}"
        LOGD "Por favor configure el API key:"
        read -p "Introduzca su key aqui:" CF_GlobalKey
        LOGD "Su API key es:${CF_GlobalKey}"
        LOGD "Por favor configure el correo electrónico registrado:"
        read -p "Introduce tu correo electrónico aquí:" CF_AccountEmail
        LOGD "Su dirección de correo electrónico registrada es:${CF_AccountEmail}"
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        if [ $? -ne 0 ]; then
            LOGE "CA predeterminada, Lets'Encrypt falló, saliendo del script..."
            exit 1
        fi
        export CF_Key="${CF_GlobalKey}"
        export CF_Email=${CF_AccountEmail}
        ~/.acme.sh/acme.sh --issue --dns dns_cf -d ${CF_Domain} -d *.${CF_Domain} --log
        if [ $? -ne 0 ]; then
            LOGE "La emisión del certificado falló, saliendo del script..."
            exit 1
        else
            LOGI "Certificado emitido exitosamente, Instalando..."
        fi
        ~/.acme.sh/acme.sh --installcert -d ${CF_Domain} -d *.${CF_Domain} --ca-file /root/cert/ca.cer \
        --cert-file /root/cert/${CF_Domain}.cer --key-file /root/cert/${CF_Domain}.key \
        --fullchain-file /root/cert/fullchain.cer
        if [ $? -ne 0 ]; then
            LOGE "La instalación del certificado falló, saliendo del script..."
            exit 1
        else
            LOGI "Certificado instalado correctamente, activando actualizaciones automáticas..."
        fi
        ~/.acme.sh/acme.sh --upgrade --auto-upgrade
        if [ $? -ne 0 ]; then
            LOGE "La configuración de actualización automática falló, saliendo del script..."
            ls -lah cert
            chmod 755 $certPath
            exit 1
        else
            LOGI "El certificado está instalado y la renovación automática está activada. La información específica es la siguiente"
            ls -lah cert
            chmod 755 $certPath
        fi
    else
        show_menu
    fi
}

warp_cloudflare() {
    echo -e "${green}\t1.${plain} Instalar el proxy WARP Socks5"
    echo -e "${green}\t2.${plain} Tipo de cuenta (free, plus, team)"
    echo -e "${green}\t3.${plain} Encender/Apagar WireProxy"
    echo -e "${green}\t4.${plain} Desinstalar WARP"
    echo -e "${green}\t0.${plain} Regresar al menú principal"
    read -p "Elige una opcion: " choice
    case "$choice" in
        0)
            show_menu 
            ;;
        1) 
            bash <(curl -sSL https://raw.githubusercontent.com/hamid-gh98/x-ui-scripts/main/install_warp_proxy.sh)
            ;;
        2) 
            warp a
            ;;
        3)
            warp y
            ;;
        4)
            warp u
            ;;
        *) echo "Opción no válida" ;;
    esac
}

run_speedtest() {
    # Check if Speedtest is already installed
    if ! command -v speedtest &> /dev/null; then
        # If not installed, install it
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
            curl -s $speedtest_install_script | bash
            $pkg_manager install -y speedtest
        fi
    fi

    # Run Speedtest
    speedtest
}

create_iplimit_jails() {
    # Use default bantime if not passed => 30 minutes
    local bantime="${1:-15}"
    
    # Uncomment 'allowipv6 = auto' in fail2ban.conf
    sed -i 's/#allowipv6 = auto/allowipv6 = auto/g' /etc/fail2ban/fail2ban.conf

    cat << EOF > /etc/fail2ban/jail.d/3x-ipl.conf
[3x-ipl]
enabled=true
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
            echo "\$(date +"%%Y/%%m/%%d %%H:%%M:%%S")   BAN   [Email] = <F-USER> [IP] = <ip> banned for <bantime> seconds." >> ${iplimit_banned_log_path}

actionunban = <iptables> -D f2b-<name> -s <ip> -j <blocktype>
              echo "\$(date +"%%Y/%%m/%%d %%H:%%M:%%S")   UNBAN   [Email] = <F-USER> [IP] = <ip> unbanned." >> ${iplimit_banned_log_path}

[Init]
EOF

    echo -e "${green}Se creó archivos que registran límites de IP con un tiempo de Baneo de ${bantime} minutos.${plain}"
}

iplimit_remove_conflicts() {
    local jail_files=(
        /etc/fail2ban/jail.conf
        /etc/fail2ban/jail.local
    )

    for file in "${jail_files[@]}"; do
        # Check for [3x-ipl] config in jail file then remove it
        if test -f "${file}" && grep -qw '3x-ipl' ${file}; then
            sed -i "/\[3x-ipl\]/,/^$/d" ${file}
            echo -e "${yellow}Removing conflicts of [3x-ipl] in jail (${file})!${plain}\n"
        fi
    done
}

iplimit_main() {
    echo -e "\n${green}\t1.${plain} Instale Fail2ban y configure el límite de IP"
    echo -e "${green}\t2.${plain} Cambiar la duración del Ban"
    echo -e "${green}\t3.${plain} Desbanear a todos"
    echo -e "${green}\t4.${plain} Verificar registros"
    echo -e "${green}\t5.${plain} Estado de fail2ban"
    echo -e "${green}\t6.${plain} Desinstalar el límite de IP"
    echo -e "${green}\t0.${plain} Regresar al menú principal"
    read -p "Elige una opcion: " choice
    case "$choice" in
        0)
            show_menu 
            ;;
        1)
            confirm "¿Continuar con la instalación de Fail2ban y IP Limiter?" "y"
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
                systemctl restart fail2ban
            else
                echo -e "${red}${NUM} no es un número! Por favor, inténtalo de nuevo.${plain}"
            fi
            iplimit_main 
            ;;
        3)
            confirm "¿Continuar con el desbaneo de los regitros de IP Limiter para todos?" "y"
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
            ;;
        5)
            service fail2ban status
            ;;

        6)
            remove_iplimit 
            ;;
        *) echo "Opción inválida" ;;
    esac
}

install_iplimit() {
    if ! command -v fail2ban-client &>/dev/null; then
        echo -e "${green}Fail2ban no está instalado. Instalando ahora...!${plain}\n"
        # Check the OS and install necessary packages
        case "${release}" in
            ubuntu|debian)
                apt update && apt install fail2ban -y 
                ;;
            centos|almalinux|rocky)
                yum update -y && yum install epel-release -y
                yum -y install fail2ban 
                ;;
            fedora)
                dnf -y update && dnf -y install fail2ban 
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

    echo -e "${green}Configurando IP Limit...${plain}\n"

    # make sure there's no conflict for jail files
    iplimit_remove_conflicts

    # Check if log file exists
    if ! test -f "${iplimit_banned_log_path}"; then
        touch ${iplimit_banned_log_path}
    fi

    # Check if service log file exists so fail2ban won't return error
    if ! test -f "${iplimit_log_path}"; then
        touch ${iplimit_log_path}
    fi

    # Create the iplimit jail files
    # we didn't pass the bantime here to use the default value
    create_iplimit_jails

    # Launching fail2ban
    if ! systemctl is-active --quiet fail2ban; then
        systemctl start fail2ban
        systemctl enable fail2ban
    else
        systemctl restart fail2ban
    fi
    systemctl enable fail2ban

    echo -e "${green}IP Limit instalado y configurado con éxito!${plain}\n"
    before_show_menu
}

remove_iplimit() {
    echo -e "${green}\t1.${plain} Eliminar solo las configuraciones de IP Limit"
    echo -e "${green}\t2.${plain} Desinstalar Fail2ban y IP Limit"
    echo -e "${green}\t0.${plain} Abortar"
    read -p "Elige una opción: " num
    case "$num" in
        1) 
            rm -f /etc/fail2ban/filter.d/3x-ipl.conf
            rm -f /etc/fail2ban/action.d/3x-ipl.conf
            rm -f /etc/fail2ban/jail.d/3x-ipl.conf
            systemctl restart fail2ban
            echo -e "${green}IP Limit removido exitosamente!${plain}\n"
            before_show_menu 
            ;;
        2)  
            rm -rf /etc/fail2ban
            systemctl stop fail2ban
            case "${release}" in
                ubuntu|debian)
                    apt-get remove -y fail2ban
                    apt-get purge -y fail2ban -y
                    apt-get autoremove -y
                    ;;
                centos|almalinux|rocky)
                    yum remove fail2ban -y
                    yum autoremove -y
                    ;;
                fedora)
                    dnf remove fail2ban -y
                    dnf autoremove -y
                    ;;
                *)
                    echo -e "${red}Sistema operativo no compatible. Desinstale Fail2ban manualmente.${plain}\n"
                    exit 1 
                    ;;
            esac
            echo -e "${green}Fail2ban e IP Limit removido exitosamente!${plain}\n"
            before_show_menu 
            ;;
        0) 
            echo -e "${yellow}Cancelado.${plain}\n"
            iplimit_main 
            ;;
        *) 
            echo -e "${red}Opción inválida. Por favor seleccione un número válido.${plain}\n"
            remove_iplimit 
            ;;
    esac
}

show_usage() {
    echo "Usos del menú de control de x-ui: "
    echo "------------------------------------------"
    echo -e "x-ui              - Ingresar al menú de control"
    echo -e "x-ui start        - Iniciar x-ui "
    echo -e "x-ui stop         - Detener  x-ui "
    echo -e "x-ui restart      - Reiniciar x-ui "
    echo -e "x-ui status       - Mostrar estado de x-ui"
    echo -e "x-ui enable       - Habilita x-ui al iniciar el sistema"
    echo -e "x-ui disable      - Deshabilita x-ui al iniciar el sistema"
    echo -e "x-ui log          - Verificar los registros de x-ui"
    echo -e "x-ui banlog       - Verificar los registros ban en Fail2ban"
    echo -e "x-ui update       - Actualizar x-ui "
    echo -e "x-ui install      - Instalar x-ui "
    echo -e "x-ui uninstall    - Desinstalar x-ui "
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
  ${green}Script de administración del panel 3x-ui${plain}
  ${green}0.${plain} Salir del Script
————————————————
  ${green}1.${plain} Instalar x-ui
  ${green}2.${plain} Actualizar x-ui
  ${green}3.${plain} Versión Personalizada
  ${green}4.${plain} Desinstalar x-ui
————————————————
  ${green}5.${plain} Restablecer nombre de usuario, contraseña y Token secreto
  ${green}6.${plain} Restablecer la configuración del Panel
  ${green}7.${plain} Cambiar puerto del Panel
  ${green}8.${plain} Ver la configuración actual del Panel
————————————————
  ${green}9.${plain} Iniciar x-ui
  ${green}10.${plain} Detener  x-ui
  ${green}11.${plain} Reiniciar x-ui
  ${green}12.${plain} Mostrar estado de x-ui
  ${green}13.${plain} Verificar los registros de x-ui
————————————————
  ${green}14.${plain} Habilitar x-ui al iniciar el sistema
  ${green}15.${plain} Deshabilita x-ui al iniciar el sistema
————————————————
  ${green}16.${plain} Gestionar certificados SSL
  ${green}17.${plain} Gestionar certificados Cloudflare SSL
  ${green}18.${plain} Gestionar IP Limit
  ${green}19.${plain} Gestionar WARP
  ${green}20.${plain} Gestionar Firewall
————————————————
  ${green}21.${plain} Habilitar BBR 
  ${green}22.${plain} Actualizar Geo Files
  ${green}23.${plain} Speedtest by Ookla
"
    show_status
    echo && read -p "Por favor ingrese una opción [0-23]: " num

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
        check_install && custom_version
        ;;
    4)
        check_install && uninstall
        ;;
    5)
        check_install && reset_user
        ;;
    6)
        check_install && reset_config
        ;;
    7)
        check_install && set_port
        ;;
    8)
        check_install && check_config
        ;;
    9)
        check_install && start
        ;;
    10)
        check_install && stop
        ;;
    11)
        check_install && restart
        ;;
    12)
        check_install && status
        ;;
    13)
        check_install && show_log
        ;;
    14)
        check_install && enable
        ;;
    15)
        check_install && disable
        ;;
    16)
        ssl_cert_issue_main
        ;;
    17)
        ssl_cert_issue_CF
        ;;
    18)
        iplimit_main
        ;;
    19)
        warp_cloudflare
        ;;
    20)
        firewall_menu
        ;;
    21)
        bbr_menu
        ;;
    22)
        update_geo
        ;;
    23)
        run_speedtest
        ;;    
    *)
        LOGE "Por favor ingrese el número correcto [0-23]"
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
    "install")
        check_uninstall 0 && install 0
        ;;
    "uninstall")
        check_install 0 && uninstall 0
        ;;
    *) show_usage ;;
    esac
else
    show_menu
fi
