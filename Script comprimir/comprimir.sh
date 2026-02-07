#!/bin/bash

set -e  # Salir si hay algún error

# Carpeta temporal
TMP_DIR=$(mktemp -d -t xui_temp_XXXX)
echo "Usando carpeta temporal: $TMP_DIR"

# URLs de descarga
urls=(
"https://github.com/MHSanaei/3x-ui/releases/download/v2.8.9/x-ui-linux-386.tar.gz"
"https://github.com/MHSanaei/3x-ui/releases/download/v2.8.9/x-ui-linux-amd64.tar.gz"
"https://github.com/MHSanaei/3x-ui/releases/download/v2.8.9/x-ui-linux-arm64.tar.gz"
"https://github.com/MHSanaei/3x-ui/releases/download/v2.8.9/x-ui-linux-armv5.tar.gz"
"https://github.com/MHSanaei/3x-ui/releases/download/v2.8.9/x-ui-linux-armv6.tar.gz"
"https://github.com/MHSanaei/3x-ui/releases/download/v2.8.9/x-ui-linux-armv7.tar.gz"
"https://github.com/MHSanaei/3x-ui/releases/download/v2.8.9/x-ui-linux-s390x.tar.gz"
"https://github.com/MHSanaei/3x-ui/releases/download/v2.8.9/x-ui-windows-amd64.zip"
)

# Descargar todos los archivos en la carpeta temporal
echo "Descargando archivos..."
cd "$TMP_DIR"
for url in "${urls[@]}"; do
    wget -c "$url"
done

# Descomprimir archivos .tar.gz (excepto Windows)
echo "Descomprimiendo archivos tar.gz..."
for tarfile in "$TMP_DIR"/x-ui-linux-*.tar.gz; do
    foldername=$(basename "$tarfile" .tar.gz)
    mkdir -p "$foldername"
    tar -xzf "$tarfile" -C "$foldername"
done

# Reemplazar x-ui.sh en cada carpeta descomprimida
echo "Reemplazando x-ui.sh..."
for folder in "$TMP_DIR"/x-ui-linux-*; do
    if [ -d "$folder/x-ui" ]; then
        rm -f "$folder/x-ui/x-ui.sh"
        cp /root/x-ui.sh "$folder/x-ui/x-ui.sh"
    fi
done

# Comprimir cada carpeta en tar.gz desde la subcarpeta x-ui
echo "Creando tar.gz finales en /root..."
for folder in "$TMP_DIR"/x-ui-linux-*; do
    foldername=$(basename "$folder")
    if [ -d "$folder/x-ui" ]; then
        (
            cd "$folder" || exit 1
            tar -czvf "/root/$foldername.tar.gz" x-ui
        )
    fi
done

# Copiar archivo Windows.zip antes de borrar la carpeta temporal
echo "Copiando x-ui-windows-amd64.zip a /root..."
cp "$TMP_DIR/x-ui-windows-amd64.zip" /root/

# Limpiar carpeta temporal
echo "Borrando carpeta temporal..."
rm -rf "$TMP_DIR"

echo "¡Proceso completado! Los archivos tar.gz y Windows.zip están en /root"