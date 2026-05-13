#!/bin/bash
# ==============================================================================
#  TRANSCODIFICADOR A AV1 — Optimizado para Intel i7-14700K
#  Encoder: SVT-AV1 (libsvtav1) vía FFmpeg
# ==============================================================================
#
#  DECISIONES DE DISEÑO:
#
#  · libsvtav1 en lugar de libaom-av1: SVT-AV1 (Intel/Netflix) es 5-10x más
#    rápido para calidad equivalente y escala perfectamente en CPUs multi-core.
#
#  · preset 5: Punto dulce velocidad/calidad para el 14700K.
#    Escala de 2 (lento, mejor) a 8 (rápido, peor).
#    Con preset 4 obtienes ~10% más calidad a ~2x más tiempo de proceso.
#
#  · crf 30: AV1 CRF 30 ≈ x265 CRF 24 visualmente, con 30-50% menos tamaño.
#    Rango: 0 (sin pérdida) → 63 (calidad mínima).
#
#  · tune=0 (VQ — Visual Quality): optimiza métricas perceptuales en lugar de
#    PSNR/SSIM matemáticos. Ideal para contenido variado (recuerdos: interior,
#    exterior, cámara en mano, etc.).
#
#  · film-grain=8: Síntesis de grano en decodificación. El encoder elimina el
#    ruido natural del vídeo (que es difícil de comprimir) y almacena solo un
#    parámetro de grano que el reproductor reconstruye. Reduce tamaño sin
#    perder la textura visual del original. Valor 8 es conservador y seguro.
#    Ponlo a 0 si tus vídeos son ya muy limpios (grabaciones modernas en buena
#    luz) o si notas que el grano resultante no te gusta.
#
#  · film-grain-denoise=0: No aplicamos denoising destructivo antes de codificar,
#    solo el modelado de grano. Preserva mejor los detalles finos.
#
#  · lp=24: Logical Processors para SVT-AV1. El i7-14700K tiene 28 hilos
#    (8 P-cores HT + 12 E-cores). Dejamos 4 libres para el sistema.
#
#  · yuv420p10le: 10 bits. AV1 aprovecha mucho mejor el 10-bit que H.264/H.265
#    (mejor compresión Y mejor calidad de color). Sin coste perceptible de
#    compatibilidad en reproductores modernos (VLC, mpv, Infuse, Kodi...).
#
#  · Contenedor: se respeta la extensión original. Solo se fuerza .mkv si el
#    archivo tiene subtítulos ASS/SSA, que MP4 no puede contener.
#
#  · Audio/Subtítulos: copiados sin recodificar. No tiene sentido recomprimir
#    audio que ya está en AAC/AC3/EAC3/FLAC.
#
# ==============================================================================


# ==============================================================================
#  CONFIGURACIÓN — Ajusta estos valores si es necesario
# ==============================================================================

# Calidad visual (CRF). Menor = mejor calidad / mayor tamaño.
# Rango útil: 25 (casi sin pérdida) — 38 (calidad aceptable, muy comprimido)
CRF=30

# Velocidad de codificación. Menor = más lento / mejor compresión.
# 4 → mejor calidad, ~2x más lento que 5
# 5 → recomendado (punto dulce para el 14700K)
# 6 → ~40% más rápido, calidad ligeramente inferior
PRESET=5

# Síntesis de grano de película (0 = desactivado, 1-50).
# Útil para vídeos con ruido natural (cámaras antiguas, poca luz, etc.).
# Ponlo a 0 para vídeos muy limpios (smartphone moderno en buena luz).
FILM_GRAIN=8

# Hilos para SVT-AV1. i7-14700K: 8P×2 + 12E = 28 hilos. Dejamos margen.
LOGICAL_PROCESSORS=24

# ==============================================================================
#  FIN DE CONFIGURACIÓN
# ==============================================================================


# Construcción de los parámetros SVT-AV1
SVT_PARAMS="tune=0:film-grain=${FILM_GRAIN}:film-grain-denoise=0:lp=${LOGICAL_PROCESSORS}"

FFMPEG_ARGS="-map 0:v \
             -map 0:a? \
             -map 0:s? \
             -c:v libsvtav1 \
             -preset ${PRESET} \
             -crf ${CRF} \
             -pix_fmt yuv420p10le \
             -svtav1-params ${SVT_PARAMS} \
             -c:a copy \
             -c:s copy \
             -map_metadata 0 \
             -movflags use_metadata_tags"

# ==============================================================================
#  FUNCIONES
# ==============================================================================

