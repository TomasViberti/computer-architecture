#!/usr/bin/env python3
"""
Cargador y ejecutor de programas RISC-V por UART (Basys 3)

Hace lo mismo que el testbench, pero contra la placa:
  1. Lee machine_code.txt (lineas "prog[n] = 32'h...;"), el mismo archivo que usa el testbench.
  2. Manda el programa a la Debug Unit con el comando LOAD.
  3. Lo ejecuta con RUN.
  4. Recibe el estado que la Debug Unit manda sola cuando el programa llega al HALT.
  5. Lo guarda en rtl_state_debug.txt con el mismo formato que escribe el testbench, para poder
     compararlo con el modelo en Python.

Protocolo (version 0), todo con el byte menos significativo primero:
  PC -> FPGA   01 LOAD  N (2 bytes) y N palabras de 4 bytes   -> responde 00 (OK), 01 o 02 (error)
  PC -> FPGA   02 RUN                                         -> responde 00 y, al llegar al HALT,
                                                                 manda el estado (tipo 10)
  Estado: tipo (1), banderas (1), PC (4), CICLOS (4), x0..x31 (128), cantidad de palabras (2),
          memoria de datos (4 bytes por palabra).

Ojo: el reset de la placa (SW15) y la Debug Unit NO vacian los registros ni la memoria de datos.
Para comparar con el modelo conviene programar la FPGA de nuevo antes de cada programa.
"""

import argparse
import re
import struct
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    print("Falta pyserial. Instala con: pip install pyserial")
    sys.exit(1)

try:
    from rich.console import Console
    from rich.markup import escape
    from rich.table import Table
    from rich.panel import Panel
    from rich import box
except ImportError:
    print("Falta rich. Instala con: pip install rich")
    sys.exit(1)

console = Console()

# ---------------- protocolo ----------------
CMD_LOAD = 0x01
CMD_RUN = 0x02
REPLY_OK = 0x00
REPLY_NAMES = {
    0x00: "OK",
    0x01: "comando desconocido",
    0x02: "parametro invalido (N = 0 o mas palabras que la memoria de programa)",
}
PKT_STATE = 0x10
HALT_WORD = 0x0000000B
SILENCIO_TRAS_ERROR = 0.3   # la Debug Unit descarta bytes hasta 100 ms de silencio despues de un error

LINEA_RE = re.compile(r"prog\[\s*(\d+)\s*\]\s*=\s*32'h([0-9a-fA-F_]+)\s*;")


class ErrorProtocolo(Exception):
    """Algo no salio como lo espera el protocolo (respuesta distinta, timeout, paquete raro)."""


@dataclass
class Estado:
    pc: int
    ciclos: int
    halt: bool
    error_imem: bool
    error_dmem: bool
    regs: list
    mem: list


# ---------------- lectura de machine_code.txt ----------------
def leer_machine_code(path, imem_depth):
    """Devuelve (palabras, faltan, repetidas). Falla si no hay programa o no entra en la memoria."""
    palabras = {}
    repetidas = []
    with open(path, encoding="utf-8") as f:
        for num, linea in enumerate(f, 1):
            m = LINEA_RE.search(linea)
            if not m:
                continue
            idx = int(m.group(1))
            valor = int(m.group(2).replace("_", ""), 16)
            if valor > 0xFFFFFFFF:
                raise ValueError(f"linea {num}: la palabra {m.group(2)} no entra en 32 bits")
            if idx in palabras:
                repetidas.append(idx)
            palabras[idx] = valor

    if not palabras:
        raise ValueError("no hay ninguna linea con el formato prog[n] = 32'h...; en el archivo")

    n = max(palabras) + 1
    if n > imem_depth:
        raise ValueError(f"el programa tiene {n} palabras y la memoria de programa solo {imem_depth}")

    faltan = [i for i in range(n) if i not in palabras]
    return [palabras.get(i, 0) for i in range(n)], faltan, repetidas


