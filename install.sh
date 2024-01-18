#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Error fatal: ${plain} Ejecute este script con privilegios de root \n " && exit 1

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

arch3xui() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv7* | armv7 | arm) echo 'armv7' ;;
    armv6* | armv6 | arm) echo 'armv6' ;;
    *) echo -e "${green}¡Arquitectura de CPU no compatible! ${plain}" && rm -f install.sh && exit 1 ;;
    esac
}
echo "arch: $(arch3xui)"

os_version=""
os_version=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)

if [[ "${release}" == "centos" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red} Por favor utilice CentOS 8 o superior ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "ubuntu" ]]; then
    if [[ ${os_version} -lt 20 ]]; then
        echo -e "${red}Por favor utilice Ubuntu 20 o una versión superior!${plain}\n" && exit 1
    fi

elif [[ "${release}" == "fedora" ]]; then
    if [[ ${os_version} -lt 36 ]]; then
        echo -e "${red}Por favor utilice Fedora 36 o una versión superior!${plain}\n" && exit 1
    fi

elif [[ "${release}" == "debian" ]]; then
    if [[ ${os_version} -lt 11 ]]; then
        echo -e "${red} Por favor utilice Debian 11 o superior ${plain}\n" && exit 1
    fi

elif [[ "${release}" == "almalinux" ]]; then
    if [[ ${os_version} -lt 9 ]]; then
        echo -e "${red} Por favor utilice AlmaLinux 9 o superior ${plain}\n" && exit 1
    fi

elif [[ "${release}" == "rocky" ]]; then
    if [[ ${os_version} -lt 9 ]]; then
        echo -e "${red} Por favor utilice RockyLinux 9 o superior ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "arch" ]]; then
    echo "Tu sistema operativo es ArchLinux"
    elif [[ "${release}" == "manjaro" ]]; then
    echo "Tu sistema operativo es Manjaro"
elif [[ "${release}" == "armbian" ]]; then
    echo "Tu sistema operativo es Armbian"

else
    echo -e "${red}No se pudo verificar la versión del sistema operativo, ¡comuníquese con el autor!${plain}" && exit 1
fi

install_base() {
    case "${release}" in
        centos|fedora|almalinux|rocky)
            yum -y update && yum install -y -q wget curl tar
            ;;
        arch|manjaro)
            pacman -Syu && pacman -Syu --noconfirm wget curl tar
            ;;
        *)
            apt-get update && apt install -y -q wget curl tar
            ;;
    esac
}


# This function will be called when user installed x-ui out of security
config_after_install() {
    echo -e "${yellow}¡Instalación/Actualización finalizada! Por seguridad se recomienda modificar la configuración del panel ${plain}"
    read -p "¿Quieres continuar con la modificación [y/n]?: " config_confirm
    if [[ "${config_confirm}" == "y" || "${config_confirm}" == "Y" ]]; then
        read -p " Por favor configura tu nombre de usuario: " config_account
        echo -e "${yellow} Su nombre de usuario será: ${config_account}${plain}"
        read -p " Por favor configura tu contraseña: " config_password
        echo -e "${yellow} Tu contraseña será: ${config_password}${plain}"
        read -p " Por favor configure el puerto del panel: " config_port
        echo -e "${yellow} El puerto de su panel es: ${config_port}${plain}"
        echo -e "${yellow} Inicializando, por favor espere...${plain}"
        /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password}
        echo -e "${yellow} Nombre de cuenta y contraseña configurados correctamente!${plain}"
        /usr/local/x-ui/x-ui setting -port ${config_port}
        echo -e "${yellow} Puerto del panel configurado correctamente!${plain}"
    else
        echo -e "${red} Cancelando...${plain}"
        if [[ ! -f "/etc/x-ui/x-ui.db" ]]; then
            local usernameTemp=$(head -c 6 /dev/urandom | base64)
            local passwordTemp=$(head -c 6 /dev/urandom | base64)
            /usr/local/x-ui/x-ui setting -username ${usernameTemp} -password ${passwordTemp}
            echo -e " Esta es una instalación nueva, generará información de inicio de sesión aleatoria por motivos de seguridad:"
            echo -e "###############################################"
            echo -e "${green} nombre de usuario: ${usernameTemp}${plain}"
            echo -e "${green} contraseña: ${passwordTemp}${plain}"
            echo -e "###############################################"
            echo -e "${red} Si olvidó su información de inicio de sesión, puede usar el comando x-ui y luego elegir opción 7 para revisarlo después de la instalación${plain}"
        else
            echo -e "${red} Esta es su actualización, se mantendrá la configuración anterior, si olvidó su información de inicio de sesión, puede usar el comando x-ui y luego elegir opción 7 para revisarlo${plain}"
        fi
    fi
    /usr/local/x-ui/x-ui migrate
}

