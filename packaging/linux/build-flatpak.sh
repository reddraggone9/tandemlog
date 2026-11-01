#!/usr/bin/env bash
set -euo pipefail
app=com.reddraggone9.tandemlog
runtime_version=50
build="$RUNNER_TEMP/tandemlog-flatpak-build"
repo="$RUNNER_TEMP/tandemlog-flatpak-repo"
qa_repo="$RUNNER_TEMP/tandemlog-flatpak-qa-repo"
# Explicit opt-in while the new signing identity/channel still awaits provisioning.
# Never create credentials in a build or silently advertise an unsigned origin.
sign_options=()
bundle_options=()
if [[ -n "${TANDEMLOG_FLATPAK_REPO_URL:-}${TANDEMLOG_FLATPAK_SIGNING_KEY:-}${TANDEMLOG_FLATPAK_GPG_HOME:-}${TANDEMLOG_FLATPAK_PUBLIC_KEY:-}" ]]; then
  : "${TANDEMLOG_FLATPAK_REPO_URL:?channel URL required}"
  : "${TANDEMLOG_FLATPAK_SIGNING_KEY:?existing approved signing key required}"
  : "${TANDEMLOG_FLATPAK_GPG_HOME:?private signing home required}"
  : "${TANDEMLOG_FLATPAK_PUBLIC_KEY:?reviewed public key required}"
  [[ "$TANDEMLOG_FLATPAK_REPO_URL" == 'https://reddraggone9.github.io/tandemlog/flatpak' ]]
  [[ "$TANDEMLOG_FLATPAK_SIGNING_KEY" =~ ^[0-9A-Fa-f]{40}$ ]]
  test -s "$TANDEMLOG_FLATPAK_PUBLIC_KEY"
  sign_options=(--gpg-sign="$TANDEMLOG_FLATPAK_SIGNING_KEY" --gpg-homedir="$TANDEMLOG_FLATPAK_GPG_HOME")
  bundle_options=(--repo-url="$TANDEMLOG_FLATPAK_REPO_URL" --gpg-keys="$TANDEMLOG_FLATPAK_PUBLIC_KEY")
fi
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user --noninteractive flathub "org.gnome.Platform//$runtime_version" "org.gnome.Sdk//$runtime_version"
flatpak build-init "$build" "$app" org.gnome.Sdk org.gnome.Platform "$runtime_version"
mkdir -p "$build/files/tandemlog" "$build/files/tandemlog-cli" "$build/files/bin" "$build/files/share/metainfo" "$build/files/share/applications" "$build/files/share/icons/hicolor/scalable/apps"
cp -a build/linux/x64/release/bundle/. "$build/files/tandemlog/"
install -m 755 packaging/linux/tandemlog "$build/files/bin/tandemlog"
# Headless agent CLI: second command of the same package, same version.
cp -a build/agent-cli/. "$build/files/tandemlog-cli/"
install -m 755 packaging/linux/tandemlog-cli "$build/files/bin/tandemlog-cli"
install -m 644 "packaging/linux/$app.desktop" "$build/files/share/applications/"
install -m 644 "packaging/linux/$app.svg" "$build/files/share/icons/hicolor/scalable/apps/"
install -m 644 "packaging/linux/$app.metainfo.xml" "$build/files/share/metainfo/"
appstreamcli --version
cat "$RUNNER_TEMP/reviewed-appstream/tool-receipt.json"
appstreamcli validate --no-net "${build}/files/share/metainfo/$app.metainfo.xml"
# Hand-built bundles need the same composed catalog as flatpak-builder.
appstreamcli compose --no-net --prefix=/ --origin="$app" \
  --result-root="$build/files" --data-dir="$build/files/share/app-info/xmls" \
  --icons-dir="$build/files/share/app-info/icons/flatpak" --components="$app" "$build/files"
python3 packaging/linux/verify_flatpak.py catalog "$build/files"
flatpak build-finish "$build" --command=tandemlog --socket=wayland --socket=fallback-x11 --share=ipc --device=dri
flatpak build-export "${sign_options[@]}" "$repo" "$build" master
flatpak build-update-repo "${sign_options[@]}" "$repo"
flatpak build-bundle "${bundle_options[@]}" --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
  "$repo" dist/tandemlog-linux-x64.flatpak "$app" master
(cd dist && sha256sum tandemlog-linux-x64.flatpak > linux-SHA256SUMS.txt)

# Private QA package: identical files/permissions, distinct OSTree commit subject.
# It never enters dist or publication and does not recompile/change the app.
flatpak build-export --subject='Private synthetic packaging replacement baseline' "$qa_repo" "$build" master
flatpak build-bundle --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
  "$qa_repo" "$RUNNER_TEMP/tandemlog-flatpak-baseline.flatpak" "$app" master
