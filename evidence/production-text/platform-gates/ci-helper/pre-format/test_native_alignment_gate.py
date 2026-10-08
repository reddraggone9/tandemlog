"""16KiB RELRO gate frozen before extending the existing ELF verifier."""
import struct,tempfile,unittest
from pathlib import Path
from build_text_engine import verify_elf,BuildError
class Alignment(unittest.TestCase):
 def test_relro_end_must_be_16k_aligned(self):
  h=bytearray(176);h[:6]=b'\x7fELF\x02\x01';struct.pack_into('<HH',h,16,3,183);struct.pack_into('<Q',h,32,64);struct.pack_into('<HH',h,54,56,2);struct.pack_into('<I',h,64,1);struct.pack_into('<Q',h,112,16384);struct.pack_into('<I',h,120,0x6474e552);struct.pack_into('<Q',h,136,0x3100);struct.pack_into('<Q',h,160,0xf00)
  with tempfile.TemporaryDirectory() as t:
   p=Path(t)/'library.so';p.write_bytes(h);verify_elf(p,183,android=True)
   struct.pack_into('<Q',h,160,0x1000);p.write_bytes(h)
   with self.assertRaisesRegex(BuildError,'RELRO'):verify_elf(p,183,android=True)
if __name__=='__main__':unittest.main()
