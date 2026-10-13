#!/usr/bin/env python3
"""Ensamblador RV32I del proyecto.

Lee un programa en assembler y escribe el codigo maquina en el formato del testbench:
    prog[ 0] = 32'h00500093;   // 0x00  addi x1, x0, 5

Uso:
    python assembler.py                                                      
    python assembler.py -i otro.txt -o salida.txt

Sintaxis:
  - Una instruccion por linea. Registros x0..x31. Comentarios con # o //.
  - Etiquetas:  loop:   (en su propia linea o antes de una instruccion).
  - Inmediatos en decimal, hexadecimal (0x1F) o binario (0b101), con signo si hace falta.
  - Cargas y almacenamientos:  lw x5, 0(x2)     sw x5, 8(x2)
  - Saltos: destino como etiqueta o como desplazamiento en bytes (+8, -4).
  - jalr acepta  jalr x1, 0(x5)  o  jalr x1, x5, 0.
  - Instrucciones: add sub sll slt sltu xor srl sra or and | addi slti sltiu xori ori andi slli srli srai
    | lb lh lw lbu lhu | sb sh sw | beq bne | lui | jal | jalr | halt
  - Pseudo-instrucciones: nop, mv rd, rs, li rd, imm, j destino
      li con un valor de 12 bits  -> addi rd, x0, imm
      li con un valor mayor        -> lui + addi (2 palabras)
"""
import argparse
import os
import re
import sys

HALT = 0x0000000B


class ErrorAsm(Exception):
    pass


# ------------------------------------------------------------ codificadores
def _chk(v, lo, hi, nombre):
    if not lo <= v <= hi:
        raise ErrorAsm(f"{nombre} = {v} fuera de rango [{lo}, {hi}]")


