"""Acciones de sistema expuestas a la interfaz."""
from __future__ import annotations

import socket
import subprocess

from PySide6.QtCore import QObject, Slot


class SystemActions(QObject):
    @Slot(result=str)
    def ipAddress(self) -> str:
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.connect(("192.0.2.1", 80))  # no envía nada, solo elige interfaz
                return s.getsockname()[0]
        except OSError:
            return "Sin red"

    @Slot(result=str)
    def hostname(self) -> str:
        return socket.gethostname()

    @Slot()
    def reboot(self) -> None:
        subprocess.Popen(["systemctl", "reboot"])

    @Slot()
    def shutdown(self) -> None:
        subprocess.Popen(["systemctl", "poweroff"])
