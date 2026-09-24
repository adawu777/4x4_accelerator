"""Reproducible v3 vectors; numerical oracle is the unchanged golden model."""
from pathlib import Path
import random

from generate_vectors import deterministic_cases, flatten
from golden_model import matmul_4x4


def main():
    cases = deterministic_cases()
    for av, bv in ((-128, -128), (-128, 127), (127, 127), (127, -128)):
        cases.append((f"extremes {av}/{bv}", [[av] * 4 for _ in range(4)],
                      [[bv] * 4 for _ in range(4)]))
    rng = random.Random(0x4A43)
    for i in range(64):
        cases.append((f"random {i}",
                      [[rng.randrange(-128, 128) for _ in range(4)] for _ in range(4)],
                      [[rng.randrange(-128, 128) for _ in range(4)] for _ in range(4)]))
    rows = [flatten(a) + flatten(b) + flatten(matmul_4x4(a, b))
            for _, a, b in cases]
    path = Path(__file__).resolve().parents[1] / "vectors/v3_vectors.txt"
    path.write_text(str(len(rows)) + "\n" + "".join(
        " ".join(map(str, row)) + "\n" for row in rows), encoding="utf-8")
    saved = path.read_text().splitlines()
    assert int(saved[0]) == len(cases)
    assert [[int(x) for x in line.split()] for line in saved[1:]] == rows
    print(f"PASS: generated and read back {len(rows)} v3 Python golden vectors")


if __name__ == "__main__":
    main()
