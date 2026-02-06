#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

xui_folder="${XUI_MAIN_FOLDER:=/usr/local/x-ui}"
xui_service="${XUI_SERVICE:=/etc/systemd/system}"

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

echo "Arch: $(arch)"

# Funciones auxiliares simples
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

# Puertos auxiliares
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

install_base() {
    case "${release}" in
        ubuntu | debian | armbian)
            apt-get update && apt-get install -y -q curl tar tzdata socat ca-certificates
        ;;
        fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol)
            dnf -y update && dnf install -y -q curl tar tzdata socat ca-certificates
        ;;
        centos)
            if [[ "${VERSION_ID}" =~ ^7 ]]; then
                yum -y update && yum install -y curl tar tzdata socat ca-certificates
            else
                dnf -y update && dnf install -y -q curl tar tzdata socat ca-certificates
            fi
        ;;
        arch | manjaro | parch)
            pacman -Syu && pacman -Syu --noconfirm curl tar tzdata socat ca-certificates
        ;;
        opensuse-tumbleweed | opensuse-leap)
            zypper refresh && zypper -q install -y curl tar timezone socat ca-certificates
        ;;
        alpine)
            apk update && apk add curl tar tzdata socat ca-certificates
        ;;
        *)
            apt-get update && apt-get install -y -q curl tar tzdata socat ca-certificates
        ;;
    esac
}

