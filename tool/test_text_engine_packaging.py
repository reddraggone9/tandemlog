"""Frozen packaging contracts, independent of CRDT implementation details."""
import struct
import tempfile
import unittest
from pathlib import Path

from build_text_engine import BuildError, validate_crate, validate_ndk, verify_elf, verify_pe


class PackagingContracts(unittest.TestCase):
    def test_missing_or_unlocked_engine_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            crate = Path(temporary)
            with self.assertRaisesRegex(BuildError, 'Cargo.toml'):
                validate_crate(crate)
            (crate / 'Cargo.toml').write_text('[lib]\nname = "tandemlog_text"\ncrate-type = ["cdylib"]\n')
            with self.assertRaisesRegex(BuildError, 'Cargo.lock'):
                validate_crate(crate)

    def test_different_ndk_cannot_silently_build_payload(self):
        with tempfile.TemporaryDirectory() as temporary:
            ndk = Path(temporary)
            (ndk / 'source.properties').write_text('Pkg.Revision = 27.0.0\n')
            with self.assertRaisesRegex(BuildError, '28.2.13676358'):
                validate_ndk(ndk)

    def test_android_architecture_and_page_alignment_are_required(self):
        # Minimal ELF64 metadata fixture, not an executable or committed binary.
        header = bytearray(120)
        header[:6] = b'\x7fELF\x02\x01'
        struct.pack_into('<H', header, 16, 3)  # ET_DYN
        struct.pack_into('<H', header, 18, 183)  # AArch64
        struct.pack_into('<Q', header, 32, 64)  # program header offset
        struct.pack_into('<HH', header, 54, 56, 1)
        struct.pack_into('<I', header, 64, 1)  # PT_LOAD
        struct.pack_into('<Q', header, 112, 16384)
        with tempfile.TemporaryDirectory() as temporary:
            library = Path(temporary) / 'libtandemlog_text.so'
            library.write_bytes(header)
            verify_elf(library, 183, android=True)
            with self.assertRaisesRegex(BuildError, 'architecture'):
                verify_elf(library, 62, android=True)
            struct.pack_into('<Q', header, 112, 4096)
            library.write_bytes(header)
            with self.assertRaisesRegex(BuildError, '16 KiB'):
                verify_elf(library, 183, android=True)
            library.write_bytes(header[:40])
            with self.assertRaises(BuildError):
                verify_elf(library, 183, android=True)

    def test_windows_library_without_production_exports_is_rejected(self):
        # A PE32+ DLL metadata fixture with an export directory but no exports.
        header = bytearray(1024)
        header[:2] = b'MZ'
        struct.pack_into('<I', header, 60, 128)
        header[128:132] = b'PE\0\0'
        struct.pack_into('<HH', header, 132, 0x8664, 1)
        struct.pack_into('<HH', header, 148, 240, 0x2000)
        struct.pack_into('<H', header, 152, 0x20b)
        struct.pack_into('<I', header, 264, 0x1000)
        struct.pack_into('<IIII', header, 400, 512, 0x1000, 512, 512)
        struct.pack_into('<I', header, 544, 0x1040)
        with tempfile.TemporaryDirectory() as temporary:
            library = Path(temporary) / 'tandemlog_text.dll'
            library.write_bytes(header)
            with self.assertRaisesRegex(BuildError, 'Missing Windows text engine exports'):
                verify_pe(library)
            struct.pack_into('<H', header, 132, 0x14c)
            library.write_bytes(header)
            with self.assertRaisesRegex(BuildError, 'x64'):
                verify_pe(library)


if __name__ == '__main__':
    unittest.main()
