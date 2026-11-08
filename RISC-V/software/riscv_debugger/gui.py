"""GUI (tkinter): editor de assembler + depurador visual de la Debug Unit.

    python gui.py                    # elegir placa o simulador en la barra de arriba
    python gui.py --sim ../scripts/program.txt

- Editor con resaltado de sintaxis; al cargar se ensambla y, si hay un error, se marca la linea.
- Memoria de programa desensamblada, con el PC marcado. Doble click = breakpoint.
- Registros, memoria de datos y latches; lo que cambio en el ultimo paso se pinta.
- Historial: la barra de abajo permite volver a cualquier estado recibido.
- Run (continuo), Step, Step N, Continuar (pasos hasta HALT o breakpoint) y Auto-step.

Toda la comunicacion corre en un hilo aparte; tkinter solo se toca desde el hilo principal.
"""
import argparse
import queue
import re
import sys
import threading
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
from tkinter.scrolledtext import ScrolledText

from . import protocol as P
from .program import ABI_NAMES, AsmError, assemble_text, disassemble, fmt_value, load_program
from .session import DebugSession
from .transport import list_serial_ports

SIM_V1 = "Simulador (v1: LOAD, RUN, STEP)"
SIM_V0 = "Simulador (v0: igual al RTL actual)"
MONO = ("Consolas", 10) if sys.platform.startswith("win") else ("DejaVu Sans Mono", 10)

C_CHANGED = "#ffd866"
C_PC = "#a6e3ff"
C_BREAK = "#ff9aa2"
C_ERR = "#ffb3b3"

MNEMONICS = ("add sub sll slt sltu xor srl sra or and addi slti sltiu xori ori andi slli srli srai "
             "lb lh lw lbu lhu sb sh sw beq bne lui jal jalr halt nop mv li j").split()


class Worker:
    """Un hilo que ejecuta las operaciones de la sesion de a una, en orden."""

    def __init__(self, results):
        self.jobs = queue.Queue()
        self.results = results
        threading.Thread(target=self._loop, daemon=True).start()

    def submit(self, fn, on_ok=None, on_err=None):
        self.jobs.put((fn, on_ok, on_err))

    def _loop(self):
        while True:
            fn, on_ok, on_err = self.jobs.get()
            try:
                r = fn()
                self.results.put(("call", on_ok, r))
            except Exception as e:                      # se informa en el hilo principal
                self.results.put(("call", on_err, e))