gen_random_string() {
    local length="$1"
    local random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

install_acme() {
    echo -e "${green}Instalando acme.sh para la gestión de certificados SSL...${plain}"
    cd ~ || return 1
    curl -s https://get.acme.sh | sh >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${red}No se pudo instalar acme.sh${plain}"
        return 1
    else
        echo -e "${green}acme.sh se instaló correctamente${plain}"
    fi
    return 0
}

setup_ssl_certificate() {
    local domain="$1"
    local server_ip="$2"
    local existing_port="$3"
    local existing_webBasePath="$4"
    
    echo -e "${green}Configurando certificado SSL...${plain}"
    
    # Verificar si acme.sh está instalado
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
        install_acme
        if [ $? -ne 0 ]; then
            echo -e "${yellow}No se pudo instalar acme.sh, omitiendo instalación SSL${plain}"
            return 1
        fi
    fi
    
    # Crear directorio de certificados
    local certPath="/root/cert/${domain}"
    mkdir -p "$certPath"
    
    # Emitir certificado
    echo -e "${green}Emitiendo certificado SSL para ${domain}...${plain}"
    echo -e "${yellow}Nota: El puerto 80 debe estar abierto y accesible desde internet${plain}"
    
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force >/dev/null 2>&1
    ~/.acme.sh/acme.sh --issue -d ${domain} --listen-v6 --standalone --httpport 80 --force
    
    if [ $? -ne 0 ]; then
        echo -e "${yellow}No se pudo emitir el certificado para ${domain}${plain}"
        echo -e "${yellow}Por favor asegúrate de que el puerto 80 esté abierto e inténtalo más tarde con: x-ui${plain}"
        rm -rf ~/.acme.sh/${domain} 2>/dev/null
        rm -rf "$certPath" 2>/dev/null
        return 1
    fi
    
    # Instalar certificado
    ~/.acme.sh/acme.sh --installcert -d ${domain} \
        --key-file /root/cert/${domain}/privkey.pem \
        --fullchain-file /root/cert/${domain}/fullchain.pem \
        --reloadcmd "systemctl restart x-ui" >/dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${yellow}No se pudo instalar el certificado${plain}"
        return 1
    fi
    
    # Habilitar auto-renovación
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade >/dev/null 2>&1
    # Permisos de seguridad: clave privada solo legible por el propietario
    chmod 600 $certPath/privkey.pem 2>/dev/null
    chmod 644 $certPath/fullchain.pem 2>/dev/null
    
    # Configurar certificado para el panel
    local webCertFile="/root/cert/${domain}/fullchain.pem"
    local webKeyFile="/root/cert/${domain}/privkey.pem"
    
    if [[ -f "$webCertFile" && -f "$webKeyFile" ]]; then
        ${xui_folder}/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile" >/dev/null 2>&1
        echo -e "${green}¡Certificado SSL instalado y configurado correctamente!${plain}"
        return 0
    else
        echo -e "${yellow}No se encontraron los archivos del certificado${plain}"
        return 1
    fi
}

# Emitir certificado IP de Let's Encrypt con perfil de corta duración (~6 días de validez)
# Requiere acme.sh y puerto 80 abierto para la prueba y validacion HTTP-01
setup_ip_certificate() {
    local ipv4="$1"
    local ipv6="$2"  # opcional

    echo -e "${green}Instalando certificado IP de Let's Encrypt (corta duración)${plain}"
    echo -e "${yellow}Nota: Los certificados IP son válidos por ~6 días y se renovarán automáticamente.${plain}"
    echo -e "${yellow}El listener predeterminado es el puerto 80. Si eliges otro puerto, asegúrate de redirigir el puerto externo 80 hacia él.${plain}"

    # Verificar acme.sh
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
        install_acme
        if [ $? -ne 0 ]; then
            echo -e "${red}No se pudo instalar acme.sh${plain}"
            return 1
        fi
    fi

    # Validar dirección IP
    if [[ -z "$ipv4" ]]; then
        echo -e "${red}Se requiere la dirección IPv4${plain}"
        return 1
    fi

    if ! is_ipv4 "$ipv4"; then
        echo -e "${red}Dirección IPv4 inválida: $ipv4${plain}"
        return 1
    fi

    # Crear directorio de certificados
    local certDir="/root/cert/ip"
    mkdir -p "$certDir"

    # Construir argumentos de dominio
    local domain_args="-d ${ipv4}"
    if [[ -n "$ipv6" ]] && is_ipv6 "$ipv6"; then
        domain_args="${domain_args} -d ${ipv6}"
        echo -e "${green}Incluyendo dirección IPv6: ${ipv6}${plain}"
    fi

    # Comando de recarga para auto-renovación (añade || true para que no falle en la primera instalación)
    local reloadCmd="systemctl restart x-ui 2>/dev/null || rc-service x-ui restart 2>/dev/null || true"

    # Elegir puerto para el listener HTTP-01 (predeterminado 80, se puede sobrescribir)
    local WebPort=""
    read -rp "Puerto a usar para el ACME HTTP-01 listener (predeterminado 80): " WebPort
    WebPort="${WebPort:-80}"
    if ! [[ "${WebPort}" =~ ^[0-9]+$ ]] || ((WebPort < 1 || WebPort > 65535)); then
        echo -e "${red}Puerto inválido proporcionado. Se usará 80.${plain}"
        WebPort=80
    fi
    echo -e "${green}Usando puerto ${WebPort} para validación independiente.${plain}"
    if [[ "${WebPort}" -ne 80 ]]; then
        echo -e "${yellow}Recordatorio: Let's Encrypt sigue conectándose al puerto 80; redirige el puerto externo 80 hacia ${WebPort}.${plain}"
    fi

    # Asegurarse que el puerto elegido esté disponible
    while true; do
        if is_port_in_use "${WebPort}"; then
            echo -e "${yellow}El puerto ${WebPort} está en uso.${plain}"

            local alt_port=""
            read -rp "Ingresa otro puerto para la escucha independiente de acme.sh (dejar vacío para abortar): " alt_port
            alt_port="${alt_port// /}"
            if [[ -z "${alt_port}" ]]; then
                echo -e "${red}El puerto ${WebPort} está ocupado; no se puede continuar.${plain}"
                return 1
            fi
            if ! [[ "${alt_port}" =~ ^[0-9]+$ ]] || ((alt_port < 1 || alt_port > 65535)); then
                echo -e "${red}Puerto inválido proporcionado.${plain}"
                return 1
            fi
            WebPort="${alt_port}"
            continue
        else
            echo -e "${green}Puerto ${WebPort} libre y listo para validación independiente.${plain}"
            break
        fi
    done

    # Emitir certificado con perfil de corta duración
    echo -e "${green}Emitiendo certificado IP para ${ipv4}...${plain}"
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force >/dev/null 2>&1
    
    ~/.acme.sh/acme.sh --issue \
        ${domain_args} \
        --standalone \
        --server letsencrypt \
        --certificate-profile shortlived \
        --days 6 \
        --httpport ${WebPort} \
        --force

    if [ $? -ne 0 ]; then
        echo -e "${red}No se pudo emitir el certificado IP${plain}"
        echo -e "${yellow}Por favor asegúrate que el puerto ${WebPort} sea accesible (o redirigido desde el puerto externo 80)${plain}"
        # Limpiar datos de acme.sh para IPv4 e IPv6 si aplica
        rm -rf ~/.acme.sh/${ipv4} 2>/dev/null
        [[ -n "$ipv6" ]] && rm -rf ~/.acme.sh/${ipv6} 2>/dev/null
        rm -rf ${certDir} 2>/dev/null
        return 1
    fi

    echo -e "${green}Certificado emitido correctamente, instalando...${plain}"

    # Instalar certificado
    # Nota: acme.sh puede reportar "Error al recargar" y salir con código distinto de cero si reloadcmd falla,
    # pero los archivos del certificado aún se instalan. Verificamos la existencia de los archivos en lugar del código de salida.
    ~/.acme.sh/acme.sh --installcert -d ${ipv4} \
        --key-file "${certDir}/privkey.pem" \
        --fullchain-file "${certDir}/fullchain.pem" \
        --reloadcmd "${reloadCmd}" 2>&1 || true

    # Verificar que existan los archivos del certificado (no confiar en el código de salida, fallo de reloadcmd devuelve distinto de cero)
    if [[ ! -f "${certDir}/fullchain.pem" || ! -f "${certDir}/privkey.pem" ]]; then
        echo -e "${red}No se encontraron los archivos del certificado después de la instalación${plain}"
        # Limpiar los datos de acme.sh para IPv4 e IPv6 si se especifica
        rm -rf ~/.acme.sh/${ipv4} 2>/dev/null
        [[ -n "$ipv6" ]] && rm -rf ~/.acme.sh/${ipv6} 2>/dev/null
        rm -rf ${certDir} 2>/dev/null
        return 1
    fi
    
    echo -e "${green}Archivos del certificado instalados correctamente${plain}"

    # Habilitar la actualización automática de acme.sh (asegura que se ejecute el trabajo con cron)
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade >/dev/null 2>&1

    # Permisos de seguridad: clave privada legible solo por el propietario
    chmod 600 ${certDir}/privkey.pem 2>/dev/null
    chmod 644 ${certDir}/fullchain.pem 2>/dev/null

    # Configurar panel para usar el certificado
    echo -e "${green}Configurando rutas del certificado para el panel...${plain}"
    ${xui_folder}/x-ui cert -webCert "${certDir}/fullchain.pem" -webCertKey "${certDir}/privkey.pem"
    
    if [ $? -ne 0 ]; then
        echo -e "${yellow}Advertencia: No se pudieron configurar las rutas y directorios del certificado automáticamente${plain}"
        echo -e "${yellow}Los archivos del certificado están en:${plain}"
        echo -e "  Cert: ${certDir}/fullchain.pem"
        echo -e "  Key:  ${certDir}/privkey.pem"
    else
        echo -e "${green}Rutas y directorios del certificado configuradas correctamente${plain}"
    fi

    echo -e "${green}Certificado IP instalado y configurado correctamente!${plain}"
    echo -e "${green}El certificado es válido por ~6 días, se renovará automáticamente mediante cron de acme.sh.${plain}"
    echo -e "${yellow}acme.sh renovará automáticamente y recargará x-ui antes de que caduque.${plain}"
    return 0
}

# Emisión manual completa de certificados SSL mediante acme.sh
ssl_cert_issue() {
    local existing_webBasePath=$(${xui_folder}/x-ui setting -show true | grep 'webBasePath:' | awk -F': ' '{print $2}' | tr -d '[:space:]' | sed 's#^/##')
    local existing_port=$(${xui_folder}/x-ui setting -show true | grep 'port:' | awk -F': ' '{print $2}' | tr -d '[:space:]')
    
    # Verificar primero si acme.sh está instalado
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
        echo "No se encontró acme.sh. Instalando ahora..."
        cd ~ || return 1
        curl -s https://get.acme.sh | sh
        if [ $? -ne 0 ]; then
            echo -e "${red}No se pudo instalar acme.sh${plain}"
            return 1
        else
            echo -e "${green}acme.sh se instaló correctamente${plain}"
        fi
    fi

    # Obtener el dominio aquí, necesitamos verificarlo
    local domain=""
    while true; do
        read -rp "Por favor ingresa tu nombre de dominio: " domain
        domain="${domain// /}"  # Quitar espacios en blanco
        
        if [[ -z "$domain" ]]; then
            echo -e "${red}El nombre de dominio no puede estar vacío. Intenta nuevamente.${plain}"
            continue
        fi
        
        if ! is_domain "$domain"; then
            echo -e "${red}Formato de dominio inválido: ${domain}. Por favor ingresa un dominio válido.${plain}"
            continue
        fi
        
        break
    done
    echo -e "${green}Tu dominio es: ${domain}, verifícando...${plain}"

    # Verificar si ya existe un certificado
    local currentCert=$(~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}')
    if [ "${currentCert}" == "${domain}" ]; then
        local certInfo=$(~/.acme.sh/acme.sh --list)
        echo -e "${red}El sistema ya tiene certificados para este dominio. No se puede emitir de nuevo.${plain}"
        echo -e "${yellow}Detalles del certificado actual:${plain}"
        echo "$certInfo"
        return 1
    else
        echo -e "${green}Tu dominio está listo para emitir certificados ahora...${plain}"
    fi

    # Crear un directorio para el certificado
    certPath="/root/cert/${domain}"
    if [ ! -d "$certPath" ]; then
        mkdir -p "$certPath"
    else
        rm -rf "$certPath"
        mkdir -p "$certPath"
    fi

    # Obtener el número de puerto para el servidor standalone
    local WebPort=80
    read -rp "Por favor elige el puerto a usar (predeterminado es 80): " WebPort
    if [[ ${WebPort} -gt 65535 || ${WebPort} -lt 1 ]]; then
        echo -e "${yellow}El puerto ${WebPort} es inválido, se usará el puerto predeterminado 80.${plain}"
        WebPort=80
    fi
    echo -e "${green}Se usará el puerto: ${WebPort} para emitir certificados. Asegúrate de que este puerto esté abierto.${plain}"

    # Detener el panel temporalmente
    echo -e "${yellow}Deteniendo el panel temporalmente...${plain}"
    systemctl stop x-ui 2>/dev/null || rc-service x-ui stop 2>/dev/null

    # Emitir el certificado
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force
    ~/.acme.sh/acme.sh --issue -d ${domain} --listen-v6 --standalone --httpport ${WebPort} --force
    if [ $? -ne 0 ]; then
        echo -e "${red}Error al emitir el certificado, por favor revisa los registros.${plain}"
        rm -rf ~/.acme.sh/${domain}
        systemctl start x-ui 2>/dev/null || rc-service x-ui start 2>/dev/null
        return 1
    else
        echo -e "${green}Certificado emitido correctamente, instalando certificados...${plain}"
    fi

    # Configurar comando de recarga
    reloadCmd="systemctl restart x-ui || rc-service x-ui restart"
    echo -e "${green}El --reloadcmd predeterminado para ACME es: ${yellow}systemctl restart x-ui || rc-service x-ui restart${plain}"
    echo -e "${green}Este comando se ejecutará en cada emisión y renovación de certificados.${plain}"
    read -rp "¿Deseas modificar --reloadcmd para ACME? (s/n): " setReloadcmd
    if [[ "$setReloadcmd" == "s" || "$setReloadcmd" == "S" ]]; then
        echo -e "\n${green}\t1.${plain} Predeterminado: systemctl reload nginx ; systemctl restart x-ui"
        echo -e "${green}\t2.${plain} Ingresa tu propio comando"
        echo -e "${green}\t0.${plain} Mantener reloadcmd predeterminado"
        read -rp "Elige una opción: " choice
        case "$choice" in
        1)
            echo -e "${green}Reloadcmd es: systemctl reload nginx ; systemctl restart x-ui${plain}"
            reloadCmd="systemctl reload nginx ; systemctl restart x-ui"
            ;;
        2)
            echo -e "${yellow}Se recomienda tipear x-ui restart al final${plain}"
            read -rp "Por favor ingresa tu reloadcmd personalizado: " reloadCmd
            echo -e "${green}Reloadcmd es: ${reloadCmd}${plain}"
            ;;
        *)
            echo -e "${green}Manteniendo reloadcmd predeterminado${plain}"
            ;;
        esac
    fi

    # Instalar el certificado
    ~/.acme.sh/acme.sh --installcert -d ${domain} \
        --key-file /root/cert/${domain}/privkey.pem \
        --fullchain-file /root/cert/${domain}/fullchain.pem --reloadcmd "${reloadCmd}"

    if [ $? -ne 0 ]; then
        echo -e "${red}Error al instalar el certificado, saliendo.${plain}"
        rm -rf ~/.acme.sh/${domain}
        systemctl start x-ui 2>/dev/null || rc-service x-ui start 2>/dev/null
        return 1
    else
        echo -e "${green}Certificado instalado correctamente, habilitando renovación automática...${plain}"
    fi

    # Habilitar auto-renovación
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    if [ $? -ne 0 ]; then
        echo -e "${yellow}Problemas al configurar la renovación automática, detalles del certificado:${plain}"
        ls -lah /root/cert/${domain}/
        # Permisos seguros: clave privada legible solo por el propietario
        chmod 600 $certPath/privkey.pem 2>/dev/null
        chmod 644 $certPath/fullchain.pem 2>/dev/null
    else
        echo -e "${green}Renovación automática configurada correctamente, detalles del certificado:${plain}"
        ls -lah /root/cert/${domain}/
        # Permisos de seguridad: clave privada legible solo por el propietario
        chmod 600 $certPath/privkey.pem 2>/dev/null
        chmod 644 $certPath/fullchain.pem 2>/dev/null
    fi

    # Iniciar el panel
    systemctl start x-ui 2>/dev/null || rc-service x-ui start 2>/dev/null

    # Preguntar al usuario si quiere configurar las rutas del panel tras instalar el certificado
    read -rp "¿Deseas configurar este certificado para el panel? (s/n): " setPanel
    if [[ "$setPanel" == "s" || "$setPanel" == "S" ]]; then
        local webCertFile="/root/cert/${domain}/fullchain.pem"
        local webKeyFile="/root/cert/${domain}/privkey.pem"

        if [[ -f "$webCertFile" && -f "$webKeyFile" ]]; then
            ${xui_folder}/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile"
            echo -e "${green}Rutas y directorios del certificado configuradas para el panel${plain}"
            echo -e "${green}Archivo de certificado: $webCertFile${plain}"
            echo -e "${green}Archivo de clave privada: $webKeyFile${plain}"
            echo ""
            echo -e "${green}URL de acceso: https://${domain}:${existing_port}/${existing_webBasePath}${plain}"
            echo -e "${yellow}El panel se reiniciará para aplicar el certificado SSL...${plain}"
            systemctl restart x-ui 2>/dev/null || rc-service x-ui restart 2>/dev/null
        else
            echo -e "${red}Error: No se encontró el archivo de certificado o clave privada para el dominio: $domain.${plain}"
        fi
    else
        echo -e "${yellow}Se omitió la configuración de rutas y directorios para el panel.${plain}"
    fi
    
    return 0
}

