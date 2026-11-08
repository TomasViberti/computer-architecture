#!/usr/bin/env python3
"""TUI de la Debug Unit. Ver README.md (python tui.py --help)."""
import sys

try:
    from riscv_debugger.tui import main
except ImportError as e:
    sys.exit(f"{e}\nLa TUI necesita Textual: pip install -r requirements.txt")

sys.exit(main())
