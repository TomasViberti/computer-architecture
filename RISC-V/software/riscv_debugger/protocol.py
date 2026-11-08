"""Protocolo de la Debug Unit: constantes, armado de comandos y lectura de paquetes.

Version 0 (la que esta en el RTL, desing/rtl/debug/debug_unit.v):
    PC -> FPGA   01 LOAD  N (2 bytes) + N palabras de 4 bytes   -> 00 OK | 01 | 02
    PC -> FPGA   02 RUN                                         -> 00 OK y, al llegar al HALT,
                                                                   el paquete de estado 10
Version 1 (PROPUESTA para el pipeline, todavia no esta en el RTL):
    PC -> FPGA   03 STEP  un ciclo de clock                     -> 00 OK + paquete de estado
    PC -> FPGA   04 INFO  version y capacidades                 -> 00 OK + paquete de info 20
    Paquete de estado 11 = estado 10 + latches intermedios.

Una Debug Unit version 0 contesta 01 (comando desconocido) a STEP e INFO, asi que el
software detecta solo que version tiene enfrente: no hace falta cambiar nada en la PC el
dia que el RTL implemente la version 1.

Todos los numeros de varios bytes van con el byte menos significativo primero.
"""
import struct
from dataclasses import dataclass, field
from typing import Dict, List, Optional

# ---------------- comandos (PC -> FPGA) ----------------
CMD_LOAD = 0x01
CMD_RUN = 0x02
CMD_STEP = 0x03     # v1 (propuesta)
CMD_INFO = 0x04     # v1 (propuesta)

# ---------------- respuestas (FPGA -> PC) ----------------
REPLY_OK = 0x00
REPLY_ERR_CMD = 0x01
REPLY_ERR_PARAM = 0x02
REPLY_NAMES = {
    REPLY_OK: "OK",
    REPLY_ERR_CMD: "comando desconocido",
    REPLY_ERR_PARAM: "parametro invalido (N = 0 o mas palabras que la memoria de programa)",
}

# ---------------- paquetes (FPGA -> PC) ----------------
PKT_STATE = 0x10        # v0: estado sin latches
PKT_STATE_LATCH = 0x11  # v1: estado + latches
PKT_INFO = 0x20         # v1: respuesta a INFO

# Banderas del paquete de estado
FLAG_HALT = 0x01
FLAG_ERR_IMEM = 0x02
FLAG_ERR_DMEM = 0x04

# Capacidades (bits del byte de capacidades del paquete INFO)
CAP_LOAD = 0x01
CAP_RUN = 0x02
CAP_STEP = 0x04
CAP_NAMES = {CAP_LOAD: "LOAD", CAP_RUN: "RUN", CAP_STEP: "STEP"}

HALT_WORD = 0x0000000B

# La Debug Unit descarta bytes hasta 100 ms de silencio despues de un error
SILENCE_AFTER_ERROR = 0.3


class ProtocolError(Exception):
    """La FPGA contesto algo que el protocolo no espera, o no contesto."""


class Unsupported(ProtocolError):
    """La Debug Unit conectada no implementa ese comando (por ejemplo, STEP en la version 0)."""


# ============================================================================
# Latches intermedios
# ============================================================================
# Cada latch llega como una lista de palabras de 32 bits. Esta tabla dice como se reparten
# los campos dentro de esas palabras. Es solo una descripcion: si el RTL del pipeline manda
# otra cosa, se cambia aca y las tres interfaces lo muestran sin tocar nada mas.
# Un latch con un id que no esta en la tabla se muestra igual, como palabras crudas.

@dataclass(frozen=True)
class FieldSpec:
    name: str
    word: int           # palabra del latch donde esta el campo
    lsb: int = 0        # bit menos significativo dentro de la palabra
    width: int = 32
    fmt: str = "hex"    # hex | dec | bin | bool | instr (se desensambla)

    def extract(self, words):
        if self.word >= len(words):
            return None
        return (words[self.word] >> self.lsb) & ((1 << self.width) - 1)


@dataclass(frozen=True)
class LatchSpec:
    id: int
    name: str
    fields: tuple


