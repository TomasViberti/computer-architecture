# Software de PC: CLI, TUI y GUI para la Debug Unit

Tres interfaces para programar el procesador por UART, ejecutarlo y ver su estado (registros,
memoria de datos y latches). Las tres usan el mismo núcleo, así que hacen lo mismo y responden igual.

| Interfaz | Para qué sirve | Arranque |
|---|---|---|
| **CLI** (`cli.py`) | Comandos sueltos para scripts y comparaciones; incluye un shell interactivo | `python cli.py --sim run ../scripts/program.txt` |
| **TUI** (`tui.py`) | Todo el estado en una pantalla de terminal, manejada con el teclado | `python tui.py --sim ../scripts/program.txt` |
| **GUI** (`gui.py`) | Editor de assembler y depurador visual: breakpoints, historial, auto-step | `python gui.py --sim ../scripts/program.txt` |

`--sim` usa una **Debug Unit simulada** en Python en lugar de la placa. Sirve para probar todo sin la
FPGA. Para usar la placa, reemplazá `--sim` por `-p <puerto>`.

---

## 1. Instalación

Requiere Python 3.9 o más nuevo. Desde `RISC-V/software`:

```bash
python -m venv .venv
# Linux / macOS:
source .venv/bin/activate
# Windows (PowerShell):
.venv\Scripts\Activate.ps1

pip install -r requirements.txt
```

| Dependencia | La usa |
|---|---|
| `pyserial` | la conexión con la placa (la CLI, la TUI y la GUI) |
| `rich` | la CLI |
| `textual` | la TUI |
| `tkinter` | la GUI. Viene con Python; en Ubuntu/Debian: `sudo apt install python3-tk` |

En **Linux**, para abrir el puerto sin `sudo` el usuario tiene que estar en el grupo `dialout`
(`sudo usermod -aG dialout $USER`, y volver a iniciar sesión). La Basys 3 aparece como dos puertos
FTDI. La UART suele ser el **segundo**: `/dev/ttyUSB1` en Linux, el COM de número más alto en Windows.

## 2. Uso rápido

```bash
cd RISC-V/software

# Sin placa
python cli.py --sim run ../scripts/program.txt --compare
python cli.py --sim step ../scripts/program.txt          # paso a paso, una línea por ciclo
python tui.py --sim ../scripts/program.txt
python gui.py --sim ../scripts/program.txt

# Con placa (bitstream de top_monocycle_debug cargado)
python cli.py ports                                       # lista los puertos
python cli.py -p /dev/ttyUSB1 run ../scripts/program.txt --compare -o ../scripts/rtl_state_debug.txt
python tui.py -p COM8 ../scripts/program.txt
python gui.py                                             # puerto y conexión se eligen en la ventana
```

El programa puede ser **assembler** (`program.txt`, `.s`) o un **`machine_code.txt`**. El software
detecta cuál es por el contenido. El assembler se ensambla con las mismas funciones de
`scripts/assembler.py`, así que acepta la misma sintaxis y da los mismos errores.

Si no se pasa `-p` y hay un solo puerto, se usa ese.

## 3. CLI

```
python cli.py [conexión] <comando> [opciones]
```

Las opciones de conexión pueden ir antes o después del comando:

| Opción | Significado |
|---|---|
| `-p, --port` | puerto serie (`COM8`, `/dev/ttyUSB1`) |
| `-b, --baud` | baudrate (115200) |
| `--sim` | usar la Debug Unit simulada |
| `--sim-protocol 0\|1` | 0 = igual al RTL actual (solo LOAD/RUN), 1 = con STEP (default) |
| `-t, --timeout` | segundos de espera del estado después de RUN (10) |
| `--no-probe` | no preguntar la versión al conectar (asume v0) |

| Comando | Qué hace |
|---|---|
| `ports` | lista los puertos serie |
| `info` | versión y capacidades de la Debug Unit |
| `asm prog.s [-o machine_code.txt]` | ensambla, sin conectarse |
| `disasm prog` | muestra el programa desensamblado, sin conectarse |
| `run prog [-o estado.txt] [--compare] [--json] [--mem-all]` | **modo continuo**: LOAD, RUN y estado final |
| `step prog [-n N] [...]` | **modo paso a paso**: LOAD y STEP hasta el HALT (o N ciclos) |
| `shell [prog]` | shell interactivo (ver abajo) |

- `--compare` corre el modelo (`scripts/monocycle_model.py`) con el mismo programa y dice `IGUALES` o
  lista las diferencias. El código de salida es 0 si coinciden y 1 si no, así que sirve para
  automatizar pruebas.
