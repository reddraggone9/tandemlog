"""Read-only proof for an already-built synthetic lab artifact; never rebuild."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def gh(path):
    return subprocess.check_output(["gh", "api", path])


artifact_id = os.environ["LAB_ARTIFACT_ID"]
expected = os.environ["LAB_ARTIFACT_SHA256"]
if not re.fullmatch(r"[1-9][0-9]{0,19}", artifact_id):
    raise ValueError("Invalid artifact ID")
if not re.fullmatch(r"[a-f0-9]{64}", expected):
    raise ValueError("Invalid expected archive digest")
endpoint = f"repos/reddraggone9/tandemlog/actions/artifacts/{artifact_id}"
meta = json.loads(gh(endpoint))
if (meta["name"] != "isolated-text-android-lab-runtime-pending"
    or meta["expired"]
    or meta["digest"] != f"sha256:{expected}"
    or meta["workflow_run"]["id"] != 37222225866
    or meta["workflow_run"]["head_sha"] != "6022b7535392669ce2db2d764ec12396a71adf2c"):
    raise ValueError("Artifact context mismatch")
out = Path("lab-inspection")
out.mkdir()
archive = gh(endpoint + "/zip")
if sha(archive) != expected:
    raise ValueError("Archive digest mismatch")
archive_path = out / "artifact.zip"
archive_path.write_bytes(archive)
with zipfile.ZipFile(archive_path) as z:
    if z.testzip() is not None:
        raise ValueError("ZIP CRC mismatch")
    candidates = [n for n in z.namelist() if n.endswith("editor_lab/build/app/outputs/flutter-apk/app-debug.apk")]
    if len(candidates) != 1:
        raise ValueError("APK count/path mismatch")
    apk = out / "app-debug.apk"
    with z.open(candidates[0]) as src, apk.open("wb") as dst:
        shutil.copyfileobj(src, dst)
    apk_hash = sha(apk.read_bytes())
    declared = z.read("evidence/editor-android-apk-sha256.txt").decode().split()[0]
    if apk_hash != declared:
        raise ValueError("APK checksum manifest mismatch")
    sdk = Path(os.environ["ANDROID_HOME"])
    signer_output = subprocess.check_output([str(sdk / "build-tools/36.0.0/apksigner"), "verify", "--verbose", "--print-certs", str(apk)], text=True)
    cert = re.search(r"Signer #1 certificate SHA-256 digest: ([a-f0-9]{64})", signer_output)
    if cert is None or "CN=Android Debug" not in signer_output:
        raise ValueError("Expected isolated debug signer missing")
    badging = subprocess.check_output([str(sdk / "build-tools/36.0.0/aapt"), "dump", "badging", str(apk)], text=True)
    if ("name='com.reddraggone9.tandemlog.yrs_editor_lab' versionCode='1' versionName='0.0.0'" not in badging
        or "application-debuggable" not in badging
        or "sdkVersion:'24'" not in badging
        or "targetSdkVersion:'36'" not in badging
        or "native-code: 'arm64-v8a' 'x86_64'" not in badging):
        raise ValueError("Lab APK identity/version/ABI mismatch")
    libraries = {}
    strip = sdk / "ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
    with zipfile.ZipFile(apk) as a:
        for abi, target in [("arm64-v8a", "aarch64-linux-android"), ("x86_64", "x86_64-linux-android")]:
            payload = a.read(f"lib/{abi}/libtandemlog_yrs_spike.so")
            original = z.read(f"target/{target}/release/libtandemlog_yrs_spike.so")
            lib = out / f"{abi}.so"
            lib.write_bytes(original)
            subprocess.run([str(strip), "--strip-unneeded", str(lib)], check=True)
            if lib.read_bytes() != payload:
                raise ValueError("Packaged native payload differs from stripped cross-build")
            libraries[abi] = {"unstripped_sha256": sha(original), "packaged_sha256": sha(payload), "packaged_size": len(payload)}
result = {"artifact_id": int(artifact_id), "artifact_run":37222225866, "source":meta["workflow_run"]["head_sha"], "archive_sha256":expected, "archive_size":len(archive), "apk_sha256":apk_hash, "apk_size":apk.stat().st_size, "certificate_sha256":cert.group(1), "package":"com.reddraggone9.tandemlog.yrs_editor_lab", "version_name":"0.0.0", "version_code":1, "debuggable":True, "min_sdk":24, "target_sdk":36, "libraries":libraries, "runtime":"not-run", "real_os_ime":"not-run", "synthetic_only":True, "production_adoption":False}
(out / "verification.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))
