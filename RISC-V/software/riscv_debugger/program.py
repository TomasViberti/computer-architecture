"""Programas: ensamblado, lectura de machine_code.txt y desensamblado.

El ensamblado reusa scripts/assembler.py (mismas reglas y mismos mensajes de error), asi
lo que se carga desde las interfaces es exactamente lo que generaria el script.
"""
import os
import re
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional

from .legacy import assembler as _asm
from .protocol import HALT_WORD

MACHINE_LINE_RE = re.compile(r"prog\[\s*(\d+)\s*\]\s*=\s*32'h([0-9a-fA-F_]+)\s*;")

AsmError = _asm.ErrorAsm


@dataclass
class Program:
    words: List[int]
    source: List[str] = field(default_factory=list)    # texto de la linea de origen, por palabra
    path: Optional[str] = None
    lines: List[int] = field(default_factory=list)     # linea del archivo fuente, por palabra

    def word_of_line(self, line):
        """Primera palabra generada por esa linea del fuente (o None)."""
        return self.lines.index(line) if line in self.lines else None

    def __len__(self):
        return len(self.words)

    @property
    def has_halt(self):
        return any((w & 0x7F) == 0x0B for w in self.words)

    def to_machine_code(self):
        """Mismo formato que escribe scripts/assembler.py."""
        name = os.path.basename(self.path) if self.path else "editor"
        out = [f"// {len(self.words)} palabras de programa, generadas por riscv_debugger desde {name}"]
        for i, w in enumerate(self.words):
            txt = self.source[i] if i < len(self.source) and self.source[i] else disassemble(w)
            out.append(f"prog[{i:2d}] = 32'h{w:08X};   // 0x{i * 4:02X}  {txt}")
        return "\n".join(out) + "\n"


