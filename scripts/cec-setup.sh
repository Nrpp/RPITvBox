#!/usr/bin/env bash
# Registra la RPi en el bus HDMI-CEC como "reproductor" para que el mando de la
# TV le envíe las teclas. El kernel las convierte en eventos de teclado normales.
set -u
NAME="${RPITVBOX_CEC_NAME:-RPi TV}"
for dev in /dev/cec*; do
    [ -e "$dev" ] || continue
    cec-ctl -d "$dev" --playback --osd-name "$NAME" >/dev/null 2>&1 \
        && echo "CEC configurado en $dev"
done
