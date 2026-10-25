#!/usr/bin/env python3
"""
run.py - Regresion de testbenches en Vivado con un solo comando.

    py run.py                  corre TODOS los testbenches (*_tb) y da PASS/FAIL
    py run.py alu_tb           corre solo ese
    py run.py --list           lista los testbenches detectados
    py run.py alu_tb --gui     abre Vivado con ese TB (para mirar ondas)

Como funciona:
    1. Lanza Vivado UNA sola vez con run.tcl, que simula cada TB y guarda sus logs.
    2. Lee los logs y decide PASS/FAIL de cada TB (funcion judge).
    3. Imprime el resumen, escribe junit.xml y sale con codigo:
          0 = todo paso | 1 = algun TB fallo | 2 = error de configuracion/Vivado
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).resolve().parent

# ---- Configuracion (editar aca) ---------------------------------------------

DEFAULT_XPR  = Path(os.environ.get("RISCV_XPR", HERE / "../../../riscv_core_sim/riscv_core_sim.xpr"))
DEFAULT_OUT  = HERE / "sim_results"
SIMSET       = "sim_1"                       # carpeta de Vivado donde estan los testbenches
TB_GLOB      = "*_tb"                        # como se llaman los testbenches
PASS_PATTERN = "TODAS LAS PRUEBAS PASARON"   # lo que imprime un TB que paso ("" = no exigir)
FAIL_PATTERN = r"^\s*(Error|Fatal|Failure):|^ERROR:|TEST[ _]FAILED"
LOGS         = ("compile", "elaborate", "simulate")

def error(msg: str) -> int:
    print(f"ERROR: {msg}", file=sys.stderr)
    return 2

def find_vivado(hint: str):
    """Busca Vivado en el PATH y, si no, en las carpetas de instalacion tipicas."""
    if shutil.which(hint):
        return shutil.which(hint)
    if os.name == "nt":
        exe = "vivado.bat"
        roots = [f"{d}:/{n}/Vivado" for d in "CDEFGH" for n in ("Xilinx", "AMDDesignTools")]
    else:
        exe = "vivado"
        roots = ["/tools/Xilinx/Vivado", "/opt/Xilinx/Vivado", str(Path.home() / "Xilinx/Vivado")]
    found = [p for r in roots for p in Path(r).glob(f"*/bin/{exe}")]
    return str(max(found, key=lambda p: p.parts[-3])) if found else None   # version mas nueva

def run_vivado(vivado: str, args, mode: str, out: Path) -> int:
    """Ejecuta run.tcl dentro de Vivado. La config viaja por variables de entorno."""
    env = {
        **os.environ,
        "MODE": mode,
        "PROJ": args.proj.resolve().as_posix(),
        "OUT": out.as_posix(),
        "SIMSET": SIMSET,
        "RUNTIME": args.runtime,
        "TB_GLOB": args.glob,
        "TB_LIST": " ".join(args.tbs),
    }
    tcl = str(HERE / "run.tcl")
    if mode == "gui":
        cmd = [vivado, str(args.proj.resolve()), "-mode", "gui", "-source", tcl]
    else:
        cmd = [vivado, "-mode", "batch", "-nojournal", "-notrace",
               "-log", str(out / "vivado.log"), "-source", tcl]

    show_output = args.verbose or mode == "gui"
    return subprocess.run(cmd, env=env, cwd=out,
                          stdout=None if show_output else subprocess.DEVNULL).returncode


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""


def judge(tb_dir: Path, pass_pattern: str):
    """Devuelve None si el TB paso, o un texto con el motivo si fallo."""
    status = read(tb_dir / "status.txt").strip() or "no se simulo"
    if status != "OK":
        return "Vivado fallo: " + status.splitlines()[0][:100]

    logs = {name: read(tb_dir / f"{name}.log") for name in LOGS}
    for text in logs.values():
        for line in text.splitlines():
            if re.search(FAIL_PATTERN, line):
                return line.strip()[:100]

    if pass_pattern and not re.search(pass_pattern, logs["simulate"]):
        return f"no aparecio '{pass_pattern}' en simulate.log"
    return None


def write_junit(path: Path, results: dict) -> None:
    """XML estandar que entienden GitHub Actions, GitLab, Jenkins, etc."""
    failures = sum(1 for reason in results.values() if reason)
    suite = ET.Element("testsuite", name="regression",
                       tests=str(len(results)), failures=str(failures))
    for tb, reason in results.items():
        case = ET.SubElement(suite, "testcase", name=tb)
        if reason:
            ET.SubElement(case, "failure", message=reason)
    ET.ElementTree(suite).write(path, encoding="utf-8", xml_declaration=True)


def print_summary(results: dict, out: Path) -> None:
    width = max(len(tb) for tb in results)
    print("\n=============== RESUMEN ===============")
    for tb, reason in results.items():
        if reason is None:
            print(f"  PASS  {tb}")
        else:
            print(f"  FAIL  {tb:<{width}}  -> {reason}")
            print(f"        log: {out / tb / 'simulate.log'}")
    passed = sum(1 for reason in results.values() if reason is None)
    print(f"\n{passed}/{len(results)} OK")


def parse_args():
    p = argparse.ArgumentParser(description="Regresion de testbenches en Vivado")
    p.add_argument("tbs", nargs="*", help="TBs a correr (default: todos los que matcheen --glob)")
    p.add_argument("--proj", type=Path, default=DEFAULT_XPR, help="proyecto .xpr (o variable RISCV_XPR)")
    p.add_argument("--glob", default=TB_GLOB, help=f"patron para detectar TBs (default: {TB_GLOB})")
    p.add_argument("--pass-pattern", default=PASS_PATTERN, help="texto que debe imprimir un TB que paso")
    p.add_argument("--runtime", default="-all", help='tiempo maximo por TB, ej. "100 us" (default: -all)')
    p.add_argument("--out", type=Path, default=DEFAULT_OUT, help="carpeta de resultados")
    p.add_argument("--vivado", default="vivado", help="ejecutable o ruta completa a vivado(.bat)")
    p.add_argument("--list", action="store_true", help="solo listar los TBs detectados")
    p.add_argument("--gui", action="store_true", help="abrir Vivado GUI con el TB indicado")
    p.add_argument("-v", "--verbose", action="store_true", help="mostrar la salida completa de Vivado")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    mode = "gui" if args.gui else "list" if args.list else "run"
    out = args.out.resolve()

    vivado = find_vivado(args.vivado)
    if not vivado:
        return error("no encuentro Vivado. Agregalo al PATH o usa --vivado <ruta a vivado.bat>")
    if not args.proj.is_file():
        return error(f"no existe el proyecto {args.proj.resolve()}\n"
                     "       Usa --proj <ruta.xpr> o defini la variable RISCV_XPR")
    if mode == "gui" and not args.tbs:
        return error("con --gui indica un TB, ej: py run.py alu_tb --gui")

    out.mkdir(parents=True, exist_ok=True)
    (out / "tbs.txt").unlink(missing_ok=True)      # si no reaparece, Vivado ni arranco

    if mode == "gui":
        return run_vivado(vivado, args, mode, out)

    print("Corriendo Vivado... (log completo en", out / "vivado.log", ")")
    run_vivado(vivado, args, mode, out)

    if not (out / "tbs.txt").exists():
        print("\n".join(read(out / "vivado.log").splitlines()[-15:]))
        return error(f"Vivado no llego a simular. Revisa {out / 'vivado.log'}")
    tbs = read(out / "tbs.txt").split()
    if not tbs:
        return error(f"no se encontraron testbenches (patron '{args.glob}' en {SIMSET})")

    if mode == "list":
        print("\n".join(tbs))
        return 0

    results = {tb: judge(out / tb, args.pass_pattern) for tb in tbs}
    print_summary(results, out)
    write_junit(out / "junit.xml", results)
    return 1 if any(results.values()) else 0


if __name__ == "__main__":
    sys.exit(main())