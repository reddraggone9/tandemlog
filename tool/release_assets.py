"""Stage versioned public installers after the full candidate integrity gates."""
from pathlib import Path
import re
import shutil
from android_release import version


def public_asset_names(release_version):
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[a-z]+\.\d+)?', release_version):
        raise ValueError('Invalid release version for installer filenames')
    return {
        'tandemlog-android.apk': f'tandemlog-{release_version}-android.apk',
        'tandemlog-windows-x64-unsigned-setup.exe': f'tandemlog-{release_version}-windows-x64-setup.exe',
        'tandemlog-linux-x64.flatpak': f'tandemlog-{release_version}-linux-x64.flatpak',
    }


def stage_public_assets(release_version, source, destination):
    names = public_asset_names(release_version)
    if any(not (source / name).is_file() for name in names):
        raise ValueError('Missing verified installer')
    destination.mkdir()  # A fresh directory prevents stale/unexpected uploads.
    for original, public in names.items():
        shutil.copyfile(source / original, destination / public)
    return names


if __name__ == '__main__':
    # publish_gate.py has already matched this source version to the tag/APK.
    release_version, _ = version(Path('pubspec.yaml').read_text())
    for name in stage_public_assets(release_version, Path('dist'), Path('public-assets')).values():
        print(name)
