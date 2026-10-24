"""Build-only QA artifact packager; never install or run the application."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

TARGET = "integration_test/windows_release_widget_viability.dart"
TARGET_SHA = "63b506d1077114c518762512b7348680ace8fe5c0fad33bd172647bb15072cdd"
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def regular(p):
    if not p.is_file() or p.is_symlink() or (
            getattr(p.lstat(), "st_file_attributes", 0) & 0x400):
        raise RuntimeError("Regular file required: " + str(p))
def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--source",type=Path,required=True)
    parser.add_argument("--output",type=Path,required=True)
    args=parser.parse_args()
    source=args.source.resolve(strict=True)
    output=args.output.absolute()
    if output.exists() or output.is_symlink():
        raise RuntimeError("QA output must be absent.")
    temp=Path(os.environ["RUNNER_TEMP"]).resolve(strict=True)
    source.relative_to(temp); output.relative_to(temp)
    if source==output or source in output.parents or output in source.parents:
        raise RuntimeError("QA source/output must be separate sibling trees.")
    target=source/TARGET;regular(target)
    if sha(target)!=TARGET_SHA: raise RuntimeError("Reviewed target bytes differ.")
    bundle=source/"build/windows/x64/runner/Release"
    files={}
    for p in sorted(bundle.rglob("*")):
        if p.is_symlink() or (getattr(p.lstat(),"st_file_attributes",0)&0x400):
            raise RuntimeError("Reparse entry refused.")
        if p.is_file():
            regular(p);files[p.relative_to(bundle).as_posix()]={"bytes":p.stat().st_size,
                                                              "sha256":sha(p)}
    if not {"tandemlog.exe","tandemlog_text.dll","flutter_windows.dll",
            "data/app.so"}.issubset(files):
        raise RuntimeError("Expected separate release payload is missing.")
    revision=subprocess.check_output(["git","-C",str(source),"rev-parse","HEAD"],
                                     text=True).strip()
    if revision!=os.environ["GITHUB_SHA"]:
        raise RuntimeError("QA checkout differs from dispatched revision.")
    dirty=subprocess.check_output(["git","-C",str(source),"status","--porcelain",
                                  "--untracked-files=no"],text=True).strip()
    if dirty:
        generated=[f"{platform}/flutter/{name}" for platform in ("linux","windows")
                   for name in ("generated_plugin_registrant.cc","generated_plugin_registrant.h","generated_plugins.cmake")]
        delta=subprocess.check_output(["git","-C",str(source),"diff","--no-color",
                                       "--no-ext-diff","--no-textconv","--",*generated],text=True)
        byteproof={name:{"workingSHA256":sha(source/name),
                         "gitSHA256":hashlib.sha256(subprocess.check_output(
                             ["git","-C",str(source),"show","HEAD:"+name])).hexdigest()}
                   for name in generated}
        raise RuntimeError("Tracked source changed during QA build (first8192 chars): " + repr(dirty[:8192])
                           + "; generated raw byte proofs: " + repr(byteproof)
                           + "; generated diff (first16384 chars): " + repr(delta[:16384]))
    sdk=Path(os.environ["RUNNER_TEMP"])/"flutter"
    sdk_revision=subprocess.check_output(["git","-C",str(sdk),"rev-parse","HEAD"],
                                         text=True).strip()
    if sdk_revision!="6a19cca56475dbfba1478ee68d7bd0c2ef891da1":
        raise RuntimeError("SDK differs from existing reviewed action.")
    pins={}
    for root in ("lib","windows/runner","native/text_engine"):
        for p in sorted((source/root).rglob("*")):
            if p.is_file() and (p.suffix in (".dart",".cpp",".h",".rs",".toml",".lock")
                               or p.name=="CMakeLists.txt"):
                regular(p);pins[p.relative_to(source).as_posix()]=sha(p)
    for rel in ("pubspec.yaml","pubspec.lock","windows/CMakeLists.txt",
                ".github/actions/setup-flutter/action.yml",
                ".github/actions/setup-text-engine/action.yml",TARGET,
                "integration_test/native_text_fixtures.dart",
                "tool/windows_widget_qa/probe_cost_trace.dart"):
        p=source/rel;regular(p);pins[rel]=sha(p)
    for rel in ("tool/build_text_engine.py","tool/bootstrap_text_engine.py",
                "tool/native_build_gates.py","windows/flutter/generated_plugins.cmake",
                "windows/flutter/generated_plugin_registrant.cc",
                "windows/flutter/generated_plugin_registrant.h"):
        p=source/rel
        regular(p);pins[rel]=sha(p)
    generated={}
    for rel in (".dart_tool/package_config.json",".flutter-plugins-dependencies"):
        p=source/rel
        regular(p);generated[rel]=sha(p)
    for p in sorted((source/"windows/flutter/ephemeral").glob("*.cmake")):
        regular(p);generated[p.relative_to(source).as_posix()]=sha(p)
    metadata={"version":1,"qaOnly":True,"installer":False,"mode":"release",
      "sourceRevision":revision,"runId":os.environ["GITHUB_RUN_ID"],
      "flutterSDKRevision":sdk_revision,"productInputsUnchangedDuringBuild":True,
      "target":TARGET,"targetSHA256":TARGET_SHA,"executable":"tandemlog.exe",
      "helperPins":{name:sha(source/"tool/windows_widget_qa"/name) for name in
                    ("windows_widget_controller.py","windows_widget_controller.ps1","package_qa.py")},
      "nativeLibrary":"tandemlog_text.dll","files":files,"sourcePins":pins,
      "signedReleaseAttribution":False,"appExecuted":False,
      "nativeABISmokeExecuted":True,
      "generatedInputPins":generated,"completeDependencySourceClosureClaimed":False,
      "qualification":"Separate test-entrypoint AOT build only; no app execution, "
        "installer, native OS input/IME, compositor presentation or release-gate pass. "
        "Existing verify_payload performs native DLL ABI smoke requests."}
    output.mkdir()
    shutil.copytree(bundle,output/"bundle")
    (output/"qa-artifact.json").write_text(json.dumps(metadata,indent=2)+"\n")
    for name in ("windows_widget_controller.py","windows_widget_controller.ps1","package_qa.py"):
        shutil.copyfile(source/"tool/windows_widget_qa"/name,output/name)
    sums={p.relative_to(output).as_posix():sha(p) for p in sorted(output.rglob("*"))
          if p.is_file()}
    (output/"QA-SHA256SUMS.txt").write_text("".join(
        digest+"  "+rel+"\n" for rel,digest in sums.items()))
    print(json.dumps({"output":str(output),"manifestSHA256":sha(output/"qa-artifact.json"),
                      "qaOnly":True,"appExecuted":False,"nativeABISmokeExecuted":True}))
if __name__=="__main__": main()
