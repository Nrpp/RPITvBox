"""Carga de la configuración de apps (apps.json)."""
from __future__ import annotations

import json
import os
from pathlib import Path

REPO_CONFIG = Path(__file__).resolve().parents[2] / "config" / "apps.json"
USER_CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "rpitvbox" / "apps.json"


def config_path() -> Path:
    env = os.environ.get("RPITVBOX_CONFIG")
    if env:
        return Path(env)
    if USER_CONFIG.exists():
        return USER_CONFIG
    return REPO_CONFIG


def load_apps() -> list[dict]:
    with open(config_path(), encoding="utf-8") as f:
        data = json.load(f)
    apps = []
    for app in data.get("apps", []):
        if "id" not in app or "name" not in app or "type" not in app:
            continue
        app.setdefault("color", "#444444")
        app.setdefault("hint", "")
        app.setdefault("install_hint", "Ejecuta scripts/install.sh para instalarla.")
        apps.append(app)
    return apps
