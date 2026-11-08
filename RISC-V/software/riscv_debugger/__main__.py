"""python -m riscv_debugger {cli,tui,gui} [opciones]"""
import sys

USO = "uso: python -m riscv_debugger {cli,tui,gui} [opciones]   (--help en cada una)"


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("cli", "tui", "gui"):
        sys.exit(USO)
    which, argv = sys.argv[1], sys.argv[2:]
    if which == "cli":
        from .cli import main as m
    elif which == "tui":
        from .tui import main as m
    else:
        from .gui import main as m
    return m(argv)


sys.exit(main())
