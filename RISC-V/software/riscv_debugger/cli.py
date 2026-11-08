"""CLI: comandos sueltos (para scripts) y un shell interactivo (para depurar a mano).

    python cli.py --sim run ../scripts/program.txt
    python cli.py -p /dev/ttyUSB1 run programa.s --compare
    python cli.py --sim step programa.s -n 10
    python cli.py --sim shell programa.s
"""
import argparse
import cmd
import json
import shlex
import sys

from rich import box
from rich.console import Console, Group
from rich.markup import escape
from rich.panel import Panel
from rich.table import Table

from . import protocol as P
from .program import ABI_NAMES, AsmError, disassemble, fmt_value, load_program
from .session import DebugSession
from .transport import list_serial_ports

console = Console(highlight=False)
err = Console(highlight=False, stderr=True)   # mensajes de progreso: stdout queda limpio para --json


# ============================================================================
# Presentacion (rich)
# ============================================================================

def _flags(st):
    out = ["[green]HALT[/green]" if st.halted else "[yellow]ejecutando[/yellow]"]
    out.append("[red]ERROR_IMEM[/red]" if st.err_imem else "[dim]imem ok[/dim]")
    out.append("[red]ERROR_DMEM[/red]" if st.err_dmem else "[dim]dmem ok[/dim]")
    return "  ".join(out)


