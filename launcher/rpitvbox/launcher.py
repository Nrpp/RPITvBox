"""Arranque y control de las apps (Kodi, addons de Kodi y comandos nativos)."""
from __future__ import annotations

import json
import os
import shutil
import socket
import signal
import subprocess
from pathlib import Path

from PySide6.QtCore import QObject, QTimer, Signal, Slot, Property

KODI_HOME = Path(os.environ.get("KODI_HOME", Path.home() / ".kodi"))


def kodi_rpc(method: str, params: dict | None = None, timeout: float = 2.0) -> dict | None:
    """Llama a la API JSON-RPC de Kodi por TCP (localhost:9090).

    Requiere en Kodi: Ajustes > Servicios > Control > "Permitir el control
    remoto desde aplicaciones de este sistema" (activado por defecto).
    Devuelve None si Kodi todavía no escucha.
    """
    req = {"jsonrpc": "2.0", "id": 1, "method": method}
    if params:
        req["params"] = params
    try:
        with socket.create_connection(("127.0.0.1", 9090), timeout=timeout) as sock:
            sock.sendall(json.dumps(req).encode())
            buf = b""
            while True:
                chunk = sock.recv(65536)
                if not chunk:
                    break
                buf += chunk
                try:
                    return json.loads(buf)
                except ValueError:
                    continue  # respuesta incompleta, seguir leyendo
    except OSError:
        return None
    return None


def kodi_binary() -> str | None:
    return shutil.which("kodi") or shutil.which("kodi-standalone")


def addon_installed(addon_id: str) -> bool:
    return (KODI_HOME / "addons" / addon_id).is_dir()


def is_available(app: dict) -> bool:
    kind = app["type"]
    if kind == "kodi":
        return kodi_binary() is not None
    if kind == "kodi-addon":
        return kodi_binary() is not None and addon_installed(app["addon"])
    if kind == "command":
        check = app.get("check") or app["command"][0]
        return shutil.which(check) is not None
    return False


class AppLauncher(QObject):
    """Lanza una app cada vez y avisa a la interfaz cuando termina."""

    runningChanged = Signal()
    appFinished = Signal(str)
    message = Signal(str)

    def __init__(self, apps: list[dict], parent=None):
        super().__init__(parent)
        self._apps = {a["id"]: a for a in apps}
        self._proc: subprocess.Popen | None = None
        self._running_id = ""
        self._pending_addon: str | None = None
        self._addon_tries = 0

        self._poll = QTimer(self)
        self._poll.setInterval(500)
        self._poll.timeout.connect(self._check_process)

        self._addon_timer = QTimer(self)
        self._addon_timer.setInterval(1500)
        self._addon_timer.timeout.connect(self._send_run_addon)

    # --- propiedades para QML -------------------------------------------
    def _get_running(self) -> str:
        return self._running_id

    runningApp = Property(str, _get_running, notify=runningChanged)

    @Slot(str, result=bool)
    def available(self, app_id: str) -> bool:
        app = self._apps.get(app_id)
        return bool(app) and is_available(app)

    # --- lanzar / cerrar --------------------------------------------------
    @Slot(str)
    def launch(self, app_id: str) -> None:
        app = self._apps.get(app_id)
        if not app:
            return
        if self._proc is not None:
            self.message.emit("Ya hay una app abierta")
            return
        if not is_available(app):
            self.message.emit(f"{app['name']} no está instalada. {app.get('install_hint', '')}")
            return

        kind = app["type"]
        if kind in ("kodi", "kodi-addon"):
            cmd = [kodi_binary()]
            if kind == "kodi-addon":
                self._pending_addon = app["addon"]
                self._addon_tries = 0
        else:
            cmd = list(app["command"])

        try:
            # Nueva sesión de procesos para poder cerrar la app con todos sus hijos.
            self._proc = subprocess.Popen(cmd, start_new_session=True)
        except OSError as exc:
            self.message.emit(f"No se pudo abrir {app['name']}: {exc}")
            self._pending_addon = None
            return

        self._running_id = app_id
        self.runningChanged.emit()
        self._poll.start()
        if self._pending_addon:
            self._addon_timer.start()

    @Slot()
    def closeRunning(self) -> None:
        """Botón Inicio: cierra la app abierta y vuelve al menú."""
        if self._proc is None:
            return
        if self._running_id and self._apps[self._running_id]["type"] != "command":
            # Pide a Kodi que salga limpiamente; si no, se mata tras 4 s.
            if kodi_rpc("Application.Quit") is None:
                self._signal(signal.SIGTERM)
        else:
            self._signal(signal.SIGTERM)
        proc = self._proc
        QTimer.singleShot(4000, lambda: self._signal(signal.SIGKILL, proc))

    def _signal(self, sig, proc: subprocess.Popen | None = None) -> None:
        proc = proc or self._proc
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(proc.pid, sig)
            except ProcessLookupError:
                pass

    # --- internos ---------------------------------------------------------
    def _send_run_addon(self) -> None:
        # Kodi tarda unos segundos en arrancar; esperamos a que responda al ping.
        if not self._pending_addon or self._proc is None:
            self._addon_timer.stop()
            return
        self._addon_tries += 1
        if kodi_rpc("JSONRPC.Ping", timeout=1.0) is not None:
            kodi_rpc("Addons.ExecuteAddon", {"addonid": self._pending_addon})
            self._pending_addon = None
            self._addon_timer.stop()
        elif self._addon_tries > 40:  # ~60 s sin respuesta
            self.message.emit("Kodi no responde a la API de control remoto")
            self._pending_addon = None
            self._addon_timer.stop()

    def _check_process(self) -> None:
        if self._proc is None or self._proc.poll() is None:
            return
        finished = self._running_id
        self._proc = None
        self._running_id = ""
        self._pending_addon = None
        self._poll.stop()
        self._addon_timer.stop()
        self.runningChanged.emit()
        self.appFinished.emit(finished)
