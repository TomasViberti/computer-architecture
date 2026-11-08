"""Tests del software de PC. Correr desde RISC-V/software:

    python -m unittest discover -s tests -v

No necesitan la placa: usan la Debug Unit simulada y los archivos que genero la placa.
"""
import contextlib
import io
import re
import struct
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT.parent / "scripts"
sys.path.insert(0, str(ROOT))

from riscv_debugger import protocol as P                                    # noqa: E402
from riscv_debugger.program import (Program, assemble_text, disassemble,    # noqa: E402
                                    load_program, parse_machine_code)
from riscv_debugger.session import DebugSession                             # noqa: E402

PROGRAM = SCRIPTS / "program.txt"


class FakeTransport:
    def __init__(self, data=b""):
        self.buf = bytearray(data)

    def read_exact(self, n, timeout):
        if len(self.buf) < n:
            raise TimeoutError("faltan bytes")
        out = bytes(self.buf[:n])
        del self.buf[:n]
        return out

    def flush_input(self):
        self.buf.clear()


class TestPrograma(unittest.TestCase):
    def test_mismo_codigo_que_assembler_py(self):
        ref = parse_machine_code((SCRIPTS / "machine_code.txt").read_text(encoding="utf-8"))
        self.assertEqual(load_program(PROGRAM).words, ref.words)

    def test_machine_code_ida_y_vuelta(self):
        p = load_program(PROGRAM)
        self.assertEqual(parse_machine_code(p.to_machine_code()).words, p.words)

    def test_desensamblar_y_volver_a_ensamblar(self):
        p = load_program(PROGRAM)
        for w in p.words:
            txt = disassemble(w)
            self.assertEqual(assemble_text(txt).words, [w], txt)

    def test_error_con_numero_de_linea(self):
        with self.assertRaisesRegex(Exception, r"linea 2"):
            assemble_text("addi x1, x0, 1\naddx x1, x2\n")

    def test_lineas_fuente(self):
        p = assemble_text("# comentario\nli x1, 0x12345678\nhalt\n")
        self.assertEqual(p.lines, [2, 2, 3])        # li se expande en 2 palabras


class TestProtocolo(unittest.TestCase):
    def test_estado_con_latches(self):
        st = P.CpuState(pc=0x40, cycles=7, halted=False, err_imem=False, err_dmem=True,
                        regs=list(range(32)), mem=[1, 2, 3],
                        latches=[P.Latch(0, [0x10, 0x00500093, 1]), P.Latch(9, [0xAB])])
        got = P.read_state(FakeTransport(P.encode_state(st, with_latches=True)), 1.0)
        self.assertEqual((got.pc, got.cycles, got.halted, got.err_dmem), (0x40, 7, False, True))
        self.assertEqual(got.regs, st.regs)
        self.assertEqual(got.mem, [1, 2, 3])
        self.assertEqual([l.words for l in got.latches], [[0x10, 0x00500093, 1], [0xAB]])
        f = {n: v for n, v, _ in got.latches[0].fields()}
        self.assertEqual((got.latches[0].name, f["pc"], f["instr"], f["valid"]), ("IF/ID", 0x10, 0x00500093, 1))
        self.assertEqual(got.latches[1].fields(), [("word0", 0xAB, "hex")])    # id sin layout

    def test_estado_v0(self):
        st = P.CpuState(0x9c, 45, True, False, False, [0] * 32, [0] * 4)
        raw = P.encode_state(st)
        self.assertEqual(raw[0], P.PKT_STATE)
        self.assertEqual(len(raw), 1 + 1 + 4 + 4 + 128 + 2 + 16)
        self.assertEqual(P.read_state(FakeTransport(raw), 1.0).pc, 0x9c)

    def test_estado_incompleto(self):
        raw = P.encode_state(P.CpuState(0, 0, True, False, False, [0] * 32, [0] * 4))
        with self.assertRaises(P.ProtocolError):
            P.read_state(FakeTransport(raw[:-3]), 1.0)

    def test_trama_load(self):
        self.assertEqual(P.encode_load([0x0000000B]), bytes([1, 1, 0, 0x0B, 0, 0, 0]))


