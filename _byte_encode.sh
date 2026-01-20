#!/bin/bash

# ==============================================================================
#  CONFIGURACIÓN
# ==============================================================================

# PRESET FFmpeg (QP 32 + AAC 128k)
FFMPEG_ARGS="-map 0 -c:v hevc_nvenc -preset slow -rc constqp -qp 32 -spatial_aq 1 -c:a aac -b:a 128k -ac 2 -c:s copy"

# Nombres para el etiquetado
NEW_V_CODEC="hevc"
NEW_A_CODEC="aac"

# ==============================================================================
#  LÓGICA
# ==============================================================================

# Función para extraer info del archivo original
get_info() {
    local file="$1"
    OLD_V_CODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file")
    OLD_A_CODEC=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file")
    SUBS_RAW=$(ffprobe -v error -select_streams s -show_entries stream_tags=language -of csv=p=0 "$file")
    
    if [ -z "$SUBS_RAW" ]; then
        SUBS_STRING=""
    else
        # Formatea subs: de "spa\neng" a " - spa - eng"
        SUBS_FORMATTED=$(echo "$SUBS_RAW" | tr '\n' ' ' | sed 's/ $//' | sed 's/ / - /g')
        SUBS_STRING=" [Subs - $SUBS_FORMATTED]"
    fi

    if [ -z "$OLD_V_CODEC" ]; then OLD_V_CODEC="unk"; fi
    if [ -z "$OLD_A_CODEC" ]; then OLD_A_CODEC="unk"; fi
}

echo "--- INICIANDO PROCESO (MODO ESPEJO CON ETIQUETAS) ---"

# Buscamos archivos recursivamente. 
# EXCLUIMOS (-not -path) las carpetas que empiecen por [byte] para no recomprimir lo ya hecho.
find . -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" \) -not -path "./\[byte\]*" | while read -r FILE; do
    
    # 1. Analizar Rutas
    DIR_NAME=$(dirname "$FILE")         # Ej: ./Temporada 1/Extras
    BASE_NAME=$(basename "$FILE")       # Ej: Capitulo1.mkv
    NAME_NO_EXT="${BASE_NAME%.*}"       # Ej: Capitulo1
    EXTENSION="${BASE_NAME##*.}"        # Ej: mkv
    
    # 2. Construir Ruta de Destino "Hermana" con [byte]
    # Truco sed: Reemplaza "./" inicial y añade "[byte] " delante de cada carpeta
    # Ej Entrada: ./Temporada 1/Extras
    # Ej Salida:  ./[byte] Temporada 1/[byte] Extras
    CLEAN_PATH=${DIR_NAME#./}
    NEW_DIR_PATH=$(echo "$CLEAN_PATH" | sed 's|/|/[byte] |g' | sed 's|^|[byte] |')
    
    # Creamos la carpeta destino
    mkdir -p "./$NEW_DIR_PATH"

    # 3. Analizar Codecs
    get_info "$FILE"

    # 4. Construir Nuevo Nombre
    # Formato: [byte] [CODECS] [SUBS] NombreOriginal.ext
    TAG_INFO="[${NEW_V_CODEC} - ${NEW_A_CODEC} (from ${OLD_V_CODEC} - ${OLD_A_CODEC})]"
    NEW_FILENAME="[byte] ${TAG_INFO}${SUBS_STRING} ${NAME_NO_EXT}.${EXTENSION}"
    
    OUTPUT_FILE="./$NEW_DIR_PATH/$NEW_FILENAME"

    # 5. Ejecutar FFmpeg
    if [ -f "$OUTPUT_FILE" ]; then
        echo "⏭️  SALTADO: $NEW_FILENAME"
    else
        echo "----------------------------------------------------------------"
        echo "📂 Origen: $FILE"
        echo "🎯 Destino: $OUTPUT_FILE"
        
        # < /dev/null evita que ffmpeg rompa el bucle while
        ffmpeg -v error -stats -i "$FILE" $FFMPEG_ARGS "$OUTPUT_FILE" < /dev/null
        
        if [ $? -eq 0 ]; then
            echo "✅ HECHO."
        else
            echo "❌ ERROR. Se borra el archivo incompleto."
            rm -f "$OUTPUT_FILE"
        fi
    fi

done

echo ""
echo "========================================"
echo " PROCESO COMPLETADO."
echo "========================================"