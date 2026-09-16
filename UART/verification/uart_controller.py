#!/usr/bin/env python3
"""
Controlador UART para ALU en FPGA
Permite ejecutar operaciones aritmeticas y logicas en tiempo real
"""

import sys
import time
import argparse

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    print("Falta pyserial. Instala con: pip install pyserial")
    sys.exit(1)

try:
    from rich.console import Console
    from rich.table import Table
    from rich.panel import Panel
    from rich.progress import track
    from rich import box
except ImportError:
    print("Falta rich. Instala con: pip install rich")
    sys.exit(1)

console = Console()


class ALUController:
    # Mapeo de operaciones: opcode (funct field estilo MIPS), descripcion y ejemplo.
    # Una sola fuente de verdad: de aca salen tanto la validacion como la tabla de ayuda.
    OPERATIONS = {
        'add': (0x20, "Suma", "add 10 20"),
        'sub': (0x22, "Resta", "sub 50 30"),
        'and': (0x24, "AND logico", "and 0xFF 0x0F"),
        'or':  (0x25, "OR logico", "or 128 64"),
        'xor': (0x26, "XOR logico", "xor 170 85"),
        'nor': (0x27, "NOR logico", "nor 15 240"),
        'srl': (0x02, "Shift Right Logical (0-7 bits)", "srl 128 2"),
        'sra': (0x03, "Shift Right Arithmetic (0-7 bits)", "sra 128 3"),
    }

    SHIFT_OPS = {'srl', 'sra'}

    # Info extra por tipo de operacion, ademas del decimal/hex/binario que se muestra siempre
    _EXTRA_INFO = {
        'add': lambda r, a, b: f"(int8: {r - 256 if r > 127 else r})",
        'sub': lambda r, a, b: f"(int8: {r - 256 if r > 127 else r})",
        'srl': lambda r, a, b: f"(valor {a} desplazado {b} posiciones a la derecha)",
        'sra': lambda r, a, b: f"(valor {a} desplazado {b} posiciones a la derecha)",
    }

    def __init__(self, port, baudrate=9600, timeout=2):
        self.port = port
        self.baudrate = baudrate
        try:
            self.ser = serial.Serial(port, baudrate, timeout=timeout)
            time.sleep(2)  # Esperar estabilizacion de la conexion
        except serial.SerialException as e:
            console.print(f"[bold red]✗ Error al abrir puerto serial:[/bold red] {e}")
            self._suggest_ports()
            sys.exit(1)

        self._print_banner()

    @staticmethod
    def _suggest_ports():
        ports = list(list_ports.comports())
        if not ports:
            console.print("[yellow]No se detectaron puertos seriales disponibles.[/yellow]")
            return
        table = Table(title="Puertos disponibles", box=box.SIMPLE)
        table.add_column("Puerto")
        table.add_column("Descripcion")
        for p in ports:
            table.add_row(p.device, p.description or "-")
        console.print(table)

    @staticmethod
    def _in_range(value, lo, hi):
        return lo <= value <= hi

    def _print_banner(self):
        ops = ", ".join(op.upper() for op in self.OPERATIONS)
        panel = Panel.fit(
            f"[bold green]✓ Conectado a {self.port} @ {self.baudrate} baud[/bold green]\n"
            f"[cyan]Operaciones disponibles:[/cyan] {ops}",
            title="Controlador ALU UART",
            border_style="green",
        )
        console.print(panel)

    @staticmethod
    def _parse_int(value):
        """Convierte string a entero soportando decimal, hex (0x..), oct (0o..) y bin (0b..)."""
        return int(value, 0)

    def execute_operation(self, operation, operand_a, shift_or_b):
        """
        Ejecuta una operacion en la ALU de la FPGA.

        Args:
            operation: Nombre de la operacion (ej: 'add', 'sub', etc.)
            operand_a: Primer operando (0-255)
            shift_or_b: Segundo operando (0-255), o cantidad de shift (0-3) para srl/sra

        Returns:
            Resultado de la operacion (0-255) o None si hay error
        """
        if operation not in self.OPERATIONS:
            console.print(f"[red]✗ Operacion '{operation}' no valida[/red]")
            return None

        opcode = self.OPERATIONS[operation][0]
        is_shift = operation in self.SHIFT_OPS
        b_max = 7 if is_shift else 255

        if not self._in_range(operand_a, 0, 255):
            console.print("[red]✗ Operando A fuera de rango (0-255)[/red]")
            return None
        if not self._in_range(shift_or_b, 0, b_max):
            label = "Cantidad de desplazamiento debe ser 0-7" if is_shift else "Operando B fuera de rango (0-255)"
            console.print(f"[red]✗ {label}[/red]")
            return None

        # B se envia tal cual: para srl/sra es la cantidad de desplazamiento (0-7),
        # no se codifica en bits altos.
        operand_b_encoded = shift_or_b

        try:
            self.ser.reset_input_buffer()
            self.ser.write(bytes([operand_a, operand_b_encoded, opcode]))
            self.ser.flush()

            result = self.ser.read(1)

            if len(result) == 1:
                return result[0]
            else:
                console.print("[red]✗ Timeout: no se recibio respuesta de la FPGA[/red]")
                return None

        except serial.SerialException as e:
            console.print(f"[red]✗ Error de comunicacion:[/red] {e}")
            return None

    def parse_and_execute(self, command):
        """Parsea un comando tipo 'add 10 15' (o 'and 0xFF 0x0F') y lo ejecuta."""
        parts = command.strip().lower().split()

        if len(parts) != 3:
            console.print("[red]✗ Formato invalido.[/red] Uso: <operacion> <operando1> <operando2>")
            console.print("  Ejemplo: [cyan]add 10 15[/cyan]  o  [cyan]and 0xFF 0x0F[/cyan]")
            return

        operation = parts[0]

        try:
            operand_a = self._parse_int(parts[1])
            operand_b = self._parse_int(parts[2])
        except ValueError:
            console.print("[red]✗ Los operandos deben ser numeros enteros (decimal, 0x.. o 0b..)[/red]")
            return

        console.print(f"[bold]→ Ejecutando:[/bold] {operation.upper()} {operand_a} {operand_b}")
        result = self.execute_operation(operation, operand_a, operand_b)

        if result is None:
            return

        base = f"{result} (decimal) = 0x{result:02X} (hex) = 0b{result:08b} (binario)"
        extra = self._EXTRA_INFO.get(operation)
        if extra:
            base += f"  {extra(result, operand_a, operand_b)}"
        console.print(f"[bold green]← Resultado:[/bold green] {base}")
        console.print("-" * 60, style="dim")

    def show_help(self):
        table = Table(title="Operaciones disponibles", box=box.ROUNDED)
        table.add_column("Op", style="bold cyan")
        table.add_column("Descripcion")
        table.add_column("Ejemplo", style="green")
        for op, (_, desc, ejemplo) in self.OPERATIONS.items():
            table.add_row(op.upper(), desc, ejemplo)
        console.print(table)
        console.print(
            "[dim]Operandos: 0-255 (decimal, 0x.. hex o 0b.. binario). "
            "Para SRL/SRA el segundo operando es la cantidad de bits (0-3).[/dim]\n"
        )

    def interactive_mode(self):
        console.rule("[bold]Modo interactivo[/bold]")
        console.print("Escribi 'help' para ver operaciones, 'ports' para ver puertos, 'quit' para salir.\n")

        while True:
            try:
                command = console.input("[bold blue]ALU>[/bold blue] ").strip()

                if not command:
                    continue
                if command.lower() in ('quit', 'exit'):
                    console.print("Cerrando conexion...")
                    break
                if command.lower() == 'help':
                    self.show_help()
                    continue
                if command.lower() == 'ports':
                    self._suggest_ports()
                    continue

                self.parse_and_execute(command)

            except KeyboardInterrupt:
                console.print("\n[yellow]Interrumpido por usuario. Cerrando...[/yellow]")
                break
            except Exception as e:
                console.print(f"[red]✗ Error:[/red] {e}")

    def close(self):
        if self.ser.is_open:
            self.ser.close()
            console.print("[green]✓ Conexion cerrada[/green]")

    def batch_test(self):
        """Ejecuta un conjunto de pruebas automaticas"""
        console.rule("[bold]Pruebas automaticas[/bold]")

        tests = [
            ("add", 10, 15),
            ("add", 100, 155),
            ("sub", 50, 20),
            ("sub", 200, 150),
            ("and", 0xFF, 0x0F),
            ("or", 0xF0, 0x0F),
            ("xor", 170, 85),
            ("nor", 0, 255),
            ("srl", 128, 1),  # 128 >> 1 = 64
            ("srl", 15, 2),   # 15 >> 2 = 3
            ("sra", 128, 3),  # arithmetic: mantiene el bit de signo
        ]

        table = Table(box=box.SIMPLE_HEAVY)
        table.add_column("Op")
        table.add_column("A")
        table.add_column("B")
        table.add_column("Resultado")

        for op, a, b in track(tests, description="Ejecutando..."):
            result = self.execute_operation(op, a, b)
            if result is None:
                table.add_row(op.upper(), str(a), str(b), "[red]ERROR[/red]")
            else:
                table.add_row(op.upper(), str(a), str(b), f"{result} = 0x{result:02X} = 0b{result:08b}")
            time.sleep(0.3)

        console.print(table)


