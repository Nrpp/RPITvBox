"""Escucha el botón Inicio del mando aunque otra app (Kodi) tenga el foco.

Lee directamente los dispositivos /dev/input/event* con python-evdev, así
funciona con mandos HDMI-CEC (el kernel los expone como dispositivo de entrada),
mandos Bluetooth y mandos/teclados USB. El usuario debe estar en el grupo 'input'.
"""
from __future__ import annotations

import os
import select
import threading
import time

from PySide6.QtCore import QObject, Signal

# Teclas que se interpretan como "Inicio". Se pueden cambiar con
# RPITVBOX_HOME_KEYS="KEY_HOMEPAGE,KEY_F12".
DEFAULT_KEYS = "KEY_HOMEPAGE,KEY_ROOT_MENU"
LONG_PRESS_BACK_SECONDS = 2.0  # mantener "Atrás" 2 s también vuelve al inicio

try:
    import evdev
    from evdev import ecodes
except ImportError:  # pragma: no cover - evdev solo existe en la RPi
    evdev = None


class HomeKeyListener(QObject):
    homePressed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        names = os.environ.get("RPITVBOX_HOME_KEYS", DEFAULT_KEYS).split(",")
        self._home_codes = set()
        self._back_codes = set()
        if evdev:
            self._home_codes = {ecodes.ecodes[n.strip()] for n in names if n.strip() in ecodes.ecodes}
            self._back_codes = {ecodes.KEY_BACK, ecodes.KEY_ESC, ecodes.KEY_EXIT}

    @property
    def enabled(self) -> bool:
        return evdev is not None

    def start(self) -> None:
        if not evdev:
            print("[rpitvbox] python-evdev no instalado: el botón Inicio global está desactivado")
            return
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()

    def _open_devices(self) -> dict:
        devices = {}
        for path in evdev.list_devices():
            try:
                dev = evdev.InputDevice(path)
            except OSError:
                continue
            keys = dev.capabilities().get(ecodes.EV_KEY, [])
            if self._home_codes.intersection(keys) or self._back_codes.intersection(keys):
                devices[dev.fd] = dev
        return devices

    def _run(self) -> None:
        devices = {}
        back_down_at: dict[int, float] = {}
        last_scan = 0.0
        while not self._stop.is_set():
            # Re-escanea cada 5 s para detectar mandos que se conectan después.
            if time.monotonic() - last_scan > 5:
                for dev in devices.values():
                    dev.close()
                devices = self._open_devices()
                last_scan = time.monotonic()
            if not devices:
                time.sleep(1)
                continue
            try:
                ready, _, _ = select.select(list(devices), [], [], 0.5)
            except (OSError, ValueError):
                last_scan = 0
                continue
            now = time.monotonic()
            for fd in ready:
                try:
                    events = list(devices[fd].read())
                except OSError:
                    last_scan = 0
                    continue
                for ev in events:
                    if ev.type != ecodes.EV_KEY:
                        continue
                    if ev.code in self._home_codes and ev.value == 1:
                        self.homePressed.emit()
                    elif ev.code in self._back_codes:
                        if ev.value == 1:
                            back_down_at[ev.code] = now
                        elif ev.value == 0:
                            back_down_at.pop(ev.code, None)
            for code, t in list(back_down_at.items()):
                if now - t >= LONG_PRESS_BACK_SECONDS:
                    back_down_at.pop(code)
                    self.homePressed.emit()
