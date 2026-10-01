#!/usr/bin/env bash
set -euo pipefail
app=com.reddraggone9.tandemlog
fixture="$RUNNER_TEMP/tandemlog-flatpak-qa"
report=dist/linux-install-smoke.json
profile="$HOME/.local/share/$app"
folder="$profile/data"
bundle=dist/tandemlog-linux-x64.flatpak
# Native default profile/data path is synthetic on this disposable hosted runner.
# The launcher and production package grants themselves must permit this flow.
install_app() { flatpak install --user --noninteractive "$bundle"; }
launch() {
  python3 packaging/smoke.py --workspace "$fixture" --report "$report" --profile "$profile" --folder "$folder" --default-profile --phase "$1" "${@:2}" -- \
    flatpak run "$app"
}
install_app
flatpak info --user --show-metadata "$app" > "$RUNNER_TEMP/tandemlog-flatpak-metadata.txt"
python3 - "$RUNNER_TEMP/tandemlog-flatpak-metadata.txt" <<'PY'
import configparser, sys
metadata = configparser.ConfigParser()
metadata.read(sys.argv[1])
context = metadata['Context']
assert set(context.get('filesystems', '').rstrip(';').split(';')) == {'~/.local/share/com.reddraggone9.tandemlog:create', '~/.local/share/tandemlog'}
assert 'network' not in context.get('shared', '')
assert 'session-bus' not in context.get('sockets', '')
PY
launch after-install --seed
candidate_commit=$(flatpak info --user --show-commit "$app")
candidate_location=$(flatpak info --user --show-location "$app")
python3 - "$candidate_location/files" "$RUNNER_TEMP/tandemlog-flatpak-payload.json" <<'PYHASH'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
json.dump({str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
           for p in root.rglob('*') if p.is_file()}, open(sys.argv[2], 'w'))
PYHASH
# Flatpak rejects reinstalling an already-deployed identical bundle checksum.
# Exercise a real commit replacement through a private packaging-only baseline,
# then update back to the exact unchanged public candidate. All recorded launches
# remain the public candidate; this does not claim old-app-version compatibility.
flatpak install --user --noninteractive "$RUNNER_TEMP/tandemlog-flatpak-baseline.flatpak"
baseline_commit=$(flatpak info --user --show-commit "$app")
test "$baseline_commit" != "$candidate_commit"
flatpak info --user --show-metadata "$app" > "$RUNNER_TEMP/tandemlog-flatpak-baseline-metadata.txt"
cmp "$RUNNER_TEMP/tandemlog-flatpak-metadata.txt" "$RUNNER_TEMP/tandemlog-flatpak-baseline-metadata.txt"
baseline_location=$(flatpak info --user --show-location "$app")
python3 - "$baseline_location/files" "$RUNNER_TEMP/tandemlog-flatpak-payload.json" <<'PYHASH'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
actual = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
          for p in root.rglob('*') if p.is_file()}
assert actual == json.load(open(sys.argv[2])), 'Baseline changed application payload'
PYHASH
(cd dist && sha256sum --check linux-SHA256SUMS.txt)
install_app
test "$(flatpak info --user --show-commit "$app")" = "$candidate_commit"
launch after-upgrade
python3 - "$report" "$candidate_commit" "$baseline_commit" <<'PYREPORT'
import json, sys
report = json.load(open(sys.argv[1]))
report['upgrade'] = {'candidate_commit': sys.argv[2], 'baseline_commit': sys.argv[3],
                     'baseline_payload_equal': True, 'baseline_permissions_equal': True,
                     'final_candidate_restored': True}
json.dump(report, open(sys.argv[1], 'w'), indent=2)
PYREPORT
flatpak uninstall --user --noninteractive "$app"
python3 packaging/smoke.py --workspace "$fixture" --report "$report" --profile "$profile" --folder "$folder" --default-profile --phase after-uninstall
install_app
test "$(flatpak info --user --show-commit "$app")" = "$candidate_commit"
(cd dist && sha256sum --check linux-SHA256SUMS.txt)
launch after-reinstall