- `-o` guarda el estado con el mismo formato que `rtl_state.txt`, así el flujo de comparación de
  `scripts/README.md` sigue funcionando.
- `--json` imprime el estado en JSON por stdout. Los mensajes de progreso van a stderr.

### Shell interactivo

`python cli.py --sim shell ../scripts/program.txt`. Enter sin nada repite el último comando, cómodo
para avanzar con `step`.

| Comando | |
|---|---|
| `load [archivo]` | ensambla y carga. Sin archivo, recarga el último (útil después de editarlo) |
| `run` / `step [n]` | modo continuo / n ciclos, con una línea por ciclo: instrucción y lo que cambió |
| `state [all]`, `regs`, `mem [all]`, `latches`, `prog` | inspección (lo que cambió se resalta) |
| `history`, `show <n>` | lista los estados recibidos / vuelve a uno anterior |
| `compare`, `save [archivo]`, `info` | comparar con el modelo / guardar el estado / versión |
| `reset`, `reprogram` | solo simulador: switch de reset / reprogramar la FPGA |
| `help [comando]`, `quit` | |

## 4. TUI

`python tui.py [--sim | -p PUERTO] [programa]`

Cuatro paneles: memoria de programa (con el PC marcado), registros, memoria de datos usada y
latches. Abajo hay una línea de estado y un log. Lo que cambió en el último paso se pinta de amarillo.

| Tecla | Acción | Tecla | Acción |
|---|---|---|---|
| `l` | cargar (vuelve a leer el archivo del disco) | `←` `→` | navegar el historial |
| `r` | run (modo continuo) | `fin` | volver al último estado |
| `s` | step | `m` | memoria: todas las palabras / solo las usadas |
| `a` | auto-step (`--auto-ms` define el período) | `c` | comparar con el modelo |
| `o` | abrir otro archivo | `w` | guardar en `rtl_state_debug.txt` |
| `x` / `p` | (sim) switch de reset / reprogramar | `q` | salir |

Un flujo cómodo es editar el `.s` en tu editor y apretar `l` y `r` (o `s`) en la TUI.

## 5. GUI

`python gui.py [--sim | -p PUERTO] [programa]`

- **Arriba:** la conexión (puerto o simulador v0/v1, se actualiza con ⟳), comparar, guardar el estado
  y el menú del simulador. Abajo de eso, la ejecución: **Cargar** (F6), **Run** (F5), **Step**
  (F10), **Step N**, **Continuar** (pasos hasta el HALT o un breakpoint), **Auto** (F8, un paso
  cada X ms) y **Parar** (Esc).
- **Editor:** resaltado de sintaxis y números de línea (Ctrl+O abre, Ctrl+S guarda). *Cargar*
  ensambla lo que hay en el editor. Si hay un error se marca la línea en rojo. Durante el paso a
  paso se marca en celeste la línea fuente de la instrucción del PC. También puede exportar el
  `machine_code.txt`.
- **Memoria de programa:** desensamblada, con el PC marcado. **Doble click pone o saca un
  breakpoint**, que usan *Continuar* y *Auto*.
- **Registros / Memoria de datos / Latches:** lo que cambió respecto del estado anterior se pinta
  de amarillo.
- **Historial:** la barra deslizante permite volver a cualquier estado recibido y compararlo con
  el anterior.

Los botones que la Debug Unit conectada no soporta quedan deshabilitados. Por ejemplo, con la placa
actual (v0) están deshabilitados Step, Step N, Continuar y Auto.

## 6. El simulador

`--sim` reemplaza la placa por `riscv_debugger/sim.py`. Habla **el mismo protocolo, byte a byte**,
que `debug_unit.v`, y el procesador es el `Cpu` de `scripts/monocycle_model.py`. Imita también el
comportamiento de la placa entre programas:

- LOAD escribe solo las N palabras del programa; el resto de la memoria de programa queda como estaba.
- Ni LOAD ni RUN vacían los registros ni la memoria de datos.
- Un programa que no termina deja a la Debug Unit sin responder, hasta "bajar y subir el switch de
  reset" (`reset` / `x`). "Reprogramar la FPGA" (`reprogram` / `p`) vacía todo.

`--sim-protocol 0` se comporta exactamente como el RTL actual. `--sim-protocol 1` (el default) agrega
STEP e INFO, la propuesta del punto 8, para poder usar y probar el modo paso a paso antes de tener
el pipeline.

## 7. Cómo está armado

