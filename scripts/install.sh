#!/usr/bin/env bash
# Instalador de RPi TV Box para Raspberry Pi OS (Desktop, 64 bits) en RPi 4 / 5.
#
#   ./scripts/install.sh               instalación completa
#   ./scripts/install.sh --no-airplay  sin receptor AirPlay
#   ./scripts/install.sh --no-spotify-connect
#   ./scripts/install.sh --keep-resolution   no forzar 1080p en la RPi 4
#   ./scripts/install.sh --no-autostart      no abrir el menú solo al encender
#
# Ejecutar como el usuario normal (no root); pedirá sudo cuando haga falta.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADDONS_DIR="$HOME/rpitvbox-addons"
WANT_AIRPLAY=1
WANT_SPOTIFY_CONNECT=1
FORCE_1080P=1
WANT_AUTOSTART=1
for arg in "$@"; do
    case "$arg" in
        --no-airplay) WANT_AIRPLAY=0 ;;
        --no-spotify-connect) WANT_SPOTIFY_CONNECT=0 ;;
        --keep-resolution) FORCE_1080P=0 ;;
        --no-autostart) WANT_AUTOSTART=0 ;;
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
# Siempre el Python del sistema: es el que ve los paquetes de apt (python3-evdev).
# Un python3 de Homebrew/pyenv/conda en el PATH no los ve y obliga a compilar.
SYS_PY=/usr/bin/python3
if [ -f "$ROOT/.venv/pyvenv.cfg" ] && ! grep -q '^home = /usr/bin$' "$ROOT/.venv/pyvenv.cfg"; then
    echo "  el .venv existente usa otro Python ($(grep '^home' "$ROOT/.venv/pyvenv.cfg")), se recrea"
    rm -rf "$ROOT/.venv"
fi
"$SYS_PY" -m venv --system-site-packages "$ROOT/.venv"
"$ROOT/.venv/bin/python" -m pip install --upgrade pip
"$ROOT/.venv/bin/python" -m pip install -r "$ROOT/requirements.txt"
if ! "$ROOT/.venv/bin/python" -c "import evdev" 2>/dev/null; then
    warn "python3-evdev no disponible: el botón Inicio global no funcionará (el resto sí)"
fi

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
MODEL="$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || true)"
if [ "$FORCE_1080P" -eq 1 ] && [[ "$MODEL" == *"Raspberry Pi 4"* ]]; then
    step "RPi 4 + TV 4K: salida HDMI fija a 1080p60 (más fluido)"
    CMDLINE=/boot/firmware/cmdline.txt
    [ -f "$CMDLINE" ] || CMDLINE=/boot/cmdline.txt
    if grep -q 'video=HDMI-A-1:' "$CMDLINE"; then
        echo "  ya había una resolución configurada en $CMDLINE, no la toco"
    else
        sudo cp "$CMDLINE" "$CMDLINE.rpitvbox.bak"
        # cmdline.txt es una sola línea: añadimos el parámetro al final.
        sudo sed -i '1 s/$/ video=HDMI-A-1:1920x1080@60/' "$CMDLINE"
        echo "  añadido video=HDMI-A-1:1920x1080@60 (copia en $CMDLINE.rpitvbox.bak)"
    fi
fi

# ---------------------------------------------------------------------------
step "Acceso en el menú del escritorio"
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/rpitvbox.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=RPi TV Box
Comment=Menú de apps estilo TV
Exec=$ROOT/scripts/start.sh
Icon=video-display
Categories=AudioVideo;
DESKTOP
echo "  Menú > Sonido y vídeo > RPi TV Box"

step "Arranque automático al iniciar sesión"
if [ "$WANT_AUTOSTART" -eq 1 ]; then
    "$ROOT/scripts/autostart.sh" on
    echo "  Para que sea como una caja de TV, activa también el inicio de sesión automático:"
    echo "  sudo raspi-config > System Options > Boot / Auto Login > Desktop Autologin"
else
    "$ROOT/scripts/autostart.sh" off
fi
echo "  Cambiarlo cuando quieras: ./scripts/autostart.sh on | off"

cat <<MSG

$(printf '\033[1;32m')Instalación terminada.$(printf '\033[0m')

Siguiente paso (una sola vez, con el mando o un teclado) — ver README, sección
"Configurar los addons en Kodi":
  1. Abre Kodi > Ajustes > Sistema > Add-ons > activa "Orígenes desconocidos".
  2. Add-ons > Instalar desde archivo zip > $ADDONS_DIR
  3. Instala Netflix, Amazon VOD (Prime Video), YouTube y Spotify.

Después reinicia: sudo reboot
MSG
