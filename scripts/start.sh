#!/usr/bin/env bash
# Arranca el lanzador RPi TV Box. Si se cierra o falla, vuelve a arrancarlo.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY="$ROOT/.venv/bin/python"
[ -x "$PY" ] || PY=python3

cd "$ROOT/launcher"
while true; do
    "$PY" -m rpitvbox "$@"
    rc=$?
    # Salida limpia (rc 0) = el usuario quiso cerrar el lanzador.
    [ "$rc" -eq 0 ] && break
    echo "[rpitvbox] el lanzador terminó con código $rc, reiniciando en 2 s" >&2
    sleep 2
done
