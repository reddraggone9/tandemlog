"""Installer subprocess cleanup must target only its captured Flatpak instance."""
import importlib.util
from contextlib import closing
import io
import hashlib
import json
import sqlite3
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    'installer_smoke', Path(__file__).resolve().parents[1]/'packaging'/'smoke.py')
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


class FlatpakCleanup(unittest.TestCase):
    def test_kills_exact_captured_instance_and_waits_for_its_disappearance(self):
        with patch.object(smoke, 'flatpak_instances', side_effect=[{'123', '999'}, {'999'}]), \
                patch.object(smoke.subprocess, 'run') as run:
            self.assertEqual(smoke.stop_flatpak_instance('flatpak', io.BytesIO(b'123')), '123')
        run.assert_called_once_with(['flatpak', 'kill', '123'], check=True,
                                    capture_output=True, text=True)

    def test_exited_instance_does_not_kill_another_instance(self):
        with patch.object(smoke, 'flatpak_instances', return_value={'999'}), \
                patch.object(smoke.subprocess, 'run') as run:
            smoke.stop_flatpak_instance('flatpak', io.BytesIO(b'123'))
        run.assert_not_called()

    def test_never_falls_back_to_application_wide_kill(self):
        with patch.object(smoke.subprocess, 'run') as run:
            with self.assertRaises(RuntimeError):
                smoke.stop_flatpak_instance('flatpak', io.BytesIO(b'com.reddraggone9.tandemlog'))
        run.assert_not_called()

    def test_surviving_instance_blocks_next_phase(self):
        with patch.object(smoke, 'flatpak_instances', return_value={'123'}), \
                patch.object(smoke.subprocess, 'run'), \
                patch.object(smoke.time, 'monotonic', side_effect=[0, 20]):
            with self.assertRaises(RuntimeError):
                smoke.stop_flatpak_instance('flatpak', io.BytesIO(b'123'))


class SharedProfileProjection(unittest.TestCase):
    def test_rebuild_clears_only_derived_namespace_and_preserves_authorities(self):
        with tempfile.TemporaryDirectory() as directory:
            profile, folder = Path(directory), Path(directory)/'synthetic-shared'
            folder.mkdir()
            epoch='22222222-2222-4222-8222-222222222222'
            (folder/'tandemlog-space.json').write_text(json.dumps({'v':5,'epoch':epoch}))
            key = hashlib.sha256(f'{folder}#app5:{epoch}'.encode()).hexdigest()
            prefix = f'tasks_{key}_'
            raw = b'{"writer":"synthetic","folder":"unchanged"}'
            with closing(sqlite3.connect(str(profile/'local.sqlite'))) as db, db:
                db.execute('PRAGMA application_id=1414284354')
                db.execute('CREATE TABLE protected_settings(singleton INTEGER,writer TEXT,raw BLOB)')
                db.execute('INSERT INTO protected_settings VALUES (1,?,?)', ('synthetic',raw))
                for table in ('events','views','positions','text_fields','text_actors','text_outbox','streams'):
                    db.execute(f'CREATE TABLE {prefix}{table}(raw TEXT)')
                    db.execute(f'INSERT INTO {prefix}{table} VALUES (?)', ('{"kind":"task"}',))
                db.execute(f'CREATE TABLE {prefix}metadata(key TEXT PRIMARY KEY,value TEXT)')
                db.execute(f"INSERT INTO {prefix}metadata VALUES ('ui.preference','retained')")
                for table in ('protected_app_workspaces','protected_app_heads','another_workspace_views'):
                    db.execute(f'CREATE TABLE {table}(value TEXT)')
                    db.execute(f'INSERT INTO {table} VALUES (?)',('retained',))
            self.assertEqual(smoke.read_settings_bytes(profile),raw)
            self.assertEqual(smoke.read_projection(profile,folder),[{'kind':'task'}])
            smoke.reset_projection(profile,folder)
            self.assertEqual(smoke.read_projection(profile,folder),[])
            with closing(sqlite3.connect(str(profile/'local.sqlite'))) as db, db:
                for table in (prefix+'streams','protected_app_workspaces','protected_app_heads','another_workspace_views'):
                    self.assertEqual(db.execute(f'SELECT count(*) FROM {table}').fetchone()[0],1)
                self.assertEqual(db.execute(f"SELECT value FROM {prefix}metadata WHERE key='replay_pending'").fetchone()[0],'1')
                self.assertEqual(db.execute(f"SELECT value FROM {prefix}metadata WHERE key='ui.preference'").fetchone()[0],'retained')
            self.assertEqual(smoke.read_settings_bytes(profile),raw)


