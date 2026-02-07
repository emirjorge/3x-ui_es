#!/bin/bash

RUTA="/etc/VPS-MX"

# Verificar carpeta
if [ ! -d "$RUTA" ]; then
    echo "❌ La carpeta $RUTA no existe."
    exit 1
fi

solo_meu=()
solo_ifconfig=()
ambos=()

# Leer archivos
while IFS= read -r -d '' archivo; do
    tiene_meu=false
    tiene_ifconfig=false

    grep -q 'MEU_IP' "$archivo" && tiene_meu=true
    grep -q 'ifconfig\.me' "$archivo" && tiene_ifconfig=true

    if $tiene_meu && $tiene_ifconfig; then
        ambos+=("$archivo")
    elif $tiene_meu; then
        solo_meu+=("$archivo")
    elif $tiene_ifconfig; then
        solo_ifconfig+=("$archivo")
    fi
done < <(find "$RUTA" -type f -print0)

# Función para mostrar grupo
mostrar_grupo() {
    local titulo="$1"
    shift
    local archivos=("$@")

    echo -e "\n$titulo (${#archivos[@]})"
    echo "--------------------------------"

    if [ ${#archivos[@]} -eq 0 ]; then
        echo "⚠️ Ninguno"
    else
        local i=1
        for f in "${archivos[@]}"; do
            echo "[$i] $f"
            ((i++))
        done
    fi
}

# Mostrar resultados
mostrar_grupo "🟢 Archivos SOLO con MEU_IP" "${solo_meu[@]}"
mostrar_grupo "🔵 Archivos SOLO con ifconfig.me" "${solo_ifconfig[@]}"
mostrar_grupo "🟣 Archivos con AMBOS (MEU_IP + ifconfig.me)" "${ambos[@]}"

echo -e "\n✅ Escaneo completado."