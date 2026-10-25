# =============================================================================
# run.tcl - Simula testbenches dentro de Vivado.
#
# Este script SOLO simula y guarda logs. NO decide PASS/FAIL (eso lo hace run.py).
# No se ejecuta a mano: lo lanza run.py, que le pasa la configuracion por
# variables de entorno (PROJ, OUT, SIMSET, RUNTIME, TB_GLOB, TB_LIST, MODE).
#
# Archivos que deja en $OUT:
#   tbs.txt                            TBs simulados, uno por linea
#   <tb>/status.txt                    "OK", o el error de Vivado (ej. no compila)
#   <tb>/{compile,elaborate,simulate}.log
# =============================================================================

proc env_or {name default} {
    if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
    return $default
}

set proj    [env_or PROJ ""]
set out     [env_or OUT sim_results]
set simset  [env_or SIMSET sim_1]
set runtime [env_or RUNTIME -all]
set glob    [env_or TB_GLOB *_tb]
set tbs     [env_or TB_LIST ""]       ;# vacio = autodetectar
set mode    [env_or MODE run]         ;# run | list | gui


# --- 1. Abrir el proyecto (en modo gui ya viene abierto) ----------------------
if {[llength [get_projects -quiet]] == 0} {
    open_project $proj
}
set proj_dir [get_property DIRECTORY [current_project]]
set proj_name [get_property NAME [current_project]]
set sim_dir "$proj_dir/$proj_name.sim/$simset/behav/xsim"


# --- 2. Decidir que TBs simular ----------------------------------------------
# Convencion: el archivo se llama igual que el modulo (alu_tb.sv -> module alu_tb)
proc find_tbs {simset glob} {
    set found {}
    foreach f [get_files -quiet -of_objects [get_filesets $simset]] {
        set name [file rootname [file tail $f]]
        set ext  [string tolower [file extension $f]]
        if {$ext in {.v .sv .vhd .vhdl} && [string match $glob $name]} {
            lappend found $name
        }
    }
    return [lsort -unique $found]
}

if {$tbs eq ""} { set tbs [find_tbs $simset $glob] }
if {$mode eq "gui"} { set tbs [lindex $tbs 0] }

file mkdir $out
set fh [open $out/tbs.txt w]
puts $fh [join $tbs \n]
close $fh

if {$mode eq "list"} { exit 0 }


# --- 3. Simular un TB y guardar sus logs -------------------------------------
proc write_status {tb text} {
    global out
    set fh [open $out/$tb/status.txt w]
    puts $fh $text
    close $fh
}

proc run_tb {tb} {
    global simset runtime out sim_dir mode

    set tb_out $out/$tb
    file delete -force $tb_out
    file mkdir $tb_out

    # Intentar borrar logs viejos. En Windows pueden estar bloqueados por otro
    # programa (ej. Vivado GUI con una simulacion abierta), por eso el 'catch'.
    # Ademas, mas abajo solo copiamos logs generados DESPUES de este momento.
    foreach name {compile elaborate simulate} { catch {file delete -force $sim_dir/$name.log} }
    set t0 [clock seconds]

    set_property top     $tb          [get_filesets $simset]
    set_property top_lib xil_defaultlib [get_filesets $simset]
    if {$mode ne "gui"} {
        set_property -name xsim.simulate.runtime -value $runtime -objects [get_filesets $simset]
    }
    update_compile_order -fileset $simset

    set status OK
    if {[catch {launch_simulation -simset $simset} err]} {
        set status $err                   ;# fallo de compilacion/elaboracion
    } elseif {$mode ne "gui"} {
        catch {close_sim}
    }

    foreach name {compile elaborate simulate} {
        set f $sim_dir/$name.log
        if {[file exists $f] && [file mtime $f] >= $t0 - 2} {
            file copy -force $f $tb_out/$name.log
        }
    }
    write_status $tb $status
}

# Si un TB provoca un error de Tcl, lo anotamos y seguimos con los demas
foreach tb $tbs {
    puts "\n=================== $tb ==================="
    if {[catch {run_tb $tb} err]} {
        puts "ERROR en $tb: $err"
        file mkdir $out/$tb
        write_status $tb "error del script: $err"
    }
}