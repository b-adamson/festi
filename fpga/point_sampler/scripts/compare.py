"""Compares xsim's DUT output against the Python golden model.

Reads vectors/results.txt (Q16.16 fixed-point ints from the SV testbench)
and vectors/golden.txt (double-precision floats from gen_vectors.py), and
checks each triple is within tolerance. Tolerance is set loosely enough to
absorb Q16.16 quantization/truncation noise but tight enough that a real
RTL bug (wrong sign, dropped term, wrong shift amount) fails loudly.
"""
import pathlib
import sys

FRAC_BITS = 16
SCALE = 1 << FRAC_BITS
TOLERANCE = 0.05  # see fpga/point_sampler/scripts/compare.py docstring

VECTORS_DIR = pathlib.Path(__file__).resolve().parent.parent / "vectors"


def to_float(fixed_int: int) -> float:
    return fixed_int / SCALE


def main():
    results_path = VECTORS_DIR / "results.txt"
    golden_path = VECTORS_DIR / "golden.txt"

    if not results_path.exists():
        print(f"FAIL: {results_path} not found -- did the sim run?")
        sys.exit(1)

    results_lines = results_path.read_text().strip().splitlines()
    golden_lines = golden_path.read_text().strip().splitlines()

    if len(results_lines) != len(golden_lines):
        print(
            f"FAIL: result count mismatch: "
            f"{len(results_lines)} DUT results vs {len(golden_lines)} golden vectors"
        )
        sys.exit(1)

    max_err = 0.0
    failures = []

    for i, (res_line, gold_line) in enumerate(zip(results_lines, golden_lines)):
        rx, ry, rz = (int(v) for v in res_line.split())
        gx, gy, gz = (float(v) for v in gold_line.split())

        dut = (to_float(rx), to_float(ry), to_float(rz))
        gold = (gx, gy, gz)

        err = max(abs(d - g) for d, g in zip(dut, gold))
        max_err = max(max_err, err)

        if err > TOLERANCE:
            failures.append((i, dut, gold, err))

    print(f"Compared {len(results_lines)} vectors, max abs error = {max_err:.6f}")

    if failures:
        print(f"FAIL: {len(failures)} vector(s) exceeded tolerance ({TOLERANCE}):")
        for i, dut, gold, err in failures[:10]:
            print(f"  [{i}] dut={dut} golden={gold} err={err:.6f}")
        sys.exit(1)

    print(f"PASS: all vectors within tolerance ({TOLERANCE})")


if __name__ == "__main__":
    main()