class DebugGUI:
    def __init__(self, root, args):
        self.root = root
        self.args = args
        self.s = None                   # DebugSession
        self.view = None                # indice del historial mostrado (None = ultimo)
        self.busy = False
        self.stop_flag = threading.Event()
        self.auto_job = None
        self._auto_first = False
        self.breakpoints = set()        # direcciones en bytes
        self.loaded_text = None         # texto del editor al momento del ultimo LOAD
        self.path = None
        self.results = queue.Queue()
        self.worker = Worker(self.results)

        root.title("RISC-V Debug Unit")
        root.geometry("1400x860")
        root.minsize(1000, 640)
        style = ttk.Style(root)
        if "clam" in style.theme_names():
            style.theme_use("clam")
        style.configure("Treeview", font=MONO, rowheight=20)
        style.configure("Treeview.Heading", font=(MONO[0], 10, "bold"))
        style.configure("Status.TLabel", font=(MONO[0], 11, "bold"), padding=4)

        self._build_toolbar()
        self._build_body()
        self._build_bottom()
        self._bind_keys()
        self._set_enabled()
        self.root.after(30, self._poll)

        if args.program:
            self.open_file(args.program)
        if args.sim or args.port:
            self.conn_var.set(SIM_V1 if args.sim and args.sim_protocol == 1 else
                              SIM_V0 if args.sim else args.port)
            self.connect()

    # ======================================================================
    # Armado de la ventana
    # ======================================================================
    def _build_toolbar(self):
        bar = ttk.Frame(self.root, padding=(6, 6, 6, 0))
        bar.pack(side=tk.TOP, fill=tk.X)

        ttk.Label(bar, text="Conexion:").pack(side=tk.LEFT)
        self.conn_var = tk.StringVar(value=SIM_V1)
        self.conn_box = ttk.Combobox(bar, textvariable=self.conn_var, width=36)
        self.conn_box.pack(side=tk.LEFT, padx=4)
        self._refresh_ports()
        ttk.Button(bar, text="⟳", width=3, command=self._refresh_ports).pack(side=tk.LEFT)
        ttk.Label(bar, text="Baud:").pack(side=tk.LEFT, padx=(8, 0))
        self.baud_var = tk.StringVar(value=str(self.args.baud))
        ttk.Entry(bar, textvariable=self.baud_var, width=8).pack(side=tk.LEFT, padx=4)
        self.btn_conn = ttk.Button(bar, text="Conectar", command=self.toggle_connection)
        self.btn_conn.pack(side=tk.LEFT, padx=4)

        ttk.Separator(bar, orient=tk.VERTICAL).pack(side=tk.LEFT, fill=tk.Y, padx=8)
        self.btn_cmp = ttk.Button(bar, text="Comparar con modelo", command=self.compare)
        self.btn_cmp.pack(side=tk.LEFT, padx=2)
        self.btn_save = ttk.Button(bar, text="Guardar estado", command=self.save_state)
        self.btn_save.pack(side=tk.LEFT, padx=2)

        mb = ttk.Menubutton(bar, text="Simulador ▾")
        menu = tk.Menu(mb, tearoff=False)
        menu.add_command(label="Switch de reset (corta un programa colgado)", command=self.sim_reset)
        menu.add_command(label="Reprogramar FPGA (vacia registros y memorias)", command=self.sim_reprogram)
        mb["menu"] = menu
        mb.pack(side=tk.LEFT, padx=2)
        self.btn_sim = mb

        # Segunda fila: ejecucion
        bar = ttk.Frame(self.root, padding=(6, 4, 6, 0))
        bar.pack(side=tk.TOP, fill=tk.X)
        self.btn_load = ttk.Button(bar, text="⇪ Cargar (F6)", command=self.load)
        self.btn_run = ttk.Button(bar, text="▶ Run (F5)", command=self.run)
        self.btn_step = ttk.Button(bar, text="⏭ Step (F10)", command=self.step)
        for b in (self.btn_load, self.btn_run, self.btn_step):
            b.pack(side=tk.LEFT, padx=2)
        self.stepn_var = tk.StringVar(value="10")
        ttk.Spinbox(bar, from_=1, to=100000, textvariable=self.stepn_var, width=6).pack(side=tk.LEFT, padx=(6, 0))
        self.btn_stepn = ttk.Button(bar, text="Step N", command=self.step_n)
        self.btn_stepn.pack(side=tk.LEFT, padx=2)
        self.btn_cont = ttk.Button(bar, text="⏩ Continuar", command=self.continue_)
        self.btn_cont.pack(side=tk.LEFT, padx=2)
        self.btn_auto = ttk.Button(bar, text="Auto (F8)", command=self.toggle_auto)
        self.btn_auto.pack(side=tk.LEFT, padx=2)
        self.auto_ms = tk.StringVar(value="300")
        ttk.Spinbox(bar, from_=20, to=5000, increment=50, textvariable=self.auto_ms, width=5).pack(side=tk.LEFT)
        ttk.Label(bar, text="ms").pack(side=tk.LEFT)
        self.btn_stop = ttk.Button(bar, text="■ Parar", command=self.stop)
        self.btn_stop.pack(side=tk.LEFT, padx=4)

    def _build_body(self):
        panes = ttk.PanedWindow(self.root, orient=tk.HORIZONTAL)
        panes.pack(side=tk.TOP, fill=tk.BOTH, expand=True, padx=6, pady=6)

        # ---- izquierda: editor y memoria de programa ----
        left = ttk.Notebook(panes)
        panes.add(left, weight=3)
        ed = ttk.Frame(left)
        left.add(ed, text="Editor (assembler)")
        edbar = ttk.Frame(ed)
        edbar.pack(fill=tk.X)
        ttk.Button(edbar, text="Abrir… (Ctrl+O)", command=self.open_dialog).pack(side=tk.LEFT)
        ttk.Button(edbar, text="Guardar (Ctrl+S)", command=self.save_file).pack(side=tk.LEFT, padx=2)
        ttk.Button(edbar, text="Exportar machine_code…", command=self.export_machine_code).pack(side=tk.LEFT, padx=2)
        self.file_label = ttk.Label(edbar, text="(sin archivo)", foreground="#666")
        self.file_label.pack(side=tk.LEFT, padx=8)
        edf = ttk.Frame(ed)
        edf.pack(fill=tk.BOTH, expand=True)
        self.gutter = tk.Text(edf, width=4, font=MONO, state=tk.DISABLED, background="#eeeeee",
                              foreground="#888", relief=tk.FLAT, takefocus=0)
        self.gutter.pack(side=tk.LEFT, fill=tk.Y)
        self.editor = tk.Text(edf, font=MONO, undo=True, wrap=tk.NONE, relief=tk.FLAT)
        sb = ttk.Scrollbar(edf, command=self._editor_scroll)
        self.editor.configure(yscrollcommand=lambda a, b: (sb.set(a, b), self.gutter.yview_moveto(a)))
        sb.pack(side=tk.RIGHT, fill=tk.Y)
        self.editor.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        for tag, color in (("mn", "#0050b3"), ("reg", "#a0522d"), ("num", "#098658"),
                           ("comment", "#888888"), ("label", "#9c27b0")):
            self.editor.tag_configure(tag, foreground=color)
        self.editor.tag_configure("pcline", background=C_PC)
        self.editor.tag_configure("errline", background=C_ERR)
        self.editor.bind("<<Modified>>", self._on_edit)

        pf = ttk.Frame(left)
        left.add(pf, text="Memoria de programa")
        self.prog = self._tree(pf, ("dir", "hex", "instr", "src"),
                               ("Dir", "Hex", "Instruccion", "Fuente"), (60, 90, 230, 230))
        self.prog.tag_configure("pc", background=C_PC)
        self.prog.tag_configure("bp", background=C_BREAK)
        self.prog.bind("<Double-1>", self._toggle_breakpoint)
        ttk.Label(pf, text="Doble click en una instruccion: breakpoint (lo usan Continuar y Auto)",
                  foreground="#666").pack(fill=tk.X)
        self.left = left

        # ---- centro: registros ----
        mid = ttk.LabelFrame(panes, text="Registros", padding=2)
        panes.add(mid, weight=2)
        self.regs = self._tree(mid, ("reg", "abi", "hex", "dec"), ("Reg", "ABI", "Hex", "Decimal"),
                               (50, 50, 110, 110))
        self.regs.tag_configure("changed", background=C_CHANGED)
        self.regs.tag_configure("zero", foreground="#999")

        # ---- derecha: memoria y latches ----
        right = ttk.Notebook(panes)
        panes.add(right, weight=3)
        mf = ttk.Frame(right)
        right.add(mf, text="Memoria de datos")
        self.mem_all = tk.BooleanVar(value=False)
        ttk.Checkbutton(mf, text="Mostrar todas las palabras (si no, solo las usadas)",
                        variable=self.mem_all, command=self.refresh).pack(anchor=tk.W)
        self.mem = self._tree(mf, ("addr", "hex", "dec", "bytes"),
                              ("Direccion", "Hex", "Decimal", "Bytes b0..b3"), (100, 100, 100, 120))
        self.mem.tag_configure("changed", background=C_CHANGED)
        lf = ttk.Frame(right)
        right.add(lf, text="Latches intermedios")
        self.latch = self._tree(lf, ("val",), ("Valor",), (260,), tree=True)
        self.latch.heading("#0", text="Latch / campo")
        self.latch.column("#0", width=160)
        self.latch.tag_configure("changed", background=C_CHANGED)

    def _build_bottom(self):
        bottom = ttk.Frame(self.root, padding=(6, 0, 6, 6))
        bottom.pack(side=tk.BOTTOM, fill=tk.X)
        self.status = ttk.Label(bottom, text="Desconectado", style="Status.TLabel", anchor=tk.W)
        self.status.pack(fill=tk.X)
        hist = ttk.Frame(bottom)
        hist.pack(fill=tk.X)
        ttk.Label(hist, text="Historial:").pack(side=tk.LEFT)
        self.hist_var = tk.DoubleVar(value=0)
        self.hist = ttk.Scale(hist, from_=0, to=0, variable=self.hist_var, command=self._on_hist)
        self.hist.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=6)
        ttk.Button(hist, text="◀", width=3, command=lambda: self._hist_move(-1)).pack(side=tk.LEFT)
        ttk.Button(hist, text="▶", width=3, command=lambda: self._hist_move(1)).pack(side=tk.LEFT)
        ttk.Button(hist, text="Ultimo", command=lambda: self._hist_move(None)).pack(side=tk.LEFT, padx=2)
        self.hist_label = ttk.Label(hist, text="", width=34)
        self.hist_label.pack(side=tk.LEFT)
        self.log_box = ScrolledText(bottom, height=7, font=MONO, state=tk.DISABLED, relief=tk.FLAT,
                                    background="#1e1e1e", foreground="#d4d4d4")
        self.log_box.pack(fill=tk.X, pady=(4, 0))
        for tag, color in (("info", "#d4d4d4"), ("ok", "#7ee787"), ("warn", "#f2cc60"), ("error", "#ff7b72")):
            self.log_box.tag_configure(tag, foreground=color)

    def _tree(self, parent, cols, heads, widths, tree=False):
        frame = ttk.Frame(parent)
        frame.pack(fill=tk.BOTH, expand=True)
        t = ttk.Treeview(frame, columns=cols, show="tree headings" if tree else "headings",
                         selectmode="browse")
        for c, h, w in zip(cols, heads, widths):
            t.heading(c, text=h, anchor=tk.W)
            t.column(c, width=w, anchor=tk.W, stretch=True)
        sb = ttk.Scrollbar(frame, command=t.yview)
        t.configure(yscrollcommand=sb.set)
        sb.pack(side=tk.RIGHT, fill=tk.Y)
        t.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        return t

    def _bind_keys(self):
        r = self.root
        r.bind("<F5>", lambda e: self.run())
        r.bind("<F6>", lambda e: self.load())
        r.bind("<F8>", lambda e: self.toggle_auto())
        r.bind("<F10>", lambda e: self.step())
        r.bind("<Control-o>", lambda e: self.open_dialog())
        r.bind("<Control-s>", lambda e: self.save_file())
        r.bind("<Escape>", lambda e: self.stop())
        r.protocol("WM_DELETE_WINDOW", self.quit)

    # ======================================================================
    # Infraestructura: hilo de trabajo, log y habilitacion de botones
    # ======================================================================
    def _poll(self):
        try:
            while True:
                kind, *rest = self.results.get_nowait()
                if kind == "log":
                    self.log(*rest)
                elif kind == "refresh":
                    self.refresh()
                elif kind == "call":
                    cb, value = rest
                    if cb:
                        cb(value)
        except queue.Empty:
            pass
        self.root.after(30, self._poll)

    def log(self, msg, level="info"):
        self.log_box.configure(state=tk.NORMAL)
        self.log_box.insert(tk.END, msg + "\n", level)
        self.log_box.see(tk.END)
        self.log_box.configure(state=tk.DISABLED)

    def _session_log(self, msg, level="info"):
        self.results.put(("log", msg, level))             # puede venir del hilo de trabajo

    def _job(self, fn, on_ok=None):
        """Corre fn en el hilo de trabajo; al terminar refresca y llama on_ok(resultado)."""
        if self.busy:
            self.log("esperando la respuesta del comando anterior…", "warn")
            return False
        self.busy = True
        self._set_enabled()

        def ok(r):
            self.busy = False
            self.view = None
            if on_ok:
                on_ok(r)
            self._set_enabled()
            self.refresh()

        def err(e):
            self.busy = False
            self.stop_auto()
            self.log(f"✗ {e}", "error")
            self._set_enabled()
            self.refresh()

        self.worker.submit(fn, ok, err)
        return True

    def _set_enabled(self):
        conn = self.s is not None
        step = conn and self.s.can_step
        idle = not self.busy

        def en(w, cond):
            w.state(["!disabled"] if cond else ["disabled"])

        en(self.btn_load, conn and idle)
        en(self.btn_run, conn and idle and self.s.program is not None)
        for b in (self.btn_step, self.btn_stepn, self.btn_cont):
            en(b, step and idle)
        en(self.btn_auto, step)
        en(self.btn_stop, self.busy or self.auto_job is not None)
        en(self.btn_cmp, conn and self.s.state is not None)
        en(self.btn_save, conn and self.s.state is not None)
        en(self.btn_sim, conn and self.s.is_sim and idle)
        en(self.conn_box, not conn)
        self.btn_conn.configure(text="Desconectar" if conn else "Conectar")
        self.btn_auto.configure(text="■ Auto (F8)" if self.auto_job else "Auto (F8)")

    # ======================================================================
    # Conexion
    # ======================================================================
    def _refresh_ports(self):
        self.conn_box["values"] = [SIM_V1, SIM_V0] + [p for p, _ in list_serial_ports()]

    def toggle_connection(self):
        if self.s:
            self.disconnect()
        else:
            self.connect()

    def connect(self):
        target = self.conn_var.get().strip()
        try:
            baud = int(self.baud_var.get())
        except ValueError:
            self.log("baudrate invalido", "error")
            return

        def open_():
            if target in (SIM_V1, SIM_V0):
                return DebugSession.open_sim(version=1 if target == SIM_V1 else 0, log=self._session_log)
            return DebugSession.open_serial(target, baud, log=self._session_log)

        def done(s):
            self.s = s
            self.log(f"✓ conectado a {s.name}", "ok")
            if not s.can_step:
                self.log("Esta Debug Unit no soporta STEP: solo modo continuo. "
                         "El paso a paso llega con el pipeline (o usa el simulador v1).", "warn")

        self.log(f"conectando a {target}…")
        self._job(open_, done)

    def disconnect(self):
        self.stop()
        if self.s:
            self.s.close()
            self.log(f"desconectado de {self.s.name}")
        self.s = None
        self.view = None
        self._set_enabled()
        self.refresh()

    def quit(self):
        self.stop()
        if self.s:
            self.s.close()
        self.root.destroy()

    # ======================================================================
    # Editor
    # ======================================================================
    def _editor_scroll(self, *a):
        self.editor.yview(*a)
        self.gutter.yview(*a)

    def _on_edit(self, _=None):
        if not self.editor.edit_modified():
            return
        self.editor.edit_modified(False)
        self._highlight()

    def _highlight(self):
        ed = self.editor
        text = ed.get("1.0", "end-1c")
        for tag in ("mn", "reg", "num", "comment", "label", "errline"):
            ed.tag_remove(tag, "1.0", tk.END)
        n = text.count("\n") + 1
        self.gutter.configure(state=tk.NORMAL)
        self.gutter.delete("1.0", tk.END)
        self.gutter.insert("1.0", "\n".join(f"{i:>3}" for i in range(1, n + 1)))
        self.gutter.configure(state=tk.DISABLED)
        for ln, line in enumerate(text.split("\n"), 1):
            code = re.split(r"#|//", line, maxsplit=1)[0]
            cpos = len(code)
            if cpos < len(line):
                ed.tag_add("comment", f"{ln}.{cpos}", f"{ln}.end")
            for m in re.finditer(r"[A-Za-z_]\w*\s*:", code):
                ed.tag_add("label", f"{ln}.{m.start()}", f"{ln}.{m.end()}")
            for m in re.finditer(r"\b[A-Za-z]+\b", code):
                if m.group(0).lower() in MNEMONICS:
                    ed.tag_add("mn", f"{ln}.{m.start()}", f"{ln}.{m.end()}")
            for m in re.finditer(r"\b[xX]([0-9]|[12][0-9]|3[01])\b", code):
                ed.tag_add("reg", f"{ln}.{m.start()}", f"{ln}.{m.end()}")
            for m in re.finditer(r"(?<![\w])[-+]?(0x[0-9A-Fa-f_]+|0b[01_]+|\d+)\b", code):
                ed.tag_add("num", f"{ln}.{m.start()}", f"{ln}.{m.end()}")
        ed.tag_raise("pcline")

    def open_dialog(self):
        path = filedialog.askopenfilename(filetypes=[("Assembler / machine code", "*.s *.asm *.txt"),
                                                     ("Todos", "*")])
        if path:
            self.open_file(path)

    def open_file(self, path):
        try:
            with open(path, encoding="utf-8") as f:
                text = f.read()
        except OSError as e:
            self.log(f"✗ {e}", "error")
            return
        self.path = path
        self.editor.delete("1.0", tk.END)
        self.editor.insert("1.0", text)
        self.editor.edit_reset()
        self.file_label.configure(text=path)
        self._highlight()
        self.log(f"abierto {path}")

    def save_file(self):
        if not self.path:
            self.path = filedialog.asksaveasfilename(defaultextension=".s",
                                                     filetypes=[("Assembler", "*.s *.txt")])
            if not self.path:
                return
        with open(self.path, "w", encoding="utf-8") as f:
            f.write(self.editor.get("1.0", "end-1c"))
        self.file_label.configure(text=self.path)
        self.log(f"✓ guardado {self.path}", "ok")

    def _assemble_editor(self):
        text = self.editor.get("1.0", "end-1c")
        depth = self.s.info.imem_depth if self.s else 256
        try:
            if re.search(r"prog\[\s*\d+\s*\]\s*=", text):            # machine_code.txt abierto
                from .program import parse_machine_code
                prog = parse_machine_code(text, self.path)
            else:
                prog = assemble_text(text, depth, self.path)
        except AsmError as e:
            m = re.search(r"linea (\d+)", str(e))
            if m:
                ln = int(m.group(1))
                self.editor.tag_add("errline", f"{ln}.0", f"{ln}.end+1c")
                self.editor.see(f"{ln}.0")
            self.left.select(0)
            self.log(f"✗ ensamblador: {e}", "error")
            return None, None
        return prog, text

    def export_machine_code(self):
        prog, _ = self._assemble_editor()
        if prog is None:
            return
        path = filedialog.asksaveasfilename(initialfile="machine_code.txt", defaultextension=".txt")
        if path:
            with open(path, "w", encoding="utf-8") as f:
                f.write(prog.to_machine_code())
            self.log(f"✓ {len(prog)} palabras escritas en {path}", "ok")

    # ======================================================================
    # Comandos
    # ======================================================================
    def load(self):
        if not self.s:
            return
        prog, text = self._assemble_editor()
        if prog is None:
            return

        def done(_):
            self.loaded_text = text
            self.breakpoints = {b for b in self.breakpoints if b // 4 < len(prog)}
            self.log(f"✓ programa cargado: {len(prog)} palabras", "ok")

        self._job(lambda: self.s.load(prog), done)

    def run(self):
        if self.s and self.s.program is not None:
            self._job(lambda: self.s.run(self.args.timeout))

    def step(self):
        if self.s and self.s.can_step:
            self._job(self.s.step)

    def step_n(self):
        try:
            n = max(1, int(self.stepn_var.get()))
        except ValueError:
            n = 1
        self._steps(n, stop_on_break=False)

    def continue_(self):
        self._steps(1_000_000, stop_on_break=True)

    def _steps(self, n, stop_on_break):
        if not (self.s and self.s.can_step):
            return
        self.stop_flag.clear()
        bps = set(self.breakpoints)

        def loop():
            for k in range(n):
                st = self.s.step()
                if st.halted or self.stop_flag.is_set():
                    break
                if stop_on_break and st.pc in bps:
                    self.results.put(("log", f"breakpoint en 0x{st.pc:04x}", "warn"))
                    break
                if k % 50 == 49:
                    self.results.put(("refresh",))
            return k + 1

        self._job(loop, lambda k: self.log(f"{k} paso(s) ejecutados"))

    def toggle_auto(self):
        if self.auto_job:
            self.stop_auto()
        elif self.s and self.s.can_step:
            self.log("auto-step: un paso cada intervalo (F8 o Esc para parar)")
            self._auto_first = True
            self._auto_tick()
        self._set_enabled()

    def _auto_tick(self):
        self.auto_job = None
        if not self.s:
            return
        st = self.s.state
        # El primer tick no mira el estado: si el ultimo fue un HALT, el STEP arranca de nuevo
        if not self._auto_first and st is not None:
            if st.halted:
                self.log("auto-step: el programa llego al HALT", "ok")
                self._set_enabled()
                return
            if st.pc in self.breakpoints:
                self.log(f"auto-step: breakpoint en 0x{st.pc:04x}", "warn")
                self._set_enabled()
                return
        self._auto_first = False
        if not self.busy:
            self._job(self.s.step)
        try:
            ms = max(20, int(self.auto_ms.get()))
        except ValueError:
            ms = 300
        self.auto_job = self.root.after(ms, self._auto_tick)
        self._set_enabled()

    def stop_auto(self):
        if self.auto_job:
            self.root.after_cancel(self.auto_job)
            self.auto_job = None

    def stop(self):
        self.stop_flag.set()
        self.stop_auto()
        self._set_enabled()

    def compare(self):
        st = self._shown()[1]
        try:
            diffs = self.s.compare_with_model(st)
        except P.ProtocolError as e:
            self.log(f"✗ {e}", "error")
            return
        if not diffs:
            self.log("IGUALES: el estado coincide con el modelo en Python", "ok")
        else:
            self.log(f"DIFERENTES: {len(diffs)} diferencia(s)", "error")
            for d in diffs:
                self.log(d, "error")
            self.log("Los registros y la memoria no se vacian entre programas: "
                     "para comparar, reprograma la FPGA antes de cargar.", "warn")

    def save_state(self):
        st = self._shown()[1]
        if st is None:
            return
        path = filedialog.asksaveasfilename(initialfile="rtl_state_debug.txt", defaultextension=".txt")
        if path:
            self.s.save_state(st, path)
            self.log(f"✓ estado guardado en {path}", "ok")

    def sim_reset(self):
        self.stop()
        self.s.sim_reset_switch()
        self.refresh()

    def sim_reprogram(self):
        if messagebox.askyesno("Reprogramar", "¿Vaciar registros, memoria de datos y memoria de programa?"):
            self.stop()
            self.s.sim_reprogram()
            self.loaded_text = None
            self._set_enabled()
            self.refresh()

    def _toggle_breakpoint(self, ev):
        row = self.prog.identify_row(ev.y)
        if not row:
            return
        addr = int(row)
        self.breakpoints ^= {addr}
        self.log(("breakpoint en " if addr in self.breakpoints else "sin breakpoint en ") + f"0x{addr:04x}")
        self.refresh()

    # ======================================================================
    # Historial
    # ======================================================================
    def _shown(self):
        h = self.s.history if self.s else []
        if not h:
            return None, None, None
        i = len(h) - 1 if self.view is None else min(self.view, len(h) - 1)
        return i, h[i], h[i - 1] if i > 0 else None

    def _on_hist(self, _):
        if not self.s or not self.s.history:
            return
        i = int(round(self.hist_var.get()))
        n = len(self.s.history)
        self.view = None if i >= n - 1 else i
        self.refresh(update_slider=False)

    def _hist_move(self, d):
        if not self.s or not self.s.history:
            return
        n = len(self.s.history)
        if d is None:
            self.view = None
        else:
            i = (n - 1 if self.view is None else self.view) + d
            i = max(0, min(n - 1, i))
            self.view = None if i == n - 1 else i
        self.refresh()

    # ======================================================================
    # Dibujo
    # ======================================================================
    def refresh(self, update_slider=True):
        i, st, prev = self._shown()
        self._draw_program(st)
        self._draw_regs(st, prev)
        self._draw_mem(st, prev)
        self._draw_latches(st, prev)
        self._draw_status(i, st, update_slider)
        self._set_enabled()

    def _draw_program(self, st):
        t = self.prog
        t.delete(*t.get_children())
        self.editor.tag_remove("pcline", "1.0", tk.END)
        p = self.s.program if self.s else None
        if p is None:
            return
        pc = st.pc if st else 0
        for k, w in enumerate(p.words):
            a = k * 4
            tags = ("pc",) if a == pc else ("bp",) if a in self.breakpoints else ()
            mark = ("● " if a in self.breakpoints else "") + ("▶ " if a == pc else "")
            t.insert("", tk.END, iid=str(a), tags=tags,
                     values=(f"{mark}{a:04x}", f"{w:08x}", disassemble(w, a),
                             p.source[k] if k < len(p.source) else ""))
        if pc % 4 == 0 and pc // 4 < len(p):
            t.see(str(pc))
            # Marca la linea del editor si el editor sigue teniendo el programa cargado
            if p.lines and self.loaded_text == self.editor.get("1.0", "end-1c"):
                ln = p.lines[pc // 4]
                self.editor.tag_add("pcline", f"{ln}.0", f"{ln}.end+1c")
                self.editor.see(f"{ln}.0")

    def _draw_regs(self, st, prev):
        t = self.regs
        t.delete(*t.get_children())
        changed = st.changed_regs(prev) if st else set()
        for r in range(32):
            v = st.regs[r] if st else 0
            tags = ("changed",) if r in changed else ("zero",) if v == 0 else ()
            t.insert("", tk.END, values=(f"x{r}", ABI_NAMES[r], f"0x{v:08x}", fmt_value(v, "sdec")), tags=tags)

    def _draw_mem(self, st, prev):
        t = self.mem
        t.delete(*t.get_children())
        if st is None:
            return
        changed = st.changed_mem(prev)
        for k, w in enumerate(st.mem):
            if self.mem_all.get() or w or k in changed:
                t.insert("", tk.END, tags=("changed",) if k in changed else (),
                         values=(f"0x{k * 4:08x}", f"0x{w:08x}", fmt_value(w, "sdec"),
                                 " ".join(f"{(w >> (8 * b)) & 0xFF:02x}" for b in range(4))))

    def _draw_latches(self, st, prev):
        t = self.latch
        t.delete(*t.get_children())
        if st is None or not st.latches:
            t.insert("", tk.END, text="—", values=("el monociclo no tiene latches (los manda el pipeline)",))
            return
        before = {l.id: {n: v for n, v, _ in l.fields()} for l in (prev.latches if prev else [])}
        for l in st.latches:
            node = t.insert("", tk.END, text=l.name, open=True, values=("",))
            for name, v, fmt in l.fields():
                old = before.get(l.id, {}).get(name, v)
                t.insert(node, tk.END, text=name, values=(fmt_value(v, fmt),),
                         tags=("changed",) if old != v else ())

    def _draw_status(self, i, st, update_slider):
        if not self.s:
            self.status.configure(text="Desconectado — elegi la placa (puerto) o el simulador y Conectar")
            self.hist_label.configure(text="")
            return
        head = f"{self.s.name} · v{self.s.info.version} ({', '.join(self.s.info.cap_names())})"
        if st is None:
            self.status.configure(text=f"{head}   —   sin estado: Cargar y despues Run"
                                  + (" o Step" if self.s.can_step else ""))
            self.hist.configure(to=0)
            self.hist_label.configure(text="")
            return
        flags = ("HALT" if st.halted else "en ejecucion") + ("  ERROR_IMEM" if st.err_imem else "") \
            + ("  ERROR_DMEM" if st.err_dmem else "")
        self.status.configure(text=f"PC 0x{st.pc:08x}   CICLOS {st.cycles}   {flags}   ({st.origin})"
                                   f"      {head}")
        n = len(self.s.history)
        self.hist.configure(to=max(0, n - 1))
        if update_slider:
            self.hist_var.set(i)
        self.hist_label.configure(text=f"estado {i + 1}/{n}" + ("   ◀ viendo el pasado" if self.view is not None else ""))


def main(argv=None):
    ap = argparse.ArgumentParser(prog="gui.py", description="GUI de la Debug Unit RISC-V")
    ap.add_argument("program", nargs="?", help="archivo a abrir en el editor")
    ap.add_argument("-p", "--port", help="conectarse a este puerto al abrir")
    ap.add_argument("-b", "--baud", type=int, default=115200)
    ap.add_argument("--sim", action="store_true", help="conectarse al simulador al abrir")
    ap.add_argument("--sim-protocol", type=int, choices=(0, 1), default=1)
    ap.add_argument("-t", "--timeout", type=float, default=10.0, help="segundos de espera del estado tras RUN")
    args = ap.parse_args(argv)
    root = tk.Tk()
    DebugGUI(root, args)
    root.mainloop()


if __name__ == "__main__":
    main()
