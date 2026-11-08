#!/usr/bin/env python3
"""GUI de la Debug Unit. Ver README.md (python gui.py --help)."""
import sys

try:
    from riscv_debugger.gui import main
except ImportError as e:
    sys.exit(f"{e}\nLa GUI usa tkinter (viene con Python; en Linux: sudo apt install python3-tk)")

main()