# Propuesta de layout para el pipeline de 5 etapas. Ajustar a lo que mande el RTL.
LATCH_LAYOUT: Dict[int, LatchSpec] = {
    0: LatchSpec(0, "IF/ID", (
        FieldSpec("pc", 0), FieldSpec("instr", 1, fmt="instr"), FieldSpec("valid", 2, 0, 1, "bool"),
    )),
    1: LatchSpec(1, "ID/EX", (
        FieldSpec("pc", 0), FieldSpec("instr", 1, fmt="instr"), FieldSpec("rs1_data", 2),
        FieldSpec("rs2_data", 3), FieldSpec("imm", 4), FieldSpec("rd", 5, 0, 5, "dec"),
        FieldSpec("rs1", 5, 5, 5, "dec"), FieldSpec("rs2", 5, 10, 5, "dec"),
        FieldSpec("ctrl", 5, 16, 16, "bin"), FieldSpec("valid", 5, 15, 1, "bool"),
    )),
    2: LatchSpec(2, "EX/MEM", (
        FieldSpec("pc", 0), FieldSpec("instr", 1, fmt="instr"), FieldSpec("alu_result", 2),
        FieldSpec("rs2_data", 3), FieldSpec("rd", 4, 0, 5, "dec"),
        FieldSpec("ctrl", 4, 16, 16, "bin"), FieldSpec("valid", 4, 15, 1, "bool"),
    )),
    3: LatchSpec(3, "MEM/WB", (
        FieldSpec("pc", 0), FieldSpec("instr", 1, fmt="instr"), FieldSpec("alu_result", 2),
        FieldSpec("mem_data", 3), FieldSpec("rd", 4, 0, 5, "dec"),
        FieldSpec("ctrl", 4, 16, 16, "bin"), FieldSpec("valid", 4, 15, 1, "bool"),
    )),
}


@dataclass
class Latch:
    id: int
    words: List[int]

    @property
    def spec(self) -> Optional[LatchSpec]:
        return LATCH_LAYOUT.get(self.id)

    @property
    def name(self):
        return self.spec.name if self.spec else f"latch {self.id}"

    def fields(self):
        """Lista de (nombre, valor, formato). Sin layout conocido: una entrada por palabra."""
        if self.spec is None:
            return [(f"word{i}", w, "hex") for i, w in enumerate(self.words)]
        return [(f.name, f.extract(self.words), f.fmt) for f in self.spec.fields]


# ============================================================================
# Estado e info
# ============================================================================

@dataclass
class CpuState:
    pc: int
    cycles: int
    halted: bool
    err_imem: bool
    err_dmem: bool
    regs: List[int]
    mem: List[int]                  # memoria de datos, una palabra por elemento
    latches: List[Latch] = field(default_factory=list)
    origin: str = ""                # "run" | "step": que comando lo produjo

    def changed_regs(self, prev: Optional["CpuState"]):
        if prev is None:
            return set()
        return {i for i in range(32) if self.regs[i] != prev.regs[i]}

    def changed_mem(self, prev: Optional["CpuState"]):
        if prev is None:
            return set()
        n = min(len(self.mem), len(prev.mem))
        return {i for i in range(n) if self.mem[i] != prev.mem[i]} | set(range(n, len(self.mem)))

    def to_text(self):
        """Mismo formato que rtl_state.txt (testbench) y py_model_state.txt (modelo)."""
        lines = [
            f"PC={self.pc:08x}",
            f"CICLOS={self.cycles}",
            f"HALT={int(self.halted)}",
            f"ERROR_IMEM={int(self.err_imem)}",
            f"ERROR_DMEM={int(self.err_dmem)}",
        ]
        lines += [f"x{i}={v:08x}" for i, v in enumerate(self.regs)]
        lines += [f"MEM[0x{i * 4:08x}]={w:08x}" for i, w in enumerate(self.mem) if w != 0]
        return "\n".join(lines) + "\n"

    def to_dict(self):
        return {
            "pc": self.pc, "cycles": self.cycles, "halted": self.halted,
            "err_imem": self.err_imem, "err_dmem": self.err_dmem,
            "regs": self.regs, "mem": self.mem, "origin": self.origin,
            "latches": [{"id": l.id, "name": l.name, "words": l.words,
                         "fields": {n: v for n, v, _ in l.fields()}} for l in self.latches],
        }


