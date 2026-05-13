#!/bin/bash

# ==============================================================================
#  CONFIGURACIÓN
# ==============================================================================

FFMPEG_ARGS="-map 0:v -map 0:a? -map 0:s? -c:v libx265 -preset slow -crf 24 -profile:v main10 -pix_fmt yuv420p10le -x265-params aq-mode=2 -c:a copy -c:s copy -map_metadata 0 -movflags use_metadata_tags"

# ==============================================================================
#  LÓGICA
# ==============================================================================

get_info() {
    local file="$1"
    SUBS_RAW=$(ffprobe -v error -select_streams s -show_entries stream_tags=language -of csv=p=0 "$file")
    
    if [ -z "$SUBS_RAW" ]; then
        SUBS_STRING=""
    else
        SUBS_FORMATTED=$(echo "$SUBS_RAW" | tr '\n' ' ' | sed 's/ $//' | sed 's/ / - /g')
        SUBS_STRING=" [Subs - $SUBS_FORMATTED]"
    fi
}

echo "--- INICIANDO PROCESO (ARCHIVOS HERMANADOS) ---"

# Buscamos archivos de vídeo.
# 1. find descarta directamente los que ya tienen ".byte." (insensible a mayúsculas con -iname)
# 2. grep filtra buscando una lista exhaustiva de extensiones de vídeo (insensible a mayúsculas con -i)
find . -type f -not -iname "*.byte.*" | grep -iE '\.(mp4|mkv|avi|mov|wmv|flv|webm|m4v|mpg|mpeg|3gp|ts|m2ts|vob)$' | while read -r FILE; do
    
    DIR_NAME=$(dirname "$FILE")
    BASE_NAME=$(basename "$FILE")
    NAME_NO_EXT="${BASE_NAME%.*}"
    EXTENSION="${BASE_NAME##*.}"
    
    # Obtenemos info de los subs
    get_info "$FILE"

    # Generamos el nombre hermanado en la misma carpeta
    NEW_FILENAME="${NAME_NO_EXT}${SUBS_STRING}.byte.${EXTENSION}"
    OUTPUT_FILE="${DIR_NAME}/${NEW_FILENAME}"

    if [ -f "$OUTPUT_FILE" ]; then
        echo "⏭️  SALTADO: Ya existe su versión hermanada -> $NEW_FILENAME"
    else
        echo "----------------------------------------------------------------"
        echo "📂 Procesando: $FILE"
        echo "🎯 Creando:    $OUTPUT_FILE"
        
        ffmpeg -v error -stats -i "$FILE" $FFMPEG_ARGS "$OUTPUT_FILE" < /dev/null
        
        # Comprobación de que FFmpeg terminó sin errores graves
        if [ $? -eq 0 ]; then
            touch -r "$FILE" "$OUTPUT_FILE"
            echo "✅ HECHO."
        else
            echo "❌ ERROR de FFmpeg detectado. Borrando el archivo incompleto..."
            rm -f "$OUTPUT_FILE"
        fi
    fi

done

echo ""
echo "========================================"
echo " PROCESO COMPLETADO."
echo "========================================"