# ---------------- estado -> archivo ----------------
def estado_a_texto(e):
    """Mismo formato que escribe el testbench en rtl_state.txt."""
    lineas = [
        f"PC={e.pc:08x}",
        f"CICLOS={e.ciclos}",
        f"HALT={int(e.halt)}",
        f"ERROR_IMEM={int(e.error_imem)}",
        f"ERROR_DMEM={int(e.error_dmem)}",
    ]
    lineas += [f"x{i}={v:08x}" for i, v in enumerate(e.regs)]
    lineas += [f"MEM[0x{i * 4:08x}]={w:08x}" for i, w in enumerate(e.mem) if w != 0]
    return "\n".join(lineas) + "\n"


class RiscvUartController:
    def __init__(self, port, baudrate=115200):
        self.port = port
        self.baudrate = baudrate
        try:
            self.ser = serial.Serial(port, baudrate, timeout=0.5, write_timeout=2)
        except serial.SerialException as e:
            console.print(f"[bold red]✗ Error al abrir puerto serial:[/bold red] {escape(str(e))}")
            self._suggest_ports()
            sys.exit(1)

        # Por si quedo algo de una corrida anterior (por ejemplo, un estado a medio recibir)
        time.sleep(0.2)
        self.ser.reset_input_buffer()

        console.print(Panel.fit(
            f"[bold green]✓ Conectado a {self.port} @ {self.baudrate} baud[/bold green]",
            title="Controlador RISC-V UART",
            border_style="green",
        ))

    @staticmethod
    def _suggest_ports():
        ports = list(list_ports.comports())
        if not ports:
            console.print("[yellow]No se detectaron puertos seriales disponibles.[/yellow]")
            return
        table = Table(title="Puertos disponibles", box=box.SIMPLE)
        table.add_column("Puerto")
        table.add_column("Descripcion")
        for p in ports:
            table.add_row(p.device, p.description or "-")
        console.print(table)

    # ---------------- bajo nivel ----------------
    def _leer(self, n, timeout):
        """Lee exactamente n bytes, esperando hasta timeout segundos en total."""
        limite = time.monotonic() + timeout
        buf = bytearray()
        while len(buf) < n:
            restante = limite - time.monotonic()
            if restante <= 0:
                raise ErrorProtocolo(f"timeout: llegaron {len(buf)} de {n} bytes")
            self.ser.timeout = min(restante, 0.25)
            buf += self.ser.read(n - len(buf))
        return bytes(buf)

    def _esperar_ok(self, que):
        """Lee la respuesta a un comando; si no es OK, deja la Debug Unit lista para el proximo."""
        try:
            r = self._leer(1, timeout=2.0)[0]
        except ErrorProtocolo:
            raise ErrorProtocolo(f"la FPGA no respondio al {que}")
        if r != REPLY_OK:
            nombre = REPLY_NAMES.get(r, "respuesta desconocida")
            # Despues de un error la Debug Unit descarta bytes hasta que hay silencio
            time.sleep(SILENCIO_TRAS_ERROR)
            self.ser.reset_input_buffer()
            raise ErrorProtocolo(f"el {que} fue rechazado: 0x{r:02X} ({nombre})")

    # ---------------- comandos ----------------
    def cargar(self, palabras):
        """LOAD: manda el programa a la memoria de instrucciones, desde la direccion 0."""
        trama = struct.pack("<BH", CMD_LOAD, len(palabras))
        trama += b"".join(struct.pack("<I", w) for w in palabras)
        self.ser.reset_input_buffer()
        for i in range(0, len(trama), 256):          # en trozos, sin pausas entre bytes
            self.ser.write(trama[i:i + 256])
        self.ser.flush()
        self._esperar_ok("LOAD")
        return len(trama)

    def ejecutar(self):
        """RUN: el procesador arranca desde la direccion 0 y corre hasta el HALT."""
        self.ser.write(bytes([CMD_RUN]))
        self.ser.flush()
        self._esperar_ok("RUN")

    def leer_estado(self, timeout):
        """Espera el paquete de estado que la Debug Unit manda sola al llegar al HALT."""
        try:
            tipo = self._leer(1, timeout)[0]
        except ErrorProtocolo:
            raise ErrorProtocolo(
                f"no llego el estado en {timeout:g} s. Si el programa no termina (por ejemplo, un bucle "
                "infinito), baja y sube el switch SW15 para cortarlo. Si es un programa largo, proba con "
                "--timeout mayor")
        if tipo != PKT_STATE:
            self.ser.reset_input_buffer()
            raise ErrorProtocolo(f"el primer byte del estado es 0x{tipo:02X}, se esperaba 0x{PKT_STATE:02X}")

        try:
            # banderas (1) + PC (4) + CICLOS (4) + registros (128) + cantidad de palabras (2)
            cab = self._leer(1 + 4 + 4 + 128 + 2, timeout=3.0)
            flags = cab[0]
            pc, ciclos = struct.unpack("<II", cab[1:9])
            regs = list(struct.unpack("<32I", cab[9:137]))
            nw = struct.unpack("<H", cab[137:139])[0]
            mem = list(struct.unpack(f"<{nw}I", self._leer(4 * nw, timeout=5.0)))
        except ErrorProtocolo as e:
            raise ErrorProtocolo(f"el estado llego incompleto ({e})")

        return Estado(pc=pc, ciclos=ciclos, halt=bool(flags & 1), error_imem=bool(flags & 2),
                      error_dmem=bool(flags & 4), regs=regs, mem=mem)

    def close(self):
        if self.ser.is_open:
            self.ser.close()
            console.print("[green]✓ Conexion cerrada[/green]")


