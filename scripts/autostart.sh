#!/usr/bin/env bash
# Activa o desactiva que RPi TV Box se abra solo al iniciar sesión.
#
#   ./scripts/autostart.sh on       se abre solo al encender
#   ./scripts/autostart.sh off      no se abre solo (ábrelo desde el menú del escritorio)
#   ./scripts/autostart.sh status   muestra cómo está
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUTOSTART="$HOME/.config/labwc/autostart"
LINE="$ROOT/scripts/start.sh &"

case "${1:-status}" in
    on)
        mkdir -p "$(dirname "$AUTOSTART")"
        touch "$AUTOSTART"
        grep -qF "$ROOT/scripts/start.sh" "$AUTOSTART" || echo "$LINE" >> "$AUTOSTART"
        echo "Arranque automático ACTIVADO (se aplica al próximo inicio de sesión)."
        ;;
    off)
        if [ -f "$AUTOSTART" ]; then
            # Borra solo nuestra línea; el resto del archivo no se toca.
            grep -vF "$ROOT/scripts/start.sh" "$AUTOSTART" > "$AUTOSTART.tmp" || true
            mv "$AUTOSTART.tmp" "$AUTOSTART"
        fi
        echo "Arranque automático DESACTIVADO. Ábrelo desde Menú > Sonido y vídeo > RPi TV Box."
        ;;
    status)
        if [ -f "$AUTOSTART" ] && grep -qF "$ROOT/scripts/start.sh" "$AUTOSTART"; then
            echo "Arranque automático: activado"
        else
            echo "Arranque automático: desactivado"
        fi
        ;;
    *)
        echo "Uso: $0 on|off|status"; exit 1 ;;
esac
