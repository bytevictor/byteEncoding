#!/bin/bash

# --- CONFIGURACIÓN ---
DIR_BASE="."
ARCHIVO_LOG="_RESULTADOS_TEST_COMPRESION.txt"

# --- FUNCIONES ---

calc_ssim() {
    local original=$1
    local encoded=$2
    if [ ! -f "$encoded" ]; then echo "0"; return; fi
    # Filtro SSIM para medir calidad objetiva
    ffmpeg -i "$encoded" -i "$original" -lavfi "ssim" -f null - 2>&1 | grep "SSIM" | awk -F'All:' '{print $2}' | awk -F' ' '{print $1}'
}

calc_percent() {
    # $1 = Tamaño Nuevo, $2 = Tamaño Referencia
    echo "scale=2; ($1 / $2) * 100" | bc
}

# --- INICIO ---

echo "--- INICIANDO BENCHMARK (ENFOQUE: TAMAÑO MÍNIMO) ---"

# 1. Seleccionar archivo al azar
INPUT_FILE=$(find "$DIR_BASE" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" \) | shuf -n 1)

if [ -z "$INPUT_FILE" ]; then
    echo "❌ Error: No se encontraron archivos."
    exit 1
fi

FILENAME=$(basename "$INPUT_FILE")
ABS_INPUT_FILE=$(realpath "$INPUT_FILE")

echo "✅ Archivo origen: $FILENAME"

# 2. GENERAR CLIP DE REFERENCIA (1 Minuto)
# Esto es vital para que el cálculo del % sea real.
echo "✂️  Generando 'Clip Maestro' de 1 minuto (del 05:00 al 06:00) para comparar..."
REF_FILE="reference_source.mkv"
ffmpeg -y -hide_banner -loglevel error -ss 00:05:00 -t 60 -i "$ABS_INPUT_FILE" -map 0 -c copy "$REF_FILE"

if [ ! -f "$REF_FILE" ]; then
    echo "❌ Error al crear el clip de referencia."
    exit 1
fi

REF_SIZE=$(stat -c%s "$REF_FILE")
REF_SIZE_MB=$(echo "scale=2; $REF_SIZE / 1048576" | bc)

echo "💾 Tamaño del Clip Maestro: $REF_SIZE_MB MB"
echo "--------------------------------------------------------"


# ==========================================
#  CABECERA Y LEYENDA
# ==========================================

echo "RESULTADOS DE COMPRESIÓN - $(date)" > "$ARCHIVO_LOG"
echo "Archivo original (Clip 1m): $REF_SIZE_MB MB" >> "$ARCHIVO_LOG"

cat <<EOF >> "$ARCHIVO_LOG"

==================================================================
 GUÍA RÁPIDA DE INTERPRETACIÓN
==================================================================
1. TAMAÑO: Menos es mejor.
2. % ORIGINAL: Porcentaje real de reducción (ej: 20% significa que ocupa una quinta parte).
3. SSIM (Calidad): 1.0 es perfecto. Buscamos > 0.94.
==================================================================
RESULTADOS DETALLADOS:
==================================================================
EOF

# ==========================================
#  MOTOR DE TESTS
# ==========================================

run_test() {
    local NAME=$1
    local OUTPUT=$2
    local CMD_FLAGS=$3

    echo "👉 Probando: $NAME ..."
    START=$SECONDS
    
    # Ejecutamos FFmpeg usando el REF_FILE como input
    # IMPORTANTE: Quitamos -ss y -t porque el input ya dura 1 min
    ffmpeg -y -hide_banner -loglevel warning -stats \
        -i "$REF_FILE" \
        $CMD_FLAGS \
        "$OUTPUT"
    
    RET_CODE=$?
    DUR=$((SECONDS - START))

    if [ $RET_CODE -ne 0 ] || [ ! -f "$OUTPUT" ]; then
        echo "❌ FALLÓ: $NAME"
        echo "$NAME: FALLÓ" >> "$ARCHIVO_LOG"
        return
    fi

    SIZE=$(stat -c%s "$OUTPUT")
    SIZE_MB=$(echo "scale=2; $SIZE / 1048576" | bc)
    
    # Calculamos porcentaje respecto al CLIP MAESTRO
    PERC=$(calc_percent $SIZE $REF_SIZE)
    
    echo "   -> Calculando SSIM..."
    SSIM=$(calc_ssim "$REF_FILE" "$OUTPUT")

    echo "   ✅ $SIZE_MB MB ($PERC%) | Tiempo: ${DUR}s | SSIM: $SSIM"
    echo "-------------------------------------"
    
    echo "FORMATO: $NAME" >> "$ARCHIVO_LOG"
    echo "  - Tiempo: $DUR s" >> "$ARCHIVO_LOG"
    echo "  - Tamaño: $SIZE_MB MB ($PERC% del original)" >> "$ARCHIVO_LOG"
    echo "  - SSIM:   $SSIM" >> "$ARCHIVO_LOG"
    echo "------------------------------------------" >> "$ARCHIVO_LOG"
}

# ==========================================
#  0. CATA RÁPIDA (BUSCANDO EL CQ PERFECTO)
# ==========================================

# NOTA: He quitado "-ss 00:05:00 -t 60" de los comandos de abajo
# porque ahora el input ("reference_source.mkv") YA ES el clip de 1 minuto.

run_test "TEST RÁPIDO - CQ 29" "test_cq29.mkv" \
    "-map 0 -c:v hevc_nvenc -preset slow -rc vbr_hq -cq 29 -b:v 0 -spatial_aq 1 -rc-lookahead 32 -c:a aac -b:a 128k -ac 2 -c:s copy"

run_test "TEST RÁPIDO - CQ 31" "test_cq31.mkv" \
    "-map 0 -c:v hevc_nvenc -preset slow -rc vbr_hq -cq 31 -b:v 0 -spatial_aq 1 -rc-lookahead 32 -c:a aac -b:a 128k -ac 2 -c:s copy"

run_test "TEST RÁPIDO - CQ 33" "test_cq33.mkv" \
    "-map 0 -c:v hevc_nvenc -preset slow -rc vbr_hq -cq 33 -b:v 0 -spatial_aq 1 -rc-lookahead 32 -c:a aac -b:a 128k -ac 2 -c:s copy"


# ==========================================
#  1. NVENC (TUS CANDIDATOS PASCAL)
# ==========================================

run_test "NVENC (Pascal Native - CQ 32)" "nvenc_pascal_cq32.mkv" \
    "-map 0 -c:v hevc_nvenc -preset slow -rc vbr_hq -cq 32 -b:v 0 -spatial_aq 1 -rc-lookahead 32 -c:a aac -b:a 128k -ac 2 -c:s copy"

run_test "NVENC (QP 32 - Fuerza Bruta)" "nvenc_qp32.mkv" \
    "-map 0 -c:v hevc_nvenc -preset slow -rc constqp -qp 32 -spatial_aq 1 -c:a aac -b:a 128k -ac 2 -c:s copy"

run_test "NVENC (VBR Smart - CQ 30)" "nvenc_vbr_cq30.mkv" \
    "-map 0 -c:v hevc_nvenc -preset slow -rc vbr_hq -cq 30 -b:v 0 -spatial_aq 1 -c:a aac -b:a 128k -ac 2 -c:s copy"

run_test "NVENC (VBR Smart - CQ 34)" "nvenc_vbr_cq34.mkv" \
    "-map 0 -c:v hevc_nvenc -preset slow -rc vbr_hq -cq 34 -b:v 0 -spatial_aq 1 -c:a aac -b:a 128k -ac 2 -c:s copy"


# ==========================================
#  2. x265 (CPU - REFERENCIA)
# ==========================================

run_test "x265 (Medium - CRF 28)" "x265_med_crf28.mkv" \
    "-map 0 -c:v libx265 -crf 28 -preset medium -c:a aac -b:a 128k -ac 2 -c:s copy"

run_test "x265 (SLOW - CRF 28)" "x265_slow_crf28.mkv" \
    "-map 0 -c:v libx265 -crf 28 -preset slow -c:a aac -b:a 128k -ac 2 -c:s copy"

run_test "x265 (SLOW - CRF 32 - Tiny)" "x265_slow_crf32.mkv" \
    "-map 0 -c:v libx265 -crf 32 -preset slow -c:a aac -b:a 128k -ac 2 -c:s copy"


# ==========================================
#  3. AV1 (FUTURO)
# ==========================================

run_test "AV1 (Preset 6 - CRF 30)" "av1_p6_crf30.mkv" \
    "-map 0 -c:v libsvtav1 -crf 30 -preset 6 -c:a aac -b:a 128k -ac 2 -c:s copy"

run_test "AV1 (Preset 6 - CRF 35)" "av1_p6_crf35.mkv" \
    "-map 0 -c:v libsvtav1 -crf 35 -preset 6 -c:a aac -b:a 128k -ac 2 -c:s copy"

run_test "AV1 (Preset 4 - CRF 32 - MAX EFICIENCIA)" "av1_p4_crf32.mkv" \
    "-map 0 -c:v libsvtav1 -crf 32 -preset 4 -c:a aac -b:a 128k -ac 2 -c:s copy"

# ==========================================
#  LIMPIEZA Y FIN
# ==========================================

# Borrar el clip de referencia si quieres ahorrar espacio
# rm "$REF_FILE"

echo ""
echo "✅ Benchmark finalizado."
echo "📄 Resultados guardados en: $ARCHIVO_LOG"
echo "--- TOP 3 GANADORES POR TAMAÑO ---"
grep "Tamaño:" "$ARCHIVO_LOG" | sort -n -k3 | head -n 3