# ---------------- presentacion ----------------
def mostrar_estado(e):
    flags = []
    flags.append("[green]HALT[/green]" if e.halt else "[red]sin HALT[/red]")
    flags.append("[red]ERROR_IMEM[/red]" if e.error_imem else "[dim]sin error de memoria de programa[/dim]")
    flags.append("[red]ERROR_DMEM[/red]" if e.error_dmem else "[dim]sin error de memoria de datos[/dim]")
    console.print(Panel.fit(
        f"[bold]PC final:[/bold] 0x{e.pc:08X}    [bold]CICLOS:[/bold] {e.ciclos}\n" + "   ".join(flags),
        title="Estado recibido", border_style="cyan"))

    tabla = Table(title="Registros", box=box.SIMPLE_HEAVY)
    for _ in range(4):
        tabla.add_column("Reg", style="bold cyan")
        tabla.add_column("Valor", style="green")
    for fila in range(8):
        celdas = []
        for col in range(4):
            r = fila + 8 * col
            celdas += [f"x{r}", f"0x{e.regs[r]:08X}"]
        tabla.add_row(*celdas)
    console.print(tabla)

    no_cero = [(i, w) for i, w in enumerate(e.mem) if w != 0]
    if no_cero:
        tm = Table(title=f"Memoria de datos (palabras distintas de cero, de {len(e.mem)})", box=box.SIMPLE_HEAVY)
        tm.add_column("Direccion", style="bold cyan")
        tm.add_column("Hex", style="green")
        tm.add_column("Decimal")
        for i, w in no_cero:
            tm.add_row(f"0x{i * 4:08X}", f"0x{w:08X}", str(w))
        console.print(tm)
    else:
        console.print("[dim]Memoria de datos: todas las palabras en cero[/dim]")


def resolve_port(explicit_port):
    """Devuelve el puerto a usar: el explicito, el unico detectado, o pregunta al usuario."""
    if explicit_port:
        return explicit_port
    ports = list(list_ports.comports())
    if len(ports) == 1:
        console.print(f"[dim]Usando unico puerto detectado: {ports[0].device}[/dim]")
        return ports[0].device
    RiscvUartController._suggest_ports()
    return console.input("[bold]Ingresa el puerto a usar:[/bold] ").strip()


def comparar_con_modelo(modelo, entrada, salida):
    """Corre el modelo en Python con el mismo programa y el estado recibido (como en el flujo del testbench)."""
    console.rule("[bold]Comparacion con el modelo[/bold]")
    r = subprocess.run([sys.executable, modelo, "-i", str(entrada), "--rtl", str(salida)],
                       capture_output=True, text=True)
    console.print((r.stdout + r.stderr).rstrip())
    return r.returncode


