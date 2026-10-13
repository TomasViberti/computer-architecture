# Flujo de prueba del monociclo

Permite comprobar que el RTL ejecuta un programa igual que el modelo en Python.
El mismo código máquina se ejecuta dos veces: en el RTL (simulado en Vivado) y en el modelo. Cada uno escribe el
estado en un archivo de texto, y la comparación dice si coinciden.

```
program.txt ──► assembler.py ──► machine_code.txt ─┬─► testbench (Vivado) ──► rtl_state.txt ─────┐
  (assembler)                     (código máquina) │                                             ├─► ¿IGUALES?
                                                   └─► monocycle_model.py ──► py_model_state.txt ┘
```

## Archivos

| Archivo | Qué hace |
|---|---|
| `program.txt` | Programa de entrada, en assembler. |
| `assembler.py` | Convierte `program.txt` en código máquina y escribe `machine_code.txt` (líneas `prog[n] = 32'h...;`). |
| `monocycle_model.py` | Modelo del CPU: ejecuta el programa, escribe `py_model_state.txt` y lo compara con `rtl_state.txt`. |
| `top_monocycle_tb.sv` | Testbench con el programa **pegado** dentro del archivo. |
| `top_monocycle_tb_from_file.sv` | Testbench que **lee** el programa directamente de `machine_code.txt`. |
| `machine_code.txt` | Generado por el ensamblador. |
| `rtl_state.txt` | Generado por el testbench: estado final del RTL. |
| `py_model_state.txt` | Generado por el modelo: estado final esperado. |

Los dos testbenches son equivalentes: cargan el programa por el puerto de escritura de la memoria de instrucciones,
ejecutan hasta el HALT y escriben `rtl_state.txt` con el mismo formato. Solo cambia cómo reciben el programa.

## Uso

### 1. Escribir y ensamblar el programa

1. Escribí el programa en `program.txt`.
2. Corré:

   ```
   python assembler.py
   ```

   Escribe `machine_code.txt`.

### 2. Simular en Vivado

#### Opción A: pegar el programa (`top_monocycle_tb.sv`)

1. Pegá el contenido de `machine_code.txt` entre los marcadores del testbench, reemplazando lo que haya entre ellos:

   ```
   // >>>>>>>>>> PEGAR AQUI EL PROGRAMA >>>>>>>>>>
   // <<<<<<<<<< FIN DEL PROGRAMA <<<<<<<<<<
   ```

2. En `RUTA_ESTADO` poné una ruta absoluta con barras normales (`/`), por ejemplo:

   ```systemverilog
   localparam RUTA_ESTADO = "C:/Users/usuario/proyecto/rtl_state.txt";
   ```

3. Simulá con **Relaunch Simulation**: cambió el testbench y hay que recompilar.

#### Opción B: leer el programa del archivo (`top_monocycle_tb_from_file.sv`)

1. Una sola vez, poné las dos rutas absolutas con barras normales (`/`):

   ```systemverilog
   localparam RUTA_PROGRAMA = "C:/Users/usuario/proyecto/machine_code.txt";
   localparam RUTA_ESTADO   = "C:/Users/usuario/proyecto/rtl_state.txt";
   ```

2. Para cada programa nuevo no hay que tocar el testbench: después de `python assembler.py`, simulá con **Restart**.
   El archivo se vuelve a leer al empezar la simulación. Si Vivado no toma el cambio, usá **Relaunch Simulation**.
3. Mirá en la consola la línea `Programa leido de ...: N palabras`. N tiene que coincidir con la cantidad de
   instrucciones del programa.

El testbench toma solo las líneas con la forma `prog[n] = 32'hXXXXXXXX;` y ignora el resto (comentarios, líneas en
blanco). Lo que no aparece en el archivo queda en HALT.

> **Nota:** los módulos se llaman distinto (`top_tb` y `top_tb_file`) para que no choquen. Si los dos están en las
> fuentes de simulación, elegí uno como top de simulación.

### 3. Comparar con el modelo

```
python monocycle_model.py --rtl "C:/Users/usuario/proyecto/rtl_state.txt"
```

Escribe `py_model_state.txt` y muestra el resultado:

- `IGUALES`: el RTL y el modelo terminaron en el mismo estado.
- `DIFERENTES`: lista cada línea que difiere, con el valor del modelo y el del RTL.

## Formato del estado

Es idéntico en `rtl_state.txt` y en `py_model_state.txt`:

```
PC=0000009c
CICLOS=45
HALT=1
ERROR_IMEM=0
ERROR_DMEM=0
x0=00000000
...
x31=00000000
MEM[0x00000000]=0000000c
```

| Línea | Significado |
|---|---|
| `PC` | PC final. |
| `CICLOS` | Instrucciones ejecutadas (sin contar el HALT). |
| `HALT` | 1 si el programa llegó al HALT. |
| `ERROR_IMEM` | 1 si alguna vez el PC estuvo fuera de la memoria de programa. |
| `ERROR_DMEM` | 1 si hubo algún acceso a datos fuera de rango mientras se ejecutaba. |
| `x0` ... `x31` | Registros finales. |
| `MEM[0x...]` | Palabras de la memoria de datos distintas de cero. La dirección es en bytes y es la del primer byte de la palabra de 4 bytes. |

## Qué prueba y qué no

- Prueba que el RTL ejecuta igual que el modelo **el mismo código máquina**.
- No prueba que el ensamblador codifique bien: un error de codificación sería igual en los dos.
- El modelo y el RTL salen de las mismas decisiones de diseño. Si ambos entienden mal una instrucción de la misma
  forma, la comparación no lo muestra.