def instr_at(program, pc):
    if program is None or pc % 4 or not 0 <= pc // 4 < len(program):
        return None
    return program.words[pc // 4]


def state_summary(st, program=None):
    w = instr_at(program, st.pc)
    nxt = f"   [bold]proxima:[/bold] {escape(disassemble(w, st.pc))}" if w is not None else ""
    return (f"[bold]PC[/bold] 0x{st.pc:08X}   [bold]CICLOS[/bold] {st.cycles}   {_flags(st)}"
            f"   [dim]({st.origin})[/dim]{nxt}")


def regs_table(st, prev=None):
    changed = st.changed_regs(prev)
    t = Table(title="Registros", box=box.SIMPLE_HEAVY, pad_edge=False)
    for _ in range(2):
        t.add_column("Reg", style="bold cyan", no_wrap=True)
        t.add_column("Hex", no_wrap=True)
        t.add_column("Decimal", justify="right", style="dim", no_wrap=True)
    for row in range(16):
        cells = []
        for r in (row, row + 16):
            style = "bold black on yellow" if r in changed else ("green" if st.regs[r] else "dim")
            cells += [f"x{r:<2} {ABI_NAMES[r]}", f"[{style}]0x{st.regs[r]:08X}[/{style}]",
                      fmt_value(st.regs[r], "sdec")]
        t.add_row(*cells)
    return t


def mem_table(st, prev=None, show_all=False):
    changed = st.changed_mem(prev)
    rows = [(i, w) for i, w in enumerate(st.mem) if show_all or w != 0 or i in changed]
    if not rows:
        return "[dim]Memoria de datos: todas las palabras en cero[/dim]"
    t = Table(title=f"Memoria de datos ({len(rows)} de {len(st.mem)} palabras)", box=box.SIMPLE_HEAVY)
    t.add_column("Direccion", style="bold cyan")
    t.add_column("Hex")
    t.add_column("Decimal", justify="right")
    t.add_column("Bytes (b0 b1 b2 b3)", style="dim")
    for i, w in rows:
        style = "bold black on yellow" if i in changed else "green"
        t.add_row(f"0x{i * 4:08X}", f"[{style}]0x{w:08X}[/{style}]", fmt_value(w, "sdec"),
                  " ".join(f"{(w >> (8 * k)) & 0xFF:02x}" for k in range(4)))
    return t


def latches_table(st, prev=None):
    if not st.latches:
        return "[dim]Sin latches intermedios (el monociclo no tiene; los manda el pipeline)[/dim]"
    prev_map = {l.id: dict((n, v) for n, v, _ in l.fields()) for l in (prev.latches if prev else [])}
    t = Table(title="Latches intermedios", box=box.SIMPLE_HEAVY)
    t.add_column("Latch", style="bold magenta")
    t.add_column("Campo", style="cyan")
    t.add_column("Valor")
    for l in st.latches:
        first = True
        for name, v, fmt in l.fields():
            old = prev_map.get(l.id, {}).get(name, v)
            txt = escape(fmt_value(v, fmt))
            t.add_row(l.name if first else "", name, f"[bold yellow]{txt}[/bold yellow]" if old != v else txt)
            first = False
    return t


def show_state(st, prev=None, program=None, mem_all=False):
    console.print(Panel(Group(state_summary(st, program), regs_table(st, prev),
                              mem_table(st, prev, mem_all), latches_table(st, prev)),
                        title="Estado", border_style="cyan"))


def change_list(st, prev):
    out = [f"x{r}: {prev.regs[r]:#x} -> {st.regs[r]:#x}" for r in sorted(st.changed_regs(prev))] if prev else []
    if prev:
        out += [f"MEM[{i * 4:#x}]: {prev.mem[i] if i < len(prev.mem) else 0:#x} -> {st.mem[i]:#x}"
                for i in sorted(st.changed_mem(prev))]
    return out


def show_step(st, prev, program):
    """Una linea por paso: lo que se ejecuto y lo que cambio."""
    pc0 = prev.pc if prev is not None and not prev.halted else 0
    w = instr_at(program, pc0)
    ins = disassemble(w, pc0) if w is not None else "?"
    ch = (", ".join(change_list(st, prev)) or "-") if prev else "(sin estado anterior para comparar)"
    halt = "  [green]HALT[/green]" if st.halted else ""
    console.print(f"[dim]{st.cycles:5d}[/dim]  [cyan]0x{pc0:04x}[/cyan]  {escape(ins):<28} "
                  f"[yellow]{escape(ch)}[/yellow]{halt}")


def show_program(program, pc=None):
    t = Table(title=f"Memoria de programa ({len(program)} palabras)", box=box.SIMPLE)
    t.add_column("", width=2)
    t.add_column("Dir", style="cyan")
    t.add_column("Hex", style="dim")
    t.add_column("Instruccion")
    t.add_column("Fuente", style="dim")
    for i, w in enumerate(program.words):
        here = pc == i * 4
        t.add_row("▶" if here else "", f"0x{i * 4:04x}", f"{w:08x}",
                  f"[bold reverse]{escape(disassemble(w, i * 4))}[/bold reverse]" if here
                  else escape(disassemble(w, i * 4)),
                  escape(program.source[i] if i < len(program.source) else ""))
    console.print(t)


def show_compare(diffs):
    if not diffs:
        console.print("[bold green]IGUALES:[/bold green] el estado recibido y el modelo coinciden")
    else:
        console.print(f"[bold red]DIFERENTES:[/bold red] {len(diffs)} diferencia(s)")
        for d in diffs:
            console.print(escape(d))
        console.print("[dim]Ojo: los registros y la memoria de datos no se vacian entre programas. "
                      "Para comparar, reprograma la FPGA antes de cargar el programa.[/dim]")


def log(msg, level="info"):
    style = {"warn": "yellow", "error": "bold red"}.get(level, "dim")
    err.print(f"[{style}]· {escape(msg)}[/{style}]")


# ============================================================================
# Conexion
# ============================================================================

def show_ports():
    ports = list_serial_ports()
    if not ports:
        console.print("[yellow]No se detectaron puertos serie[/yellow]")
        return
    t = Table(title="Puertos disponibles", box=box.SIMPLE)
    t.add_column("Puerto")
    t.add_column("Descripcion")
    for dev, desc in ports:
        t.add_row(dev, desc)
    console.print(t)


def connect(args):
    if args.sim:
        s = DebugSession.open_sim(version=args.sim_protocol, log=log)
    else:
        port = args.port
        if not port:
            ports = list_serial_ports()
            if len(ports) != 1:
                show_ports()
                raise SystemExit("Indica el puerto con -p (o usa --sim para el simulador)")
            port = ports[0][0]
        try:
            s = DebugSession.open_serial(port, args.baud, log=log, probe=not args.no_probe)
        except Exception as e:
            show_ports()
            raise SystemExit(f"No se pudo abrir {port}: {e}")
    err.print(f"[green]✓ Conectado:[/green] {escape(s.name)}   "
                  f"[dim]Debug Unit v{s.info.version} ({', '.join(s.info.cap_names())})[/dim]")
    return s


def read_program(path, depth=256):
    try:
        p = load_program(path, depth)
    except (OSError, AsmError) as e:
        raise SystemExit(f"{path}: {e}")
    err.print(f"[bold]Programa:[/bold] {escape(path)}, {len(p)} palabras")
    return p


# ============================================================================
# Shell interactivo
# ============================================================================

class Shell(cmd.Cmd):
    intro = ("Shell de la Debug Unit. 'help' lista los comandos, 'help <comando>' explica uno.\n"
             "Enter vacio repite el ultimo comando (util para 'step').")

    def __init__(self, session, program=None, timeout=10.0):
        super().__init__()
        self.s, self.timeout = session, timeout
        self.view = None                # indice del historial que se muestra (None = el ultimo)
        self.program_path = None
        self.prompt = "rv> "
        if program:
            self.do_load(program)

    def onecmd(self, line):
        try:
            return super().onecmd(line)
        except (P.ProtocolError, AsmError, OSError, ValueError) as e:
            console.print(f"[bold red]✗ {escape(str(e))}[/bold red]")
        except KeyboardInterrupt:
            console.print("[yellow]interrumpido[/yellow]")

    def emptyline(self):
        if self.lastcmd:
            return self.onecmd(self.lastcmd)

    def default(self, line):
        console.print(f"[red]comando desconocido: {escape(line)}[/red] ('help' para ver la lista)")

    def _current(self):
        if not self.s.history:
            raise P.ProtocolError("todavia no hay estado: usa run o step")
        i = len(self.s.history) - 1 if self.view is None else self.view
        return i, self.s.history[i], self.s.history[i - 1] if i > 0 else None

    # ---- programa ----
    def do_load(self, arg):
        """load [archivo]   Ensambla (o lee machine_code) y lo carga en la memoria de programa.
                     Sin archivo vuelve a cargar el ultimo (util despues de editarlo)."""
        path = arg.strip() or self.program_path
        if not path:
            raise ValueError("indica el archivo: load programa.s")
        p = load_program(path, self.s.info.imem_depth)
        self.s.load(p)
        self.program_path = path
        console.print(f"[green]✓[/green] {escape(path)}: {len(p)} palabras cargadas")

    def do_prog(self, arg):
        """prog   Muestra la memoria de programa cargada, marcando el PC actual."""
        if not self.s.program:
            raise P.ProtocolError("no hay programa cargado")
        st = self.s.state
        show_program(self.s.program, st.pc if st and not st.halted else (None if st else 0))

    # ---- ejecucion ----
    def do_run(self, arg):
        """run   Modo continuo: ejecuta desde PC = 0 hasta el HALT y muestra el estado."""
        prev = self.s.state
        st = self.s.run(self.timeout)
        self.view = None
        show_state(st, prev, self.s.program)

    def do_step(self, arg):
        """step [n]   Modo paso a paso: n ciclos de clock (1 por defecto), una linea por ciclo."""
        n = int(arg) if arg.strip() else 1
        self.view = None
        for _ in range(n):
            prev = self.s.state
            st = self.s.step()
            show_step(st, prev, self.s.program)
            if st.halted:
                break

    # ---- inspeccion ----
    def do_state(self, arg):
        """state [all]   Estado completo (registros, memoria, latches). 'all' muestra toda la memoria."""
        i, st, prev = self._current()
        console.print(f"[dim]estado #{i} del historial[/dim]")
        show_state(st, prev, self.s.program, mem_all=arg.strip() == "all")

    def do_regs(self, arg):
        """regs   Banco de registros (en amarillo los que cambiaron)."""
        _, st, prev = self._current()
        console.print(state_summary(st, self.s.program))
        console.print(regs_table(st, prev))

    def do_mem(self, arg):
        """mem [all]   Memoria de datos usada (o toda, con 'all')."""
        _, st, prev = self._current()
        console.print(mem_table(st, prev, arg.strip() == "all"))

    def do_latches(self, arg):
        """latches   Latches intermedios del pipeline (IF/ID, ID/EX, EX/MEM, MEM/WB)."""
        _, st, prev = self._current()
        console.print(latches_table(st, prev))

    def do_history(self, arg):
        """history   Lista los estados recibidos. 'show <n>' vuelve a uno; 'show' vuelve al ultimo."""
        for i, st in enumerate(self.s.history[-40:], start=max(0, len(self.s.history) - 40)):
            mark = "▶" if (self.view if self.view is not None else len(self.s.history) - 1) == i else " "
            console.print(f"{mark} #{i:<4} {st.origin:<4} ciclo {st.cycles:<6} PC 0x{st.pc:08x}"
                          + ("  HALT" if st.halted else ""))

    def do_show(self, arg):
        """show [n]   Muestra el estado n del historial (sin n, el ultimo)."""
        if not arg.strip():
            self.view = None
        else:
            n = int(arg)
            if not 0 <= n < len(self.s.history):
                raise ValueError(f"el historial tiene {len(self.s.history)} estados")
            self.view = n
        self.do_state("")

    # ---- utilidades ----
    def do_compare(self, arg):
        """compare   Compara el estado con lo que da el modelo en Python con el mismo programa."""
        _, st, _ = self._current()
        show_compare(self.s.compare_with_model(st))

    def do_save(self, arg):
        """save [archivo]   Guarda el estado en el formato de rtl_state.txt (default: rtl_state_debug.txt)."""
        _, st, _ = self._current()
        path = arg.strip() or "rtl_state_debug.txt"
        self.s.save_state(st, path)
        console.print(f"[green]✓ guardado en {escape(path)}[/green]")

    def do_info(self, arg):
        """info   Version y capacidades de la Debug Unit (vuelve a preguntar)."""
        i = self.s.probe()
        console.print(f"v{i.version}  capacidades: {', '.join(i.cap_names())}  "
                      f"imem {i.imem_depth} palabras  dmem {i.dmem_depth} palabras")

    def do_reset(self, arg):
        """reset   (simulador) Como bajar y subir el switch de reset: corta un programa colgado."""
        self.s.sim_reset_switch()

    def do_reprogram(self, arg):
        """reprogram   (simulador) Como reprogramar la FPGA: vacia registros y memorias."""
        self.s.sim_reprogram()
        self.view = None

    def do_quit(self, arg):
        """quit   Sale del shell."""
        return True

    do_exit = do_quit
    do_EOF = do_quit


# ============================================================================
# main
# ============================================================================

CONN_DEFAULTS = {"port": None, "baud": 115200, "sim": False, "sim_protocol": 1,
                 "no_probe": False, "timeout": 10.0}


def build_parser():
    # Las opciones de conexion se aceptan antes o despues del subcomando. Con SUPPRESS el
    # subparser no pisa con su default lo que se dio antes; los defaults se ponen en main().
    S = argparse.SUPPRESS
    conn = argparse.ArgumentParser(add_help=False)
    g = conn.add_argument_group("conexion")
    g.add_argument("-p", "--port", default=S, help="puerto serie (COM8, /dev/ttyUSB1). Sin -p: el unico detectado")
    g.add_argument("-b", "--baud", type=int, default=S, help="baudrate (default: 115200)")
    g.add_argument("--sim", action="store_true", default=S, help="usar la Debug Unit simulada en lugar de la placa")
    g.add_argument("--sim-protocol", type=int, choices=(0, 1), default=S,
                   help="0 = como el RTL actual (LOAD/RUN), 1 = propuesta con STEP (default)")
    g.add_argument("--no-probe", action="store_true", default=S, help="no preguntar version al conectar (asume v0)")
    g.add_argument("-t", "--timeout", type=float, default=S, help="segundos de espera del estado tras RUN (default: 10)")

    ap = argparse.ArgumentParser(prog="cli.py", description="CLI de la Debug Unit RISC-V",
                                 parents=[conn])
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("ports", help="lista los puertos serie")
    sub.add_parser("info", parents=[conn], help="version y capacidades de la Debug Unit")

    a = sub.add_parser("asm", help="ensambla a machine_code.txt (sin conectarse)")
    a.add_argument("source")
    a.add_argument("-o", "--output", default="machine_code.txt")

    d = sub.add_parser("disasm", help="muestra un programa desensamblado (sin conectarse)")
    d.add_argument("program")

    for name, hlp in (("run", "carga, ejecuta hasta el HALT y muestra el estado final"),
                      ("step", "carga y ejecuta paso a paso, mostrando cada ciclo")):
        r = sub.add_parser(name, parents=[conn], help=hlp)
        r.add_argument("program", help="assembler (.s/.txt) o machine_code.txt")
        r.add_argument("-o", "--output", help="guardar el estado final (formato rtl_state.txt)")
        r.add_argument("--compare", action="store_true", help="comparar con el modelo en Python")
        r.add_argument("--json", action="store_true", help="imprimir el/los estado(s) en JSON")
        r.add_argument("--mem-all", action="store_true", help="mostrar toda la memoria de datos")
        if name == "step":
            r.add_argument("-n", type=int, default=1000, help="maximo de ciclos (default: hasta el HALT, 1000)")

    sh = sub.add_parser("shell", parents=[conn], help="shell interactivo")
    sh.add_argument("program", nargs="?")
    return ap


def main(argv=None):
    args = build_parser().parse_args(argv)
    for k, v in CONN_DEFAULTS.items():
        if not hasattr(args, k):
            setattr(args, k, v)

    if args.cmd == "ports":
        show_ports()
        return 0
    if args.cmd == "asm":
        p = read_program(args.source)
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(p.to_machine_code())
        console.print(f"[green]✓ {len(p)} palabras escritas en {escape(args.output)}[/green]")
        return 0
    if args.cmd == "disasm":
        show_program(read_program(args.program))
        return 0

    program = read_program(args.program) if getattr(args, "program", None) and args.cmd != "shell" else None
    s = connect(args)
    try:
        if args.cmd == "info":
            i = s.info
            console.print(f"v{i.version}  capacidades: {', '.join(i.cap_names())}  "
                          f"imem {i.imem_depth}  dmem {i.dmem_depth}")
            return 0
        if args.cmd == "shell":
            Shell(s, args.program, args.timeout).cmdloop()
            return 0

        s.load(program)
        if args.cmd == "run":
            states = [s.run(args.timeout)]
        else:
            states = []
            for _ in range(args.n):
                prev = s.state
                states.append(s.step())
                if not args.json:
                    show_step(states[-1], prev, program)
                if states[-1].halted:
                    break
        final = states[-1]
        if args.json:
            print(json.dumps([st.to_dict() for st in states] if args.cmd == "step" else final.to_dict()))
        else:
            show_state(final, states[-2] if len(states) > 1 else None, program, args.mem_all)
        if args.output:
            s.save_state(final, args.output)
            console.print(f"[green]✓ estado guardado en {escape(args.output)}[/green]")
        if args.compare:
            diffs = s.compare_with_model(final)
            show_compare(diffs)
            return 1 if diffs else 0
        return 0
    except P.ProtocolError as e:
        console.print(f"[bold red]✗ {escape(str(e))}[/bold red]")
        return 1
    except KeyboardInterrupt:
        console.print("\n[yellow]interrumpido[/yellow]")
        return 130
    finally:
        s.close()


if __name__ == "__main__":
    sys.exit(main())
