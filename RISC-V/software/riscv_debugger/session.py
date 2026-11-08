"""DebugSession: la unica API que usan la CLI, la TUI y la GUI.

    s = DebugSession.open_sim()            # o DebugSession.open_serial("/dev/ttyUSB1")
    s.load(load_program("programa.s"))
    estado = s.run()                       # modo continuo
    estado = s.step()                      # modo paso a paso (si la Debug Unit lo soporta)

Agregar algo nuevo a la Debug Unit (por ejemplo, otro comando del pipeline) se hace aca y en
protocol.py; las interfaces solo llaman a estos metodos y leen los CpuState del historial.
"""
import threading
from pathlib import Path

from . import protocol as P
from .legacy import model
from .program import Program
from .sim import SimulatedDebugUnit
from .transport import SerialTransport, SimTransport

MAX_HISTORY = 10_000


class DebugSession:
    def __init__(self, transport, probe=True, log=None):
        self.transport = transport
        self.log = log or (lambda msg, level="info": None)
        self.info = P.INFO_V0
        self.program = None             # ultimo Program cargado con LOAD
        self.history = []               # CpuState recibidos, el ultimo es el actual
        self._lock = threading.Lock()   # la GUI y la TUI llaman desde hilos de trabajo
        if probe:
            self.probe()

    # ---------------- apertura ----------------
    @classmethod
    def open_serial(cls, port, baudrate=115200, **kw):
        return cls(SerialTransport(port, baudrate), **kw)

    @classmethod
    def open_sim(cls, version=1, **kw):
        return cls(SimTransport(SimulatedDebugUnit(version=version)), **kw)

    @property
    def is_sim(self):
        return isinstance(self.transport, SimTransport)

    @property
    def name(self):
        return self.transport.name

    @property
    def can_step(self):
        return self.info.has(P.CAP_STEP)

    @property
    def state(self):
        return self.history[-1] if self.history else None

    @property
    def previous(self):
        return self.history[-2] if len(self.history) > 1 else None

    def close(self):
        self.transport.close()

    # ---------------- bajo nivel ----------------
    def _expect_ok(self, what, timeout=2.0):
        try:
            r = self.transport.read_exact(1, timeout)[0]
        except TimeoutError:
            raise P.ProtocolError(f"la FPGA no respondio al {what}. Si quedo ejecutando un programa "
                                  "que no termina, baja y subi el switch de reset")
        if r != P.REPLY_OK:
            self._drain_after_error()
            if r == P.REPLY_ERR_CMD:
                raise P.Unsupported(f"la Debug Unit no conoce el comando {what}")
            raise P.ProtocolError(f"{what} rechazado: 0x{r:02X} ({P.REPLY_NAMES.get(r, 'desconocida')})")

    def _drain_after_error(self):
        if not self.is_sim:
            import time
            time.sleep(P.SILENCE_AFTER_ERROR)
        self.transport.flush_input()

    def _push(self, state):
        self.history.append(state)
        del self.history[:-MAX_HISTORY]
        return state

    # ---------------- comandos ----------------
    def probe(self):
        """Pregunta version y capacidades. Una Debug Unit v0 no conoce INFO: se asume v0."""
        with self._lock:
            self.transport.flush_input()
            self.transport.write(bytes([P.CMD_INFO]))
            try:
                self._expect_ok("INFO", timeout=1.0)
                self.info = P.read_info(self.transport)
            except P.Unsupported:
                self.info = P.INFO_V0
        self.log(f"Debug Unit v{self.info.version}: {', '.join(self.info.cap_names())}")
        return self.info

    def load(self, program: Program):
        if len(program) > self.info.imem_depth:
            raise P.ProtocolError(f"el programa tiene {len(program)} palabras y la memoria de "
                                  f"programa {self.info.imem_depth}")
        with self._lock:
            self.transport.flush_input()
            self.transport.write(P.encode_load(program.words))
            self._expect_ok("LOAD", timeout=2.0 + len(program) * 0.001)
        self.program = program
        self.log(f"LOAD: {len(program)} palabras cargadas")
        if not program.has_halt:
            self.log("el programa no tiene HALT: termina solo si el PC sale de la memoria", "warn")

    def run(self, timeout=10.0):
        """Modo continuo: desde PC = 0 hasta el HALT. Devuelve el estado final."""
        with self._lock:
            self.transport.write(bytes([P.CMD_RUN]))
            self._expect_ok("RUN")
            try:
                st = P.read_state(self.transport, timeout, origin="run")
            except P.ProtocolError as e:
                raise P.ProtocolError(f"{e}. Si el programa no termina (bucle infinito), baja y "
                                      "subi el switch de reset; si es largo, usa un timeout mayor")
        self.log(f"RUN: HALT en PC=0x{st.pc:08x} despues de {st.cycles} ciclos")
        return self._push(st)

    def step(self):
        """Modo paso a paso: un ciclo de clock. Devuelve el estado despues de ese ciclo."""
        if not self.can_step:
            raise P.Unsupported(f"la Debug Unit v{self.info.version} no soporta STEP "
                                "(llega con el pipeline; mientras tanto, usa el simulador)")
        with self._lock:
            self.transport.write(bytes([P.CMD_STEP]))
            self._expect_ok("STEP")
            st = P.read_state(self.transport, 2.0, origin="step")
        if st.halted:
            self.log(f"STEP: llego al HALT (PC=0x{st.pc:08x}, {st.cycles} ciclos). "
                     "El proximo STEP empieza de nuevo desde PC = 0")
        return self._push(st)

    def step_n(self, n, stop_on_halt=True):
        out = []
        for _ in range(n):
            out.append(self.step())
            if stop_on_halt and out[-1].halted:
                break
        return out

    # ---------------- solo simulador ----------------
    def sim_reset_switch(self):
        self._sim_unit().reset_switch()
        self.log("simulador: switch de reset (registros y memorias se mantienen)")

    def sim_reprogram(self):
        self._sim_unit().reprogram_fpga()
        self.history.clear()
        self.program = None
        self.log("simulador: FPGA reprogramada (todo en cero, memoria de programa en HALT)")

    def _sim_unit(self):
        if not self.is_sim:
            raise P.ProtocolError("solo disponible con el simulador")
        return self.transport.unit

    # ---------------- utilidades ----------------
    def compare_with_model(self, state=None, max_cycles=200_000):
        """Corre el modelo con el ultimo programa cargado y compara. Devuelve la lista de diferencias."""
        state = state or self.state
        if state is None or self.program is None:
            raise P.ProtocolError("hace falta un programa cargado y un estado recibido")
        cpu = model.Cpu(self.program.words, self.info.imem_depth, self.info.dmem_depth)
        while cpu.ciclos < max_cycles and cpu.paso():
            pass
        expected = dict(l.split("=", 1) for l in model.lineas_estado(cpu, cpu.en_halt()))
        got = dict(l.split("=", 1) for l in state.to_text().splitlines())
        return model.comparar(expected, got)

    @staticmethod
    def save_state(state, path):
        Path(path).write_text(state.to_text(), encoding="utf-8", newline="\n")
