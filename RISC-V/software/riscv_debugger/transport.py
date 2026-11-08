"""Transportes: por donde viajan los bytes del protocolo.

Las interfaces nunca hablan con el puerto serie directamente: usan una DebugSession, que
usa un Transport. Hay dos:
  - SerialTransport : la placa, por UART (pyserial).
  - SimTransport    : una Debug Unit simulada en Python (sim.py), para usar las
                      interfaces sin placa. Habla el mismo protocolo byte a byte.
"""
import time


class Transport:
    name = "?"

    def write(self, data: bytes):
        raise NotImplementedError

    def read_exact(self, n: int, timeout: float) -> bytes:
        """Lee exactamente n bytes o lanza TimeoutError."""
        raise NotImplementedError

    def flush_input(self):
        raise NotImplementedError

    def close(self):
        pass


class SerialTransport(Transport):
    def __init__(self, port, baudrate=115200):
        import serial                                   # solo hace falta para la placa
        self.port, self.baudrate = port, baudrate
        self.name = f"{port} @ {baudrate}"
        self.ser = serial.Serial(port, baudrate, timeout=0.25, write_timeout=2)
        time.sleep(0.2)                                 # por si quedo algo de una corrida anterior
        self.ser.reset_input_buffer()

    def write(self, data):
        for i in range(0, len(data), 256):              # en trozos, sin pausas largas entre bytes
            self.ser.write(data[i:i + 256])
        self.ser.flush()

    def read_exact(self, n, timeout):
        limit = time.monotonic() + timeout
        buf = bytearray()
        while len(buf) < n:
            left = limit - time.monotonic()
            if left <= 0:
                raise TimeoutError(f"llegaron {len(buf)} de {n} bytes")
            self.ser.timeout = min(left, 0.25)
            buf += self.ser.read(n - len(buf))
        return bytes(buf)

    def flush_input(self):
        self.ser.reset_input_buffer()

    def close(self):
        if self.ser.is_open:
            self.ser.close()


class SimTransport(Transport):
    def __init__(self, unit):
        self.unit = unit
        self.name = f"simulador (protocolo v{unit.version})"

    def write(self, data):
        self.unit.receive(data)

    def read_exact(self, n, timeout):
        data = self.unit.take(n)
        if len(data) < n:
            # La simulacion es instantanea: si no estan los bytes, no van a llegar.
            # Se respeta el timeout para que el comportamiento se parezca al de la placa,
            # pero acotado, para no congelar las interfaces.
            time.sleep(min(timeout, 0.2))
            data += self.unit.take(n - len(data))
            if len(data) < n:
                self.unit.untake(data)
                raise TimeoutError(f"llegaron {len(data)} de {n} bytes")
        return data

    def flush_input(self):
        self.unit.take(len(self.unit.out))


def list_serial_ports():
    """[(dispositivo, descripcion)]. Vacio si pyserial no esta instalado."""
    try:
        from serial.tools import list_ports
    except ImportError:
        return []
    # En Linux aparecen /dev/ttyS0..31 sin hardware detras (hwid "n/a"): se ocultan
    return [(p.device, p.description or "-") for p in list_ports.comports() if p.hwid != "n/a"]
