#!/usr/bin/env bash
set -euo pipefail
app=com.reddraggone9.tandemlog
runtime_version=50
build="$RUNNER_TEMP/tandemlog-flatpak-build"
repo="$RUNNER_TEMP/tandemlog-flatpak-repo"
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user --noninteractive flathub "org.gnome.Platform//$runtime_version" "org.gnome.Sdk//$runtime_version"
flatpak build-init "$build" "$app" org.gnome.Sdk org.gnome.Platform "$runtime_version"
mkdir -p "$build/files/tandemlog" "$build/files/bin" "$build/files/share/applications" "$build/files/share/icons/hicolor/scalable/apps"
cp -a build/linux/x64/release/bundle/. "$build/files/tandemlog/"
install -m 755 packaging/linux/tandemlog "$build/files/bin/tandemlog"
install -m 644 "packaging/linux/$app.desktop" "$build/files/share/applications/"
install -m 644 "packaging/linux/$app.svg" "$build/files/share/icons/hicolor/scalable/apps/"
flatpak build-finish "$build" --command=tandemlog --socket=wayland --socket=fallback-x11 --share=ipc --device=dri \
  '--filesystem=~/.local/share/com.reddraggone9.tandemlog:create' '--filesystem=~/.local/share/tandemlog'
flatpak build-export "$repo" "$build"
flatpak build-bundle --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
  "$repo" dist/tandemlog-linux-x64.flatpak "$app"
(cd dist && sha256sum tandemlog-linux-x64.flatpak > linux-SHA256SUMS.txt)