def _r(f7, rs2, rs1, f3, rd, op):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def _i(imm, rs1, f3, rd, op):
    _chk(imm, -2048, 2047, "el inmediato")
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def _s(imm, rs2, rs1, f3, op):
    _chk(imm, -2048, 2047, "el desplazamiento")
    i = imm & 0xFFF
    return ((i >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((i & 0x1F) << 7) | op


def _b(imm, rs2, rs1, f3, op):
    _chk(imm, -4096, 4094, "el desplazamiento del branch")
    if imm % 2:
        raise ErrorAsm("el desplazamiento de un branch debe ser par")
    i = imm & 0x1FFF
    return ((((i >> 12) & 1) << 31) | (((i >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15)
            | (f3 << 12) | (((i >> 1) & 0xF) << 8) | (((i >> 11) & 1) << 7) | op)


def _u(imm20, rd, op):
    _chk(imm20, 0, 0xFFFFF, "el inmediato de lui")
    return (imm20 << 12) | (rd << 7) | op


def _j(imm, rd, op):
    _chk(imm, -(1 << 20), (1 << 20) - 2, "el desplazamiento de jal")
    if imm % 2:
        raise ErrorAsm("el desplazamiento de jal debe ser par")
    i = imm & 0x1FFFFF
    return ((((i >> 20) & 1) << 31) | (((i >> 1) & 0x3FF) << 21) | (((i >> 11) & 1) << 20)
            | (((i >> 12) & 0xFF) << 12) | (rd << 7) | op)


R_OPS = {"add": (0x00, 0), "sub": (0x20, 0), "sll": (0x00, 1), "slt": (0x00, 2), "sltu": (0x00, 3),
         "xor": (0x00, 4), "srl": (0x00, 5), "sra": (0x20, 5), "or": (0x00, 6), "and": (0x00, 7)}
I_OPS = {"addi": 0, "slti": 2, "sltiu": 3, "xori": 4, "ori": 6, "andi": 7}
SHIFT_I = {"slli": (0x00, 1), "srli": (0x00, 5), "srai": (0x20, 5)}
LOADS = {"lb": 0, "lh": 1, "lw": 2, "lbu": 4, "lhu": 5}
STORES = {"sb": 0, "sh": 1, "sw": 2}
BRANCHES = {"beq": 0, "bne": 1}


# ---------------------------------------------------------------- operandos
def reg(tok):
    m = re.fullmatch(r"[xX](\d+)", tok.strip())
    if not m or int(m.group(1)) > 31:
        raise ErrorAsm(f"registro invalido '{tok.strip()}' (se espera x0..x31)")
    return int(m.group(1))


def num(tok):
    t = tok.strip().replace("_", "")
    try:
        return int(t, 0)
    except ValueError:
        try:
            return int(t, 10)
        except ValueError:
            raise ErrorAsm(f"numero invalido '{tok.strip()}'")


def mem_operand(tok):
    m = re.fullmatch(r"(.*)\(\s*([xX]\d+)\s*\)", tok.strip())
    if not m:
        raise ErrorAsm(f"operando de memoria invalido '{tok.strip()}' (se espera imm(rs1), por ejemplo 0(x2))")
    return (num(m.group(1)) if m.group(1).strip() else 0), reg(m.group(2))


def destino(tok, pc, etiquetas):
    t = tok.strip()
    if re.fullmatch(r"[A-Za-z_]\w*", t):
        if t not in etiquetas:
            raise ErrorAsm(f"etiqueta no definida '{t}'")
        return etiquetas[t] - pc
    return num(t)


def secuencia_li(v):
    """li rd, v  ->  lista de (mnemonico, operandos) con lui/addi."""
    if not -(1 << 31) <= v <= (1 << 32) - 1:
        raise ErrorAsm(f"li: el valor {v} no entra en 32 bits")
    if -2048 <= v <= 2047:
        return [("addi", "x0", v)]
    v32 = v & 0xFFFFFFFF
    low = v32 & 0xFFF
    low = low - 0x1000 if low & 0x800 else low
    alto = ((v32 - low) & 0xFFFFFFFF) >> 12
    return [("lui", alto)] + ([("addi", "rd", low)] if low else [])


def tam_palabras(mn, ops):
    if mn == "li":
        if len(ops) != 2:
            raise ErrorAsm("'li' necesita 2 operandos: li rd, imm")
        return len(secuencia_li(num(ops[1])))
    return 1


def ensamblar(mn, ops, pc, etiquetas):
    def n(k):
        if len(ops) != k:
            raise ErrorAsm(f"'{mn}' necesita {k} operando(s) y tiene {len(ops)}")
    if mn == "halt":
        n(0)
        return [HALT]
    if mn == "nop":
        n(0)
        return [_i(0, 0, 0, 0, 0x13)]
    if mn == "mv":
        n(2)
        return [_i(0, reg(ops[1]), 0, reg(ops[0]), 0x13)]
    if mn == "li":
        n(2)
        rd, seq = reg(ops[0]), secuencia_li(num(ops[1]))
        palabras = []
        for item in seq:
            if item[0] == "addi" and item[1] == "x0":           # valor chico
                palabras.append(_i(item[2], 0, 0, rd, 0x13))
            elif item[0] == "lui":
                palabras.append(_u(item[1], rd, 0x37))
            else:                                               # addi rd, rd, low
                palabras.append(_i(item[2], rd, 0, rd, 0x13))
        return palabras
    if mn == "j":
        n(1)
        return [_j(destino(ops[0], pc, etiquetas), 0, 0x6F)]
    if mn in R_OPS:
        n(3)
        f7, f3 = R_OPS[mn]
        return [_r(f7, reg(ops[2]), reg(ops[1]), f3, reg(ops[0]), 0x33)]
    if mn in I_OPS:
        n(3)
        return [_i(num(ops[2]), reg(ops[1]), I_OPS[mn], reg(ops[0]), 0x13)]
    if mn in SHIFT_I:
        n(3)
        sh = num(ops[2])
        _chk(sh, 0, 31, "el desplazamiento (shamt)")
        f7, f3 = SHIFT_I[mn]
        return [(f7 << 25) | (sh << 20) | (reg(ops[1]) << 15) | (f3 << 12) | (reg(ops[0]) << 7) | 0x13]
    if mn in LOADS:
        n(2)
        imm, rs1 = mem_operand(ops[1])
        return [_i(imm, rs1, LOADS[mn], reg(ops[0]), 0x03)]
    if mn in STORES:
        n(2)
        imm, rs1 = mem_operand(ops[1])
        return [_s(imm, reg(ops[0]), rs1, STORES[mn], 0x23)]
    if mn in BRANCHES:
        n(3)
        return [_b(destino(ops[2], pc, etiquetas), reg(ops[1]), reg(ops[0]), BRANCHES[mn], 0x63)]
    if mn == "lui":
        n(2)
        return [_u(num(ops[1]), reg(ops[0]), 0x37)]
    if mn == "jal":
        n(2)
        return [_j(destino(ops[1], pc, etiquetas), reg(ops[0]), 0x6F)]
    if mn == "jalr":
        if len(ops) == 2:
            imm, rs1 = mem_operand(ops[1])
        elif len(ops) == 3:
            rs1, imm = reg(ops[1]), num(ops[2])
        else:
            raise ErrorAsm("'jalr' necesita: jalr rd, imm(rs1)  o  jalr rd, rs1, imm")
        return [_i(imm, rs1, 0, reg(ops[0]), 0x67)]
    raise ErrorAsm(f"instruccion desconocida '{mn}'")


# ------------------------------------------------------------------ programa
def leer_fuente(ruta):
    """Devuelve la lista de instrucciones: (n_linea, etiquetas, mnemonico, operandos, texto)."""
    items, pendientes = [], []
    with open(ruta, encoding="utf-8") as f:
        lineas = f.read().splitlines()
    for nl, crudo in enumerate(lineas, 1):
        linea = re.split(r"#|//", crudo)[0].strip()
        while True:                                   # una o mas etiquetas al principio
            m = re.match(r"([A-Za-z_]\w*)\s*:\s*(.*)$", linea)
            if not m:
                break
            pendientes.append(m.group(1))
            linea = m.group(2).strip()
        if not linea:
            continue
        partes = linea.split(None, 1)
        mn = partes[0].lower()
        ops = [o.strip() for o in partes[1].split(",")] if len(partes) > 1 else []
        items.append((nl, pendientes, mn, ops, linea))
        pendientes = []
    if pendientes:
        raise ErrorAsm(f"la etiqueta '{pendientes[0]}' no esta seguida de ninguna instruccion")
    return items


def main():
    ap = argparse.ArgumentParser(description="Ensamblador RV32I -> lineas prog[n] para el testbench")
    ap.add_argument("-i", "--entrada", default="program.txt")
    ap.add_argument("-o", "--salida", default="machine_code.txt")
    ap.add_argument("--profundidad", type=int, default=256, help="palabras de la memoria de programa (256)")
    a = ap.parse_args()
    try:
        items = leer_fuente(a.entrada)
        # pasada 1: direcciones y etiquetas
        etiquetas, pc = {}, 0
        for nl, labs, mn, ops, txt in items:
            for e in labs:
                if e in etiquetas:
                    raise ErrorAsm(f"la etiqueta '{e}' esta repetida")
                etiquetas[e] = pc
            try:
                pc += 4 * tam_palabras(mn, ops)
            except ErrorAsm as ex:
                raise ErrorAsm(f"linea {nl}: {ex}")
        if pc // 4 > a.profundidad:
            raise ErrorAsm(f"el programa tiene {pc // 4} palabras y la memoria de programa {a.profundidad}")
        # pasada 2: codigo maquina
        salida, pc = [], 0
        for nl, labs, mn, ops, txt in items:
            try:
                palabras = ensamblar(mn, ops, pc, etiquetas)
            except ErrorAsm as ex:
                raise ErrorAsm(f"linea {nl} ('{txt}'): {ex}")
            for k, w in enumerate(palabras):
                texto = (" ".join(l + ":" for l in labs) + " " if labs and k == 0 else "") + (txt if k == 0 else "(continuacion de li)")
                salida.append((pc // 4, pc, w, texto))
                pc += 4
    except (ErrorAsm, OSError) as ex:
        sys.exit(f"ERROR: {ex}")
    with open(a.salida, "w", encoding="utf-8") as f:
        f.write(f"// {len(salida)} palabras de programa, generadas por ensamblador.py desde {os.path.basename(a.entrada)}\n")
        for n, pc, w, texto in salida:
            f.write(f"prog[{n:2d}] = 32'h{w:08X};   // 0x{pc:02X}  {texto}\n")
    print(f"{len(salida)} palabras escritas en {a.salida}")


if __name__ == "__main__":
    main()
