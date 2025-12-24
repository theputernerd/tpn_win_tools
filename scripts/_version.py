"""
Single source of truth for the whole tools bundle version.
"""
from __future__ import annotations

from pathlib import Path


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def read_version(default: str = "0.0.0") -> str:
    p = repo_root() / "VERSION"
    try:
        v = p.read_text(encoding="utf-8").strip()
        return v if v else default
    except FileNotFoundError:
        return default


__version__ = read_version()
