"""TUI (Textual): todo el estado del procesador en una pantalla, manejada con el teclado.

    python tui.py --sim ../scripts/program.txt
    python tui.py -p /dev/ttyUSB1 programa.s

Teclas (tambien aparecen abajo):
    l cargar (vuelve a leer el archivo)   r run    s step    a auto-step    c comparar
    ← → navegar el historial    fin  volver al ultimo estado    m toda la memoria / solo usada
    o abrir otro archivo        w guardar estado    x reset (sim)    p reprogramar (sim)    q salir
"""
import argparse
import sys
import threading

from rich.markup import escape
from rich.text import Text
from textual import work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.widgets import DataTable, Footer, Header, Input, RichLog, Static

from . import protocol as P
from .program import ABI_NAMES, AsmError, disassemble, fmt_value, load_program
from .session import DebugSession
from .transport import list_serial_ports

CHANGED = "bold black on yellow"


class DebugTUI(App):
    TITLE = "RISC-V Debug Unit"
    CSS = """
    #main { height: 1fr; }
    .pane { border: round $primary; height: 1fr; }
    .pane:focus-within { border: round $accent; }
    #prog-pane { width: 54; }
    #regs-pane { width: 42; }
    #right { width: 1fr; }
    #mem-pane { height: 2fr; }
    #latch-pane { height: 1fr; }
    #status { height: 3; border: round $secondary; padding: 0 1; }
    #log { height: 7; border: round $secondary; }
    #open { dock: bottom; display: none; }
    DataTable { height: 1fr; }
    """
    BINDINGS = [
        Binding("l", "load", "Cargar"),
        Binding("r", "run", "Run"),
        Binding("s", "step", "Step"),
        Binding("a", "auto", "Auto-step"),
        Binding("left", "hist(-1)", "◀ Hist", show=True),
        Binding("right", "hist(1)", "Hist ▶", show=True),
        Binding("end", "hist_last", "Ultimo", show=False),
        Binding("c", "compare", "Comparar"),
        Binding("m", "toggle_mem", "Memoria"),
        Binding("o", "open", "Abrir"),
        Binding("w", "save", "Guardar"),
        Binding("x", "sim_reset", "Reset(sim)", show=False),
        Binding("p", "sim_reprogram", "Reprog(sim)", show=False),
        Binding("q", "quit", "Salir"),
    ]

    def __init__(self, session: DebugSession, program_path=None, timeout=10.0, auto_ms=300):
        super().__init__()
        self.s = session
        self.path = program_path
        self.timeout = timeout
        self.auto_ms = auto_ms
        self.view = None                # indice del historial mostrado (None = ultimo)
        self.mem_all = False
        self._auto = None
        self._busy = False

    # ---------------- armado ----------------
    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        with Horizontal(id="main"):
            with Vertical(id="prog-pane", classes="pane"):
                yield DataTable(id="prog", cursor_type="row", zebra_stripes=True)
            with Vertical(id="regs-pane", classes="pane"):
                yield DataTable(id="regs", cursor_type="row", zebra_stripes=True)
            with Vertical(id="right"):
                with Vertical(id="mem-pane", classes="pane"):
                    yield DataTable(id="mem", cursor_type="row", zebra_stripes=True)
                with Vertical(id="latch-pane", classes="pane"):
                    yield DataTable(id="latch", cursor_type="row")
        yield Static(id="status")
        yield RichLog(id="log", markup=True, wrap=True)
        yield Input(placeholder="archivo de programa (.s, .txt o machine_code.txt) y Enter", id="open")
        yield Footer()

    def on_mount(self):
        self.sub_title = f"{self.s.name} · Debug Unit v{self.s.info.version} " \
                         f"({', '.join(self.s.info.cap_names())})"
        for tid, title in (("prog-pane", "Memoria de programa"), ("regs-pane", "Registros"),
                           ("mem-pane", "Memoria de datos"), ("latch-pane", "Latches intermedios")):
            self.query_one(f"#{tid}").border_title = title
        self.query_one("#prog", DataTable).add_columns(" ", "Dir", "Hex", "Instruccion")
        self.query_one("#regs", DataTable).add_columns("Reg", "ABI", "Hex", "Decimal")
        self.query_one("#mem", DataTable).add_columns("Direccion", "Hex", "Decimal", "Bytes")
        self.query_one("#latch", DataTable).add_columns("Latch", "Campo", "Valor")
        # La sesion loguea desde los hilos de trabajo y tambien desde el hilo principal
        main = threading.get_ident()
        self.s.log = lambda msg, level="info": (self.log_msg(msg, level) if threading.get_ident() == main
                                                else self.call_from_thread(self.log_msg, msg, level))
        if not self.s.can_step:
            self.log_msg("Esta Debug Unit no soporta STEP: solo modo continuo (r).", "warn")
        self.refresh_views()
        if self.path:
            self.action_load()

    # ---------------- utilidades ----------------
    def log_msg(self, msg, level="info"):
        color = {"warn": "yellow", "error": "bold red", "ok": "green"}.get(level, "white")
        self.query_one("#log", RichLog).write(f"[{color}]{escape(str(msg))}[/{color}]")

    def _shown(self):
        h = self.s.history
        if not h:
            return None, None, None
        i = len(h) - 1 if self.view is None else self.view
        return i, h[i], h[i - 1] if i > 0 else None

    def _start(self):
        if self._busy:
            self.log_msg("esperando la respuesta del comando anterior...", "warn")
            return False
        self._busy = True
        return True

    def _done(self):
        self._busy = False
        self.view = None
        self.refresh_views()

    def _fail(self, e):
        self._busy = False
        self.stop_auto()
        self.log_msg(f"✗ {e}", "error")
        self.refresh_views()

    # ---------------- dibujo ----------------
    def refresh_views(self):
        i, st, prev = self._shown()
        self._draw_program(st)
        self._draw_regs(st, prev)
        self._draw_mem(st, prev)
        self._draw_latches(st, prev)
        self._draw_status(i, st)

    def _draw_program(self, st):
        t = self.query_one("#prog", DataTable)
        t.clear()
        p = self.s.program
        if p is None:
            t.add_row("", "", "", Text("(sin programa: 'l' u 'o')", style="dim"))
            return
        pc = None if st is None else st.pc
        for k, w in enumerate(p.words):
            here = pc == k * 4
            style = "bold reverse" if here else ""
            t.add_row("▶" if here else "", Text(f"{k * 4:04x}", style="cyan"),
                      Text(f"{w:08x}", style="dim"), Text(disassemble(w, k * 4), style=style))
        if pc is not None and pc % 4 == 0 and pc // 4 < len(p):
            t.move_cursor(row=pc // 4, animate=False)

    def _draw_regs(self, st, prev):
        t = self.query_one("#regs", DataTable)
        t.clear()
        changed = st.changed_regs(prev) if st else set()
        for r in range(32):
            v = st.regs[r] if st else 0
            style = CHANGED if r in changed else ("green" if v else "dim")
            t.add_row(Text(f"x{r}", style="bold cyan"), ABI_NAMES[r], Text(f"0x{v:08x}", style=style),
                      Text(fmt_value(v, "sdec"), style=style))

    def _draw_mem(self, st, prev):
        t = self.query_one("#mem", DataTable)
        t.clear()
        pane = self.query_one("#mem-pane")
        if st is None:
            pane.border_subtitle = ""
            return
        changed = st.changed_mem(prev)
        rows = [(k, w) for k, w in enumerate(st.mem) if self.mem_all or w or k in changed]
        pane.border_subtitle = f"{'todas' if self.mem_all else 'usadas'}: {len(rows)}/{len(st.mem)} (m)"
        for k, w in rows:
            style = CHANGED if k in changed else "green" if w else "dim"
            t.add_row(Text(f"0x{k * 4:08x}", style="cyan"), Text(f"0x{w:08x}", style=style),
                      fmt_value(w, "sdec"), " ".join(f"{(w >> (8 * b)) & 0xFF:02x}" for b in range(4)))

    def _draw_latches(self, st, prev):
        t = self.query_one("#latch", DataTable)
        t.clear()
        if st is None or not st.latches:
            t.add_row(Text("-", style="dim"), Text("el monociclo no tiene latches", style="dim"), "")
            return
        before = {l.id: {n: v for n, v, _ in l.fields()} for l in (prev.latches if prev else [])}
        for l in st.latches:
            for j, (name, v, fmt) in enumerate(l.fields()):
                old = before.get(l.id, {}).get(name, v)
                t.add_row(Text(l.name if j == 0 else "", style="bold magenta"), name,
                          Text(fmt_value(v, fmt), style=CHANGED if old != v else ""))

    def _draw_status(self, i, st):
        w = self.query_one("#status", Static)
        if st is None:
            w.update("Sin estado todavia. [b]l[/b] carga el programa, [b]r[/b] lo ejecuta"
                     + (", [b]s[/b] da un paso." if self.s.can_step else "."))
            return
        flags = ("[green]HALT[/green]" if st.halted else "[yellow]en ejecucion[/yellow]") \
            + ("  [red]ERROR_IMEM[/red]" if st.err_imem else "") + ("  [red]ERROR_DMEM[/red]" if st.err_dmem else "")
        hist = f"historial {i + 1}/{len(self.s.history)}" + ("  [reverse] VIENDO EL PASADO [/reverse]"
                                                            if self.view is not None else "")
        auto = "  [bold magenta]AUTO[/bold magenta]" if self._auto else ""
        prog = f"  [dim]{self.path}[/dim]" if self.path else ""
        w.update(f"[b]PC[/b] 0x{st.pc:08x}   [b]CICLOS[/b] {st.cycles}   {flags}   "
                 f"[dim]({st.origin})[/dim]   {hist}{auto}{prog}")

    # ---------------- acciones ----------------
    def action_load(self):
        if not self.path:
            self.action_open()
            return
        try:
            prog = load_program(self.path, self.s.info.imem_depth)
        except (OSError, AsmError) as e:
            self.log_msg(f"✗ {self.path}: {e}", "error")
            return
        if self._start():
            self._load(prog)

    @work(thread=True)
    def _load(self, prog):
        try:
            self.s.load(prog)
            self.call_from_thread(self.log_msg, f"✓ {self.path}: {len(prog)} palabras", "ok")
            self.call_from_thread(self._done)
        except P.ProtocolError as e:
            self.call_from_thread(self._fail, e)

    def action_run(self):
        if self._start():
            self._run()

    @work(thread=True)
    def _run(self):
        try:
            self.s.run(self.timeout)
            self.call_from_thread(self._done)
        except P.ProtocolError as e:
            self.call_from_thread(self._fail, e)

    def action_step(self):
        if not self.s.can_step:
            self.log_msg("STEP no disponible en esta Debug Unit (v0). Proba con --sim.", "warn")
            return
        if self._start():
            self._step()

    @work(thread=True)
    def _step(self):
        try:
            st = self.s.step()
            self.call_from_thread(self._done)
            if st.halted:
                self.call_from_thread(self.stop_auto)
        except P.ProtocolError as e:
            self.call_from_thread(self._fail, e)

    def action_auto(self):
        if self._auto:
            self.stop_auto()
        elif self.s.can_step:
            self._auto = self.set_interval(self.auto_ms / 1000, self._auto_tick)
            self.log_msg(f"auto-step cada {self.auto_ms} ms ('a' para parar)")
        else:
            self.log_msg("auto-step necesita STEP", "warn")
        self.refresh_views()

    def _auto_tick(self):
        if not self._busy:
            self.action_step()

    def stop_auto(self):
        if self._auto:
            self._auto.stop()
            self._auto = None
            self.refresh_views()

    def action_hist(self, d):
        n = len(self.s.history)
        if not n:
            return
        i = (n - 1 if self.view is None else self.view) + d
        i = max(0, min(n - 1, i))
        self.view = None if i == n - 1 else i
        self.refresh_views()

    def action_hist_last(self):
        self.view = None
        self.refresh_views()

    def action_toggle_mem(self):
        self.mem_all = not self.mem_all
        self.refresh_views()

    def action_compare(self):
        _, st, _ = self._shown()
        try:
            diffs = self.s.compare_with_model(st)
        except P.ProtocolError as e:
            self.log_msg(f"✗ {e}", "error")
            return
        if not diffs:
            self.log_msg("IGUALES: el estado coincide con el modelo en Python", "ok")
        else:
            self.log_msg(f"DIFERENTES: {len(diffs)} diferencia(s)", "error")
            for d in diffs[:20]:
                self.log_msg(d.strip(), "error")
            self.log_msg("(los registros y la memoria no se vacian entre programas: reprograma la FPGA)", "warn")

    def action_save(self):
        _, st, _ = self._shown()
        if st is None:
            self.log_msg("no hay estado para guardar", "warn")
            return
        self.s.save_state(st, "rtl_state_debug.txt")
        self.log_msg("✓ estado guardado en rtl_state_debug.txt", "ok")

    def action_open(self):
        box = self.query_one("#open", Input)
        box.display = True
        box.value = self.path or ""
        box.focus()

    def on_input_submitted(self, ev: Input.Submitted):
        ev.input.display = False
        if ev.value.strip():
            self.path = ev.value.strip()
            self.action_load()

    def action_sim_reset(self):
        self._sim(self.s.sim_reset_switch)

    def action_sim_reprogram(self):
        self._sim(self.s.sim_reprogram)

    def _sim(self, fn):
        try:
            fn()
        except P.ProtocolError as e:
            self.log_msg(f"✗ {e}", "error")
        self._busy = False
        self.view = None
        self.refresh_views()


def main(argv=None):
    ap = argparse.ArgumentParser(prog="tui.py", description="TUI de la Debug Unit RISC-V")
    ap.add_argument("program", nargs="?", help="assembler (.s/.txt) o machine_code.txt")
    ap.add_argument("-p", "--port", help="puerto serie. Sin -p: el unico detectado")
    ap.add_argument("-b", "--baud", type=int, default=115200)
    ap.add_argument("--sim", action="store_true", help="usar la Debug Unit simulada")
    ap.add_argument("--sim-protocol", type=int, choices=(0, 1), default=1)
    ap.add_argument("-t", "--timeout", type=float, default=10.0)
    ap.add_argument("--auto-ms", type=int, default=300, help="periodo del auto-step (ms)")
    a = ap.parse_args(argv)

    if a.sim:
        s = DebugSession.open_sim(version=a.sim_protocol)
    else:
        port = a.port
        if not port:
            ports = list_serial_ports()
            if len(ports) != 1:
                print("Puertos:", ", ".join(p for p, _ in ports) or "ninguno")
                return "Indica el puerto con -p (o usa --sim)"
            port = ports[0][0]
        try:
            s = DebugSession.open_serial(port, a.baud)
        except Exception as e:
            return f"No se pudo abrir {port}: {e}"
    try:
        DebugTUI(s, a.program, a.timeout, a.auto_ms).run()
    finally:
        s.close()


if __name__ == "__main__":
    sys.exit(main())
