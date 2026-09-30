"""Exercise the compiled rehearsal CLI on private disposable synthetic data."""
import pathlib
import subprocess
import sys
import tempfile


def main():
    binary = str(pathlib.Path(sys.argv[1]).resolve(strict=True))
    source_bytes = (
        "- [ ] Example #sample #start-time-0930 🔁 every month when done "
        "🛫 2026-10-01 📅 2026-10-02\r\n"
        "- [x] Finished example ✅ 2026-09-30\n"
    ).encode("utf-8")
    with tempfile.TemporaryDirectory(prefix="tandemlog-migration-smoke-") as root:
        root = pathlib.Path(root)
        source = root / "source.md"
        staging = root / "staging"
        reconstructed = root / "reconstructed.md"
        source.write_bytes(source_bytes)
        subprocess.run([binary, "dry-run", str(source), str(staging),
                        "Example user"], check=True, capture_output=True)
        subprocess.run([binary, "export", str(staging), str(reconstructed)],
                       check=True, capture_output=True)
        if source.read_bytes() != source_bytes or reconstructed.read_bytes() != source_bytes:
            raise RuntimeError("Compiled migration round trip changed source bytes")
    print("Compiled migration CLI preserved synthetic source and round-tripped exact bytes.")


if __name__ == "__main__":
    main()
