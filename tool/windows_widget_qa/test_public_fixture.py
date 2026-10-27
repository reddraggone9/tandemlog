"""Pure public-fixture loader controls; never main/WinDLL/app/desktop."""
from pathlib import Path
import tempfile,json,hashlib,runpy,unittest
from unittest.mock import patch
CODE=runpy.run_path(str(Path(__file__).with_name("windows_widget_controller.py")),run_name="pure_fixture_policy")
load=CODE["load_public_fixture"]
class FixturePolicyTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
        self.workspace=self.root/"workspace";self.workspace.mkdir()
        self.names=["tandemlog-space.json","a.applog","b.applog","c.applog"]
        self.files={}
        for name in self.names:
            data=("nonexecuted fixture "+name).encode();(self.workspace/name).write_bytes(data)
            self.files[name]=hashlib.sha256(data).hexdigest()
        raw=json.dumps({"syntheticOnly":True,"baselinePhysicalRecords":1325,"files":self.files}).encode()
        (self.root/"ui-fixture-original.json").write_bytes(raw)
        self.policy=patch.dict(load.__globals__,{"PUBLIC_FIXTURE_SHA":hashlib.sha256(raw).hexdigest()})
        self.policy.start()
    def tearDown(self):
        self.policy.stop();self.tmp.cleanup()
    def test_positive_canonical_only_no_profile_required(self):
        self.assertEqual(load(self.root),self.root.resolve())
    def test_profile_bytes_are_not_required_or_read(self):
        (self.root/"profile").mkdir();(self.root/"profile"/"arbitrary-private-state").write_text("ignored")
        self.assertEqual(load(self.root),self.root.resolve())
    def test_contract_tampering_refused(self):
        (self.root/"ui-fixture-original.json").write_text("{}")
        with self.assertRaisesRegex(RuntimeError,"contract differs"):load(self.root)
    def test_modified_canonical_refused(self):
        (self.workspace/"a.applog").write_bytes(b"changed")
        with self.assertRaisesRegex(RuntimeError,"canonical bytes differ"):load(self.root)
    def test_extra_inventory_refused(self):
        (self.workspace/"unexpected").write_text("x")
        with self.assertRaisesRegex(RuntimeError,"inventory differs"):load(self.root)
    def test_missing_inventory_refused(self):
        (self.workspace/"a.applog").unlink()
        with self.assertRaisesRegex(RuntimeError,"inventory differs"):load(self.root)
    def test_linked_member_refused_without_creating_real_links(self):
        original=Path.is_symlink
        def linked(p):return p.name=="a.applog" or original(p)
        with patch.object(Path,"is_symlink",linked):
            with self.assertRaisesRegex(RuntimeError,"Reparse|Regular"):load(self.root)
if __name__=="__main__":unittest.main()
