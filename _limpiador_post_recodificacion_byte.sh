#!/bin/bash

# === CONFIGURACIÓN ===
TOLERANCIA_SEG=2

# === COLORES ===
R='\033[0m';  BOLD='\033[1m'
GREEN='\033[0;32m'; YELLOW='\033[1;33m'
RED='\033[0;31m';   CYAN='\033[0;36m'
BLUE='\033[0;34m';  DIM='\033[2m'

# === ARGUMENTOS ===
TARGET_DIR="${1:-.}"
DRY_RUN=false
[[ "$2" == "--dry-run" || "$2" == "-n" ]] && DRY_RUN=true

# === VERIFICACIONES PREVIAS ===
if [ ! -d "$TARGET_DIR" ]; then
    echo -e "${RED}❌ Error: La ruta '$TARGET_DIR' no existe o no es un directorio.${R}"
    exit 1
fi

if ! command -v ffprobe &>/dev/null; then
    echo -e "${RED}❌ Error: 'ffprobe' no está instalado o no está en el PATH.${R}"
    exit 1
fi

TARGET_DIR=$(realpath "$TARGET_DIR")
LOG_FALLOS="$TARGET_DIR/errores_recodificacion.log"

# === LIMPIEZA ANTE INTERRUPCIÓN ===
TMP_BORRAR=$(mktemp)
trap 'rm -f "$TMP_BORRAR"; echo -e "\n${YELLOW}⚠️  Interrumpido. No se borró nada.${R}"; exit 1' INT TERM

> "$LOG_FALLOS"

# === VARIABLES ===
DISCREPANCIAS=0; CORRECTOS=0
TOTAL_FILES_ORIG=0; FILES_RECODIFIED=0
FILES_RECODED_WINS=0; FILES_ORIGINAL_WINS=0
SIZE_TOTAL_ORIG=0; SIZE_TOTAL_FINAL=0
SIZE_AHORRO_REAL=0
SEC_RECODIFIED=0; SEC_PENDING=0

# === FUNCIONES ===
format_time() {
    local T=$1
    printf "%02dh %02dm %02ds" $((T/3600)) $(((T%3600)/60)) $((T%60))
}

progress_bar() {
    local PCT=$1 WIDTH=28
    local FILLED=$(awk "BEGIN{printf \"%d\", $PCT * $WIDTH / 100}")
    local EMPTY=$(( WIDTH - FILLED ))
    local BAR="" EMP=""
    for ((i=0; i<FILLED; i++)); do BAR+="█"; done
    for ((i=0; i<EMPTY;  i++)); do EMP+="░"; done
    echo -e "   [${GREEN}${BAR}${R}${DIM}${EMP}${R}] ${BOLD}${PCT}%${R}"
}