def main():
    parser = argparse.ArgumentParser(description="Carga un programa RISC-V por UART, lo ejecuta y recibe el estado final")
    parser.add_argument("-p", "--port", default="COM12", help="Puerto serial (ej: COM8, /dev/ttyUSB0)")
    parser.add_argument("-b", "--baud", type=int, default=115200, help="Baudrate (default: 115200)")
    parser.add_argument("-i", "--input", default="machine_code.txt", help="Archivo con el programa (default: machine_code.txt)")
    parser.add_argument("-o", "--output", default="rtl_state_debug.txt", help="Archivo donde se guarda el estado (default: rtl_state_debug.txt)")
    parser.add_argument("-t", "--timeout", type=float, default=10.0,
                        help="Segundos que se espera el estado despues de RUN (default: 10)")
    parser.add_argument("--imem-depth", type=int, default=256, help="Palabras de la memoria de programa (default: 256)")
    parser.add_argument("--model", default=None,
                        help="Ruta al modelo en Python (ej: monocycle_model.py): si se indica, se corre al final para comparar")
    parser.add_argument("--list-ports", action="store_true", help="Mostrar los puertos disponibles y salir")
    args = parser.parse_args()

    if args.list_ports:
        RiscvUartController._suggest_ports()
        return 0

    # Primero el programa, asi un error en el archivo aparece antes de tocar el puerto
    try:
        palabras, faltan, repetidas = leer_machine_code(args.input, args.imem_depth)
    except (OSError, ValueError) as e:
        console.print(f"[bold red]✗ {escape(args.input)}:[/bold red] {escape(str(e))}")
        return 1
    console.print(f"[bold]Programa:[/bold] {escape(args.input)}, {len(palabras)} palabras")
    if faltan:
        console.print(f"[yellow]⚠ Faltan las lineas prog\\[n] para n = {faltan}: se mandan en cero[/yellow]")
    if repetidas:
        console.print(f"[yellow]⚠ Lineas repetidas para n = {sorted(set(repetidas))}: vale la ultima[/yellow]")
    if HALT_WORD not in palabras:
        console.print("[dim]El programa no tiene ninguna instruccion HALT (0x0000000B): termina solo si el PC sale de la memoria.[/dim]")

    port = resolve_port(args.port)
    ctrl = RiscvUartController(port=port, baudrate=args.baud)
    codigo = 0
    try:
        t0 = time.monotonic()
        with console.status("Cargando programa..."):
            enviados = ctrl.cargar(palabras)
        console.print(f"[green]✓ LOAD:[/green] {len(palabras)} palabras ({enviados} bytes) en {time.monotonic() - t0:.2f} s")

        ctrl.ejecutar()
        console.print("[green]✓ RUN:[/green] el procesador esta ejecutando")

        t1 = time.monotonic()
        with console.status("Esperando el estado..."):
            estado = ctrl.leer_estado(args.timeout)
        console.print(f"[green]✓ Estado recibido[/green] ({time.monotonic() - t1:.2f} s desde RUN)")

        Path(args.output).write_text(estado_a_texto(estado), encoding="utf-8", newline="\n")
        console.print(f"[green]✓ Estado guardado en[/green] {args.output}")
        mostrar_estado(estado)
        console.print("[dim]Nota: los registros y la memoria de datos no se vacian entre ejecuciones. "
                      "Para comparar con el modelo, programa la FPGA de nuevo antes de cada programa.[/dim]")

        if args.model:
            codigo = comparar_con_modelo(args.model, args.input, args.output)

    except ErrorProtocolo as e:
        console.print(f"[bold red]✗ {escape(str(e))}[/bold red]")
        codigo = 1
    except KeyboardInterrupt:
        console.print("\n[yellow]Interrumpido. Si el programa seguia ejecutando, baja y sube SW15 para cortarlo.[/yellow]")
        codigo = 130
    except serial.SerialException as e:
        console.print(f"[bold red]✗ Error de comunicacion:[/bold red] {escape(str(e))}")
        codigo = 1
    finally:
        ctrl.close()
    return codigo


if __name__ == "__main__":
    sys.exit(main())
