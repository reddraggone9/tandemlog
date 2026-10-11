"""Fail packaging before handoff when catalog identity or isolation is missing."""
import argparse
import configparser
import gzip
import json
from pathlib import Path
import xml.etree.ElementTree as ET

APP = 'com.reddraggone9.tandemlog'


def verify_catalog(root):
    root = Path(root)
    catalog_dir = root / 'share/app-info/xmls'
    catalog = catalog_dir / f'{APP}.xml.gz'
    if not catalog.is_file():
        raise ValueError('Missing exact app-ID catalog used by Flatpak bundle export')
    matches = []
    for file in [catalog]:
        raw = gzip.decompress(file.read_bytes()) if file.suffix == '.gz' else file.read_bytes()
        data = ET.fromstring(raw)
        matches.extend(c for c in data.findall('component') if c.findtext('id') == APP)
    if len(matches) != 1 or matches[0].findtext('name') != 'Tandemlog':
        raise ValueError('Composed catalog must contain exactly one named Tandemlog component')
    component = matches[0]
    icons = []
    for icon in component.findall("icon[@type='cached']"):
        name = icon.text or ''
        if Path(name).name != name or not name.startswith(APP + '.'):
            raise ValueError('Unexpected cached app icon identity')
        width, height = icon.get('width'), icon.get('height')
        if not width or width != height:
            raise ValueError('Cached app icon must declare square dimensions')
        scale = icon.get('scale', '1')
        if not scale.isdigit() or int(scale) < 1:
            raise ValueError('Invalid cached app icon scale')
        size = f'{width}x{height}' + (f'@{scale}' if scale != '1' else '')
        path = root / 'share/app-info/icons/flatpak' / size / name
        if not path.is_file() or not path.stat().st_size:
            raise ValueError('Composed catalog references a missing app icon')
        icons.append(path.relative_to(root).as_posix())
    required_icons = {f'share/app-info/icons/flatpak/{size}/{APP}.png'
                      for size in ['64x64', '128x128']}
    if not required_icons.issubset(icons):
        raise ValueError('Catalog must include the 64px and 128px icons embedded by Flatpak')
    return {'id': APP, 'name': component.findtext('name'), 'icons': icons,
            'catalogs': [p.relative_to(root).as_posix() for p in sorted(catalog_dir.glob('*.xml*'))]}


def verify_permissions(metadata):
    context = metadata['Context']
    if context.get('filesystems', '').strip(';'):
        raise ValueError('Package must not grant static host filesystem access')
    if 'network' in context.get('shared', '').split(';'):
        raise ValueError('Package must not grant network access')
    if 'session-bus' in context.get('sockets', '').split(';'):
        raise ValueError('Package must not grant unfiltered session bus access')


def verify_profile(profile):
    profile = Path(profile)
    if not (profile / 'local.sqlite').is_file():
        raise ValueError('Installed app did not create its private local database')
    databases = sorted(str(p.relative_to(profile)) for p in profile.rglob('*.sqlite'))
    if databases != ['local.sqlite']:
        raise ValueError(f'Expected one permanent app database, found {databases}')
    # The smoke gate force-stops its exact sandbox instance. A recovery WAL is
    # permitted after process death; never delete or require its absence here.
    return {'profile': str(profile), 'permanent_databases': databases}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['catalog', 'permissions', 'profile'])
    parser.add_argument('path')
    args = parser.parse_args()
    if args.mode == 'catalog':
        result = verify_catalog(args.path)
    elif args.mode == 'profile':
        result = verify_profile(args.path)
    else:
        metadata = configparser.ConfigParser()
        metadata.read(args.path)
        verify_permissions(metadata)
        result = {'static_host_filesystem_access': False, 'network_access': False}
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
