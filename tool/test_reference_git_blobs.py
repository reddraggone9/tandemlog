"""Bulk Git transport equivalence and fail-closed protocol regressions."""
import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent / 'performance'))
import reference_receipt as receipt


def blob_id(content):
    return hashlib.sha1(b'blob ' + str(len(content)).encode() + b'\0' + content).hexdigest()


def response(content, obj=None, kind=b'blob', size=None):
    return ((obj or blob_id(content)).encode() + b' ' + kind + b' ' +
            str(len(content) if size is None else size).encode() + b'\n' + content + b'\n')


class BatchProtocolTests(unittest.TestCase):
    def test_binary_newlines_empty_and_duplicate_requests(self):
        contents = [b'\x00\xff\nheader blob 3\n\r\n', b'', b'no final newline']
        ids = [blob_id(value) for value in contents]
        with patch.object(receipt.subprocess, 'check_output', return_value=b''.join(map(response, contents))) as git:
            self.assertEqual(receipt.git_blobs('/repo', ids + ids), dict(zip(ids, contents)))
        git.assert_called_once_with(['git', '-C', '/repo', 'cat-file', '--batch'],
                                    input=('\n'.join(ids) + '\n').encode())

    def test_no_objects_needs_no_process(self):
        with patch.object(receipt.subprocess, 'check_output') as git:
            self.assertEqual(receipt.git_blobs('/repo', []), {})
        git.assert_not_called()

    def test_invalid_object_requests_never_reach_git(self):
        for obj in ['abc', 'a'*40 + '\nHEAD', 'A'*40, 'g'*40]:
            with self.subTest(obj=obj), patch.object(receipt.subprocess, 'check_output') as git:
                with self.assertRaisesRegex(ValueError, 'object ID'):
                    receipt.git_blobs('/repo', [obj])
                git.assert_not_called()

    def test_malformed_missing_truncated_wrong_or_trailing_responses(self):
        content = b'a\x00\n'
        obj = blob_id(content)
        valid = response(content)
        other = b'other'
        cases = {
            'empty/missing': b'',
            'missing header newline': valid.split(b'\n')[0],
            'missing object': obj.encode() + b' missing\n',
            'error': b'fatal: corrupt object\n',
            'wrong id': response(other),
            'wrong type': response(content, kind=b'tree'),
            'uppercase id': response(content, obj=obj.upper()),
            'short id': response(content, obj='abc'),
            'negative size': response(content, size=-1),
            'leading zero size': valid.replace(b'blob 3\n', b'blob 03\n', 1),
            'noninteger size': valid.replace(b'blob 3\n', b'blob x\n', 1),
            'extra header field': valid.replace(b'blob 3\n', b'blob 3 extra\n', 1),
            'truncated body': valid[:-2],
            'missing terminator': valid[:-1],
            'wrong terminator': valid[:-1] + b'!',
            'wrong size': response(content, size=2),
            'content hash differs': response(b'b\x00\n', obj=obj),
            'trailing bytes': valid + b'junk',
            'extra newline': valid + b'\n',
            'duplicate extra response': valid + valid,
        }
        for name, output in cases.items():
            with self.subTest(name=name), patch.object(receipt.subprocess, 'check_output', return_value=output):
                with self.assertRaises(ValueError):
                    receipt.git_blobs('/repo', [obj])
        for output in (valid, valid + valid):
            with self.subTest(output=output), patch.object(receipt.subprocess, 'check_output', return_value=output):
                with self.assertRaises(ValueError):
                    receipt.git_blobs('/repo', [obj, blob_id(other)])

    def test_nonzero_git_is_not_accepted_even_with_complete_stdout(self):
        content = b'complete'
        with patch.object(receipt.subprocess, 'check_output', side_effect=subprocess.CalledProcessError(
                7, ['git'], output=response(content))):
            with self.assertRaises(subprocess.CalledProcessError):
                receipt.git_blobs('/repo', [blob_id(content)])


class BulkIdentityTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.repo = Path(temporary.name)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Blob Test')
        self.git('config', 'user.email', 'blob@example.invalid')
        self.git('config', 'core.autocrlf', 'false')
        self.contents = {'binary': b'\x00\xff\n\r\n', 'duplicate': b'\x00\xff\n\r\n',
                         'empty': b'', 'empty-copy': b'', 'newlines': b'line\n\n',
                         'pubspec.yaml': b'name: test\nversion: 2026.10.8+102\n',
                         receipt.METAINFO: b'<component><releases><release version="2026.10.8" '
                         b'date="2026-10-28" type="stable"/></releases></component>\n',
                         'executable': b'#!/bin/sh\n', 'design/ignored': b'not pinned'}
        for name, content in self.contents.items():
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        (self.repo / 'executable').chmod(0o755)
        self.git('add', '.')
        self.git('update-index', '--chmod=+x', 'executable')
        self.git('commit', '-qm', 'fixture')
        self.revision = self.git('rev-parse', 'HEAD').decode().strip()

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args])

    def legacy(self, scheme, committed):
        pins = {}
        args = ('ls-tree', '-r', '-z', self.revision) if committed else ('ls-files', '--stage', '-z')
        for row in self.git(*args).decode().split('\0'):
            if not row:
                continue
            info, name = row.split('\t', 1)
            if not receipt.relevant(name):
                continue
            mode, second, third = info.split()
            obj = third if committed else second
            content = self.git('cat-file', 'blob', obj)
            pins[name] = receipt.pin(name, content, mode, scheme)
        return receipt.identity(pins, scheme)

    def test_real_git_matches_legacy_identities_with_one_batch_per_inventory(self):
        for scheme in (receipt.IDENTITY_V1, receipt.IDENTITY_V2):
            for committed in (False, True):
                with self.subTest(scheme=scheme, committed=committed):
                    expected = self.legacy(scheme, committed)
                    original = subprocess.check_output
                    with patch.object(receipt.subprocess, 'check_output', wraps=original) as git:
                        actual = (receipt.committed_identity(self.repo, self.revision, scheme) if committed
                                  else receipt.source_identity(self.repo, scheme))
                    self.assertEqual(actual, expected)
                    calls = [call for call in git.call_args_list if 'cat-file' in call.args[0]]
                    self.assertEqual(len(calls), 1)
                    self.assertEqual(calls[0].args[0][-1], '--batch')
                    requested = calls[0].kwargs['input'].splitlines()
                    self.assertEqual(len(requested), len(set(requested)))
                    self.assertEqual(len(requested), len({blob_id(v) for n, v in self.contents.items()
                                                         if receipt.relevant(n)}))
                    self.assertEqual(actual['files']['executable']['mode'], '100755')

    def test_duplicate_inventory_paths_are_rejected(self):
        original = subprocess.check_output
        for committed, command in ((False, 'ls-files'), (True, 'ls-tree')):
            def duplicated(args, **kwargs):
                output = original(args, **kwargs)
                if command in args and ('--stage' in args or command == 'ls-tree'):
                    output += output.split(b'\0', 1)[0] + b'\0'
                return output
            with self.subTest(committed=committed), patch.object(receipt.subprocess, 'check_output', side_effect=duplicated):
                with self.assertRaisesRegex(ValueError, 'Duplicate.*inventory path'):
                    if committed:
                        receipt.committed_identity(self.repo, self.revision)
                    else:
                        receipt.source_identity(self.repo)

    def test_dirty_untracked_and_literal_worktree_checks_remain(self):
        path = self.repo / 'binary'
        path.write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'dirty or untracked'):
            receipt.source_identity(self.repo)
        # Even an assume-unchanged index entry must be checked against literal worktree bytes.
        self.git('update-index', '--assume-unchanged', 'binary')
        with self.assertRaisesRegex(ValueError, 'literal Git bytes'):
            receipt.source_identity(self.repo)
        path.write_bytes(self.contents['binary'])
        (self.repo / 'untracked').write_bytes(b'new')
        with self.assertRaisesRegex(ValueError, 'dirty or untracked'):
            receipt.source_identity(self.repo)

    def test_linked_or_missing_worktree_and_committed_symlinks_are_rejected(self):
        path = self.repo / 'binary'
        self.git('update-index', '--assume-unchanged', 'binary')
        path.unlink()
        for linked in (False, True):
            if linked:
                try:
                    path.symlink_to(self.repo / 'duplicate')
                except OSError:
                    self.skipTest('symlink creation unavailable')
            with self.subTest(linked=linked), self.assertRaisesRegex(ValueError, 'missing or linked'):
                receipt.source_identity(self.repo)
        self.git('update-index', '--no-assume-unchanged', 'binary')
        self.git('add', 'binary')
        self.git('commit', '-qm', 'linked source')
        revision = self.git('rev-parse', 'HEAD').decode().strip()
        with self.assertRaisesRegex(ValueError, 'Linked/unexpected'):
            receipt.committed_identity(self.repo, revision)


if __name__ == '__main__':
    unittest.main()