def resolve_port(explicit_port):
    """Devuelve el puerto a usar: el explicito, el unico detectado, o pregunta al usuario."""
    if explicit_port:
        return explicit_port

    ports = list(list_ports.comports())
    if len(ports) == 1:
        console.print(f"[dim]Usando unico puerto detectado: {ports[0].device}[/dim]")
        return ports[0].device

    ALUController._suggest_ports()
    return console.input("[bold]Ingresa el puerto a usar:[/bold] ").strip()


def main():
    parser = argparse.ArgumentParser(description="Controlador UART para ALU en FPGA")
    parser.add_argument("-p", "--port", default=None, help="Puerto serial (ej: COM8, /dev/ttyUSB0)")
    parser.add_argument("-b", "--baud", type=int, default=9600, help="Baudrate (default: 9600)")
    parser.add_argument("--test", action="store_true", help="Correr bateria de pruebas automaticas y salir")
    args = parser.parse_args()

    port = resolve_port(args.port)

    alu = None
    try:
        alu = ALUController(port=port, baudrate=args.baud)
        if args.test:
            alu.batch_test()
        else:
            alu.interactive_mode()
    except Exception as e:
        console.print(f"[bold red]Error fatal:[/bold red] {e}")
        sys.exit(1)
    finally:
        if alu is not None:
            alu.close()


if __name__ == "__main__":
    main()