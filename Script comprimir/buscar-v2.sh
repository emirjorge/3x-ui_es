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
    grep -q 'MEU_IP' "$archivo" && tiene_meu=true || tiene_meu=false
    grep -q 'ifconfig\.me' "$archivo" && tiene_ifconfig=true || tiene_ifconfig=false

    if $tiene_meu && $tiene_ifconfig; then
        ambos+=("$archivo")
    elif $tiene_meu; then
        solo_meu+=("$archivo")
    elif $tiene_ifconfig; then
        solo_ifconfig+=("$archivo")
    fi
done < <(find "$RUTA" -type f -print0)

# Función para imprimir listas numeradas
imprimir_lista() {
    local titulo="$1"
    shift
    local lista=("$@")

    echo -e "\n$titulo"
    echo "--------------------------------"
    if [ ${#lista[@]} -eq 0 ]; then
        echo "⚠️ Ninguno (0)"
    else
        local i=1
        for item in "${lista[@]}"; do
            printf "%2d) %s\n" "$i" "$item"
            ((i++))
        done
        echo "➡️ Total: ${#lista[@]}"
    fi
}

# Mostrar resultados
imprimir_lista "🟢 Archivos SOLO con MEU_IP" "${solo_meu[@]}"
imprimir_lista "🔵 Archivos SOLO con ifconfig.me" "${solo_ifconfig[@]}"
imprimir_lista "🟣 Archivos con AMBOS (MEU_IP + ifconfig.me)" "${ambos[@]}"

echo -e "\n✅ Escaneo completado."
