"""Generate deterministic row-major matrix vectors using the golden model."""

from pathlib import Path

from golden_model import matmul_4x4


def deterministic_cases():
    """Return ordered (name, A, B) cases with signed INT8 operands."""
    identity = [[int(i == j) for j in range(4)] for i in range(4)]
    sequential = [[4 * i + j + 1 for j in range(4)] for i in range(4)]
    signed_A = [
        [-3, 0, 5, -2],
        [7, -4, 1, 0],
        [-128, 6, -7, 3],
        [2, -1, 0, 127],
    ]
    signed_B = [
        [4, -2, 0, 7],
        [-5, 3, 6, 0],
        [1, 0, -4, 2],
        [0, 8, -3, -6],
    ]
    zeros = [[0 for _ in range(4)] for _ in range(4)]
    boundary_A = [
        [-128, -128, -128, -128],
        [127, 127, 127, 127],
        [-128, 127, -128, 127],
        [0, -1, 1, 127],
    ]
    boundary_B = [
        [-128, 127, -128, 0],
        [-128, 127, 127, -1],
        [-128, 127, -128, 1],
        [-128, 127, 127, 127],
    ]
    return [
        ("sequential times identity", sequential, identity),
        ("signed golden-model case", signed_A, signed_B),
        ("all zeros", zeros, zeros),
        ("identity times signed matrix", identity, signed_B),
        ("signed INT8 boundaries", boundary_A, boundary_B),
    ]


def flatten(matrix):
    return [value for row in matrix for value in row]


def read_vectors(path, width, count):
    """Validate actual file contents, including testcase and integer counts."""
    lines = path.read_text(encoding="utf-8").splitlines()
    if len(lines) != count:
        raise ValueError(f"{path}: expected {count} lines, got {len(lines)}")
    rows = []
    for number, line in enumerate(lines, start=1):
        tokens = line.split()
        if len(tokens) != width:
            raise ValueError(
                f"{path} line {number}: expected {width} integers, got {len(tokens)}"
            )
        rows.append([int(token, 10) for token in tokens])
    return rows


def main():
    # Resolve against this script, so invocation works from any directory.
    vectors_dir = Path(__file__).resolve().parent.parent / "vectors"
    vectors_dir.mkdir(parents=True, exist_ok=True)
    input_path = vectors_dir / "input_vectors.txt"
    expected_path = vectors_dir / "expected_vectors.txt"
    cases = deterministic_cases()
    inputs = []
    expected = []
    for _name, A, B in cases:
        C = matmul_4x4(A, B)
        inputs.append(flatten(A) + flatten(B))
        expected.append(flatten(C))

    # Overwrite both files, with no headers or blank lines.
    for path, rows in ((input_path, inputs), (expected_path, expected)):
        path.write_text(
            "".join(" ".join(map(str, row)) + "\n" for row in rows),
            encoding="utf-8",
        )

    saved_inputs = read_vectors(input_path, 32, len(cases))
    saved_expected = read_vectors(expected_path, 16, len(cases))
    if saved_inputs != inputs or saved_expected != expected:
        raise AssertionError("Saved vectors differ from generated testcase order")
    for number, (values, result) in enumerate(
        zip(saved_inputs, saved_expected), start=1
    ):
        A = [values[offset:offset + 4] for offset in range(0, 16, 4)]
        B = [values[offset:offset + 4] for offset in range(16, 32, 4)]
        if flatten(matmul_4x4(A, B)) != result:
            raise AssertionError(f"Golden result mismatch on line {number}")

    print(f"Generated {len(cases)} deterministic testcases.")
    print(f"Inputs:   {input_path}")
    print(f"Expected: {expected_path}")
    print("PASS: vector widths, integer contents, order, and golden results verified.")


if __name__ == "__main__":
    main()
