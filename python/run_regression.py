"""Run every existing and v3 testbench; never report a skipped simulation as PASS.

Usage: python3 python/run_regression.py [--simulator auto|verilator|iverilog]
                                       [--build-dir /tmp/accelerator-regression]
Requires Verilator with --binary/--timing, or Icarus plus vvp.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(command, log):
    with log.open("w", encoding="utf-8") as stream:
        stream.write("Command: " + " ".join(map(str, command)) + "\n")
        stream.flush()
        try:
            result = subprocess.run(list(map(str, command)), cwd=ROOT,
                                    stdout=stream, stderr=subprocess.STDOUT,
                                    timeout=300, check=False)
        except (subprocess.TimeoutExpired, OSError) as exc:
            stream.write(f"\nERROR: {exc}\n")
            return False
    return result.returncode == 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", choices=("auto", "verilator", "iverilog"), default="auto")
    parser.add_argument("--build-dir", type=Path)
    args = parser.parse_args()
    build = (args.build_dir or Path(tempfile.mkdtemp(prefix="accelerator-regression-"))).resolve()
    build.mkdir(parents=True, exist_ok=True)
    print(f"Logs and build products: {build}", flush=True)
    # Existing scripts are unchanged; generators verify serialized contents.
    for name in ("golden_model", "generate_vectors", "generate_vectors_v3"):
        if not run([sys.executable, ROOT / "python" / f"{name}.py"], build / f"{name}.log"):
            print(f"FAIL Python {name}")
            return 1
        print(f"PASS Python {name}", flush=True)

    simulator = args.simulator
    if simulator == "auto":
        simulator = next((s for s in ("verilator", "iverilog") if shutil.which(s)), None)
    if not simulator or not shutil.which(simulator) or (simulator == "iverilog" and not shutil.which("vvp")):
        print("NOT RUN: no requested compatible simulator found; RTL remains unverified.")
        return 2
    run([simulator, "--version" if simulator == "verilator" else "-V"], build / "simulator_version.log")
    sources = sorted((ROOT / "rtl").glob("*.sv"))
    failed = []
    benches = sorted((ROOT / "tb").glob("tb_*.sv"))
    for bench in benches:
        name = bench.stem
        target = build / name
        target.mkdir(exist_ok=True)
        executable = target / "simulation"
        if simulator == "verilator":
            command = [simulator, "--binary", "--timing", "-Wno-fatal",
                       "--top-module", name, "--Mdir", target, "-o", executable,
                       *sources, bench]
            simulation = [executable]
        else:
            command = [simulator, "-g2012", "-s", name, "-o", executable, *sources, bench]
            simulation = ["vvp", executable]
        if not run(command, target / "compile.log"):
            print(f"FAIL compile {name}: {target / 'compile.log'}", flush=True)
            failed.append(name)
            continue
        success = run(simulation, target / "simulation.log")
        output = (target / "simulation.log").read_text()
        # These self-checking benches emit PASS and fatal on failure. Keep a
        # textual failure check too for legacy nonfatal accumulated errors.
        success = success and "PASS" in output and "FAIL" not in output
        print(f"{'PASS' if success else 'FAIL'} simulation {name}: {target / 'simulation.log'}", flush=True)
        if not success:
            failed.append(name)
    print(f"Simulated regression: {len(benches)-len(failed)}/{len(benches)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
