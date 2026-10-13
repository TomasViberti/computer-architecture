FLUJO DE PRUEBA: ensamblador -> testbench (RTL) -> modelo -> comparacion
========================================================================

Archivos
  assembler.py             assembler -> lineas prog[n] = 32'h...; para pegar en el testbench

  monocycle_model.py       modelo del CPU: ejecuta el programa, escribe py_model_state.txt y lo
                           compara con rtl_state.txt

  top_monocycle_tb.sv      testbench simple: carga el programa, lo ejecuta hasta el HALT y escribe el
                           estado final en un archivo. No hace chequeos: de eso se encarga el modelo

  program.txt              el programa principal de tu testbench, en assembler

Pasos
  1. Escribi el programa en program.txt

  2. python assembler.py
       -> escribe machine_code.txt

  3. En top_monocycle_tb.sv pega el contenido de machine_code.txt entre los marcadores
      
  4. Pone en RUTA_ESTADO una ruta absoluta con barras normales, por ejemplo
       "C:/Users/usuario/proyecto/rtl_state.txt"

  5. Simula en Vivado (Relaunch Simulation, porque cambio el testbench y hay que recompilar).
       -> el testbench escribe rtl_state.txt

  6. python monocycle_model.py --rtl "C:/Users/usuario/proyecto/rtl_state.txt"
       -> escribe py_model_state.txt y dice IGUALES o DIFERENTES (con las lineas que difieren).

Formato del estado (identico en los dos archivos)
  PC=0000009c
  CICLOS=45             instrucciones ejecutadas (sin contar el HALT)
  HALT=1                1 si el programa llego al HALT
  ERROR_IMEM=0          alguna vez el PC estuvo fuera de la memoria de programa
  ERROR_DMEM=0          algun acceso a datos fuera de rango mientras se ejecutaba
  x0=00000000 ... x31=...
  MEM[0x00000000]=0000000c   solo las palabras de datos distintas de cero

Que prueba y que no
  - Prueba que el RTL ejecuta igual que el modelo el MISMO codigo maquina.
  - No prueba que el ensamblador codifique bien (un error de codificacion seria igual en los dos).
  - El modelo y el RTL salen de las mismas decisiones de diseno: si ambos entienden mal una instruccion
    de la misma forma, la comparacion no lo muestra.
