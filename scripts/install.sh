#!/usr/bin/env bash
# Instalador de RPi TV Box para Raspberry Pi OS (Desktop, 64 bits) en RPi 4 / 5.
#
#   ./scripts/install.sh               instalación completa
#   ./scripts/install.sh --no-airplay  sin receptor AirPlay
#   ./scripts/install.sh --no-spotify-connect
#
# Ejecutar como el usuario normal (no root); pedirá sudo cuando haga falta.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADDONS_DIR="$HOME/rpitvbox-addons"
WANT_AIRPLAY=1
WANT_SPOTIFY_CONNECT=1
for arg in "$@"; do
    case "$arg" in
        --no-airplay) WANT_AIRPLAY=0 ;;
        --no-spotify-connect) WANT_SPOTIFY_CONNECT=0 ;;
        *) echo "Opción desconocida: $arg"; exit 1 ;;
    esac
done

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }

if [ "$(id -u)" -eq 0 ]; then
    echo "Ejecuta este script como tu usuario normal, no como root."; exit 1
fi

# ---------------------------------------------------------------------------
step "Paquetes del sistema (Kodi, DRM, CEC, Python)"
sudo apt-get update
sudo apt-get install -y \
    kodi kodi-inputstream-adaptive kodi-peripheral-joystick \
    python3-venv python3-evdev python3-pycryptodome \
    v4l-utils curl unzip
if [ "$WANT_AIRPLAY" -eq 1 ]; then
    sudo apt-get install -y shairport-sync
fi

# ---------------------------------------------------------------------------
step "Entorno Python del lanzador (.venv con PySide6)"
python3 -m venv --system-site-packages "$ROOT/.venv"
"$ROOT/.venv/bin/pip" install --upgrade pip
"$ROOT/.venv/bin/pip" install -r "$ROOT/requirements.txt"

# ---------------------------------------------------------------------------
step "Permisos para leer el mando (grupo input)"
sudo usermod -aG input "$USER"

# ---------------------------------------------------------------------------
step "Mando de la TV por HDMI-CEC"
sed "s#@ROOT@#$ROOT#g" "$ROOT/systemd/rpitvbox-cec.service" \
    | sudo tee /etc/systemd/system/rpitvbox-cec.service >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable --now rpitvbox-cec.service || warn "No se pudo activar CEC (¿TV apagada o sin CEC?)"

# ---------------------------------------------------------------------------
step "Atajo de Kodi: botón Inicio = volver al menú"
mkdir -p "$HOME/.kodi/userdata/keymaps"
cp "$ROOT/config/kodi/rpitvbox-keymap.xml" "$HOME/.kodi/userdata/keymaps/"

# ---------------------------------------------------------------------------
step "Descargando repositorios de addons en $ADDONS_DIR"
mkdir -p "$ADDONS_DIR"
# Descarga el .zip más reciente que aparezca en una página índice.
latest_zip() {  # $1 = URL índice, $2 = prefijo del zip
    curl -fsSL "$1" | grep -o "href=\"$2[^\"]*\.zip\"" | sed 's/href="//;s/"$//' \
        | sort -V | tail -n1
}
fetch_latest() {  # $1 = URL índice (acabada en /), $2 = prefijo
    local z
    if z="$(latest_zip "$1" "$2")" && [ -n "$z" ]; then
        curl -fsSL -o "$ADDONS_DIR/$z" "$1$z" && echo "  ok  $z"
    else
        warn "No se pudo descargar $2 desde $1 (descárgalo a mano, ver README)"
    fi
}
# Netflix (CastagnaIT)
fetch_latest "https://castagnait.github.io/repository.castagnait/" "repository.castagnait"
# Spotify para Kodi (glk1001)
fetch_latest "https://glk1001.github.io/" "plugin.audio.spotify"
# Prime Video (Sandmann79): repositorio publicado en GitHub releases
SANDMANN_URL="$(curl -fsSL https://api.github.com/repos/Sandmann79/xbmc/releases/latest 2>/dev/null \
    | grep -o '"browser_download_url": *"[^"]*repository[^"]*\.zip"' | head -n1 | sed 's/.*"\(http[^"]*\)"/\1/')" || true
if [ -n "${SANDMANN_URL:-}" ]; then
    curl -fsSL -o "$ADDONS_DIR/$(basename "$SANDMANN_URL")" "$SANDMANN_URL" && echo "  ok  $(basename "$SANDMANN_URL")"
else
    warn "No se pudo descargar el repositorio de Sandmann79 (Prime Video). Ver README."
fi

# ---------------------------------------------------------------------------
if [ "$WANT_SPOTIFY_CONNECT" -eq 1 ]; then
    step "Spotify Connect (raspotify): la RPi aparece como altavoz en la app de Spotify"
    if ! dpkg -s raspotify >/dev/null 2>&1; then
        curl -fsSL https://dtcooper.github.io/raspotify/install.sh | sh \
            || warn "No se pudo instalar raspotify"
    fi
    if [ -f /etc/raspotify/conf ]; then
        sudo sed -i 's/^#\?LIBRESPOT_NAME=.*/LIBRESPOT_NAME="RPi TV"/' /etc/raspotify/conf
        sudo systemctl restart raspotify || true
    fi
fi

if [ "$WANT_AIRPLAY" -eq 1 ]; then
    step "AirPlay (shairport-sync): envía Apple Music desde el iPhone"
    sudo sed -E -i '0,/^(\/\/)?\s*name = /s//\tname = "RPi TV"; \/\/ /' /etc/shairport-sync.conf || true
    sudo systemctl enable --now shairport-sync || warn "No se pudo arrancar shairport-sync"
fi

# ---------------------------------------------------------------------------
step "Arranque automático al iniciar sesión (labwc / Wayland)"
AUTOSTART="$HOME/.config/labwc/autostart"
mkdir -p "$(dirname "$AUTOSTART")"
touch "$AUTOSTART"
LINE="$ROOT/scripts/start.sh &"
grep -qF "$ROOT/scripts/start.sh" "$AUTOSTART" || echo "$LINE" >> "$AUTOSTART"
echo "  añadido a $AUTOSTART"
echo "  Activa el inicio de sesión automático: sudo raspi-config > System > Boot / Auto login > Desktop Autologin"

cat <<MSG

$(printf '\033[1;32m')Instalación terminada.$(printf '\033[0m')

Siguiente paso (una sola vez, con el mando o un teclado) — ver README, sección
"Configurar los addons en Kodi":
  1. Abre Kodi > Ajustes > Sistema > Add-ons > activa "Orígenes desconocidos".
  2. Add-ons > Instalar desde archivo zip > $ADDONS_DIR
  3. Instala Netflix, Amazon VOD (Prime Video), YouTube y Spotify.

Después reinicia: sudo reboot
MSG
