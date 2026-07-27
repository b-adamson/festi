#!/usr/bin/env python3
"""Persistent on-board bridge for barycentric_axi, listening on a plain TCP
socket over the board's ethernet link (see fpga/point_sampler/README.md
section 4 for how the accelerator gets loaded via xmutil in the first
place).

Accepts a connection and reads lines of "v0x v0y v0z v1x v1y v1z v2x v2y
v2z u v" (plain decimal floats), drives the AXI4-Lite register interface
via mmap on /dev/uio4, and writes one "x y z" line per input line back --
the same request/response shape hw/dashboard_server.py's /api/batch
already speaks, so the Windows-side engine code (queryFpgaBatch in
src/model.cpp) needs no changes at all.

This replaces an earlier version of this script that spoke the same
protocol over the board's serial console instead of TCP -- that link ran
at 115200 baud (a debug-console rate, ~3-10ms overhead just to move a
handful of bytes across the wire) and dominated every round trip. A real
ethernet link removes that bottleneck entirely; round trips are now
sub-millisecond, limited by the actual AXI register access, not the wire.

Run with: sudo python3 uio_bridge.py
"""
import mmap
import os
import socket
import struct

UIO_DEVICE = "/dev/uio4"
MAP_SIZE = 0x1000

OFF = {
    "V0X": 0x00, "V0Y": 0x04, "V0Z": 0x08,
    "V1X": 0x0C, "V1Y": 0x10, "V1Z": 0x14,
    "V2X": 0x18, "V2Y": 0x1C, "V2Z": 0x20,
    "U": 0x24, "V": 0x28, "CTRL": 0x2C, "STATUS": 0x30,
    "OUTX": 0x34, "OUTY": 0x38, "OUTZ": 0x3C,
}
NAMES = ["V0X", "V0Y", "V0Z", "V1X", "V1Y", "V1Z", "V2X", "V2Y", "V2Z", "U", "V"]


def to_fixed(x: float) -> int:
    return int(round(x * 65536)) & 0xFFFFFFFF


def from_fixed(v: int) -> float:
    if v & 0x80000000:
        v -= 0x100000000
    return v / 65536.0


def run_one(mm, line: str) -> tuple:
    values = [float(x) for x in line.split()]
    if len(values) != 11:
        raise ValueError(f"expected 11 values, got {len(values)}: {line!r}")

    for name, val in zip(NAMES, values):
        o = OFF[name]
        mm[o:o + 4] = struct.pack("<I", to_fixed(val))

    mm[OFF["CTRL"]:OFF["CTRL"] + 4] = struct.pack("<I", 1)

    # The core's own latency is 3 clock cycles (nanoseconds) so DONE is
    # essentially always already set by the first check -- busy-spin rather
    # than sleep between checks, since sleeping would add far more delay
    # than the poll itself ever needs.
    for _ in range(100000):
        status = struct.unpack("<I", mm[OFF["STATUS"]:OFF["STATUS"] + 4])[0]
        if status & 1:
            break
    else:
        raise TimeoutError("DONE never asserted")

    ox = struct.unpack("<I", mm[OFF["OUTX"]:OFF["OUTX"] + 4])[0]
    oy = struct.unpack("<I", mm[OFF["OUTY"]:OFF["OUTY"] + 4])[0]
    oz = struct.unpack("<I", mm[OFF["OUTZ"]:OFF["OUTZ"] + 4])[0]
    return from_fixed(ox), from_fixed(oy), from_fixed(oz)


HOST = "0.0.0.0"
PORT = 9765


def handle_client(conn, mm):
    buf = b""
    with conn:
        conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        while True:
            chunk = conn.recv(4096)
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                raw_line, buf = buf.split(b"\n", 1)
                line = raw_line.decode("ascii", errors="replace").strip()
                if not line:
                    continue
                try:
                    x, y, z = run_one(mm, line)
                    resp = f"{x} {y} {z}\n"
                except Exception as e:  # noqa: BLE001 -- surface any failure to the client
                    resp = f"ERROR {e}\n"
                conn.sendall(resp.encode("ascii"))


def main():
    fd = os.open(UIO_DEVICE, os.O_RDWR)
    mm = mmap.mmap(fd, MAP_SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0)

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as srv:
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind((HOST, PORT))
        srv.listen(1)
        print(f"BRIDGE_READY {UIO_DEVICE} listening on {HOST}:{PORT}", flush=True)
        while True:
            conn, addr = srv.accept()
            print(f"client connected: {addr}", flush=True)
            try:
                handle_client(conn, mm)
            except Exception as e:  # noqa: BLE001 -- keep serving after a client drops
                print(f"client error: {e}", flush=True)
            print(f"client disconnected: {addr}", flush=True)


if __name__ == "__main__":
    main()