install_x-ui() {
    cd /usr/local/

    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/emirjorge/3x-ui_es/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}No se pudo encontrar la versión x-ui, tal vez debido a restricciones de la API de Github, inténtelo más tarde${plain}"
            exit 1
        fi
        echo -e "Se encontró la última versión de x-ui: ${last_version}, comenzando la instalación..."
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-$(arch3xui).tar.gz https://github.com/emirjorge/3x-ui_es/releases/download/${last_version}/x-ui-linux-$(arch3xui).tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Error al descargar x-ui, asegúrese de que su servidor pueda acceder a Github ${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/emirjorge/3x-ui_es/releases/download/${last_version}/x-ui-linux-$(arch3xui).tar.gz"
        echo -e "Comenzando a instalar x-ui $1"
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-$(arch3xui).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Error al descargar x-ui $1, por favor verifique que exista la versión ${plain}"
            exit 1
        fi
    fi

    if [[ -e /usr/local/x-ui/ ]]; then
        systemctl stop x-ui
        rm /usr/local/x-ui/ -rf
    fi

    tar zxvf x-ui-linux-$(arch3xui).tar.gz
    rm x-ui-linux-$(arch3xui).tar.gz -f
    cd x-ui
    chmod +x x-ui

    # Verifica la arquitectura del sistema y renombra el archivo en consecuencia
    if [[ $(arch3xui) == "armv6" || $(arch3xui) == "armv7" ]]; then
    mv bin/xray-linux-$(arch3xui) bin/xray-linux-arm
    chmod +x bin/xray-linux-arm
    fi
    
    chmod +x x-ui bin/xray-linux-$(arch3xui)
    cp -f x-ui.service /etc/systemd/system/
    wget --no-check-certificate -O /usr/bin/x-ui https://raw.githubusercontent.com/emirjorge/3x-ui_es/main/x-ui.sh
    chmod +x /usr/local/x-ui/x-ui.sh
    chmod +x /usr/bin/x-ui
    config_after_install

    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui
    echo -e "${green}La instalación de x-ui ${last_version}${plain} finalizó, ya esta funcionando..."
    echo -e ""
    echo -e "Menú de control de x-ui: "
    echo -e "----------------------------------------------"
    echo -e "x-ui              - Ingrese al menú de administración"
    echo -e "x-ui start        - Iniciar x-ui"
    echo -e "x-ui stop         - Detener x-ui"
    echo -e "x-ui restart      - Reiniciar x-ui"
    echo -e "x-ui status       - Mostrar estado de x-ui"
    echo -e "x-ui enable       - Habilitar x-ui al iniciar el sistema"
    echo -e "x-ui disable      - Deshabilitar x-ui al iniciar el sistema"
    echo -e "x-ui log          - Verificar los registros de x-ui"
    echo -e "x-ui banlog       - Verificar los baneos en los registros de Fail2ban"
    echo -e "x-ui update       - Actualizar x-ui"
    echo -e "x-ui install      - Instalar x-ui"
    echo -e "x-ui uninstall    - Desinstalar x-ui"
    echo -e "----------------------------------------------"
}

echo -e "${green}Ejecutando...${plain}"
install_base
install_x-ui $1
