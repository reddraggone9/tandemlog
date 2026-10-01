"""Installer subprocess cleanup must target only its captured Flatpak instance."""
import importlib.util
import io
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


if __name__ == '__main__':
    unittest.main()
