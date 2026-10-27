"""Pure fake API ownership controls. Never imports/executes main or WinDLL."""
from pathlib import Path
import runpy
import ast
import ctypes as C
from types import SimpleNamespace
import unittest

CODE = runpy.run_path(str(Path(__file__).with_name("windows_widget_controller.py")),
                     run_name="review_only_not_main")
acquire = CODE["acquire_owned_job"]
class OwnershipTests(unittest.TestCase):
    def fake(self, error, handle):
        calls = []
        current_error = 0
        def set_error(value):
            nonlocal current_error
            current_error = value
            calls.append(("clear-error",value))
        def create(security, name):
            nonlocal current_error
            calls.append(("create",security,name))
            current_error = error
            return handle
        def close(value):
            calls.append(("close-borrowed",value))
            return True
        return calls, create, close, set_error, lambda:current_error
    def test_collision_never_transfers_ownership_or_mutates_foreign_job(self):
        calls,create,close,set_error,get_error = self.fake(183,77)
        owned = None
        with self.assertRaisesRegex(RuntimeError,"Existing Job"):
            try:
                owned = acquire(create,close,set_error,get_error)
                calls.append(("set-limits",owned))
                calls.append(("assign",owned))
            finally:
                if owned:
                    calls.append(("terminate",owned))
        self.assertIsNone(owned)
        self.assertEqual(calls,[("clear-error",0),("create",None,None),
                                ("close-borrowed",77)])
    def test_success_requests_unnamed_only(self):
        calls,create,close,set_error,get_error = self.fake(0,88)
        self.assertEqual(acquire(create,close,set_error,get_error),88)
        self.assertEqual(calls,[("clear-error",0),("create",None,None)])
    def test_creation_failure_never_closes_or_owns_foreign_handle(self):
        calls,create,close,set_error,get_error = self.fake(5,None)
        with self.assertRaisesRegex(RuntimeError,"CreateJobObjectW failed"):
            acquire(create,close,set_error,get_error)
        self.assertEqual(calls,[("clear-error",0),("create",None,None)])

class AttributeTests(unittest.TestCase):
    def fake(self, init_ok=True, update_ok=True, query_error=122):
        calls = []; error = 0
        def set_error(value):
            nonlocal error
            error=value
        def get_error(): return error
        def initialize(buffer,count,flags,size):
            nonlocal error
            calls.append(("initialize",buffer is None,count,flags))
            C.cast(size,C.POINTER(C.c_size_t))[0]=64
            if buffer is None:
                error=query_error
                return False
            return init_ok
        def update(buffer,flags,key,value,size,old,returned):
            calls.append(("update",flags,key,size,
              C.cast(value,C.POINTER(C.c_void_p))[0],old,returned))
            return update_ok
        def delete(buffer): calls.append(("delete",))
        return calls,initialize,update,delete,set_error,get_error
    def test_job_value_and_attribute_survive_through_creation(self):
        calls,initialize,update,delete,set_error,get_error=self.fake()
        buffer,jobs=CODE["prepare_job_attribute"](
          initialize,update,delete,88,set_error,get_error)
        self.assertEqual(jobs[0],88)
        self.assertEqual(C.sizeof(jobs),8)
        self.assertEqual(calls,[("initialize",True,1,0),
          ("initialize",False,1,0),("update",0,0x2000D,8,88,None,None)])
        # Caller retains BOTH objects until after CreateProcess completion.
        self.assertEqual(C.sizeof(buffer),64)
        delete(buffer)
        self.assertEqual(calls[-1],("delete",))
    def test_unsupported_attribute_never_creates_child_and_deletes_list(self):
        calls,initialize,update,delete,set_error,get_error=self.fake(update_ok=False)
        with self.assertRaisesRegex(RuntimeError,"unsupported"):
            CODE["prepare_job_attribute"](
              initialize,update,delete,88,set_error,get_error)
            calls.append(("CreateProcess",))
        self.assertEqual(calls[-1],("delete",))
        self.assertFalse(any(row[0]=="CreateProcess" for row in calls))
    def test_failed_initialize_never_creates_child_or_deletes_uninitialized_list(self):
        calls,initialize,update,delete,set_error,get_error=self.fake(init_ok=False)
        with self.assertRaisesRegex(RuntimeError,"initialization failed"):
            CODE["prepare_job_attribute"](
              initialize,update,delete,88,set_error,get_error)
            calls.append(("CreateProcess",))
        self.assertEqual(calls,[("initialize",True,1,0),("initialize",False,1,0)])
    def test_bad_size_probe_fails_closed_before_creation(self):
        calls,initialize,update,delete,set_error,get_error=self.fake(query_error=5)
        with self.assertRaisesRegex(RuntimeError,"determine"):
            CODE["prepare_job_attribute"](
              initialize,update,delete,88,set_error,get_error)
            calls.append(("CreateProcess",))
        self.assertEqual(calls,[("initialize",True,1,0)])
    def test_expired_deadline_never_resumes(self):
        for expired,now in [(True,10),(False,150),(False,151)]:
            calls=[]
            with self.assertRaisesRegex(RuntimeError,"Deadline"):
                CODE["check_resume_deadline"](expired,0,now)
                calls.append("ResumeThread")
            self.assertEqual(calls,[])
        CODE["check_resume_deadline"](False,0,149.99)
    def test_win64_extended_startup_layout_from_actual_source(self):
        tree=ast.parse(Path(__file__).with_name(
          "windows_widget_controller.py").read_text())
        main=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=="main")
        classes=[n for n in main.body if isinstance(n,ast.ClassDef)
                 and n.name in ("STARTUPINFO","STARTUPINFOEX")]
        # Fixed Windows LLP64 fields, not this Linux host's c_ulong/wchar width.
        fields=SimpleNamespace(DWORD=C.c_uint32,LPWSTR=C.c_void_p,
          WORD=C.c_uint16,HANDLE=C.c_void_p)
        namespace={"C":C,"W":fields,"H":C.c_void_p}
        exec(compile(ast.Module(body=classes,type_ignores=[]),"<actual-layout>","exec"),
             namespace)
        self.assertEqual(C.sizeof(namespace["STARTUPINFO"]),104)
        self.assertEqual(C.sizeof(namespace["STARTUPINFOEX"]),112)
        self.assertEqual(namespace["STARTUPINFOEX"].lpAttributeList.offset,104)
    def test_actual_creation_has_no_unassigned_fallback(self):
        text=Path(__file__).with_name("windows_widget_controller.py").read_text()
        tree=ast.parse(text)
        main=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=="main")
        creations=[n for n in ast.walk(main) if isinstance(n,ast.Call)
          and isinstance(n.func,ast.Name) and n.func.id=="CreateProcess"]
        self.assertEqual(len(creations),1)
        flags={n.id for n in ast.walk(creations[0].args[5]) if isinstance(n,ast.Name)}
        self.assertEqual(flags,{"CREATE_SUSPENDED","CREATE_UNICODE_ENVIRONMENT",
                                "EXTENDED_STARTUPINFO_PRESENT"})
        self.assertNotIn("AssignProcessToJobObject",text)
        self.assertIn("C.byref(startup.StartupInfo)",text)
        self.assertIn("startup.lpAttributeList = C.cast(attribute_buffer",text)
        self.assertLess(text.index("prepare_job_attribute(\n          Initialize"),
                        text.index("win(CreateProcess("))
        self.assertLess(text.index('need(member.value, "Atomic creation'),
                        text.index('need(Resume('))
if __name__=="__main__":
    unittest.main()