# Configuración SSL interactiva reutilizable (dominio o IP)
# Establece la variable global `SSL_HOST` con el dominio/IP elegido para usar en la URL de acceso
prompt_and_setup_ssl() {
    local panel_port="$1"
    local web_base_path="$2"   # se espera sin la barra inicial
    local server_ip="$3"

    local ssl_choice=""

    echo -e "${yellow}Elige el método de configuración del certificado SSL:${plain}"
    echo -e " "
    echo -e "${green}1.${plain} Let's Encrypt para Dominio (90 días, autorenovación)"
    echo -e "${green}2.${plain} Let's Encrypt para IP (6 días, autorenovación)"
    echo -e "${green}3.${plain} Certs SSL custom (ubica y usa archivos existentes)"
    echo -e "${blue}Nota:${plain} Las opciones 1 y 2 requieren el puerto 80 abierto."
    echo -e "${plain}      La opción 3 requiere ruta y archivo del cert."
    echo -e " "
    read -rp "Elige una opción (predeterminado 2 para IP): " ssl_choice
    ssl_choice="${ssl_choice// /}"  # Quitar espacios en blanco
    
    # Usar 2 (certificado IP) por defecto si la entrada está vacía o es inválida (no es 1 ni 3)
    if [[ "$ssl_choice" != "1" && "$ssl_choice" != "3" ]]; then
        ssl_choice="2"
    fi

    case "$ssl_choice" in
    1)
        # El usuario eligió la opción Let's Encrypt para dominio
        echo -e "${green}Usando Let's Encrypt para certificado de dominio...${plain}"
        ssl_cert_issue
        # Extraer el dominio usado desde el certificado
        local cert_domain=$(~/.acme.sh/acme.sh --list 2>/dev/null | tail -1 | awk '{print $1}')
        if [[ -n "${cert_domain}" ]]; then
            SSL_HOST="${cert_domain}"
            echo -e "${green}✓ Certificado SSL configurado correctamente con el dominio: ${cert_domain}${plain}"
        else
            echo -e "${yellow}La configuración SSL puede haberse completado, pero no se pudo extraer el dominio${plain}"
            SSL_HOST="${server_ip}"
        fi
        ;;
    2)
        # El usuario eligió la opción Let's Encrypt para IP
        echo -e "${green}Usando Let's Encrypt para certificado IP (corta duración)...${plain}"
        
        # Solicitar IPv6 opcional
        local ipv6_addr=""
        read -rp "¿Tienes dirección IPv6 para incluir? (vacío para omitir): " ipv6_addr
        ipv6_addr="${ipv6_addr// /}"  # Quitar espacios en blanco
        
        # Detener el panel si está en ejecución (se necesita el puerto 80)
        if [[ $release == "alpine" ]]; then
            rc-service x-ui stop >/dev/null 2>&1
        else
            systemctl stop x-ui >/dev/null 2>&1
        fi
        
        setup_ip_certificate "${server_ip}" "${ipv6_addr}"
        if [ $? -eq 0 ]; then
            SSL_HOST="${server_ip}"
            echo -e "${green}✓ Certificado IP Let's Encrypt configurado correctamente${plain}"
        else
            echo -e "${red}✗ Falló la configuración del certificado IP. Verifica que el puerto 80 esté abierto.${plain}"
            SSL_HOST="${server_ip}"
        fi
        ;;
    3)
        # El usuario eligió rutas personalizadas (proporcionadas por el usuario)
        echo -e "${green}Usando certificado existente personalizado...${plain}"
        local custom_cert=""
        local custom_key=""
        local custom_domain=""

        # 3.1 Solicitar dominio para construir la URL del panel
        read -rp "Por favor ingresa el dominio para el cual fue emitido el certificado: " custom_domain
        custom_domain="${custom_domain// /}" # Quitar espacios

        # 3.2 Bucle para la ruta del certificado
        while true; do
            read -rp "Ingresa la ruta del cert (palabras clave: .crt / fullchain): " custom_cert
            # Eliminar comillas si existen
            custom_cert=$(echo "$custom_cert" | tr -d '"' | tr -d "'")

            if [[ -f "$custom_cert" && -r "$custom_cert" && -s "$custom_cert" ]]; then
                break
            elif [[ ! -f "$custom_cert" ]]; then
                echo -e "${red}Error: El archivo no existe. Intenta nuevamente.${plain}"
            elif [[ ! -r "$custom_cert" ]]; then
                echo -e "${red}Error: El archivo existe pero es ilegible \n       (verifica permisos)!${plain}"
            else
                echo -e "${red}Error: El archivo está vacío!${plain}"
            fi
        done

        # 3.3 Bucle para la ruta de la clave privada
        while true; do
            read -rp "Ingresa la ruta de la clave privada (palabras clave: .key / privatekey): " custom_key
            # Eliminar comillas si existen
            custom_key=$(echo "$custom_key" | tr -d '"' | tr -d "'")

            if [[ -f "$custom_key" && -r "$custom_key" && -s "$custom_key" ]]; then
                break
            elif [[ ! -f "$custom_key" ]]; then
                echo -e "${red}Error: El archivo no existe. Intenta nuevamente.${plain}"
            elif [[ ! -r "$custom_key" ]]; then
                echo -e "${red}Error: El archivo existe pero es ilegible \n       (verifica permisos).${plain}"
            else
                echo -e "${red}Error: El archivo está vacío.${plain}"
            fi
        done

        # 3.4 Aplicar configuración mediante el binario x-ui
        ${xui_folder}/x-ui cert -webCert "$custom_cert" -webCertKey "$custom_key" >/dev/null 2>&1
        
        # Establecer SSL_HOST para construir la URL del panel
        if [[ -n "$custom_domain" ]]; then
            SSL_HOST="$custom_domain"
        else
            SSL_HOST="${server_ip}"
        fi

        echo -e "${green}✓ Rutas del certificado personalizado aplicadas.${plain}"
        echo -e "${yellow}Nota: Eres responsable de renovar estos archivos externamente.${plain}"

        systemctl restart x-ui >/dev/null 2>&1 || rc-service x-ui restart >/dev/null 2>&1
        ;;
    *)
        echo -e "${red}Opción inválida. Omitiendo configuración SSL.${plain}"
        SSL_HOST="${server_ip}"
        ;;
    esac
}