def assemble_text(text, depth=256, path=None):
    """Ensambla un programa completo. Lanza AsmError con 'linea N: ...' si algo esta mal."""
    # leer_fuente del ensamblador lee de un archivo
    fd, tmp = tempfile.mkstemp(suffix=".s", text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        items = _asm.leer_fuente(tmp)
    finally:
        os.unlink(tmp)

    # Las dos pasadas son las mismas que en assembler.main()
    labels, pc = {}, 0
    for nl, labs, mn, ops, txt in items:
        for e in labs:
            if e in labels:
                raise AsmError(f"la etiqueta '{e}' esta repetida")
            labels[e] = pc
        try:
            pc += 4 * _asm.tam_palabras(mn, ops)
        except AsmError as ex:
            raise AsmError(f"linea {nl}: {ex}")
    if pc // 4 > depth:
        raise AsmError(f"el programa tiene {pc // 4} palabras y la memoria de programa {depth}")

    words, source, lines, pc = [], [], [], 0
    for nl, labs, mn, ops, txt in items:
        try:
            ws = _asm.ensamblar(mn, ops, pc, labels)
        except AsmError as ex:
            raise AsmError(f"linea {nl} ('{txt}'): {ex}")
        for k, w in enumerate(ws):
            lab = " ".join(l + ":" for l in labs) + " " if labs and k == 0 else ""
            words.append(w)
            source.append(lab + (txt if k == 0 else "(continuacion de li)"))
            lines.append(nl)
            pc += 4
    if not words:
        raise AsmError("el programa esta vacio")
    return Program(words, source, path, lines)


def parse_machine_code(text, path=None):
    """Lee lineas prog[n] = 32'h...; (lo que genera el ensamblador). Huecos = HALT, como el modelo."""
    found, comments = {}, {}
    for line in text.splitlines():
        m = MACHINE_LINE_RE.search(line)
        if m:
            idx = int(m.group(1))
            found[idx] = int(m.group(2).replace("_", ""), 16) & 0xFFFFFFFF
            c = line.split("//", 1)
            comments[idx] = re.sub(r"^\s*0x[0-9A-Fa-f]+\s+", "", c[1]).strip() if len(c) > 1 else ""
    if not found:
        raise AsmError("no hay ninguna linea con el formato prog[n] = 32'h...;")
    n = max(found) + 1
    return Program([found.get(i, HALT_WORD) for i in range(n)],
                   [comments.get(i, "") for i in range(n)], path)


def load_program(path, depth=256):
    """Abre un .s/.asm/.txt en assembler o un machine_code.txt (se detecta por el contenido)."""
    text = Path(path).read_text(encoding="utf-8")
    if MACHINE_LINE_RE.search(text):
        prog = parse_machine_code(text, str(path))
        if len(prog) > depth:
            raise AsmError(f"el programa tiene {len(prog)} palabras y la memoria de programa {depth}")
        return prog
    return assemble_text(text, depth, str(path))


# ============================================================================
# Desensamblador (para mostrar la memoria de programa y los latches)
# ============================================================================

_R = {(0x00, 0): "add", (0x20, 0): "sub", (0x00, 1): "sll", (0x00, 2): "slt", (0x00, 3): "sltu",
      (0x00, 4): "xor", (0x00, 5): "srl", (0x20, 5): "sra", (0x00, 6): "or", (0x00, 7): "and"}
_I = {0: "addi", 2: "slti", 3: "sltiu", 4: "xori", 6: "ori", 7: "andi"}
_L = {0: "lb", 1: "lh", 2: "lw", 4: "lbu", 5: "lhu"}
_S = {0: "sb", 1: "sh", 2: "sw"}
_B = {0: "beq", 1: "bne"}


def _sext(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


def disassemble(w, pc=None):
    """Una palabra -> texto con la sintaxis del ensamblador. Si se da pc, agrega el destino de saltos."""
    op, rd, f3 = w & 0x7F, (w >> 7) & 31, (w >> 12) & 7
    rs1, rs2, f7 = (w >> 15) & 31, (w >> 20) & 31, w >> 25
    imm_i = _sext(w >> 20, 12)

    def dest(off):
        return f"{off:+d}" + (f"  -> 0x{(pc + off) & 0xFFFFFFFF:x}" if pc is not None else "")

    if w == HALT_WORD:
        return "halt"
    if op == 0x0B:
        return f"halt (0x{w:08x})"
    if op == 0x33 and (f7, f3) in _R:
        return f"{_R[(f7, f3)]} x{rd}, x{rs1}, x{rs2}"
    if op == 0x13:
        if f3 == 1 and f7 == 0:
            return f"slli x{rd}, x{rs1}, {rs2}"
        if f3 == 5 and f7 in (0x00, 0x20):
            return f"{'srai' if f7 else 'srli'} x{rd}, x{rs1}, {rs2}"
        if f3 in _I:
            if w == 0x00000013:
                return "nop"
            return f"{_I[f3]} x{rd}, x{rs1}, {imm_i}"
    if op == 0x03 and f3 in _L:
        return f"{_L[f3]} x{rd}, {imm_i}(x{rs1})"
    if op == 0x23 and f3 in _S:
        imm = _sext((f7 << 5) | rd, 12)
        return f"{_S[f3]} x{rs2}, {imm}(x{rs1})"
    if op == 0x63 and f3 in _B:
        imm = _sext((((w >> 31) & 1) << 12) | (((w >> 7) & 1) << 11)
                    | (((w >> 25) & 0x3F) << 5) | (((w >> 8) & 0xF) << 1), 13)
        return f"{_B[f3]} x{rs1}, x{rs2}, {dest(imm)}"
    if op == 0x37:
        return f"lui x{rd}, 0x{w >> 12:x}"
    if op == 0x6F:
        imm = _sext((((w >> 31) & 1) << 20) | (((w >> 12) & 0xFF) << 12)
                    | (((w >> 20) & 1) << 11) | (((w >> 21) & 0x3FF) << 1), 21)
        return f"jal x{rd}, {dest(imm)}"
    if op == 0x67 and f3 == 0:
        return f"jalr x{rd}, {imm_i}(x{rs1})"
    return f".word 0x{w:08x}"


ABI_NAMES = ["zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1", "a0", "a1", "a2", "a3",
             "a4", "a5", "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11",
             "t3", "t4", "t5", "t6"]


def fmt_value(v, fmt="hex"):
    """Formato comun para las tres interfaces."""
    if v is None:
        return "-"
    if fmt == "dec":
        return str(v)
    if fmt == "sdec":
        return str(_sext(v, 32))
    if fmt == "bin":
        return bin(v)
    if fmt == "bool":
        return "1" if v else "0"
    if fmt == "instr":
        return f"{v:08x}  {disassemble(v)}"
    return f"0x{v:08x}"
