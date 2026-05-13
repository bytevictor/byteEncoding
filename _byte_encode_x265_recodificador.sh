#!/bin/bash

# ==============================================================================
# CONFIGURACIÓN
# ==============================================================================

# PRESET FFmpeg (NVENC 10-bit, Alta Calidad, Copia Audio/Subs + Metadatos)
FFMPEG_ARGS="-map 0:v -map 0:a? -map 0:s? -c:v libx265 -preset slow -crf 24 -profile:v main10 -pix_fmt yuv420p10le -x265-params aq-mode=2 -c:a copy -c:s copy -map_metadata 0 -movflags use_metadata_tags"

NEW_V_CODEC="HEVC"
NEW_A_CODEC="COPY"

# ==============================================================================
# LÓGICA
# ==============================================================================

get_info() {
    local file="$1"
    OLD_V_CODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file")
    OLD_A_CODEC=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file")
    SUBS_RAW=$(ffprobe -v error -select_streams s -show_entries stream_tags=language -of csv=p=0 "$file")
    
    if [ -z "$SUBS_RAW" ]; then
        SUBS_STRING=""
    else
        SUBS_FORMATTED=$(echo "$SUBS_RAW" | tr '\n' ' ' | sed 's/ $//' | sed 's/ / - /g')
        SUBS_STRING=" [Subs - $SUBS_FORMATTED]"
    fi
}

echo "--- INICIANDO PROCESO (MODO FICHERO HERMANO) ---"

# Buscamos archivos recursivamente.
# IMPORTANTE: Excluimos archivos que ya empiecen por "[byte]" para evitar bucles infinitos.
find . -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" \) -not -name "\[byte\]*" | while read -r FILE; do
    
    # 1. Analizar Rutas
    DIR_NAME=$(dirname "$FILE")         # Carpeta actual del archivo
    BASE_NAME=$(basename "$FILE")       # Nombre con extensión
    NAME_NO_EXT="${BASE_NAME%.*}"       # Nombre sin extensión
    EXTENSION="${BASE_NAME##*.}"        # Extensión
    
    # 2. Analizar Codecs y Subs
    get_info "$FILE"

    # 3. Construir Nuevo Nombre (se creará en la misma carpeta DIR_NAME)
    NEW_FILENAME="[byte] ${NAME_NO_EXT}${SUBS_STRING}.${EXTENSION}"
    OUTPUT_FILE="$DIR_NAME/$NEW_FILENAME"

    # 4. Ejecutar FFmpeg
    if [ -f "$OUTPUT_FILE" ]; then
        echo "⏭️  SALTADO (Ya existe): $NEW_FILENAME"
    else
        echo "----------------------------------------------------------------"
        echo "📂 Origen: $FILE"
        echo "🎯 Destino: $OUTPUT_FILE"
        
        ffmpeg -v error -stats -i "$FILE" $FFMPEG_ARGS "$OUTPUT_FILE" < /dev/null
        
        if [ $? -eq 0 ]; then
            # Clonar fechas del archivo original al nuevo
            touch -r "$FILE" "$OUTPUT_FILE"
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