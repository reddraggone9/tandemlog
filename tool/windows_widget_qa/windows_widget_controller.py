"""SOURCE-ONLY Windows QA controller; no execution has been accepted.
Private inactive Desktop + suspended child assigned to kill-on-close Job.
No input injection, desktop switching, process attachment or production profile.
"""
from __future__ import annotations
import argparse
import ctypes as C
from ctypes import wintypes as W
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import threading
import time

TARGET_SHA = "e89624e837b7e94942191c0fee2d4fab5e3ba491d24af122b3f957847c6e7d5c"
TTL_SECONDS = 150
CLEANUP_SECONDS = 20
# Microsoft WinBase.h: attribute number13 | INPUT0x20000; Windows10+ only.
PROC_THREAD_ATTRIBUTE_JOB_LIST = 13 | 0x00020000
CREATE_SUSPENDED = 0x00000004
CREATE_UNICODE_ENVIRONMENT = 0x00000400
EXTENDED_STARTUPINFO_PRESENT = 0x00080000
def need(ok, why):
    if not ok:
        raise RuntimeError(why)
def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()
def regular(p):
    st = p.lstat()
    need(not (getattr(st, "st_file_attributes", 0) & 0x400),
         "Reparse point refused: " + str(p))
    need(p.is_file(), "Regular file required: " + str(p))
def clean_tree(root):
    for p in (root, *root.parents):
        need(not (getattr(p.lstat(), "st_file_attributes", 0) & 0x400),
             "Reparse ancestor refused.")
    for p in root.rglob("*"):
        need(not (getattr(p.lstat(), "st_file_attributes", 0) & 0x400),
             "Reparse entry refused.")
def acquire_owned_job(create_job, close_handle, set_error, get_error):
    # Unnamed Jobs are fresh. Defend even a surprising ERROR_ALREADY_EXISTS:
    # do not transfer handle ownership until collision handling has completed.
    set_error(0)
    handle = create_job(None, None)
    error = get_error()
    need(bool(handle), "CreateJobObjectW failed: " + str(error))
    if error == 183:
        need(bool(close_handle(handle)), "Could not close borrowed Job handle.")
        raise RuntimeError("Existing Job handle refused; no ownership acquired.")
    return handle

def prepare_job_attribute(initialize, update, delete, job, set_error, get_error):
    # Attribute value array and opaque buffer remain alive through CreateProcess.
    # Unsupported APIs/attributes fail here, BEFORE any child creation.
    size = C.c_size_t()
    set_error(0)
    first = initialize(None, 1, 0, C.byref(size))
    need(not first and get_error() == 122 and 0 < size.value <= 65536,
         "Cannot determine supported Job-list attribute buffer.")
    buffer = C.create_string_buffer(size.value)
    initialized = False
    try:
        need(bool(initialize(buffer,1,0,C.byref(size))),
             "Job-list attribute initialization failed.")
        initialized = True
        jobs = (C.c_void_p * 1)(job)
        need(bool(update(buffer,0,PROC_THREAD_ATTRIBUTE_JOB_LIST,
                         C.cast(jobs,C.c_void_p),C.sizeof(jobs),None,None)),
             "Atomic Job-list process creation is unsupported.")
        return buffer,jobs
    except BaseException:
        if initialized: delete(buffer)
        raise

def check_resume_deadline(expired, started, now):
    need(not expired and now-started < TTL_SECONDS,
         "Deadline expired before child resume.")

def load_artifact(root, manifest_sha):
    root = root.resolve(strict=True)
    clean_tree(root)
    manifest = root / "qa-artifact.json"
    regular(manifest)
    need(sha(manifest) == manifest_sha, "Artifact manifest binding differs.")
    data = json.loads(manifest.read_text())
    need(data["qaOnly"] is True and data["targetSHA256"] == TARGET_SHA
         and data["mode"] == "release" and data["installer"] is False,
         "Not the reviewed separate release-QA artifact.")
    need(data["helperPins"]["windows_widget_controller.py"] ==
         sha(Path(__file__).resolve()), "Reviewed controller bytes differ.")
    bundle = root / "bundle"
    paths = {p.relative_to(bundle).as_posix(): p
             for p in bundle.rglob("*") if p.is_file()}
    need(set(paths) == set(data["files"]), "Payload inventory differs.")
    for rel, p in paths.items():
        regular(p)
        need(sha(p) == data["files"][rel]["sha256"]
             and p.stat().st_size == data["files"][rel]["bytes"],
             "Payload bytes differ: " + rel)
    need(data["executable"] == "tandemlog.exe"
         and data["nativeLibrary"] == "tandemlog_text.dll",
         "Unexpected executable/native names.")
    return data, bundle

