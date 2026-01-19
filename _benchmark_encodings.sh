#!/bin/bash

# --- CONFIGURACIÓN ---
# "." significa el directorio actual donde estás ejecutando el script
DIR_BASE="."
ARCHIVO_LOG="RESULTADOS_TEST_BENCHMARK.txt"

# --- FUNCIONES ---

# Calcular SSIM (Calidad visual 0-1)
calc_ssim() {
    local original=$1
    local encoded=$2
    # Compara visualmente y extrae el valor
    ffmpeg -i "$encoded" -i "$original" -lavfi "ssim" -f null - 2>&1 | grep "SSIM" | awk -F'All:' '{print $2}' | awk -F' ' '{print $1}'
}

# Calcular porcentaje
calc_percent() {
    echo "scale=2; ($1 / $2) * 100" | bc
}

# --- INICIO ---

echo "--- INICIANDO BENCHMARK EXTENDIDO (CON FEEDBACK) ---"
echo "Directorio de búsqueda: $(pwd)"

# Seleccionar un archivo aleatorio recursivamente desde aquí
INPUT_FILE=$(find "$DIR_BASE" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" \) | shuf -n 1)

if [ -z "$INPUT_FILE" ]; then
    echo "❌ Error: No se encontraron archivos de vídeo (.mkv, .mp4, .avi)."
    exit 1
fi

FILENAME=$(basename "$INPUT_FILE")
ABS_INPUT_FILE=$(realpath "$INPUT_FILE")
ORIGINAL_SIZE=$(stat -c%s "$INPUT_FILE")
ORIGINAL_SIZE_MB=$(echo "$ORIGINAL_SIZE / 1048576" | bc)

echo "✅ Archivo seleccionado al azar: $FILENAME"
echo "📂 Ubicación: $ABS_INPUT_FILE"
echo "💾 Tamaño Original: $ORIGINAL_SIZE_MB MB"

# --- GENERAR CABECERA ---
echo "==========================================" > "$ARCHIVO_LOG"
echo "   INFORME DE TRANSCODIFICACIÓN (SWEET SPOT)" >> "$ARCHIVO_LOG"
echo "==========================================" >> "$ARCHIVO_LOG"
echo "Fecha: $(date)" >> "$ARCHIVO_LOG"
echo "Archivo: $FILENAME ($ORIGINAL_SIZE_MB MB)" >> "$ARCHIVO_LOG"
echo "Nota: Se incluye audio y subtítulos (-map 0) para peso real." >> "$ARCHIVO_LOG"
echo "==========================================" >> "$ARCHIVO_LOG"
echo "" >> "$ARCHIVO_LOG"

# ==========================================
#  TESTS DE GRÁFICA (NVENC - GTX 1050)
# ==========================================

# --- TEST 1: NVENC Estándar (CQ 24) ---
OUTPUT="test_nvenc_cq24.mkv"
echo "1. 🚀 NVENC (Calidad - CQ 24)..."
START=$SECONDS
# AÑADIDO: -stats para ver progreso
ffmpeg -y -hide_banner -loglevel error -stats -i "$ABS_INPUT_FILE" -map 0 -c:v hevc_nvenc -preset slow -rc constqp -qp 24 -spatial_aq 1 -c:a copy -c:s copy "$OUTPUT"
DUR=$((SECONDS - START))

SIZE=$(stat -c%s "$OUTPUT")
SIZE_MB=$(echo "$SIZE / 1048576" | bc)
PERC=$(calc_percent $SIZE $ORIGINAL_SIZE)
echo "   -> Calculando SSIM..."
SSIM=$(calc_ssim "$ABS_INPUT_FILE" "$OUTPUT")

echo "FORMATO: NVENC (CQ 24 - Calidad)" >> "$ARCHIVO_LOG"
echo "  - Tiempo:      $DUR s" >> "$ARCHIVO_LOG"
echo "  - Tamaño:      $SIZE_MB MB ($PERC%)" >> "$ARCHIVO_LOG"
echo "  - SSIM:        $SSIM" >> "$ARCHIVO_LOG"
echo "------------------------------------------" >> "$ARCHIVO_LOG"

# --- TEST 2: NVENC Ahorro (CQ 29) ---
OUTPUT="test_nvenc_cq29.mkv"
echo "2. 🚀 NVENC (Ahorro - CQ 29)..."
START=$SECONDS
ffmpeg -y -hide_banner -loglevel error -stats -i "$ABS_INPUT_FILE" -map 0 -c:v hevc_nvenc -preset slow -rc constqp -qp 29 -spatial_aq 1 -c:a copy -c:s copy "$OUTPUT"
DUR=$((SECONDS - START))

SIZE=$(stat -c%s "$OUTPUT")
SIZE_MB=$(echo "$SIZE / 1048576" | bc)
PERC=$(calc_percent $SIZE $ORIGINAL_SIZE)
echo "   -> Calculando SSIM..."
SSIM=$(calc_ssim "$ABS_INPUT_FILE" "$OUTPUT")

echo "FORMATO: NVENC (CQ 29 - Ahorro)" >> "$ARCHIVO_LOG"
echo "  - Tiempo:      $DUR s" >> "$ARCHIVO_LOG"
echo "  - Tamaño:      $SIZE_MB MB ($PERC%)" >> "$ARCHIVO_LOG"
echo "  - SSIM:        $SSIM" >> "$ARCHIVO_LOG"
echo "------------------------------------------" >> "$ARCHIVO_LOG"


# ==========================================
#  TESTS DE PROCESADOR (CPU - x265)
# ==========================================

# --- TEST 3: x265 Medium (Referencia) ---
OUTPUT="test_x265_med.mkv"
echo "3. 🐢 x265 (Referencia - Medium)..."
START=$SECONDS
ffmpeg -y -hide_banner -loglevel error -stats -i "$ABS_INPUT_FILE" -map 0 -c:v libx265 -crf 24 -preset medium -c:a copy -c:s copy "$OUTPUT"
DUR=$((SECONDS - START))

SIZE=$(stat -c%s "$OUTPUT")
SIZE_MB=$(echo "$SIZE / 1048576" | bc)
PERC=$(calc_percent $SIZE $ORIGINAL_SIZE)
echo "   -> Calculando SSIM..."
SSIM=$(calc_ssim "$ABS_INPUT_FILE" "$OUTPUT")

echo "FORMATO: x265 (Medium - Referencia)" >> "$ARCHIVO_LOG"
echo "  - Tiempo:      $DUR s" >> "$ARCHIVO_LOG"
echo "  - Tamaño:      $SIZE_MB MB ($PERC%)" >> "$ARCHIVO_LOG"
echo "  - SSIM:        $SSIM" >> "$ARCHIVO_LOG"
echo "------------------------------------------" >> "$ARCHIVO_LOG"

# --- TEST 4: x265 Fast (Velocidad) ---
OUTPUT="test_x265_fast.mkv"
echo "4. 🐇 x265 (Rápido - Fast)..."
START=$SECONDS
ffmpeg -y -hide_banner -loglevel error -stats -i "$ABS_INPUT_FILE" -map 0 -c:v libx265 -crf 24 -preset fast -c:a copy -c:s copy "$OUTPUT"
DUR=$((SECONDS - START))

SIZE=$(stat -c%s "$OUTPUT")
SIZE_MB=$(echo "$SIZE / 1048576" | bc)
PERC=$(calc_percent $SIZE $ORIGINAL_SIZE)
echo "   -> Calculando SSIM..."
SSIM=$(calc_ssim "$ABS_INPUT_FILE" "$OUTPUT")

echo "FORMATO: x265 (Fast - Velocidad)" >> "$ARCHIVO_LOG"
echo "  - Tiempo:      $DUR s" >> "$ARCHIVO_LOG"
echo "  - Tamaño:      $SIZE_MB MB ($PERC%)" >> "$ARCHIVO_LOG"
echo "  - SSIM:        $SSIM" >> "$ARCHIVO_LOG"
echo "------------------------------------------" >> "$ARCHIVO_LOG"


# ==========================================
#  TESTS DE AV1 (CPU)
# ==========================================

# --- TEST 5: AV1 Preset 6 (El verdadero AV1) ---
OUTPUT="test_av1_p6.mkv"
echo "5. 🐌 AV1 (Eficiente - Preset 6)..."
START=$SECONDS
ffmpeg -y -hide_banner -loglevel error -stats -i "$ABS_INPUT_FILE" -map 0 -c:v libsvtav1 -crf 26 -preset 6 -c:a copy -c:s copy "$OUTPUT"
DUR=$((SECONDS - START))

SIZE=$(stat -c%s "$OUTPUT")
SIZE_MB=$(echo "$SIZE / 1048576" | bc)
PERC=$(calc_percent $SIZE $ORIGINAL_SIZE)
echo "   -> Calculando SSIM..."
SSIM=$(calc_ssim "$ABS_INPUT_FILE" "$OUTPUT")

echo "FORMATO: AV1 (Preset 6 - Balanceado)" >> "$ARCHIVO_LOG"
echo "  - Tiempo:      $DUR s" >> "$ARCHIVO_LOG"
echo "  - Tamaño:      $SIZE_MB MB ($PERC%)" >> "$ARCHIVO_LOG"
echo "  - SSIM:        $SSIM" >> "$ARCHIVO_LOG"
echo "------------------------------------------" >> "$ARCHIVO_LOG"


# ==========================================
#  CONCLUSIONES
# ==========================================
echo "" >> "$ARCHIVO_LOG"
echo "=== CONCLUSIÓN AUTOMÁTICA ===" >> "$ARCHIVO_LOG"
# Extraemos el ganador de tamaño y tiempo usando sort
GANADOR_TAMANO=$(grep "Tamaño:" "$ARCHIVO_LOG" | sort -n -k3 | head -1)
GANADOR_TIEMPO=$(grep "Tiempo:" "$ARCHIVO_LOG" | sort -n -k3 | head -1)

echo "🏆 MEJOR COMPRESIÓN: $GANADOR_TAMANO" >> "$ARCHIVO_LOG"
echo "🏎️  MÁS RÁPIDO:      $GANADOR_TIEMPO" >> "$ARCHIVO_LOG"

echo ""
echo "✅ ¡Test finalizado!" 
echo "Resultados guardados en: $ARCHIVO_LOG"
echo "Ábrelo para ver quién ganó."