class DefaultProfileSeed(unittest.TestCase):
    def _initialize(self, folder, workspace, native_library, *, wal=False):
        spec = json.loads((workspace/'synthetic-workload.json').read_text())
        staged = Path(spec['profile'])
        self.assertTrue(staged.is_relative_to(workspace))
        staged.mkdir()
        raw = json.dumps({'writer': spec['writer'], 'folder': str(folder),
                          'user': spec['user'], 'appearance': 'system'}).encode()
        with closing(sqlite3.connect(str(staged/'local.sqlite'))) as db, db:
            db.execute('PRAGMA application_id=1414284354')
            db.execute('CREATE TABLE protected_settings(singleton INTEGER,writer TEXT,raw BLOB)')
            db.execute('INSERT INTO protected_settings VALUES(1,?,?)', (spec['writer'],raw))
        (folder/'synthetic.applog').write_bytes(b'canonical synthetic bytes')
        if wal:
            (staged/'local.sqlite-wal').write_bytes(b'unfinished synthetic WAL')
        return {'settings_sha256': hashlib.sha256(raw).hexdigest()}

    def test_actual_default_profile_may_be_outside_seed_workspace(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            workspace = base/'workspace'
            workspace.mkdir()
            profile = base/'sandbox-default'
            folder = profile/'shared-data'
            with patch.object(smoke, 'initialize_fixture', side_effect=self._initialize):
                receipt = smoke.seed_fixture(folder, profile, workspace, 'pinned-native')
            self.assertEqual(hashlib.sha256(smoke.read_settings_bytes(profile)).hexdigest(),
                             receipt['settings_sha256'])
            self.assertEqual(json.loads(smoke.read_settings_bytes(profile))['folder'], str(folder))
            self.assertEqual((folder/'synthetic.applog').read_bytes(), b'canonical synthetic bytes')
            self.assertEqual((profile/'local.sqlite').read_bytes(),
                             (workspace/'installer-profile-stage/local.sqlite').read_bytes())

    def test_existing_default_profile_is_never_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory);profile=base/'default';profile.mkdir()
            original=profile/'local.sqlite';original.write_bytes(b'existing profile')
            with patch.object(smoke, 'initialize_fixture') as initialize:
                with self.assertRaisesRegex(RuntimeError, 'overwrite'):
                    smoke.seed_fixture(profile/'shared-data',profile,base,'pinned-native')
            initialize.assert_not_called()
            self.assertEqual(original.read_bytes(),b'existing profile')
            self.assertFalse((base/'synthetic-workload.json').exists())

    def test_unclosed_staging_database_is_never_published(self):
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory);workspace=base/'workspace';workspace.mkdir()
            profile=base/'default';folder=profile/'shared-data'
            with patch.object(smoke, 'initialize_fixture',
                              side_effect=lambda *args:self._initialize(*args,wal=True)):
                with self.assertRaisesRegex(RuntimeError, 'closed database'):
                    smoke.seed_fixture(folder,profile,workspace,'pinned-native')
            self.assertFalse((profile/'local.sqlite').exists())
            self.assertTrue((workspace/'installer-profile-stage/local.sqlite-wal').exists())


if __name__ == '__main__':
    unittest.main()
