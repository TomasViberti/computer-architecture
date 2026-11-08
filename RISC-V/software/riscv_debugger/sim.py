"""Debug Unit simulada: el mismo protocolo que la placa, con el modelo en Python como procesador.

Sirve para usar y probar las interfaces sin la FPGA. Recibe y manda bytes igual que
debug_unit.v, y el procesador es el Cpu de scripts/monocycle_model.py.

Imita tambien lo que hace la placa entre programas:
  - LOAD escribe solo las N primeras palabras; el resto de la memoria de programa queda
    como estaba.
  - Ni LOAD ni RUN vacian los registros ni la memoria de datos.
  - Un programa que no termina deja a la Debug Unit sin contestar hasta que se "baja y sube
    el switch de reset" (reset_switch()). Reprogramar la FPGA (reprogram_fpga()) si vacia todo.

version=0 se comporta exactamente como el RTL actual (solo LOAD y RUN).
version=1 agrega STEP e INFO, la propuesta de protocolo para el pipeline.
"""
import struct

from .legacy import model
from . import protocol as P


class SimulatedDebugUnit:
    def __init__(self, version=1, imem_depth=256, dmem_depth=256, max_cycles=200_000):
        self.version = version
        self.imem_depth, self.dmem_depth = imem_depth, dmem_depth
        self.max_cycles = max_cycles    # mas que esto se toma como "no termina nunca"
        self.out = bytearray()
        self.reprogram_fpga()

    # ---------------- acciones "fisicas" sobre la placa ----------------
    def reprogram_fpga(self):
        """Como volver a programar el bitstream: todo vuelve al estado inicial."""
        self.cpu = model.Cpu([], self.imem_depth, self.dmem_depth)
        self.reset_switch()

    def reset_switch(self):
        """Como bajar y subir el switch de reset: corta lo que este haciendo la Debug Unit."""
        self._pending = bytearray()
        self._busy = False              # el procesador esta en un programa que no termina
        self._stepping = False          # el procesador esta fuera de reset en modo paso a paso
        self.out.clear()

    # ---------------- lado transporte ----------------
    def take(self, n):
        data = bytes(self.out[:n])
        del self.out[:n]
        return data

    def untake(self, data):
        self.out[:0] = data

    def receive(self, data):
        if self._busy:
            return                      # igual que el RTL en RUN_EXEC: no atiende comandos
        self._pending += data
        while self._pending and not self._busy:
            if not self._command():
                break                   # faltan bytes del comando actual

    # ---------------- comandos ----------------
    def _reply(self, b):
        self.out.append(b)

    def _error(self, code):
        # La Debug Unit descarta todo hasta un silencio. Aca: lo que haya llegado junto.
        self._reply(code)
        self._pending.clear()

    def _command(self):
        """Procesa un comando de _pending. Devuelve False si todavia no llego completo."""
        cmd = self._pending[0]
        if cmd == P.CMD_LOAD:
            if len(self._pending) < 3:
                return False
            n = struct.unpack("<H", self._pending[1:3])[0]
            if n == 0 or n > self.imem_depth:
                self._error(P.REPLY_ERR_PARAM)
                return True
            if len(self._pending) < 3 + 4 * n:
                return False
            words = struct.unpack(f"<{n}I", self._pending[3:3 + 4 * n])
            del self._pending[:3 + 4 * n]
            self.cpu.imem[:n] = list(words)
            self._stepping = False      # el procesador queda en reset
            self._reply(P.REPLY_OK)
            return True

        del self._pending[:1]
        if cmd == P.CMD_RUN:
            self._reply(P.REPLY_OK)
            self._run()
        elif cmd == P.CMD_STEP and self.version >= 1:
            self._reply(P.REPLY_OK)
            self._step()
        elif cmd == P.CMD_INFO and self.version >= 1:
            self._reply(P.REPLY_OK)
            self.out += P.encode_info(P.DebugInfo(self.version, P.CAP_LOAD | P.CAP_RUN | P.CAP_STEP,
                                                  self.imem_depth, self.dmem_depth))
        else:
            self._error(P.REPLY_ERR_CMD)
        return True

    def _release_reset(self):
        cpu = self.cpu
        cpu.pc, cpu.ciclos, cpu.err_imem, cpu.err_dmem = 0, 0, False, False

    def _run(self):
        self._release_reset()
        self._stepping = False
        cpu = self.cpu
        while cpu.ciclos < self.max_cycles:
            if not cpu.paso():
                self._send_state()
                return
        self._busy = True               # no llega nunca al HALT: no manda el estado

    def _step(self):
        cpu = self.cpu
        if not self._stepping:
            self._release_reset()
            self._stepping = True
        # El RTL captura ERROR_IMEM en cada ciclo (instruccion() con marcar=True hace lo mismo)
        if (cpu.instruccion() & 0x7F) != 0x0B:
            cpu.paso()
            cpu.instruccion()
        halted = cpu.en_halt()
        if halted:
            self._stepping = False      # como despues de RUN: el procesador vuelve a reset
        self._send_state(halted)

    def _send_state(self, halted=True):
        cpu = self.cpu
        mem = [int.from_bytes(cpu.mem[i:i + 4], "little") for i in range(0, len(cpu.mem), 4)]
        st = P.CpuState(pc=cpu.pc, cycles=cpu.ciclos, halted=halted, err_imem=cpu.err_imem,
                        err_dmem=cpu.err_dmem, regs=list(cpu.x), mem=mem)
        # El monociclo no tiene latches: con la version 1 se manda el paquete 11 con 0 latches,
        # para ejercitar el mismo camino que va a usar el pipeline.
        self.out += P.encode_state(st, with_latches=self.version >= 1)