@dataclass
class DebugInfo:
    version: int
    caps: int
    imem_depth: int
    dmem_depth: int

    def has(self, cap):
        return bool(self.caps & cap)

    def cap_names(self):
        return [n for bit, n in CAP_NAMES.items() if self.caps & bit]


# Lo que se asume de una Debug Unit que no contesta INFO (la del RTL actual)
INFO_V0 = DebugInfo(version=0, caps=CAP_LOAD | CAP_RUN, imem_depth=256, dmem_depth=256)


# ============================================================================
# Armado de comandos
# ============================================================================

def encode_load(words):
    frame = struct.pack("<BH", CMD_LOAD, len(words))
    return frame + b"".join(struct.pack("<I", w & 0xFFFFFFFF) for w in words)


def encode_state(state: CpuState, with_latches=False):
    """Paquete de estado tal como lo manda la Debug Unit (lo usa el simulador)."""
    flags = (FLAG_HALT if state.halted else 0) | (FLAG_ERR_IMEM if state.err_imem else 0) \
        | (FLAG_ERR_DMEM if state.err_dmem else 0)
    pkt = struct.pack("<BBII", PKT_STATE_LATCH if with_latches else PKT_STATE, flags,
                      state.pc & 0xFFFFFFFF, state.cycles & 0xFFFFFFFF)
    pkt += struct.pack("<32I", *state.regs)
    pkt += struct.pack("<H", len(state.mem)) + struct.pack(f"<{len(state.mem)}I", *state.mem)
    if with_latches:
        pkt += struct.pack("<B", len(state.latches))
        for l in state.latches:
            pkt += struct.pack("<BB", l.id, len(l.words)) + struct.pack(f"<{len(l.words)}I", *l.words)
    return pkt


def encode_info(info: DebugInfo):
    return struct.pack("<BBBHH", PKT_INFO, info.version, info.caps, info.imem_depth, info.dmem_depth)


# ============================================================================
# Lectura de paquetes
# ============================================================================

def read_state(transport, first_byte_timeout, origin=""):
    """Lee un paquete de estado (10 u 11) completo desde el transporte."""
    try:
        kind = transport.read_exact(1, first_byte_timeout)[0]
    except TimeoutError:
        raise ProtocolError(f"no llego el estado en {first_byte_timeout:g} s")
    if kind not in (PKT_STATE, PKT_STATE_LATCH):
        transport.flush_input()
        raise ProtocolError(f"se esperaba un paquete de estado y llego 0x{kind:02X}")
    try:
        head = transport.read_exact(1 + 4 + 4 + 128 + 2, 3.0)
        flags = head[0]
        pc, cycles = struct.unpack("<II", head[1:9])
        regs = list(struct.unpack("<32I", head[9:137]))
        nw = struct.unpack("<H", head[137:139])[0]
        mem = list(struct.unpack(f"<{nw}I", transport.read_exact(4 * nw, 5.0))) if nw else []
        latches = []
        if kind == PKT_STATE_LATCH:
            for _ in range(transport.read_exact(1, 1.0)[0]):
                lid, nwl = transport.read_exact(2, 1.0)
                words = list(struct.unpack(f"<{nwl}I", transport.read_exact(4 * nwl, 1.0))) if nwl else []
                latches.append(Latch(lid, words))
    except TimeoutError as e:
        raise ProtocolError(f"el estado llego incompleto ({e})")
    return CpuState(pc=pc, cycles=cycles, halted=bool(flags & FLAG_HALT),
                    err_imem=bool(flags & FLAG_ERR_IMEM), err_dmem=bool(flags & FLAG_ERR_DMEM),
                    regs=regs, mem=mem, latches=latches, origin=origin)


def read_info(transport):
    try:
        kind = transport.read_exact(1, 1.0)[0]
        if kind != PKT_INFO:
            transport.flush_input()
            raise ProtocolError(f"se esperaba el paquete de info y llego 0x{kind:02X}")
        version, caps, imem, dmem = struct.unpack("<BBHH", transport.read_exact(6, 1.0))
    except TimeoutError as e:
        raise ProtocolError(f"el paquete de info llego incompleto ({e})")
    return DebugInfo(version, caps, imem, dmem)
