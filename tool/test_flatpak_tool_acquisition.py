"""Audited build tools must never downgrade or modify runner libraries."""
import copy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('appstream_tools', ROOT / 'packaging/linux/prepare_appstream_tools.py')
tools = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(tools)
MANIFEST = ROOT / 'evidence/flatpak-2026.10.4-rc.2/tool-audit-manifest.json'


class Response(io.BytesIO):
    def __init__(self, data, url):
        super().__init__(data)
        self.url = url

    def geturl(self):
        return self.url


class AcquisitionContracts(unittest.TestCase):
    def setUp(self):
        self.packages = tools.load_packages(MANIFEST)
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def synthetic_packages(self):
        packages = copy.deepcopy(self.packages)
        payloads = {}
        for package in packages:
            payload = package['file'].encode()
            package.update(size=len(payload), sha256=hashlib.sha256(payload).hexdigest())
            payloads[package['url']] = payload
        return packages, payloads

    def test_exact_six_allowlisted_packages_only(self):
        self.assertEqual(len(self.packages), 6)
        manifest = json.loads(MANIFEST.read_text())
        mutations = [manifest[:-1] + [dict(self.packages[0])],
                     [p for p in manifest if p['file'] != self.packages[0]['file']],
                     manifest + [dict(self.packages[0], file='unknown_1_amd64.deb')],
                     [dict(p, sha256='') if p['file'] == self.packages[0]['file'] else p for p in manifest],
                     [dict(p, url=p['url'].replace('archive.ubuntu.com', 'other.example')) if p['file'] == self.packages[0]['file'] else p for p in manifest]]
        for i, value in enumerate(mutations):
            path = self.root / f'manifest-{i}.json'
            path.write_text(json.dumps(value))
            with self.assertRaises(ValueError):
                tools.load_packages(path)

    def test_all_payloads_verified_before_any_package_command(self):
        packages, payloads = self.synthetic_packages()
        payloads[packages[-1]['url']] = b'bad final payload'
        with patch.object(tools.subprocess, 'run') as run:
            with self.assertRaises(ValueError):
                tools.prepare_tools(self.root / 'prepared', packages,
                                    opener=lambda url, **_: Response(payloads[url], url))
        run.assert_not_called()

    def test_wrong_hash_size_and_redirect_fail_without_extraction(self):
        packages, payloads = self.synthetic_packages()
        package = packages[0]
        attempts = [(b'changed', package['url']),
                    (payloads[package['url']] + b'extra', package['url']),
                    (payloads[package['url']], 'https://other.example/package.deb')]
        for i, (payload, url) in enumerate(attempts):
            with self.assertRaises(ValueError):
                tools.download_packages(self.root / f'download-{i}', [package],
                                        opener=lambda *_, **__: Response(payload, url))

    def test_read_only_package_metadata_rejects_wrong_architecture(self):
        package = self.packages[0]
        path = self.root / package['file']
        path.write_bytes(b'synthetic')
        with patch.object(tools.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, 'Package: appstream\nVersion: 1.0.2-1build6\nArchitecture: arm64\n')) as run:
            with self.assertRaises(ValueError):
                tools.extract_packages(self.root / 'extracted', [(package, path)])
        self.assertEqual(run.call_count, 1)
        self.assertEqual(run.call_args.args[0][:2], ['dpkg-deb', '--field'])

    def test_extraction_never_installs_or_executes_package_hooks(self):
        package = self.packages[0]
        path = self.root / package['file']
        path.write_bytes(b'synthetic')
        with patch.object(tools.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, 'Package: appstream\nVersion: 1.0.2-1build6\nArchitecture: amd64\n')) as run:
            tools.extract_packages(self.root / 'extracted', [(package, path)])
        self.assertEqual([call.args[0][:2] for call in run.call_args_list],
                         [['dpkg-deb', '--field'], ['dpkg-deb', '--extract']])

    @unittest.skipUnless(sys.platform.startswith('linux'), 'Actual native wrapper execution requires Linux')
    def test_wrapper_scopes_audited_libraries_to_exact_tool_child(self):
        extracted = self.root / 'extracted'
        for relative in ['usr/bin/appstreamcli', 'usr/libexec/appstreamcli-compose']:
            path = extracted / relative
            path.parent.mkdir(parents=True)
            path.write_text('#!/usr/bin/env python3\nimport json,os,sys\nprint(json.dumps({"target":sys.argv[0],"args":sys.argv[1:],"library":os.environ.get("LD_LIBRARY_PATH")}))\n')
            path.chmod(0o755)
        wrapper = tools.write_wrapper(self.root / 'bin', extracted)
        env = dict(os.environ, LD_LIBRARY_PATH='/unrelated/ambient')
        for args, target in [(['--version'], 'usr/bin/appstreamcli'),
                             (['compose', '--no-net', '/input'], 'usr/libexec/appstreamcli-compose')]:
            result = subprocess.run([str(wrapper), *args], env=env, text=True, capture_output=True, check=True)
            data = json.loads(result.stdout)
            self.assertEqual(data['target'], str(extracted / target))
            self.assertEqual(data['library'], str(extracted / 'usr/lib/x86_64-linux-gnu'))
            self.assertEqual(data['args'], args[1:] if args[0] == 'compose' else args)
        self.assertEqual(env['LD_LIBRARY_PATH'], '/unrelated/ambient')

    def test_runtime_rejects_loading_a_host_library_instead_of_audited_closure(self):
        wrapper = self.root / 'prepared/bin/appstreamcli'
        wrapper.parent.mkdir(parents=True)
        with patch.object(tools.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, 'libappstream.so.5 => /usr/lib/libappstream.so.5\n')) as run:
            with self.assertRaises(ValueError):
                tools.verify_runtime(wrapper)
        self.assertEqual(run.call_count, 1)

    def test_workflow_uses_unprivileged_adapter_without_host_install(self):
        workflow = (ROOT / '.github/workflows/validate.yml').read_text()
        step = workflow.split('- name: Prepare reviewed AppStream packaging tools', 1)[1].split('- uses:', 1)[0]
        self.assertIn('prepare_appstream_tools.py', step)
        self.assertNotIn('sudo', step)
        self.assertNotIn('apt-get', step)
        self.assertNotIn('allow-downgrades', step)
        self.assertNotIn('GITHUB_ENV', step)


if __name__ == '__main__':
    unittest.main()