# === ESCANEO PREVIO ===
echo -e "${BLUE}🔍 Escaneando archivos de vídeo...${R}"
# FIX: -iname para extensiones case-insensitive (MKV, mkv, Mkv, etc.)
#      -not -iname para excluir hermanos .byte también en cualquier capitalización
mapfile -d '' ALL_FILES < <(find "$TARGET_DIR" -type f \
    \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" \) \
    -not -iname "*.byte.*" \
    -print0 | sort -z)

TOTAL_FILES_ORIG=${#ALL_FILES[@]}

if [ "$TOTAL_FILES_ORIG" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  No se encontraron archivos de vídeo en '$TARGET_DIR'.${R}"
    rm -f "$TMP_BORRAR"; exit 0
fi

echo -e "${BOLD}═══════════════════════════════════════════════${R}"
echo -e " Ruta:  ${CYAN}$TARGET_DIR${R}"
echo -e " Total: ${BOLD}$TOTAL_FILES_ORIG archivos${R} encontrados"
$DRY_RUN && echo -e " ${CYAN}[MODO DRY-RUN — no se borrará nada]${R}"
echo -e "${BOLD}═══════════════════════════════════════════════${R}\n"

# === BUCLE PRINCIPAL ===
IDX=0
for ORIGINAL in "${ALL_FILES[@]}"; do
    ((IDX++))
    PROG="${DIM}[${IDX}/${TOTAL_FILES_ORIG}]${R}"

    S_ORIG=$(stat -c%s "$ORIGINAL")
    SIZE_TOTAL_ORIG=$((SIZE_TOTAL_ORIG + S_ORIG))

    DUR_ORIG_RAW=$(ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$ORIGINAL" 2>/dev/null)
    DUR_ORIG=$(echo "$DUR_ORIG_RAW" | awk '{print int($1 + 0.5)}')
    [ -z "$DUR_ORIG" ] && DUR_ORIG=0

    DIR_NAME=$(dirname "$ORIGINAL")
    BASE_NAME=$(basename "$ORIGINAL")
    NAME_NO_EXT="${BASE_NAME%.*}"
    EXTENSION="${BASE_NAME##*.}"

    # FIX: -iname en la búsqueda del hermano también
    HERMANO=$(find "$DIR_NAME" -maxdepth 1 \
        -iname "${NAME_NO_EXT}*.byte.${EXTENSION}" 2>/dev/null | head -n 1)

    if [ -n "$HERMANO" ] && [ -f "$HERMANO" ]; then
        ((FILES_RECODIFIED++))

        S_HERM=$(stat -c%s "$HERMANO")

        DUR_HERM_RAW=$(ffprobe -v error -show_entries format=duration \
            -of default=noprint_wrappers=1:nokey=1 "$HERMANO" 2>/dev/null)
        DUR_HERM=$(echo "$DUR_HERM_RAW" | awk '{print int($1 + 0.5)}')
        [ -z "$DUR_HERM" ] && DUR_HERM=0

        DIFF=$(( DUR_ORIG - DUR_HERM )); DIFF=${DIFF#-}

        if [ "$DIFF" -le "$TOLERANCIA_SEG" ] && [ "$DUR_ORIG" -gt 0 ]; then
            ((CORRECTOS++))
            SEC_RECODIFIED=$((SEC_RECODIFIED + DUR_ORIG))

            # FIX: awk en lugar de división entera bash para MBs decimales
            RATIO=$(awk "BEGIN{printf \"%.1f\", (1 - $S_HERM/$S_ORIG) * 100}")

            if [ "$S_HERM" -lt "$S_ORIG" ]; then
                ((FILES_RECODED_WINS++))
                DIFF_MB=$(awk "BEGIN{printf \"%.1f\", ($S_ORIG-$S_HERM)/1048576}")
                SIZE_AHORRO_REAL=$((SIZE_AHORRO_REAL + S_ORIG - S_HERM))
                echo -e "${GREEN}✅${R} $PROG ${BOLD}$BASE_NAME${R}"
                echo -e "   └─ ${GREEN}Recodificado elegido${R} · -${DIFF_MB} MB · ${RATIO}% más ligero"
                echo "$ORIGINAL" >> "$TMP_BORRAR"
                SIZE_TOTAL_FINAL=$((SIZE_TOTAL_FINAL + S_HERM))
            else
                ((FILES_ORIGINAL_WINS++))
                DIFF_MB=$(awk "BEGIN{printf \"%.1f\", ($S_HERM-$S_ORIG)/1048576}")
                echo -e "${CYAN}♻️ ${R} $PROG ${BOLD}$BASE_NAME${R}"
                echo -e "   └─ ${CYAN}Original elegido${R} · el nuevo era +${DIFF_MB} MB más pesado"
                echo "$HERMANO" >> "$TMP_BORRAR"
                SIZE_TOTAL_FINAL=$((SIZE_TOTAL_FINAL + S_ORIG))
            fi
        else
            echo -e "${RED}❌${R} $PROG ${BOLD}$BASE_NAME${R}"
            echo -e "   └─ ${RED}Duración no coincide${R} · orig: ${DUR_ORIG}s · nuevo: ${DUR_HERM}s · diff: ${DIFF}s"
            echo "Fallo duración: $ORIGINAL (orig: $DUR_ORIG_RAW, nuevo: $DUR_HERM_RAW)" >> "$LOG_FALLOS"
            ((DISCREPANCIAS++))
            SEC_PENDING=$((SEC_PENDING + DUR_ORIG))
            SIZE_TOTAL_FINAL=$((SIZE_TOTAL_FINAL + S_ORIG))
        fi
    else
        echo -e "${YELLOW}⚠️ ${R} $PROG ${BOLD}$BASE_NAME${R}"
        echo -e "   └─ ${YELLOW}Sin recodificado encontrado${R}"
        echo "Sin recodificado: $ORIGINAL" >> "$LOG_FALLOS"
        ((DISCREPANCIAS++))
        SEC_PENDING=$((SEC_PENDING + DUR_ORIG))
        SIZE_TOTAL_FINAL=$((SIZE_TOTAL_FINAL + S_ORIG))
    fi
done

# === CÁLCULOS FINALES ===
SEC_TOTAL=$((SEC_RECODIFIED + SEC_PENDING))
TIME_DONE=$(format_time $SEC_RECODIFIED)
TIME_TOTAL=$(format_time $SEC_TOTAL)

# FIX: 1073741824 en lugar de /1024/1024/1024 encadenado
GB_ORIG=$(awk  "BEGIN{printf \"%.2f\", $SIZE_TOTAL_ORIG  / 1073741824}")
GB_FINAL=$(awk "BEGIN{printf \"%.2f\", $SIZE_TOTAL_FINAL / 1073741824}")
GB_AHORRO=$(awk "BEGIN{printf \"%.2f\", $SIZE_AHORRO_REAL / 1073741824}")
PCT_AHORRO=$(awk "BEGIN{if($SIZE_TOTAL_ORIG>0) printf \"%.1f\", ($SIZE_AHORRO_REAL*100)/$SIZE_TOTAL_ORIG; else print \"0.0\"}")

# === RESUMEN ===
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${R}"
echo -e "${BOLD}           RESUMEN DE VERIFICACIÓN             ${R}"
echo -e "${BOLD}═══════════════════════════════════════════════${R}"
echo -e ""
echo -e " 📂 ${BOLD}Archivos${R}"
echo -e "   ├─ Total escaneados:     ${BOLD}$TOTAL_FILES_ORIG${R}"
echo -e "   ├─ Con recodificado:     $FILES_RECODIFIED"
echo -e "   ├─ ${GREEN}Nuevo más ligero:${R}      $FILES_RECODED_WINS"
echo -e "   ├─ ${CYAN}Original más ligero:${R}   $FILES_ORIGINAL_WINS"
echo -e "   └─ ${YELLOW}Pendientes/error:${R}      $DISCREPANCIAS"
echo ""
echo -e " 💾 ${BOLD}Espacio${R}"
echo -e "   ├─ Antes:   ${BOLD}$GB_ORIG GB${R}"
echo -e "   ├─ Después: ${BOLD}$GB_FINAL GB${R}"
echo -e "   └─ ${GREEN}Ahorro real: $GB_AHORRO GB (${PCT_AHORRO}% del total)${R}"
echo ""
echo -e " ⏱️  ${BOLD}Tiempo de contenido${R}"
echo -e "   ├─ Validado: $TIME_DONE"
echo -e "   └─ Total:    $TIME_TOTAL"

if [ "$SEC_TOTAL" -gt 0 ]; then
    PCT_T=$(awk "BEGIN{printf \"%.1f\", ($SEC_RECODIFIED*100)/$SEC_TOTAL}")
    echo ""
    echo -e " 📊 ${BOLD}Progreso${R}"
    progress_bar "$PCT_T"
fi

echo -e "${BOLD}═══════════════════════════════════════════════${R}"

if [ "$DISCREPANCIAS" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  $DISCREPANCIAS archivos pendientes o con errores → $LOG_FALLOS${R}"
elif [ "$CORRECTOS" -eq 0 ]; then
    echo -e "${YELLOW}No se encontraron parejas para verificar.${R}"
else
    echo -e "${GREEN}🎉 ¡Completado! El 100% del contenido ha sido evaluado.${R}"
fi

# === BORRADO ===
if [ "$CORRECTOS" -gt 0 ]; then
    echo ""
    TOTAL_DESCARTAR=$(wc -l < "$TMP_BORRAR")
    echo -e " Se han marcado ${BOLD}$TOTAL_DESCARTAR archivos${R} para eliminar (los más pesados de cada pareja)."

    if $DRY_RUN; then
        echo -e "${CYAN} [DRY-RUN] Se borrarían:${R}"
        while IFS= read -r F; do
            echo -e "   🗑️  $(basename "$F")"
        done < "$TMP_BORRAR"
    else
        echo -e "${YELLOW} ⚠️  Esta operación es irreversible.${R}"
        read -rp " Escribe 'SI' para confirmar el borrado: " CONFIRMACION
        echo ""
        if [ "$CONFIRMACION" == "SI" ]; then
            BORRADOS=0; ERRORES_BORRADO=0
            while IFS= read -r FILE_TO_DELETE; do
                if rm -- "$FILE_TO_DELETE" 2>/dev/null; then
                    echo -e "   ${RED}🗑️  Borrado:${R} $(basename "$FILE_TO_DELETE")"
                    ((BORRADOS++))
                else
                    echo -e "   ${RED}❌ Error al borrar:${R} $(basename "$FILE_TO_DELETE")"
                    ((ERRORES_BORRADO++))
                fi
            done < "$TMP_BORRAR"
            echo ""
            echo -e "${GREEN}✅ Limpieza completada: $BORRADOS borrados, $ERRORES_BORRADO errores.${R}"
        else
            echo -e "${RED}❌ Operación cancelada. No se borró nada.${R}"
        fi
    fi
fi

rm -f "$TMP_BORRAR"