class TestSimulador(unittest.TestCase):
    def setUp(self):
        self.prog = load_program(PROGRAM)

    def test_run_igual_a_la_placa(self):
        """El estado que devolvio la placa (rtl_state_debug.txt) sale igual del simulador."""
        s = DebugSession.open_sim()
        s.load(self.prog)
        st = s.run()
        self.assertEqual(st.to_text(), (SCRIPTS / "rtl_state_debug.txt").read_text(encoding="utf-8"))
        self.assertEqual(s.compare_with_model(), [])

    def test_paso_a_paso_llega_al_mismo_estado(self):
        s = DebugSession.open_sim()
        s.load(self.prog)
        ref = s.run().to_text()
        s.sim_reprogram()
        s.load(self.prog)
        steps = s.step_n(10_000)
        self.assertTrue(steps[-1].halted)
        self.assertEqual(len(steps), steps[-1].cycles)
        self.assertEqual(steps[-1].to_text(), ref)
        # Despues del HALT, el proximo STEP empieza de nuevo desde PC = 0
        self.assertEqual(s.step().cycles, 1)

    def test_v0_no_tiene_step(self):
        s = DebugSession.open_sim(version=0)
        self.assertEqual(s.info.version, 0)
        self.assertFalse(s.can_step)
        s.load(self.prog)
        with self.assertRaises(P.Unsupported):
            s.step()
        self.assertEqual(s.run().cycles, 45)

    def test_registros_y_memoria_no_se_vacian(self):
        s = DebugSession.open_sim()
        s.load(assemble_text("addi x5, x0, 42\nsw x5, 0(x0)\nhalt"))
        s.run()
        st = (s.load(assemble_text("halt")), s.run())[1]
        self.assertEqual((st.regs[5], st.mem[0]), (42, 42))
        s.sim_reprogram()
        s.load(assemble_text("halt"))
        st = s.run()
        self.assertEqual((st.regs[5], st.mem[0]), (0, 0))

    def test_load_parcial_deja_el_resto(self):
        s = DebugSession.open_sim()
        s.load(assemble_text("addi x1, x0, 1\naddi x2, x0, 2\nhalt"))
        s.load(assemble_text("addi x3, x0, 3"))      # pisa solo la palabra 0
        st = s.run()
        self.assertEqual((st.regs[2], st.regs[3]), (2, 3))

    def test_programa_que_no_termina(self):
        s = DebugSession.open_sim()
        s.transport.unit.max_cycles = 1000
        s.load(assemble_text("loop: j loop"))
        with self.assertRaisesRegex(P.ProtocolError, "switch de reset"):
            s.run(timeout=0.1)
        with self.assertRaises(P.ProtocolError):     # la Debug Unit no atiende
            s.load(assemble_text("halt"))
        s.sim_reset_switch()
        s.load(assemble_text("halt"))
        self.assertTrue(s.run().halted)

    def test_load_vacio_rechazado(self):
        s = DebugSession.open_sim()
        with self.assertRaisesRegex(P.ProtocolError, "0x02"):
            s.load(Program([]))
        s.load(assemble_text("halt"))                # despues del error sigue funcionando

    def test_error_imem(self):
        s = DebugSession.open_sim()
        s.load(assemble_text("li x1, 0x10000\njalr x0, 0(x1)"))
        st = s.run()
        self.assertTrue(st.err_imem)
        self.assertEqual(s.compare_with_model(), [])


class TestCLI(unittest.TestCase):
    def _cli(self, *argv):
        from riscv_debugger import cli
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            cli.console.file = out
            rc = cli.main(list(argv))
        return rc, out.getvalue()

    def test_run_compare(self):
        rc, out = self._cli("--sim", "run", str(PROGRAM), "--compare")
        self.assertEqual(rc, 0)
        self.assertIn("IGUALES", out)

    def test_opciones_despues_del_subcomando(self):
        rc, out = self._cli("step", str(PROGRAM), "--sim", "-n", "3")
        self.assertEqual(rc, 0)
        self.assertEqual(len(re.findall(r"^\s+\d+\s+0x", out, re.M)), 3)

    def test_step_en_v0_falla(self):
        rc, _ = self._cli("step", str(PROGRAM), "--sim", "--sim-protocol", "0")
        self.assertEqual(rc, 1)


if __name__ == "__main__":
    unittest.main()