def main():
    need(os.name == "nt", "Windows-only controller.")
    need(C.sizeof(C.c_void_p) == 8, "Require native 64-bit Python.")
    need(sys.getwindowsversion().build >= 10240,
         "Atomic Job-list creation requires Windows10+/Server2016+.")
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact", type=Path, required=True)
    parser.add_argument("--manifest-sha256", required=True)
    args = parser.parse_args()
    need(len(args.manifest_sha256) == 64, "Exact manifest SHA256 required.")
    metadata, bundle = load_artifact(args.artifact, args.manifest_sha256)
    exe = (bundle / metadata["executable"]).resolve(strict=True)
    native = (bundle / metadata["nativeLibrary"]).resolve(strict=True)
    nonce = secrets.token_hex(16)
    output = Path(tempfile.mkdtemp(prefix="windows-widget-controller-" + nonce + "-"))
    tmp = output / "tmp"; tmp.mkdir()
    for name in ("local", "roaming", "home"):
        (output / name).mkdir()
    desktop_name = "TandemlogQa" + nonce
    run_name = "windows-widget-viability-" + nonce
    run_root = tmp / run_name
    log = run_root / "probe.jsonl"
    controller_log = output / "controller.jsonl"
    # The external bounded wrapper retains this location even if APIs later hang.
    print(json.dumps({"controllerOutput":str(output)}),flush=True)
    def emit(phase, **data):
        with controller_log.open("a", encoding="utf-8") as stream:
            stream.write(json.dumps({"phase": phase, "monotonic": time.monotonic(),
                                     **data}) + "\n")
            stream.flush()
            os.fsync(stream.fileno())

    K = C.WinDLL("kernel32", use_last_error=True)
    U = C.WinDLL("user32", use_last_error=True)
    H = W.HANDLE
    class STARTUPINFO(C.Structure):
        _fields_ = [("cb", W.DWORD), ("lpReserved", W.LPWSTR),
          ("lpDesktop", W.LPWSTR), ("lpTitle", W.LPWSTR),
          ("dwX", W.DWORD), ("dwY", W.DWORD), ("dwXSize", W.DWORD),
          ("dwYSize", W.DWORD), ("dwXCountChars", W.DWORD),
          ("dwYCountChars", W.DWORD), ("dwFillAttribute", W.DWORD),
          ("dwFlags", W.DWORD), ("wShowWindow", W.WORD),
          ("cbReserved2", W.WORD), ("lpReserved2", C.POINTER(C.c_ubyte)),
          ("hStdInput", H), ("hStdOutput", H), ("hStdError", H)]
    class STARTUPINFOEX(C.Structure):
        _fields_ = [("StartupInfo",STARTUPINFO),("lpAttributeList",C.c_void_p)]
    need(C.sizeof(STARTUPINFO)==104 and C.sizeof(STARTUPINFOEX)==112 and
         STARTUPINFOEX.lpAttributeList.offset==104,"Win64 startup ABI differs.")
    class PROCESSINFO(C.Structure):
        _fields_ = [("hProcess", H), ("hThread", H),
                    ("dwProcessId", W.DWORD), ("dwThreadId", W.DWORD)]
    class BASIC_LIMIT(C.Structure):
        _fields_ = [("PerProcessUserTimeLimit", C.c_longlong),
          ("PerJobUserTimeLimit", C.c_longlong), ("LimitFlags", W.DWORD),
          ("MinimumWorkingSetSize", C.c_size_t), ("MaximumWorkingSetSize", C.c_size_t),
          ("ActiveProcessLimit", W.DWORD), ("Affinity", C.c_size_t),
          ("PriorityClass", W.DWORD), ("SchedulingClass", W.DWORD)]
    class IO_COUNTERS(C.Structure):
        _fields_ = [(n, C.c_ulonglong) for n in (
          "ReadOperationCount", "WriteOperationCount", "OtherOperationCount",
          "ReadTransferCount", "WriteTransferCount", "OtherTransferCount")]
    class EXTENDED_LIMIT(C.Structure):
        _fields_ = [("BasicLimitInformation", BASIC_LIMIT), ("IoInfo", IO_COUNTERS),
          ("ProcessMemoryLimit", C.c_size_t), ("JobMemoryLimit", C.c_size_t),
          ("PeakProcessMemoryUsed", C.c_size_t), ("PeakJobMemoryUsed", C.c_size_t)]
    class ACCOUNTING(C.Structure):
        _fields_ = [("TotalUserTime", C.c_longlong), ("TotalKernelTime", C.c_longlong),
          ("ThisPeriodTotalUserTime", C.c_longlong),
          ("ThisPeriodTotalKernelTime", C.c_longlong), ("TotalPageFaultCount", W.DWORD),
          ("TotalProcesses", W.DWORD), ("ActiveProcesses", W.DWORD),
          ("TotalTerminatedProcesses", W.DWORD)]
    ENUM = C.WINFUNCTYPE(W.BOOL, W.HWND, W.LPARAM)
    def api(lib, name, result, *types):
        f = getattr(lib, name); f.restype = result; f.argtypes = list(types)
        return f
    CreateDesktop = api(U, "CreateDesktopW", H, W.LPCWSTR, W.LPCWSTR,
                        C.c_void_p, W.DWORD, W.DWORD, C.c_void_p)
    OpenDesktop = api(U, "OpenDesktopW", H, W.LPCWSTR, W.DWORD, W.BOOL, W.DWORD)
    OpenInputDesktop = api(U, "OpenInputDesktop", H, W.DWORD, W.BOOL, W.DWORD)
    CloseDesktop = api(U, "CloseDesktop", W.BOOL, H)
    GetThreadDesktop = api(U, "GetThreadDesktop", H, W.DWORD)
    SetThreadDesktop = api(U, "SetThreadDesktop", W.BOOL, H)
    Station = api(U, "GetProcessWindowStation", H)
    ObjectInfo = api(U, "GetUserObjectInformationW", W.BOOL, H, C.c_int,
                     C.c_void_p, W.DWORD, C.POINTER(W.DWORD))
    EnumWindows = api(U, "EnumDesktopWindows", W.BOOL, H, ENUM, W.LPARAM)
    WindowPid = api(U, "GetWindowThreadProcessId", W.DWORD, W.HWND,
                    C.POINTER(W.DWORD))
    PostMessage = api(U, "PostMessageW", W.BOOL, W.HWND, W.UINT, W.WPARAM, W.LPARAM)
    ThreadId = api(K, "GetCurrentThreadId", W.DWORD)
    CreateJob = api(K, "CreateJobObjectW", H, C.c_void_p, W.LPCWSTR)
    SetJob = api(K, "SetInformationJobObject", W.BOOL, H, C.c_int,
                 C.c_void_p, W.DWORD)
    QueryJob = api(K, "QueryInformationJobObject", W.BOOL, H, C.c_int,
                   C.c_void_p, W.DWORD, C.POINTER(W.DWORD))
    InitializeAttributes = api(K,"InitializeProcThreadAttributeList",W.BOOL,
      C.c_void_p,W.DWORD,W.DWORD,C.POINTER(C.c_size_t))
    UpdateAttribute = api(K,"UpdateProcThreadAttribute",W.BOOL,
      C.c_void_p,W.DWORD,C.c_size_t,C.c_void_p,C.c_size_t,C.c_void_p,
      C.POINTER(C.c_size_t))
    DeleteAttributes = api(K,"DeleteProcThreadAttributeList",None,C.c_void_p)
    IsInJob = api(K, "IsProcessInJob", W.BOOL, H, H, C.POINTER(W.BOOL))
    TerminateJob = api(K, "TerminateJobObject", W.BOOL, H, W.UINT)
    CreateProcess = api(K, "CreateProcessW", W.BOOL, W.LPCWSTR, W.LPWSTR,
      C.c_void_p, C.c_void_p, W.BOOL, W.DWORD, C.c_void_p, W.LPCWSTR,
      C.POINTER(STARTUPINFO), C.POINTER(PROCESSINFO))
    Resume = api(K, "ResumeThread", W.DWORD, H)
    Wait = api(K, "WaitForSingleObject", W.DWORD, H, W.DWORD)
    ExitCode = api(K, "GetExitCodeProcess", W.BOOL, H, C.POINTER(W.DWORD))
    Times = api(K, "GetProcessTimes", W.BOOL, H, C.POINTER(W.FILETIME),
                C.POINTER(W.FILETIME), C.POINTER(W.FILETIME), C.POINTER(W.FILETIME))
    Image = api(K, "QueryFullProcessImageNameW", W.BOOL, H, W.DWORD,
                W.LPWSTR, C.POINTER(W.DWORD))
    TerminateProcess = api(K, "TerminateProcess", W.BOOL, H, W.UINT)
    Close = api(K, "CloseHandle", W.BOOL, H)
    def win(ok, label):
        if not ok:
            raise C.WinError(C.get_last_error(), label)
    def object_name(handle):
        length = W.DWORD()
        ObjectInfo(handle, 2, None, 0, C.byref(length))
        need(0 < length.value <= 4096, "Invalid object-name bound.")
        text = C.create_unicode_buffer(length.value // 2 + 1)
        win(ObjectInfo(handle, 2, text, C.sizeof(text), C.byref(length)), "object name")
        return text.value
    def input_name():
        handle = OpenInputDesktop(0, False, 1)
        win(handle, "read current input Desktop")
        try: return object_name(handle)
        finally: win(CloseDesktop(handle), "close input Desktop read handle")
    def identity(process):
        fields = [W.FILETIME() for _ in range(4)]
        win(Times(process, *(C.byref(f) for f in fields)), "process times")
        text = C.create_unicode_buffer(32768); length = W.DWORD(len(text))
        win(Image(process, 0, text, C.byref(length)), "process image")
        return {"creationTime100ns": (fields[0].dwHighDateTime << 32) |
                fields[0].dwLowDateTime, "image": str(Path(text.value).resolve())}
    original_thread_desktop = GetThreadDesktop(ThreadId())
    win(original_thread_desktop, "read original thread Desktop")
    original_input = input_name()
    station = object_name(Station())
    # Explicitly require interactive station; no station/security/ACL changes.
    need(station.casefold() == "winsta0", "Require existing WinSta0; no station changes.")
    existing = OpenDesktop(desktop_name, 0, False, 1)
    if existing:
        CloseDesktop(existing); raise RuntimeError("Fresh Desktop collision.")
    need(C.get_last_error() in (2, 3), "Cannot establish fresh Desktop absence.")
    desktop = job = None
    attribute_buffer = job_handles = None
    info = PROCESSINFO()
    assigned = resumed = terminated = False
    timer = None
    timed_out = threading.Event()
    started = time.monotonic()
    exit_code = None
    result = {"passed": False, "sourceOnlyPreparationPreviously": True,
              "artifactManifestSHA256": args.manifest_sha256,
              "targetSHA256": TARGET_SHA, "output": str(output)}
    emit("preparing", desktop=desktop_name, station=station,
         inputDesktop=original_input, ttlSeconds=TTL_SECONDS,
         cleanupSeconds=CLEANUP_SECONDS, childEnvironmentCurated=True,
         stdoutNotInherited=True, childInputInjection=False)
    try:
        # READOBJECTS|CREATEWINDOW|ENUMERATE|WRITEOBJECTS; deliberately no SWITCHDESKTOP.
        desktop = CreateDesktop(desktop_name, None, None, 0, 0xC3, None)
        win(desktop, "create private inactive Desktop")
        need(object_name(desktop) == desktop_name, "Created Desktop name differs.")
        job = acquire_owned_job(CreateJob, Close, C.set_last_error, C.get_last_error)
        limits = EXTENDED_LIMIT()
        limits.BasicLimitInformation.LimitFlags = 0x2000 | 0x8 | 0x200
        limits.BasicLimitInformation.ActiveProcessLimit = 8
        limits.JobMemoryLimit = 6 * 1024**3
        win(SetJob(job, 9, C.byref(limits), C.sizeof(limits)), "set finite Job limits")
        attribute_buffer,job_handles = prepare_job_attribute(
          InitializeAttributes,UpdateAttribute,DeleteAttributes,job,
          C.set_last_error,C.get_last_error)
        def expire():
            timed_out.set()
            # Only this newly created Job; main thread retains handle until join.
            TerminateJob(job, 124)
        timer = threading.Timer(max(0, started + TTL_SECONDS - time.monotonic()), expire)
        timer.daemon = True; timer.start()
        env = {key: os.environ[key] for key in ("SystemRoot", "WINDIR") if key in os.environ}
        need("SystemRoot" in env, "SystemRoot missing.")
        env.update({"PATH": str(bundle) + ";" + env["SystemRoot"] + r"\System32",
          "TEMP": str(tmp), "TMP": str(tmp), "USERPROFILE": str(output / "home"),
          "LOCALAPPDATA": str(output / "local"), "APPDATA": str(output / "roaming"),
          "TANDEMLOG_TEXT_LIBRARY": str(native),
          "TANDEMLOG_WINDOWS_WIDGET_RUN": run_name})
        block = C.create_unicode_buffer("\0".join(k + "=" + v for k,v in
          sorted(env.items(), key=lambda item:item[0].upper())) + "\0\0")
        startup = STARTUPINFOEX()
        startup.StartupInfo.cb = C.sizeof(startup)
        startup.StartupInfo.lpDesktop = station + "\\" + desktop_name
        startup.lpAttributeList = C.cast(attribute_buffer,C.c_void_p)
        command = C.create_unicode_buffer(subprocess.list2cmdline([str(exe)]))
        # bInheritHandles FALSE: no token, GitHub credentials, desktop/job or log handles.
        win(CreateProcess(str(exe), command, None, None, False,
          CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT | EXTENDED_STARTUPINFO_PRESENT,
          C.cast(block,C.c_void_p),str(bundle),C.byref(startup.StartupInfo),
          C.byref(info)),"create suspended QA child ATOMICALLY in own Job")
        process_identity = identity(info.hProcess)
        need(Path(process_identity["image"]) == exe, "Child image differs.")
        member = W.BOOL()
        win(IsInJob(info.hProcess, job, C.byref(member)), "confirm own Job")
        need(member.value, "Atomic creation did not establish owned Job.")
        assigned = True
        emit("armed-before-resume", pid=info.dwProcessId, tid=info.dwThreadId,
             identity=process_identity, desktop=desktop_name)
        check_resume_deadline(timed_out.is_set(),started,time.monotonic())
        need(input_name() == original_input,
             "Input Desktop changed before any QA input.")
        need(Resume(info.hThread) != 0xFFFFFFFF, "Resume failed.")
        resumed = True
        closed_requested = False
        records = []
        while Wait(info.hProcess, 0) == 258:
            need(not timed_out.is_set() and time.monotonic()-started < TTL_SECONDS,
                 "QA wall deadline expired.")
            if log.exists():
                regular(log)
                raw = log.read_bytes()
                need(len(raw) <= 8*1024*1024, "Target log exceeded8MiB.")
                complete = raw[:raw.rfind(b"\n")+1]
                records = [json.loads(line) for line in complete.splitlines()]
                need(all(r.get("pid") == info.dwProcessId and r.get("release") is True
                         for r in records), "Wrong target PID/release log.")
                need(not any(r["phase"] == "failed" for r in records), "Target failed.")
                suites = [r for r in records if r["phase"] == "suite-finished"]
                closures = [r for r in records if r["phase"] == "normal-resources-closed"]
                if suites and closures and not closed_requested:
                    need(len(suites)==len(closures)==1 and suites[0]["passed"] is True,
                         "Suite failed or ambiguous.")
                    closure = closures[0]
                    need(closure["typedActionCount"] == 2 and all(closure.get(k) is True
                      for k in ("nativeDisposed", "profileDatabaseClosed", "fullAuditReturned",
                                "prefixesPreserved", "nonownerUnchanged",
                                "taskSemanticStateRestored")), "Target proof incomplete.")
                    need([r["name"] for r in records if r["phase"]=="action"] ==
                      ["task-open","title-save","closed-editor-title-undo"],
                      "Action sequence differs.")
                    boot = [r for r in records if r["phase"]=="bootstrap"]
                    need(len(boot)==1 and boot[0]["nativeSHA256"]==sha(native)
                      and boot[0]["frameworkTextChannelMocked"] is True,
                      "Bootstrap native/input qualification differs.")
                    need(identity(info.hProcess)==process_identity, "Child identity changed.")
                    windows, callback_errors = [], []
                    @ENUM
                    def collect(hwnd, unused):
                        try:
                            owner = W.DWORD()
                            tid = WindowPid(hwnd, C.byref(owner))
                            if owner.value == info.dwProcessId:
                                need(object_name(GetThreadDesktop(tid)) == desktop_name,
                                     "Owned window on wrong Desktop.")
                                windows.append(int(hwnd))
                            return True
                        except BaseException as error:
                            callback_errors.append(repr(error))
                            return False
                    enumerated = EnumWindows(desktop, collect, 0)
                    need(not callback_errors, "Window identity callback failed: " +
                         repr(callback_errors))
                    win(enumerated, "enumerate own Desktop")
                    need(len(windows)==1, "Require one owned top-level native window.")
                    win(PostMessage(windows[0], 0x10, 0, 0), "post own WM_CLOSE")
                    closed_requested = True
                    emit("own-native-close-requested", hwnd=windows[0],
                         manualProductExitWasOnlyResourceWitness=True)
            time.sleep(0.05)
        code = W.DWORD()
        win(ExitCode(info.hProcess, C.byref(code)), "read exit code")
        exit_code = code.value
        need(closed_requested and exit_code == 0 and not timed_out.is_set(),
             "Native normal exit not established.")
        need(input_name() == original_input, "Input Desktop changed.")
        result["passed"] = True
        result["qualification"] = ("Framework-injected release QA target; not OS input, "
          "IME, presented pixels, exact installer or performance gate.")
    except BaseException as error:
        result["error"] = repr(error)
    finally:
        cleanup_errors = []
        def cleanup(label, action):
            try:
                return action()
            except BaseException as error:
                cleanup_errors.append({"step":label,"error":repr(error)})
                return None
        if timer:
            timer.cancel(); timer.join(2)
            if timer.is_alive():
                cleanup_errors.append({"step":"deadline thread","error":"still active"})
        def stop_child():
            nonlocal terminated
            if not info.hProcess: return
            state = Wait(info.hProcess, 0)
            need(state in (0,258), "Owned process wait failed.")
            if state == 258:
                terminated = True
                if assigned:
                    win(TerminateJob(job,125),"stop only own Job")
                else:
                    need(not resumed,"Unassigned running child.")
                    win(TerminateProcess(info.hProcess,125),
                        "stop owned suspended unassigned child")
                need(Wait(info.hProcess,5000)==0,"Owned child failed to stop.")
        cleanup("stop owned child",stop_child)
        def drain_job():
            if not job: return None
            until = time.monotonic()+5
            while True:
                account = ACCOUNTING()
                win(QueryJob(job,1,C.byref(account),C.sizeof(account),None),
                    "query own Job cleanup")
                if account.ActiveProcesses == 0: return 0
                if time.monotonic() >= until:
                    # Still only the fresh owned Job. Do not touch any other PID.
                    win(TerminateJob(job,125),"stop remaining own Job children")
                    raise RuntimeError("Owned Job failed to drain before cleanup bound.")
                time.sleep(.05)
        active = cleanup("drain owned Job",drain_job)
        for label,handle in (("thread",info.hThread),("process",info.hProcess)):
            if handle:
                cleanup("close owned "+label,
                        lambda handle=handle:win(Close(handle),"close owned handle"))
        if attribute_buffer is not None:
            cleanup("delete creation attribute list",
                    lambda:DeleteAttributes(attribute_buffer))
        if job:
            cleanup("close own kill-on-close Job",
                    lambda:win(Close(job),"close own Job"))
        if desktop:
            # Restore controller-thread association only, never input Desktop.
            cleanup("restore controller thread Desktop",
                    lambda:win(SetThreadDesktop(original_thread_desktop),
                               "restore controller thread Desktop"))
            cleanup("close own inactive Desktop",
                    lambda:win(CloseDesktop(desktop),"close own Desktop"))
        same_input = cleanup("verify input Desktop",
                             lambda:input_name()==original_input)
        result.update(exitCode=exit_code,ownJobTerminated=terminated,
          ownJobActiveProcesses=active,timedOut=timed_out.is_set(),
          inputDesktopUnchanged=same_input,cleanupErrors=cleanup_errors)
        result["passed"] = bool(result["passed"] and not terminated and
          not cleanup_errors and same_input and active==0)
        if log.exists():
            result["targetLogSHA256"] = cleanup("hash retained target log",
                                                lambda:sha(log))
        result["canonicalFiles"] = cleanup("hash retained public canonical",lambda:{
          p.name:{"bytes":p.stat().st_size,"sha256":sha(p)}
          for p in (run_root/"shared").glob("*") if p.is_file()})
        if cleanup_errors: result["passed"]=False
        (output/"result.json").write_text(json.dumps(result,indent=2)+"\n")
    print(json.dumps({"output":str(output),"passed":result["passed"]}))
    return 0 if result["passed"] else 1
if __name__ == "__main__":
    raise SystemExit(main())
