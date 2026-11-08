"""Acceso a los scripts que ya existen en RISC-V/scripts, sin copiarlos ni modificarlos.

- assembler.py        : el ensamblador (se reusan sus funciones de codificacion).
- monocycle_model.py  : el modelo del CPU (lo usa el simulador y la comparacion).

Se cargan por ruta para no depender del directorio desde el que se ejecuta el programa.
"""
import importlib.util
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parents[2] / "scripts"


def _load(name, filename):
    path = SCRIPTS_DIR / filename
    if not path.exists():
        raise ImportError(f"no encontre {path}: el software espera estar en RISC-V/software")
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


assembler = _load("rv_legacy_assembler", "assembler.py")
model = _load("rv_legacy_model", "monocycle_model.py")
