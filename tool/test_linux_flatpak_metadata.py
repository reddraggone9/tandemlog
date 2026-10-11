"""Package identity, composed catalog and minimum permissions are release gates."""
import configparser
import gzip
import re
import importlib.util
from pathlib import Path, PureWindowsPath
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
APP = 'com.reddraggone9.tandemlog'
SPEC = importlib.util.spec_from_file_location('flatpak_verification', ROOT / 'packaging/linux/verify_flatpak.py')


class FlatpakSourceContracts(unittest.TestCase):
    def test_matching_complete_metainfo(self):
        data = ET.parse(ROOT / f'packaging/linux/{APP}.metainfo.xml').getroot()
        self.assertEqual(data.attrib['type'], 'desktop-application')
        self.assertEqual(data.findtext('id'), APP)
        self.assertEqual(data.findtext('name'), 'Tandemlog')
        self.assertEqual(data.findtext('metadata_license'), 'CC0-1.0')
        self.assertEqual(data.findtext('project_license'), 'CC0-1.0')
        self.assertEqual(data.findtext("launchable[@type='desktop-id']"), APP + '.desktop')
        self.assertTrue(data.findtext('summary'))
        self.assertTrue(data.findtext('description/p'))
        self.assertTrue(data.findtext("url[@type='homepage']"))

    def test_metainfo_release_matches_actual_candidate_version(self):
        data = ET.parse(ROOT / f'packaging/linux/{APP}.metainfo.xml').getroot()
        version = re.findall(r'^version: ([^+\s]+)\+', (ROOT / 'pubspec.yaml').read_text(), re.M)
        self.assertEqual(len(version), 1)
        self.assertEqual(data.find('releases/release').get('version'), version[0])

    def test_catalog_composed_before_export_and_bundle(self):
        script = (ROOT / 'packaging/linux/build-flatpak.sh').read_text()
        self.assertLess(script.index('appstreamcli validate'), script.index('appstreamcli compose'))
        self.assertLess(script.index('appstreamcli compose'), script.index('flatpak build-export'))
        self.assertLess(script.index('verify_flatpak.py catalog'), script.index('flatpak build-export'))
        self.assertNotIn('--filesystem=', script)
        self.assertNotIn('--share=network', script)
        self.assertNotIn('--socket=session-bus', script)


class InstalledCatalogContracts(unittest.TestCase):
    def setUp(self):
        self.verifier = importlib.util.module_from_spec(SPEC)
        SPEC.loader.exec_module(self.verifier)
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.xml = self.root / f'share/app-info/xmls/{APP}.xml.gz'
        self.xml.parent.mkdir(parents=True)
        for size in ['64x64', '128x128']:
            icon = self.root / f'share/app-info/icons/flatpak/{size}/{APP}.png'
            icon.parent.mkdir(parents=True)
            icon.write_bytes(b'synthetic icon')
        self.write_catalog()

    def write_catalog(self, name='Tandemlog', app=APP, icon=APP + '.png'):
        self.xml.write_bytes(gzip.compress(f'<components><component type="desktop-application"><id>{app}</id><name>{name}</name><icon type="cached" width="64" height="64">{icon}</icon><icon type="cached" width="128" height="128">{icon}</icon></component></components>'.encode()))

    def test_actual_composed_name_and_icon_are_required(self):
        self.verifier.verify_catalog(self.root)
        for name, app, icon in [('Wrong', APP, APP + '.png'),
                                ('Tandemlog', 'wrong.id', APP + '.png'),
                                ('Tandemlog', APP, 'missing.png')]:
            self.write_catalog(name, app, icon)
            with self.assertRaises(ValueError):
                self.verifier.verify_catalog(self.root)

    def test_catalog_relative_paths_are_portable_on_windows(self):
        relative_to = Path.relative_to
        with patch.object(Path, 'relative_to', lambda path, *parents:
                          PureWindowsPath(relative_to(path, *parents).as_posix())):
            catalog = self.verifier.verify_catalog(self.root)
        self.assertEqual(catalog['icons'], [
            f'share/app-info/icons/flatpak/{size}/{APP}.png'
            for size in ['64x64', '128x128']])
        self.assertEqual(catalog['catalogs'], [f'share/app-info/xmls/{APP}.xml.gz'])

    def test_wrong_catalog_filename_cannot_supply_bundle_metadata(self):
        self.xml.rename(self.xml.with_name('wrong.xml.gz'))
        with self.assertRaises(ValueError):
            self.verifier.verify_catalog(self.root)

    def test_missing_catalog_is_not_replaced_by_metainfo(self):
        self.xml.unlink()
        with self.assertRaises(ValueError):
            self.verifier.verify_catalog(self.root)

    def test_one_permanent_database_after_process_stop_allows_recovery_wal(self):
        profile = self.root / 'private-profile'
        profile.mkdir()
        with self.assertRaises(ValueError):
            self.verifier.verify_profile(profile)
        (profile / 'local.sqlite').write_bytes(b'synthetic stopped DB')
        (profile / 'local.sqlite-wal').write_bytes(b'protected recovery WAL')
        self.assertEqual(self.verifier.verify_profile(profile)['permanent_databases'], ['local.sqlite'])
        (profile / 'another.sqlite').write_bytes(b'unexpected DB')
        with self.assertRaises(ValueError):
            self.verifier.verify_profile(profile)
        self.assertEqual((profile / 'local.sqlite-wal').read_bytes(), b'protected recovery WAL')

    def test_scaled_icon_must_exist_at_its_declared_size(self):
        self.xml.write_bytes(gzip.compress(f'<components><component><id>{APP}</id><name>Tandemlog</name><icon type="cached" width="64" height="64">{APP}.png</icon><icon type="cached" width="128" height="128">{APP}.png</icon><icon type="cached" width="64" height="64" scale="2">{APP}.png</icon></component></components>'.encode()))
        with self.assertRaises(ValueError):
            self.verifier.verify_catalog(self.root)
        icon = self.root / f'share/app-info/icons/flatpak/64x64@2/{APP}.png'
        icon.parent.mkdir(parents=True)
        icon.write_bytes(b'scaled synthetic icon')
        self.verifier.verify_catalog(self.root)

    def test_no_static_host_filesystem_or_network_grant(self):
        metadata = configparser.ConfigParser()
        metadata.read_string('[Context]\nshared=ipc;\nsockets=wayland;fallback-x11;\ndevices=dri;\n')
        self.verifier.verify_permissions(metadata)
        for key, value in [('filesystems', 'home;'), ('filesystems', '~/.local/share/tandemlog;'),
                           ('shared', 'ipc;network;'), ('sockets', 'x11;session-bus;')]:
            changed = configparser.ConfigParser()
            changed.read_dict(metadata)
            changed['Context'][key] = value
            with self.assertRaises(ValueError):
                self.verifier.verify_permissions(changed)


if __name__ == '__main__':
    unittest.main()
