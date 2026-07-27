"""Local dashboard server for the barycentric.sv live FPGA demo.

Serves hw/dashboard.html at http://localhost:8765 and bridges its
"Query FPGA" button to the board's barycentric_axi accelerator over a
plain TCP socket on the board's ethernet link (see hw/uio_bridge.py, and
fpga/point_sampler/README.md section 4 for how the accelerator gets loaded
via xmutil in the first place). uio_bridge.py must already be running on
the board for this to work.

This used to go over the board's serial console (115200 baud -- a
debug-console rate, not a data link -- dominated every round trip with
~3-10ms just to move a handful of bytes across the wire) before that, a
fresh `vivado -mode batch` JTAG script per query (~15-30s each). Both are
gone now that the board has a real ethernet link and the accelerator is
reachable directly as normal Linux MMIO; the HTTP API here is unchanged so
neither dashboard.html nor src/model.cpp's queryFpgaBatch needed to change
at all, only what answers the request.

Run from anywhere:  python hw/dashboard_server.py
Then open:           http://localhost:8765
"""
import http.server
import json
import pathlib
import socket
import threading

PORT = 8765
BRIDGE_HOST = "192.168.100.2"
BRIDGE_PORT = 9765

HW_DIR = pathlib.Path(__file__).resolve().parent
DASHBOARD_HTML = HW_DIR / "dashboard.html"

bridge_lock = threading.Lock()
_sock: socket.socket | None = None
_sock_file = None


def get_bridge():
    global _sock, _sock_file
    if _sock is None:
        _sock = socket.create_connection((BRIDGE_HOST, BRIDGE_PORT), timeout=5)
        _sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        _sock_file = _sock.makefile("rwb")
    return _sock, _sock_file


def query_bridge(values: list) -> tuple:
    """Send one "v0x v0y v0z v1x v1y v1z v2x v2y v2z u v" line to
    uio_bridge.py over TCP and return its (x, y, z) response."""
    line = " ".join(str(v) for v in values) + "\n"
    with bridge_lock:
        _, sock_file = get_bridge()
        sock_file.write(line.encode("ascii"))
        sock_file.flush()
        resp = sock_file.readline().decode("ascii", errors="replace").strip()

    if not resp:
        raise RuntimeError("no response from board -- is uio_bridge.py running?")
    if resp.startswith("ERROR"):
        raise RuntimeError(resp)

    x, y, z = (float(p) for p in resp.split())
    return x, y, z


def run_query(params: dict) -> dict:
    values = [
        params["v0"][0], params["v0"][1], params["v0"][2],
        params["v1"][0], params["v1"][1], params["v1"][2],
        params["v2"][0], params["v2"][1], params["v2"][2],
        params["u"], params["v"],
    ]
    x, y, z = query_bridge(values)
    return {"valid": 1, "outx": x, "outy": y, "outz": z}


def run_batch(lines: list) -> list:
    """`lines` is a list of "v0x v0y v0z v1x v1y v1z v2x v2y v2z u v"
    strings (plain decimal floats); returns a list of (x, y, z) float
    tuples in the same order, one board round-trip per line."""
    results = []
    for idx, line in enumerate(lines):
        values = [float(x) for x in line.split()]
        if len(values) != 11:
            raise ValueError(f"line {idx} has {len(values)} values, expected 11: {line!r}")
        results.append(query_bridge(values))
    return results


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print("[dashboard]", fmt % args)

    def do_GET(self):
        if self.path == "/":
            body = DASHBOARD_HTML.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == "/api/query":
            self._handle_query()
        elif self.path == "/api/batch":
            self._handle_batch()
        else:
            self.send_response(404)
            self.end_headers()

    def _handle_query(self):
        length = int(self.headers.get("Content-Length", 0))
        try:
            params = json.loads(self.rfile.read(length))
            result = run_query(params)
        except Exception as e:  # noqa: BLE001 -- surface any failure to the page
            result = {"error": str(e)}

        body = json.dumps(result).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _handle_batch(self):
        # Plaintext in, plaintext out -- deliberately not JSON, so the C++
        # client doesn't need a JSON library. Request: one line per pending
        # instance, "v0x v0y v0z v1x v1y v1z v2x v2y v2z u v" as plain
        # decimal floats. Response: one line per instance, "x y z".
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length).decode("utf-8")
        lines = [line for line in raw.splitlines() if line.strip()]

        status = 200
        try:
            results = run_batch(lines)
            body_text = "\n".join(f"{x} {y} {z}" for x, y, z in results) + "\n"
        except Exception as e:  # noqa: BLE001 -- surface any failure to the client
            status = 500
            body_text = f"ERROR {e}\n"

        body = body_text.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    server = http.server.ThreadingHTTPServer(("localhost", PORT), Handler)
    print(f"Dashboard running at http://localhost:{PORT}")
    print(f"Using TCP bridge: {BRIDGE_HOST}:{BRIDGE_PORT} (uio_bridge.py must be running on the board)")
    server.serve_forever()


if __name__ == "__main__":
    main()