# Extrae info de pistas de subtítulos para añadirla al nombre del archivo
get_info() {
    local file="$1"
    SUBS_RAW=$(ffprobe -v error \
        -select_streams s \
        -show_entries stream_tags=language \
        -of csv=p=0 \
        "$file")

    if [ -z "$SUBS_RAW" ]; then
        SUBS_STRING=""
    else
        SUBS_FORMATTED=$(echo "$SUBS_RAW" | tr '\n' ' ' | sed 's/ $//' | sed 's/ / - /g')
        SUBS_STRING=" [Subs - $SUBS_FORMATTED]"
    fi
}

# Comprueba que libsvtav1 esté disponible en la instalación de FFmpeg
check_svtav1() {
    if ! ffmpeg -encoders 2>/dev/null | grep -q "libsvtav1"; then
        echo "❌ ERROR CRÍTICO: libsvtav1 no está disponible en tu FFmpeg."
        echo ""
        echo "   Instala FFmpeg con soporte SVT-AV1:"
        echo "   · Ubuntu/Debian:  sudo apt install ffmpeg          (Ubuntu 22.04+)"
        echo "   · Si la versión de tu repo es antigua, usa:"
        echo "     https://johnvansickle.com/ffmpeg/  (builds estáticos actualizados)"
        echo "   · macOS (Homebrew): brew install ffmpeg"
        echo ""
        exit 1
    fi
}

# ==============================================================================
#  LÓGICA PRINCIPAL
# ==============================================================================

check_svtav1

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         TRANSCODIFICADOR AV1 — i7-14700K                    ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Encoder  : libsvtav1 (SVT-AV1)                             ║"
printf "║  CRF      : %-49s║\n" "$CRF"
printf "║  Preset   : %-49s║\n" "$PRESET"
printf "║  Film Grain: %-48s║\n" "$FILM_GRAIN"
printf "║  Threads  : %-49s║\n" "$LOGICAL_PROCESSORS"
echo "║  Contenedor: MKV (forzado para máxima compatibilidad AV1)   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Buscamos archivos de vídeo:
# 1. Excluimos los que ya tienen ".byte." en el nombre (ya procesados)
# 2. Filtramos por extensiones de vídeo conocidas
find . -type f -not -iname "*.byte.*" \
    | grep -iE '\.(mp4|mkv|avi|mov|wmv|flv|webm|m4v|mpg|mpeg|3gp|ts|m2ts|vob)$' \
    | while read -r FILE; do

    DIR_NAME=$(dirname "$FILE")
    BASE_NAME=$(basename "$FILE")
    NAME_NO_EXT="${BASE_NAME%.*}"

    # Obtenemos info de pistas de subtítulos
    get_info "$FILE"

    # El archivo de salida SIEMPRE es .mkv (mejor contenedor para AV1)
    NEW_FILENAME="${NAME_NO_EXT}${SUBS_STRING}.byte.mkv"
    OUTPUT_FILE="${DIR_NAME}/${NEW_FILENAME}"

    if [ -f "$OUTPUT_FILE" ]; then
        echo "⏭️  SALTADO (ya existe): $NEW_FILENAME"
        continue
    fi

    echo "----------------------------------------------------------------"
    echo "📂 Origen  : $FILE"
    echo "🎯 Destino : $OUTPUT_FILE"
    echo "⏳ Codificando con SVT-AV1 preset ${PRESET}, CRF ${CRF}..."
    echo ""

    # shellcheck disable=SC2086
    ffmpeg -v error -stats -i "$FILE" $FFMPEG_ARGS "$OUTPUT_FILE" < /dev/null

    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        # Preservamos la fecha de modificación del archivo original
        touch -r "$FILE" "$OUTPUT_FILE"

        # Mostramos la reducción de tamaño conseguida
        ORIG_SIZE=$(du -sh "$FILE" 2>/dev/null | cut -f1)
        NEW_SIZE=$(du -sh "$OUTPUT_FILE" 2>/dev/null | cut -f1)
        echo ""
        echo "✅ COMPLETADO"
        echo "   Original : $ORIG_SIZE  →  AV1: $NEW_SIZE"
    else
        echo ""
        echo "❌ ERROR en FFmpeg (código $EXIT_CODE). Eliminando archivo incompleto..."
        rm -f "$OUTPUT_FILE"
    fi

done

echo ""
echo "════════════════════════════════════════"
echo " PROCESO COMPLETADO."
echo "════════════════════════════════════════"
echo ""