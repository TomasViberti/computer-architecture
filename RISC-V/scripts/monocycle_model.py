#!/usr/bin/env python3
"""Modelo del CPU RV32I: ejecuta el programa y escribe el estado final.

Lee el codigo maquina que genero ensamblador.py (lineas prog[n] = 32'h...;), lo ejecuta
hasta el HALT y escribe estado_modelo.txt. Si encuentra rtl_state.txt (el que escribe el
testbench) lo compara y dice si el RTL termino en el mismo estado.

Uso:
    python monocycle_model.py
    python monocycle_model.py -i otro.txt --rtl ruta/rtl_state.txt

El modelo reproduce el comportamiento del diseno:
  - memoria de datos little-endian; acceso desalineado = alineado hacia abajo;
  - dato fuera de rango: no escribe, lee 0 y marca ERROR_DMEM;
  - instruccion fuera de rango o sin programa: devuelve HALT (marca ERROR_IMEM si es fuera de rango);
  - opcode desconocido: se comporta como nop;  x0 vale siempre 0.
"""
import argparse
import os
import re
import sys

MASK = 0xFFFFFFFF
HALT = 0x0000000B


def s32(v):
    v &= MASK
    return v - (1 << 32) if v >> 31 else v


def sext(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


class Cpu:
    def __init__(self, palabras, imem=256, dmem=256):
        self.imem_depth, self.dmem_depth = imem, dmem
        self.ibits, self.dbits = imem.bit_length() - 1, dmem.bit_length() - 1
        self.imem = [HALT] * imem
        self.imem[:len(palabras)] = palabras
        self.mem = bytearray(4 * dmem)
        self.x = [0] * 32
        self.pc = 0
        self.ciclos = 0
        self.err_imem = False
        self.err_dmem = False

    def instruccion(self, marcar=True):
        if (self.pc >> (self.ibits + 2)) != 0:
            if marcar:
                self.err_imem = True
            return HALT
        return self.imem[(self.pc >> 2) & (self.imem_depth - 1)]

    def en_halt(self):
        return (self.instruccion(False) & 0x7F) == 0x0B

    def _base(self, addr):
        if (addr >> (self.dbits + 2)) != 0:
            self.err_dmem = True
            return None
        return ((addr >> 2) & (self.dmem_depth - 1)) * 4

    def _cargar(self, addr, f3):
        b = self._base(addr)
        if b is None:
            return 0
        tam, sin_signo = f3 & 3, (f3 >> 2) & 1
        if tam == 0:
            v = self.mem[b + (addr & 3)]
            return v if sin_signo or not v & 0x80 else v | 0xFFFFFF00
        if tam == 1:
            o = addr & 2
            v = self.mem[b + o] | (self.mem[b + o + 1] << 8)
            return v if sin_signo or not v & 0x8000 else v | 0xFFFF0000
        return int.from_bytes(self.mem[b:b + 4], "little") if tam == 2 else 0

    def _guardar(self, addr, f3, dato):
        b = self._base(addr)
        if b is None:
            return
        tam = f3 & 3
        if tam == 0:
            self.mem[b + (addr & 3)] = dato & 0xFF
        elif tam == 1:
            o = addr & 2
            self.mem[b + o] = dato & 0xFF
            self.mem[b + o + 1] = (dato >> 8) & 0xFF
        elif tam == 2:
            self.mem[b:b + 4] = (dato & MASK).to_bytes(4, "little")

    @staticmethod
    def _alu(f3, alt, a, b):
        if f3 == 0:
            return (a - b) & MASK if alt else (a + b) & MASK
        if f3 == 1:
            return (a << (b & 31)) & MASK
        if f3 == 2:
            return int(s32(a) < s32(b))
        if f3 == 3:
            return int(a < b)
        if f3 == 4:
            return a ^ b
        if f3 == 5:
            return (s32(a) >> (b & 31)) & MASK if alt else a >> (b & 31)
        return (a | b) if f3 == 6 else (a & b)

    def paso(self):
        """Ejecuta una instruccion. Devuelve False si es HALT (el PC no avanza)."""
        ins = self.instruccion()
        op, f3 = ins & 0x7F, (ins >> 12) & 7
        rd, rs1, rs2 = (ins >> 7) & 31, (ins >> 15) & 31, (ins >> 20) & 31
        a, b, b30 = self.x[rs1], self.x[rs2], (ins >> 30) & 1
        pc, sig, esc = self.pc, (self.pc + 4) & MASK, None
        imm_i = sext(ins >> 20, 12)
        if op == 0x0B:
            return False
        if op == 0x33:
            esc = self._alu(f3, b30 and f3 in (0, 5), a, b)
        elif op == 0x13:
            esc = self._alu(f3, b30 and f3 == 5, a, imm_i & MASK)
        elif op == 0x03:
            esc = self._cargar((a + imm_i) & MASK, f3)
        elif op == 0x23:
            imm_s = sext(((ins >> 25) << 5) | ((ins >> 7) & 0x1F), 12)
            self._guardar((a + imm_s) & MASK, f3, b)
        elif op == 0x63:
            imm_b = sext((((ins >> 31) & 1) << 12) | (((ins >> 7) & 1) << 11)
                         | (((ins >> 25) & 0x3F) << 5) | (((ins >> 8) & 0xF) << 1), 13)
            if ((a != b) if (f3 & 1) else (a == b)):
                sig = (pc + imm_b) & MASK
        elif op == 0x37:
            esc = ins & 0xFFFFF000
        elif op == 0x6F:
            imm_j = sext((((ins >> 31) & 1) << 20) | (((ins >> 12) & 0xFF) << 12)
                         | (((ins >> 20) & 1) << 11) | (((ins >> 21) & 0x3FF) << 1), 21)
            esc, sig = (pc + 4) & MASK, (pc + imm_j) & MASK
        elif op == 0x67:
            esc, sig = (pc + 4) & MASK, ((a + imm_i) & MASK) & ~1 & MASK
        if esc is not None and rd != 0:
            self.x[rd] = esc & MASK
        self.pc = sig
        self.ciclos += 1
        return True


def leer_programa(ruta):
    with open(ruta, encoding="utf-8") as f:
        texto = f.read()
    palabras = {int(m.group(1)): int(m.group(2).replace("_", ""), 16)
                for m in re.finditer(r"prog\[\s*(\d+)\s*\]\s*=\s*32'h([0-9A-Fa-f_]+)\s*;", texto)}
    if not palabras:
        sys.exit(f"ERROR: no encontre lineas prog[n] = 32'h...; en {ruta}")
    return [palabras.get(i, HALT) for i in range(max(palabras) + 1)]


def lineas_estado(cpu, halt):
    L = [f"PC={cpu.pc:08x}", f"CICLOS={cpu.ciclos}", f"HALT={int(halt)}",
         f"ERROR_IMEM={int(cpu.err_imem)}", f"ERROR_DMEM={int(cpu.err_dmem)}"]
    L += [f"x{i}={v:08x}" for i, v in enumerate(cpu.x)]
    for i in range(0, len(cpu.mem), 4):
        w = int.from_bytes(cpu.mem[i:i + 4], "little")
        if w:
            L.append(f"MEM[0x{i:08x}]={w:08x}")
    return L


def leer_estado(ruta):
    d = {}
    with open(ruta, encoding="utf-8") as f:
        for l in f:
            l = l.strip()
            if "=" in l:
                k, v = l.split("=", 1)
                d[k.strip()] = v.strip().lower()
    return d


def comparar(modelo, rtl):
    dif = []
    for k in sorted(set(modelo) | set(rtl), key=lambda s: (not s.startswith(("PC", "CICLOS", "HALT", "ERROR")), s.startswith("MEM"), s.zfill(4))):
        vm, vr = modelo.get(k), rtl.get(k)
        if k.startswith("MEM["):
            vm, vr = vm or "00000000", vr or "00000000"
        if vm != vr:
            dif.append(f"  {k}: modelo {vm}, RTL {vr}")
    return dif


def main():
    ap = argparse.ArgumentParser(description="Modelo del CPU RV32I")
    ap.add_argument("-i", "--entrada", default="machine_code.txt")
    ap.add_argument("-o", "--salida", default="py_model_state.txt")
    ap.add_argument("--rtl", default="rtl_state.txt")
    ap.add_argument("--imem", type=int, default=256, help="palabras de la memoria de programa")
    ap.add_argument("--dmem", type=int, default=256, help="palabras de la memoria de datos")
    ap.add_argument("--max-ciclos", type=int, default=500, help="igual que MAX_CYCLES del testbench")
    a = ap.parse_args()
    cpu = Cpu(leer_programa(a.entrada), a.imem, a.dmem)
    while cpu.ciclos < a.max_ciclos:
        if not cpu.paso():
            break
    halt = cpu.en_halt()
    with open(a.salida, "w", encoding="utf-8") as f:
        f.write("\n".join(lineas_estado(cpu, halt)) + "\n")
    print(f"Modelo: {cpu.ciclos} instrucciones ejecutadas, PC final = {cpu.pc:#x}"
          + ("" if halt else "  (ATENCION: no llego al HALT)"))
    print(f"Estado escrito en {a.salida}")
    if not os.path.exists(a.rtl):
        print(f"No encontre {a.rtl}: simula el RTL (genera ese archivo) y volve a correr para comparar.")
        return
    dif = comparar(leer_estado(a.salida), leer_estado(a.rtl))
    if dif:
        print(f"\nDIFERENTES: {len(dif)} diferencia(s) entre el modelo y el RTL")
        print("\n".join(dif))
        sys.exit(1)
    print(f"\nIGUALES: el RTL y el modelo terminaron en el mismo estado ({cpu.ciclos} ciclos)")


if __name__ == "__main__":
    main()