```
 cli.py      tui.py      gui.py          <- interfaces: solo muestran y llaman a la sesión
    \          |          /
     DebugSession  (session.py)          <- load / run / step / probe / historial / comparar
           |
     protocol.py                         <- comandos, paquetes, CpuState, layout de latches
           |
     Transport  (transport.py)
       ├── SerialTransport  -> placa por UART (pyserial)
       └── SimTransport     -> SimulatedDebugUnit (sim.py) -> Cpu de monocycle_model.py

 program.py: ensamblado (reusa scripts/assembler.py), machine_code.txt y desensamblador
 legacy.py : importa scripts/assembler.py y scripts/monocycle_model.py sin copiarlos
```

- Cada comando devuelve un `CpuState` (PC, ciclos, banderas, 32 registros, memoria de datos y
  latches) que se agrega al **historial** de la sesión. Las interfaces dibujan el estado elegido y
  marcan las diferencias con el anterior.
- La GUI y la TUI hacen la comunicación en un hilo aparte, así la ventana no se congela mientras
  la placa ejecuta.
- No se modificó nada fuera de `RISC-V/software/`: el RTL y los scripts quedaron iguales.

## 8. Preparado para el pipeline (paso a paso y latches)

El protocolo actual (v0) solo tiene `LOAD` y `RUN`. Para el pipeline, el software ya implementa
esta **propuesta (v1)**. El RTL todavía no la tiene:

| PC → FPGA | Respuesta | Significado |
|---|---|---|
| `03` STEP | `00` + paquete de estado | ejecuta **un ciclo de clock** y manda el estado |
| `04` INFO | `00` + `20 ver caps imem(2) dmem(2)` | versión, capacidades (bit0 LOAD, bit1 RUN, bit2 STEP) y profundidades |

**Paquete de estado `11`:** es igual al `10` y al final agrega los latches:

```
... (todo lo del paquete 10) ...
1 byte   L = cantidad de latches
L veces: 1 byte id | 1 byte W = cantidad de palabras | W palabras de 4 bytes (LSB primero)
```

**Semántica propuesta de STEP:** si el procesador está en reset (después de LOAD o de un HALT), STEP
lo saca del reset con PC = 0 y contadores en cero, y ejecuta el primer ciclo. Cuando el programa
termina (en el pipeline, cuando el HALT llega a WB y el pipeline quedó vacío), el estado sale con
la bandera HALT y el procesador vuelve a reset. RUN sigue igual que en v0.

**Detección automática:** al conectarse, el software manda INFO. La Debug Unit v0 responde `01`
(comando desconocido), y el software asume v0 y deshabilita el paso a paso. **El día que el RTL
implemente v1, las tres interfaces habilitan STEP solas, sin cambiar nada en la PC.**

**Latches:** el significado de cada palabra está en `LATCH_LAYOUT`
(`riscv_debugger/protocol.py`): id → nombre (IF/ID, ID/EX, EX/MEM, MEM/WB) y campos (palabra, bits,
formato). Si el RTL manda otra cosa, se ajusta **solo esa tabla**, y la CLI, la TUI y la GUI la
muestran sin más cambios. Un id que no está en la tabla se muestra como palabras crudas.

### Checklist para agregar algo nuevo

1. Comando nuevo: la constante y el armado o la lectura del paquete en `protocol.py`, un método
   en `DebugSession` y, si hay que probarlo sin placa, el caso en `sim.py`.
2. Las interfaces solo llaman al método nuevo: un subcomando o `do_x` en `cli.py`, una `Binding`
   en `tui.py` y un botón en `gui.py`.
3. Un test en `tests/test_software.py`.

## 9. Tests

```bash
cd RISC-V/software
python -m unittest discover -s tests -v
```

No necesitan la placa. Entre otras cosas, verifican lo siguiente:

- El ensamblado coincide con `scripts/machine_code.txt`.
- El simulador devuelve exactamente `scripts/rtl_state_debug.txt` (lo que devolvió la placa).
- El paso a paso llega al mismo estado que RUN.
- El paquete con latches se lee bien.
- Se respeta la persistencia de registros y memoria entre programas.
- Se manejan bien los programas que no terminan.

## 10. Problemas comunes

| Síntoma | Causa / solución |
|---|---|
| `No se pudo abrir /dev/ttyUSB1: Permission denied` | falta el grupo `dialout` (ver Instalación) |
| `la FPGA no respondió al INFO/LOAD` | puerto equivocado (probá el otro de la Basys 3), placa sin bitstream o switch de reset (SW15) en 0 |
| `no llegó el estado en 10 s` | el programa no termina (bucle infinito): bajá y subí **SW15**. Si es largo, usá `-t` |
| `compare` da `DIFERENTES` con la placa | los registros y la memoria **no se vacían** entre programas: reprogramá la FPGA antes de cargar |
| La TUI dice `No module named textual` | `pip install -r requirements.txt` |
| La GUI no abre en Linux | `sudo apt install python3-tk` |
