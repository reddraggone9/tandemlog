"""Bounded synthetic artifact and desktop-handler fixtures for dependency audits."""

import hashlib
import json
import os
from pathlib import Path
import sys


PAYLOADS = {
    "dependency smoke café 東京.txt": "Tandemlog dependency audit — synthetic only\n".encode(),
    "provenance.json": b'{"purpose":"non-publishing cross-run smoke","schema":1}\n',
}


def main():
    command, location = sys.argv[1:]
    root = Path(location).resolve()
    root.mkdir(parents=True, exist_ok=True)
    if command == "seed":
        for name, data in PAYLOADS.items():
            (root / name).write_bytes(data)
    elif command == "verify":
        assert {p.name for p in root.iterdir()} == set(PAYLOADS)
        for name, data in PAYLOADS.items():
            actual = (root / name).read_bytes()
            assert actual == data, name
            print(json.dumps({"filename": name, "bytes": len(actual),
                              "sha256": hashlib.sha256(actual).hexdigest()},
                             ensure_ascii=False))
    elif command == "desktop":
        applications = root / "data/applications"
        applications.mkdir(parents=True)
        (root / "config").mkdir()
        capture = root / "capture.py"
        capture.write_text(
            "import json, pathlib, sys\n"
            f"pathlib.Path({str(root / 'launch.json')!r}).write_text(json.dumps(sys.argv[1:]))\n"
        )
        (applications / "tandemlog-folder-smoke.desktop").write_text(
            "[Desktop Entry]\nType=Application\nName=Synthetic folder handler\n"
            f"Exec=/usr/bin/python3 {capture} %u\n"
            "MimeType=inode/directory;x-scheme-handler/file;\nTerminal=false\n"
        )
        (root / "config/mimeapps.list").write_text(
            "[Default Applications]\n"
            "inode/directory=tandemlog-folder-smoke.desktop;\n"
            "x-scheme-handler/file=tandemlog-folder-smoke.desktop;\n"
        )
        # Isolate the missing-handler case from every installed desktop app.
        for directory in ["missing/data", "missing/config", "missing/system"]:
            (root / directory).mkdir(parents=True)
        os.symlink("/usr/share/mime", root / "missing/system/mime")
    else:
        raise ValueError(command)


if __name__ == "__main__":
    main()
