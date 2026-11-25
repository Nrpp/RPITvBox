#!/usr/bin/env bash
# Registra la RPi en el bus HDMI-CEC como "reproductor" para que el mando de la
# TV le envíe las teclas. El kernel las convierte en eventos de teclado normales.
#
#   cec-setup.sh           solo registrarse (arranque)
#   cec-setup.sh --active  además pedir a la TV que muestre esta entrada HDMI
#                          (se usa al volver de Kodi, que al salir suele liberar
#                          el CEC y la TV — p. ej. Sony Google TV — cambia de entrada)
set -u
NAME="${RPITVBOX_CEC_NAME:-RPi TV}"
ACTIVE=0
[ "${1:-}" = "--active" ] && ACTIVE=1

for dev in /dev/cec*; do
    [ -e "$dev" ] || continue
    cec-ctl -d "$dev" --playback --osd-name "$NAME" >/dev/null 2>&1 || continue
    echo "CEC configurado en $dev"
    [ "$ACTIVE" -eq 1 ] || continue
    # Dirección física de este puerto HDMI de la TV (p. ej. 3.0.0.0).
    pa="$(cec-ctl -d "$dev" 2>/dev/null | awk -F': ' '/Physical Address/ {print $2; exit}' | tr -d ' ')"
    if [ -n "$pa" ] && [ "$pa" != "f.f.f.f" ]; then
        cec-ctl -d "$dev" --to 0 --image-view-on >/dev/null 2>&1
        cec-ctl -d "$dev" --to 15 --active-source "phys-addr=$pa" >/dev/null 2>&1 \
            && echo "  entrada activa: $pa"
    fi
done
