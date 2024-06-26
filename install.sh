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

arch() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    i*86 | x86) echo '386' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv7* | armv7 | arm) echo 'armv7' ;;
    armv6* | armv6) echo 'armv6' ;;
    armv5* | armv5) echo 'armv5' ;;
    s390x) echo 's390x' ;;
    *) echo -e "${green}¡Arquitectura de CPU no compatible! ${plain}" && rm -f install.sh && exit 1 ;;
    esac
}

echo "arch: $(arch)"

os_version=""
os_version=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)

if [[ "${release}" == "arch" ]]; then
    echo "Tu sistema operativo es Arch Linux"
    elif [[ "${release}" == "parch" ]]; then
    echo "Tu sistema operativo es Parch linux"
    elif [[ "${release}" == "manjaro" ]]; then
    echo "Tu sistema operativo es Manjaro"
elif [[ "${release}" == "armbian" ]]; then
    echo "Tu sistema operativo es Armbian"
    elif [[ "${release}" == "opensuse-tumbleweed" ]]; then
    echo "Tu sistema operativo es OpenSUSE Tumbleweed"
elif [[ "${release}" == "centos" ]]; then
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
        echo -e "${red} Por favor utilice Alma Linux 9 o superior ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "rocky" ]]; then
    if [[ ${os_version} -lt 9 ]]; then
        echo -e "${red} Por favor utilice Rocky Linux 9 o superior ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "oracle" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red} Por favor utilice Oracle Linux 8 o superior ${plain}\n" && exit 1
    fi
else
    echo -e "${red}Su sistema operativo no es compatible con este script.${plain}\n"
    echo "Por favor, asegúrese de estar utilizando uno de los siguientes sistemas operativos compatibles:"
    echo "- Ubuntu 20.04+"
    echo "- Debian 11+"
    echo "- CentOS 8+"
    echo "- Fedora 36+"
    echo "- Arch Linux"
    echo "- Parch Linux"
    echo "- Manjaro"
    echo "- Armbian"
    echo "- AlmaLinux 9+"
    echo "- Rocky Linux 9+"
    echo "- Oracle Linux 8+"
    echo "- OpenSUSE Tumbleweed"
    exit 1

fi

install_base() {
    case "${release}" in
    ubuntu | debian | armbian)
        apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
    centos | almalinux | rocky | oracle)
        yum -y update && yum install -y -q wget curl tar tzdata
        ;;
    fedora)
        dnf -y update && dnf install -y -q wget curl tar tzdata
        ;;
    arch | manjaro | parch)
        pacman -Syu && pacman -Syu --noconfirm wget curl tar tzdata
        ;;
    opensuse-tumbleweed)
        zypper refresh && zypper -q install -y wget curl tar timezone
        ;;
    *)
        apt-get update && apt install -y -q wget curl tar tzdata
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
        read -p "Por favor, configure la ruta base web (ip:puerto/rutabaseweb/): " config_webBasePath
        echo -e "${yellow}Tu ruta base web es: ${config_webBasePath}${plain}"
        echo -e "${yellow} Inicializando, por favor espere...${plain}"
        /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password}
        echo -e "${yellow} Nombre de cuenta y contraseña configurados correctamente!${plain}"
        /usr/local/x-ui/x-ui setting -port ${config_port}
        echo -e "${yellow} Puerto del panel configurado correctamente!${plain}"
        /usr/local/x-ui/x-ui setting -webBasePath ${config_webBasePath}
        echo -e "${yellow}¡Ruta base web configurada con éxito!${plain}"
    else
        echo -e "${red} Cancelando...${plain}"
        if [[ ! -f "/etc/x-ui/x-ui.db" ]]; then
            local usernameTemp=$(head -c 6 /dev/urandom | base64)
            local passwordTemp=$(head -c 6 /dev/urandom | base64)
            local webBasePathTemp=$(head -c 6 /dev/urandom | base64)
            /usr/local/x-ui/x-ui setting -username ${usernameTemp} -password ${passwordTemp} -webBasePath ${webBasePathTemp}
            echo -e " Esta es una instalación nueva, generará información de inicio de sesión aleatoria por motivos de seguridad:"
            echo -e "###############################################"
            echo -e "${green} nombre de usuario: ${usernameTemp}${plain}"
            echo -e "${green} contraseña: ${passwordTemp}${plain}"
            echo -e "${green} Ruta Base Web: ${webBasePathTemp}${plain}"
            echo -e "###############################################"
            echo -e "${red} Si olvidó su información de inicio de sesión, puede usar el comando x-ui y luego elegir opción 8 para revisarlo después de la instalación${plain}"
        else
            echo -e "${red} Esta es su actualización, se mantendrá la configuración anterior, si olvidó su información de inicio de sesión, puede usar el comando x-ui y luego elegir opción 8 para revisarlo${plain}"
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
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-$(arch).tar.gz https://github.com/emirjorge/3x-ui_es/releases/download/${last_version}/x-ui-linux-$(arch).tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Error al descargar x-ui, asegúrese de que su servidor pueda acceder a Github ${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/emirjorge/3x-ui_es/releases/download/${last_version}/x-ui-linux-$(arch).tar.gz"
        echo -e "Comenzando a instalar x-ui $1"
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-$(arch).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Error al descargar x-ui $1, por favor verifique que exista la versión ${plain}"
            exit 1
        fi
    fi

    if [[ -e /usr/local/x-ui/ ]]; then
        systemctl stop x-ui
        rm /usr/local/x-ui/ -rf
    fi

    tar zxvf x-ui-linux-$(arch).tar.gz
    rm x-ui-linux-$(arch).tar.gz -f
    cd x-ui
    chmod +x x-ui

    # Verifica la arquitectura del sistema y renombra el archivo en consecuencia
    if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
    mv bin/xray-linux-$(arch) bin/xray-linux-arm
    chmod +x bin/xray-linux-arm
    fi
    
    chmod +x x-ui bin/xray-linux-$(arch)
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