config_after_install() {
        local existing_hasDefaultCredential=$(${xui_folder}/x-ui setting -show true | grep -Eo 'hasDefaultCredential: .+' | awk '{print $2}')
    local existing_webBasePath=$(${xui_folder}/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}' | sed 's#^/##')
    local existing_port=$(${xui_folder}/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    # Detectar correctamente un certificado vacío comprobando si la línea cert: existe y tiene contenido después
    local existing_cert=$(${xui_folder}/x-ui setting -getCert true | grep 'cert:' | awk -F': ' '{print $2}' | tr -d '[:space:]')
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
    
    if [[ ${#existing_webBasePath} -lt 4 ]]; then
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_webBasePath=$(gen_random_string 18)
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)

            read -rp "¿Deseas personalizar la configuración del puerto del Panel? (Si no, se asignará un puerto aleatorio) [s/n]: " config_confirm
            if [[ "${config_confirm}" == "s" || "${config_confirm}" == "S" ]]; then
                read -rp "Por favor, configura el puerto del panel: " config_port
                echo -e "${yellow}El puerto de tu Panel es: ${config_port}${plain}"
            else
                local config_port=$(shuf -i 1024-62000 -n 1)
                echo -e "${yellow}Puerto aleatorio generado: ${config_port}${plain}"
            fi
            
            ${xui_folder}/x-ui setting -username "${config_username}" -password "${config_password}" -port "${config_port}" -webBasePath "${config_webBasePath}"
            
            echo ""
            echo -e "${green}════════════════════════════════════════════${plain}"
            echo -e "${green}  Configuración del Cert SSL (OBLIGATORIO)  ${plain}"
            echo -e "${green}════════════════════════════════════════════${plain}"
            echo -e "${yellow}Por seguridad, el certificado SSL es obligatorio para todos los paneles.${plain}"
            echo -e "${yellow}¡Let's Encrypt ahora soporta dominios y direcciones IP!${plain}"
            echo ""

            prompt_and_setup_ssl "${config_port}" "${config_webBasePath}" "${server_ip}"
            
            # Mostrar credenciales finales e información de acceso
            echo ""
            echo -e "${green}════════════════════════════════════════════${plain}"
            echo -e "${green}     ¡Instalación del Panel Completada!     ${plain}"
            echo -e "${green}════════════════════════════════════════════${plain}"
            echo -e "${green}Usuario:       ${config_username}${plain}"
            echo -e "${green}Contraseña:    ${config_password}${plain}"
            echo -e "${green}Puerto:        ${config_port}${plain}"
            echo -e "${green}WebBasePath:   ${config_webBasePath}${plain}"
            echo -e "${green}URL de acceso: https://${SSL_HOST}:${config_port}/${config_webBasePath}${plain}"
            echo -e "${green}════════════════════════════════════════════${plain}"
            echo -e "${yellow}⚠ IMPORTANTE: ¡Guarda estas credenciales de forma segura!${plain}"
            echo -e "${yellow}⚠ Certificado SSL: Habilitado y configurado${plain}"
        else
            local config_webBasePath=$(gen_random_string 18)
            echo -e "${yellow}WebBasePath faltante o demasiado corto. Generando uno nuevo...${plain}"
            ${xui_folder}/x-ui setting -webBasePath "${config_webBasePath}"
            echo -e "${green}Nuevo WebBasePath: ${config_webBasePath}${plain}"

            # Si el panel ya está instalado pero no hay certificado configurado, solicitar SSL ahora
            if [[ -z "${existing_cert}" ]]; then
                echo ""
                echo -e "${green}═════════════════════════════════════════════${plain}"
                echo -e "${green}   Configuración del CertSSL (RECOMENDADO)   ${plain}"
                echo -e "${green}═════════════════════════════════════════════${plain}"
                echo -e "${yellow}¡Let's Encrypt ahora soporta dominios y direcciones IP!${plain}"
                echo ""
                prompt_and_setup_ssl "${existing_port}" "${config_webBasePath}" "${server_ip}"
                echo -e "${green}URL de acceso:  https://${SSL_HOST}:${existing_port}/${config_webBasePath}${plain}"
            else
                # Si el certificado ya existe, solo mostrar la URL de acceso
                echo -e "${green}URL de acceso: https://${server_ip}:${existing_port}/${config_webBasePath}${plain}"
            fi
        fi
    else
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)
            
            echo -e "${yellow}Credenciales por defecto detectadas. Se requiere una actualización de seguridad...${plain}"
            ${xui_folder}/x-ui setting -username "${config_username}" -password "${config_password}"
            echo -e "Se generaron nuevas credenciales de inicio de sesión aleatorias:"
            echo -e "###############################################"
            echo -e "${green}Usuario: ${config_username}${plain}"
            echo -e "${green}Contraseña: ${config_password}${plain}"
            echo -e "###############################################"
        else
            echo -e "${green}Usuario, contraseña y WebBasePath están configurados correctamente.${plain}"
        fi

        # Instalación existente: si no hay certificado configurado, solicitar configuración SSL
        # Detectar correctamente un certificado vacío comprobando si la línea cert: existe y tiene contenido
        existing_cert=$(${xui_folder}/x-ui setting -getCert true | grep 'cert:' | awk -F': ' '{print $2}' | tr -d '[:space:]')
        if [[ -z "$existing_cert" ]]; then
            echo ""
            echo -e "${green}═════════════════════════════════════════════${plain}"
            echo -e "${green}   Configuración del CertSSL (RECOMENDADO)   ${plain}"
            echo -e "${green}═════════════════════════════════════════════${plain}"
            echo -e "${yellow}¡Let's Encrypt ahora soporta dominios y direcciones IP!${plain}"
            echo ""
            prompt_and_setup_ssl "${existing_port}" "${existing_webBasePath}" "${server_ip}"
            echo -e "${green}URL de acceso:  https://${SSL_HOST}:${existing_port}/${existing_webBasePath}${plain}"
        else
            echo -e "${green}El certificado SSL ya está configurado. No se requiere ninguna acción.${plain}"
        fi
    fi
    
    ${xui_folder}/x-ui migrate
}

install_x-ui() {
    cd ${xui_folder%/x-ui}/

    # Descargar recursos
    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/emirjorge/3x-ui_es/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${yellow}Intentando obtener la versión usando IPv4...${plain}"
            last_version=$(curl -4 -Ls "https://api.github.com/repos/emirjorge/3x-ui_es/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
            if [[ ! -n "$last_version" ]]; then
                echo -e "${red}No se pudo obtener la versión de x-ui, puede deberse a restricciones de la API de GitHub. Por favor, inténtalo más tarde.${plain}"
            exit 1
        fi
    fi
        echo -e "Se encontró la última versión de x-ui: ${last_version}, comenzando la instalación..."
        curl -4fLRo ${xui_folder}-linux-$(arch).tar.gz https://github.com/emirjorge/3x-ui_es/releases/download/${last_version}/x-ui-linux-$(arch).tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Error al descargar x-ui, asegúrese de que su servidor pueda acceder a Github ${plain}"
            exit 1
        fi
    else
        last_version=$1
        last_version_numeric=${last_version#v}
        min_version="2.3.5"

        if [[ "$(printf '%s\n' "$min_version" "$last_version_numeric" | sort -V | head -n1)" != "$min_version" ]]; then
            echo -e "${red}Por favor, usa una versión más reciente (al menos v2.3.5). Saliendo de la instalación.${plain}"
            exit 1
        fi
            
        url="https://github.com/emirjorge/3x-ui_es/releases/download/${last_version}/x-ui-linux-$(arch).tar.gz"
        echo -e "Comenzando a instalar x-ui $1"
        curl -4fLRo ${xui_folder}-linux-$(arch).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Error al descargar x-ui $1, por favor verifique que exista la versión ${plain}"
            exit 1
        fi
    fi
    curl -4fLRo /usr/bin/x-ui-temp https://raw.githubusercontent.com/emirjorge/3x-ui_es/main/x-ui.sh                            
    if [[ $? -ne 0 ]]; then
        echo -e "${red}No se pudo descargar x-ui.sh${plain}"
        exit 1
    fi

    # Detener el servicio x-ui y eliminar recursos antiguos
    if [[ -e ${xui_folder}/ ]]; then
        if [[ $release == "alpine" ]]; then
            rc-service x-ui stop
        else
            systemctl stop x-ui
        fi
        rm ${xui_folder}/ -rf
    fi

    # Extraer los recursos y asignar permisos
    tar zxvf x-ui-linux-$(arch).tar.gz
    rm x-ui-linux-$(arch).tar.gz -f

    cd x-ui
    chmod +x x-ui
    chmod +x x-ui.sh

    # Verifica la arquitectura del sistema y renombra el archivo en consecuencia
    if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
        mv bin/xray-linux-$(arch) bin/xray-linux-arm
        chmod +x bin/xray-linux-arm
    fi    
    chmod +x x-ui bin/xray-linux-$(arch)

    # Actualizar el CLI de x-ui y establecer los permisos
    mv -f /usr/bin/x-ui-temp /usr/bin/x-ui
    chmod +x /usr/bin/x-ui
    mkdir -p /var/log/x-ui
    config_after_install

    # Compatibilidad con Etckeeper
    if [ -d "/etc/.git" ]; then
        if [ -f "/etc/.gitignore" ]; then
            if ! grep -q "x-ui/x-ui.db" "/etc/.gitignore"; then
                echo "" >> "/etc/.gitignore"
                echo "x-ui/x-ui.db" >> "/etc/.gitignore"
                echo -e "${green}Se añadió x-ui.db a /etc/.gitignore para etckeeper${plain}"
            fi
        else
            echo "x-ui/x-ui.db" > "/etc/.gitignore"
            echo -e "${green}Se creó /etc/.gitignore y se añadió x-ui.db para etckeeper${plain}"
        fi
    fi
    
    if [[ $release == "alpine" ]]; then
        curl -4fLRo /etc/init.d/x-ui https://raw.githubusercontent.com/emirjorge/3x-ui_es/main/x-ui.rc
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Error al descargar x-ui.rc${plain}"
            exit 1
        fi
        chmod +x /etc/init.d/x-ui
        rc-update add x-ui
        rc-service x-ui start
    else
        # Instalar archivo de servicio systemd
        service_installed=false
        
        if [ -f "x-ui.service" ]; then
            echo -e "${green}Se encontró x-ui.service en los archivos extraídos, instalando...${plain}"
            cp -f x-ui.service ${xui_service}/ >/dev/null 2>&1
            if [[ $? -eq 0 ]]; then
                service_installed=true
            fi
        fi
        
        if [ "$service_installed" = false ]; then
            case "${release}" in
                ubuntu | debian | armbian)
                    if [ -f "x-ui.service.debian" ]; then
                        echo -e "${green}Se encontró x-ui.service.debian en los archivos extraídos, instalando...${plain}"
                        cp -f x-ui.service.debian ${xui_service}/x-ui.service >/dev/null 2>&1
                        if [[ $? -eq 0 ]]; then
                            service_installed=true
                        fi
                    fi
                ;;
                arch | manjaro | parch)
                    if [ -f "x-ui.service.arch" ]; then
                        echo -e "${green}Se encontró x-ui.service.arch en los archivos extraídos, instalando...${plain}"
                        cp -f x-ui.service.arch ${xui_service}/x-ui.service >/dev/null 2>&1
                        if [[ $? -eq 0 ]]; then
                            service_installed=true
                        fi
                    fi
                ;;
                *)
                    if [ -f "x-ui.service.rhel" ]; then
                        echo -e "${green}Se encontró x-ui.service.rhel en los archivos extraídos, instalando...${plain}"
                        cp -f x-ui.service.rhel ${xui_service}/x-ui.service >/dev/null 2>&1
                        if [[ $? -eq 0 ]]; then
                            service_installed=true
                        fi
                    fi
                ;;
            esac
        fi
        
        # Si no se encontró el archivo de servicio en el tar.gz, descargarlo desde GitHub
        if [ "$service_installed" = false ]; then
            echo -e "${yellow}Archivos de servicio no encontrados en el tar.gz, descargando desde GitHub...${plain}"
            case "${release}" in
                ubuntu | debian | armbian)
                    curl -4fLRo ${xui_service}/x-ui.service https://raw.githubusercontent.com/emirjorge/3x-ui_es/main/x-ui.service.debian >/dev/null 2>&1
                ;;
                arch | manjaro | parch)
                    curl -4fLRo ${xui_service}/x-ui.service https://raw.githubusercontent.com/emirjorge/3x-ui_es/main/x-ui.service.arch >/dev/null 2>&1
                ;;
                *)
                    curl -4fLRo ${xui_service}/x-ui.service https://raw.githubusercontent.com/emirjorge/3x-ui_es/main/x-ui.service.rhel >/dev/null 2>&1
                ;;
            esac
            
            if [[ $? -ne 0 ]]; then
                echo -e "${red}Error al instalar x-ui.service desde GitHub${plain}"
                exit 1
            fi
            service_installed=true
        fi
        
        if [ "$service_installed" = true ]; then
            echo -e "${green}Configurando la unidad systemd...${plain}"
            chown root:root ${xui_service}/x-ui.service >/dev/null 2>&1
            chmod 644 ${xui_service}/x-ui.service >/dev/null 2>&1
            systemctl daemon-reload
            systemctl enable x-ui
            systemctl start x-ui
        else
            echo -e "${red}Error al instalar el archivo x-ui.service${plain}"
            exit 1
        fi
    fi
    
    echo -e "${green}La instalación de x-ui ${last_version}${plain} finalizó, ya esta funcionando..."
    echo -e ""
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

echo -e "${green}Ejecutando...${plain}"
install_base
install_x-ui $1