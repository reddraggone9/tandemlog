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
# Import the exact same candidate again to rehearse replacement, without
# rebuilding or disguising it as an old-version compatibility claim.
flatpak install --user --noninteractive --reinstall "$bundle"
launch after-upgrade
flatpak uninstall --user --noninteractive "$app"
python3 packaging/smoke.py --workspace "$fixture" --report "$report" --profile "$profile" --folder "$folder" --default-profile --phase after-uninstall
install_app
launch after-reinstall
