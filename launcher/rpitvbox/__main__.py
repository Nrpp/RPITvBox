"""Punto de entrada: python3 -m rpitvbox"""
from __future__ import annotations

import os
import signal
import sys
from pathlib import Path

from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

from .config import load_apps
from .homekey import HomeKeyListener
from .launcher import AppLauncher
from .system import SystemActions

QML_DIR = Path(__file__).resolve().parent.parent / "qml"


def main() -> int:
    app = QGuiApplication(sys.argv)
    app.setApplicationName("RPi TV Box")
    signal.signal(signal.SIGINT, signal.SIG_DFL)

    apps = load_apps()
    launcher = AppLauncher(apps)
    system = SystemActions()
    home = HomeKeyListener()

    engine = QQmlApplicationEngine()
    ctx = engine.rootContext()
    ctx.setContextProperty("appsModel", apps)
    ctx.setContextProperty("launcher", launcher)
    ctx.setContextProperty("system", system)
    ctx.setContextProperty("windowed", os.environ.get("RPITVBOX_WINDOWED") == "1")
    engine.load(QML_DIR / "Main.qml")
    if not engine.rootObjects():
        return 1

    root = engine.rootObjects()[0]
    home.homePressed.connect(launcher.closeRunning)
    launcher.appFinished.connect(lambda _id: root.bringToFront())
    home.start()

    rc = app.exec()
    home.stop()
    return rc


if __name__ == "__main__":
    sys.exit(main())
