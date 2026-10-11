#!/usr/bin/env bash
set -euo pipefail
app=com.reddraggone9.tandemlog
fixture="$RUNNER_TEMP/tandemlog-flatpak-qa"
report=dist/linux-install-smoke.json
profile="$HOME/.var/app/$app/data/$app"
folder="$profile/shared-data"
bundle=dist/tandemlog-linux-x64.flatpak
# Sandbox-private default profile/shared-data is synthetic on this disposable runner.
# No profile override or extra filesystem grant may satisfy this gate.
install_app() { flatpak install --user --noninteractive "$bundle"; }
launch() {
  python3 packaging/smoke.py --workspace "$fixture" --report "$report" --profile "$profile" --folder "$folder" --default-profile --phase "$1" "${@:2}" -- \
    flatpak run "$app"
}
install_app
flatpak info --user --show-metadata "$app" > "$RUNNER_TEMP/tandemlog-flatpak-metadata.txt"
python3 packaging/linux/verify_flatpak.py permissions "$RUNNER_TEMP/tandemlog-flatpak-metadata.txt"
# Query the actual installed sandbox instead of assuming Flatpak's host path.
sandbox_data=$(flatpak run --command=sh "$app" -c 'test -z "${TANDEMLOG_PROFILE:-}"; printf "%s" "$XDG_DATA_HOME"')
test "$sandbox_data/$app" = "$profile"
launch after-install --seed
candidate_commit=$(flatpak info --user --show-commit "$app")
candidate_location=$(flatpak info --user --show-location "$app")
python3 packaging/linux/verify_flatpak.py catalog "$candidate_location/files" > "$RUNNER_TEMP/tandemlog-flatpak-catalog.json"
python3 packaging/linux/verify_flatpak.py profile "$profile" > "$RUNNER_TEMP/tandemlog-flatpak-profile.json"
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

python3 packaging/linux/verify_flatpak.py profile "$profile" > "$RUNNER_TEMP/tandemlog-flatpak-profile.json"
python3 - "$report" "$RUNNER_TEMP/tandemlog-flatpak-catalog.json" "$RUNNER_TEMP/tandemlog-flatpak-profile.json" <<'PYREPORT'
import json, sys
report = json.load(open(sys.argv[1]))
report['appstream'] = json.load(open(sys.argv[2]))
report['sandbox_profile'] = json.load(open(sys.argv[3]))
report['sandbox_profile']['default_without_override'] = True
report['permissions'] = {'static_host_filesystem_access': False, 'network_access': False}
json.dump(report, open(sys.argv[1], 'w'), indent=2)
PYREPORT
