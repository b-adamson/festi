"""Golden-model vector generator for the barycentric interpolation core.

Mirrors the point-on-triangle formula from festi's addRndInstance()
(src/model.cpp, near the end of the function):

    instanceTransform.translation += (1.0f - u - v) * v0 + u * v1 + v * v2;

Produces:
  vectors/vectors.txt  - DUT stimulus, Q16.16 fixed-point integers
  vectors/golden.txt   - double-precision reference output, one "x y z" per line

Run from the point_sampler/ directory: `python scripts/gen_vectors.py`
"""
import random
import pathlib

FRAC_BITS = 16
SCALE = 1 << FRAC_BITS
COORD_RANGE = 500.0  # keeps values well inside signed Q16.16 range (~+-32767.99998)

VECTORS_DIR = pathlib.Path(__file__).resolve().parent.parent / "vectors"
NUM_VECTORS = 200
SEED = 12345


def to_fixed(x: float) -> int:
    return int(round(x * SCALE))


def random_vertex(rng: random.Random):
    return tuple(rng.uniform(-COORD_RANGE, COORD_RANGE) for _ in range(3))


def barycentric_point(v0, v1, v2, u, v):
    w = 1.0 - u - v
    return tuple(w * v0[i] + u * v1[i] + v * v2[i] for i in range(3))


def main():
    VECTORS_DIR.mkdir(exist_ok=True)
    rng = random.Random(SEED)

    stimulus_lines = []
    golden_lines = []

    for i in range(NUM_VECTORS):
        v0 = random_vertex(rng)
        v1 = random_vertex(rng)
        v2 = random_vertex(rng)

        # Mostly physically-meaningful samples (u+v <= 1, inside the
        # triangle), plus a handful of out-of-triangle / edge cases since
        # the hardware doesn't know or care about that constraint -- it's
        # just an affine combination.
        if i % 10 == 0:
            u = rng.uniform(-0.5, 1.5)
            v = rng.uniform(-0.5, 1.5)
        else:
            u = rng.uniform(0.0, 1.0)
            v = rng.uniform(0.0, 1.0 - u)

        fixed_vals = [to_fixed(c) for vert in (v0, v1, v2) for c in vert]
        fixed_vals += [to_fixed(u), to_fixed(v)]
        stimulus_lines.append(" ".join(str(val) for val in fixed_vals))

        out = barycentric_point(v0, v1, v2, u, v)
        golden_lines.append(f"{out[0]!r} {out[1]!r} {out[2]!r}")

    (VECTORS_DIR / "vectors.txt").write_text(
        f"{NUM_VECTORS}\n" + "\n".join(stimulus_lines) + "\n"
    )
    (VECTORS_DIR / "golden.txt").write_text("\n".join(golden_lines) + "\n")

    print(f"Wrote {NUM_VECTORS} vectors to {VECTORS_DIR}")


if __name__ == "__main__":
    main()
