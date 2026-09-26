#!/usr/bin/env python3
"""Stop hook: phiên đã sửa code thì build lại và đọc toàn bộ Issue của Xcode
(error + warning, cả project) trước khi cho agent dừng.

Exit 2 = chặn dừng; stderr là danh sách issue trả về cho agent sửa.

Vì sao đọc .dia chứ không chỉ grep log: build incremental chỉ in warning của
file vừa được compile lại, còn Issue navigator của Xcode thì giữ warning của
mọi file. Swift ghi diagnostics từng file vào Objects-normal/<arch>/<File>.dia
và chỉ ghi đè khi file đó compile lại — đọc hết các .dia là ra đúng danh sách
Xcode đang hiển thị. Issue không phải Swift (asset catalog, linker, script
phase) lấy từ log và được nhớ trong build/hook/other-issues.json cho tới khi
task sinh ra nó chạy lại mà không báo nữa.

    SHOTDEX_BUILD_HOOK=0          tắt hook
    SHOTDEX_BUILD_HOOK_DEVICE=... tên hoặc UDID simulator (mặc định iPhone 17)
"""
import ctypes
import fcntl
import gzip
import json
import os
import pathlib
import re
import subprocess
import sys
import time

ROOT = pathlib.Path(os.environ.get("CLAUDE_PROJECT_DIR")
                    or pathlib.Path(__file__).resolve().parents[2])
STATE = ROOT / "build" / "hook"
DERIVED = ROOT / "build" / "sim"          # chung với /build, /sim, /screens
INTERMEDIATES = DERIVED / "Build" / "Intermediates.noindex" / "ShotDex.build" / "Debug-iphonesimulator"
LIBCLANG = ("/Applications/Xcode.app/Contents/Developer/Toolchains/"
            "XcodeDefault.xctoolchain/usr/lib/libclang.dylib")
MAX_BLOCKS = 3                             # quá số lần chặn liên tiếp này thì nhả, tránh vòng lặp vô tận
MAX_LINES = 80
DIAG_RE = re.compile(r"^(/[^:\n]+?)(?::(\d+))?(?::(\d+))?: (warning|error): (.+)$")
SEVERITY = {2: "warning", 3: "error", 4: "error"}


# ---------------------------------------------------------------- .dia (libclang)

class CXString(ctypes.Structure):
    _fields_ = [("data", ctypes.c_void_p), ("flags", ctypes.c_uint)]


class CXSourceLocation(ctypes.Structure):
    _fields_ = [("ptr_data", ctypes.c_void_p * 2), ("int_data", ctypes.c_uint)]


def load_libclang():
    try:
        lib = ctypes.CDLL(LIBCLANG)
    except OSError:
        return None
    vp, u = ctypes.c_void_p, ctypes.c_uint
    lib.clang_getCString.restype, lib.clang_getCString.argtypes = ctypes.c_char_p, [CXString]
    lib.clang_disposeString.argtypes = [CXString]
    lib.clang_loadDiagnostics.restype = vp
    lib.clang_loadDiagnostics.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_int), ctypes.POINTER(CXString)]
    lib.clang_disposeDiagnosticSet.argtypes = [vp]
    lib.clang_getNumDiagnosticsInSet.argtypes = [vp]
    lib.clang_getDiagnosticInSet.restype, lib.clang_getDiagnosticInSet.argtypes = vp, [vp, u]
    lib.clang_getDiagnosticSeverity.argtypes = [vp]
    lib.clang_getDiagnosticSpelling.restype, lib.clang_getDiagnosticSpelling.argtypes = CXString, [vp]
    lib.clang_getDiagnosticLocation.restype, lib.clang_getDiagnosticLocation.argtypes = CXSourceLocation, [vp]
    lib.clang_getFileName.restype, lib.clang_getFileName.argtypes = CXString, [vp]
    lib.clang_getSpellingLocation.argtypes = [CXSourceLocation, ctypes.POINTER(vp),
                                              ctypes.POINTER(u), ctypes.POINTER(u), ctypes.POINTER(u)]
    return lib


def dia_issues(lib, include_tests: bool) -> set:
    def text(cx):
        value = lib.clang_getCString(cx)
        lib.clang_disposeString(cx)
        return (value or b"").decode(errors="replace")

    issues = set()
    for dia in INTERMEDIATES.glob("*.build/Objects-normal/*/*.dia"):
        target = dia.parts[-4]
        if not include_tests and target.startswith("ShotDexTests"):
            continue
        err, err_text = ctypes.c_int(), CXString()
        dset = lib.clang_loadDiagnostics(str(dia).encode(), ctypes.byref(err), ctypes.byref(err_text))
        if not dset:
            continue
        for i in range(lib.clang_getNumDiagnosticsInSet(dset)):
            diag = lib.clang_getDiagnosticInSet(dset, i)
            severity = SEVERITY.get(lib.clang_getDiagnosticSeverity(diag))
            if not severity:
                continue
            f, line, col, off = ctypes.c_void_p(), ctypes.c_uint(), ctypes.c_uint(), ctypes.c_uint()
            lib.clang_getSpellingLocation(lib.clang_getDiagnosticLocation(diag), ctypes.byref(f),
                                          ctypes.byref(line), ctypes.byref(col), ctypes.byref(off))
            path = text(lib.clang_getFileName(f)) if f.value else ""
            src = pathlib.Path(path)
            # Chỉ tin diagnostic của chính file đó: compile theo batch, một .dia
            # còn mang cả diagnostic của file khác cùng batch, và bản đó không
            # được ghi lại khi file kia sửa xong — warning đã sửa vẫn hiện.
            # .dia cũ hơn file nguồn = file không còn được build (bị bỏ khỏi target).
            if (src.stem != dia.stem or not in_project(path) or not src.exists()
                    or src.stat().st_mtime > dia.stat().st_mtime):
                continue
            issues.add((path, line.value, col.value, severity, text(lib.clang_getDiagnosticSpelling(diag))))
        lib.clang_disposeDiagnosticSet(dset)
    return issues


# ---------------------------------------------------------------- helpers

def in_project(path: str) -> bool:
    p = pathlib.Path(path)
    try:
        rel = p.relative_to(ROOT)
    except ValueError:
        return False
    return bool(rel.parts) and rel.parts[0] != "build"


def resolve_device() -> str:
    want = os.environ.get("SHOTDEX_BUILD_HOOK_DEVICE", "iPhone 17")
    if re.fullmatch(r"[0-9A-F-]{36}", want):
        return want
    try:
        out = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"],
                             capture_output=True, text=True, timeout=30).stdout
        for devices in json.loads(out)["devices"].values():
            for d in devices:
                if d["name"] == want:
                    return d["udid"]      # hai "iPhone 17" khác runtime: build thì chọn cái nào cũng được
    except Exception:
        pass
    return ""


def xcodebuild(action: str, log_path: pathlib.Path) -> int:
    udid = resolve_device()
    dest = f"id={udid}" if udid else "generic/platform=iOS Simulator"
    cmd = ["xcodebuild", "-project", "ShotDex.xcodeproj", "-scheme", "ShotDex",
           "-destination", dest, "-derivedDataPath", str(DERIVED), action]
    with open(log_path, "w") as log:
        return subprocess.run(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT).returncode


def parse_log(text: str):
    """-> (lỗi build bất kỳ, {file không-Swift: issue})."""
    errors, other = set(), {}
    for raw in re.split(r"[\r\n]+", text):
        m = DIAG_RE.match(raw.strip())
        if m:
            path, line, col, severity, msg = m.groups()
            item = (path, int(line or 0), int(col or 0), severity, msg.strip())
            if path.endswith(".swift"):
                if severity == "error":
                    errors.add(item)          # .dia cũng có, set sẽ gộp
            elif in_project(path):
                other.setdefault(path, set()).add(item)
        elif re.match(r"^(?:[\w.-]+: )?error: ", raw):   # ld/xcodebuild/script: không có đường dẫn
            errors.add(("", 0, 0, "error", raw.strip()))
    return errors, other


def seed_from_activity_logs() -> dict:
    """Lần đầu chưa có cache: lấy issue không-Swift từ log build cũ của Xcode
    (build/sim/Logs/Build/*.xcactivitylog, mới nhất thắng), vì task sinh ra
    chúng (vd. actool) có thể đã được cache và không chạy lại lần này."""
    seeded = {}
    logs = sorted((DERIVED / "Logs" / "Build").glob("*.xcactivitylog"),
                  key=lambda p: p.stat().st_mtime, reverse=True)[:30]
    for path in logs:
        try:
            text = gzip.open(path).read().decode("utf-8", "replace")
        except Exception:
            continue
        for file, items in parse_log(text)[1].items():
            seeded.setdefault(file, items)
    return seeded


def log_issues(log: str, cache_path: pathlib.Path):
    """(lỗi build bất kỳ, issue không-Swift có nhớ qua các lần build)."""
    errors, fresh = parse_log(log)
    try:
        cache = {k: {tuple(i) for i in v} for k, v in json.loads(cache_path.read_text()).items()}
    except Exception:
        cache = seed_from_activity_logs()
    # Task của file đó chạy lại lần này: một dòng tiêu đề task (không thụt lề)
    # nhắc tới nó. ExecuteExternalTool thì không tính — actool
    # --print-asset-tag-combinations chạy mọi lần build mà không compile catalog.
    headers = [ln for ln in re.split(r"[\r\n]+", log)
               if ln[:1].isalpha() and not ln.startswith("ExecuteExternalTool") and not DIAG_RE.match(ln)]
    ran = {p for p in cache if any(p in ln for ln in headers)}
    for path in list(cache):
        if path in ran or not pathlib.Path(path).exists():
            cache.pop(path)
    cache.update(fresh)
    cache_path.write_text(json.dumps({k: sorted(v) for k, v in cache.items()}, ensure_ascii=False, indent=1))
    other = set().union(*cache.values()) if cache else set()
    return errors, other


def fmt(item) -> str:
    path, line, col, severity, msg = item
    if not path:
        return msg if msg.startswith(("error", "warning")) or ": error: " in msg else f"{severity}: {msg}"
    rel = str(pathlib.Path(path).relative_to(ROOT)) if in_project(path) else path
    loc = f"{rel}:{line}:{col}" if line else rel
    return f"{loc}: {severity}: {msg}"


# ---------------------------------------------------------------- main

def main() -> int:
    if os.environ.get("SHOTDEX_BUILD_HOOK") == "0":
        return 0
    try:
        data = json.load(sys.stdin)
    except Exception:
        data = {}
    session = data.get("session_id", "default")
    dirty = STATE / f"dirty-{session}"
    blocks = STATE / f"blocks-{session}"
    if not dirty.exists():
        return 0
    if not data.get("stop_hook_active"):
        blocks.unlink(missing_ok=True)       # lượt mới của người dùng: đếm lại

    touched = dirty.read_text().splitlines()
    with_tests = any(p.startswith(("ShotDexTests/", "<bash>")) for p in touched)
    action = "build-for-testing" if with_tests else "build"

    STATE.mkdir(parents=True, exist_ok=True)
    log_path = STATE / "last-build.log"
    started = time.time()
    with open(STATE / "build.lock", "w") as lock:  # hai agent chung checkout: build lần lượt
        fcntl.flock(lock, fcntl.LOCK_EX)
        status = xcodebuild(action, log_path)
        log = log_path.read_text(errors="replace")
        errors, other = log_issues(log, STATE / "other-issues.json")
        lib = load_libclang()
        swift = dia_issues(lib, with_tests) if lib else set()
    elapsed = time.time() - started

    issues = sorted(errors | other | swift, key=lambda i: (i[3] != "error", i[0], i[1], i[2]))
    if status != 0 and not any(i[3] == "error" for i in issues):
        tail = "\n".join(log.splitlines()[-15:])
        issues.insert(0, ("", 0, 0, "error", f"BUILD FAILED, không đọc được lỗi — đuôi log:\n{tail}"))
    if lib is None:
        issues.append(("", 0, 0, "warning", f"không nạp được {LIBCLANG}; chỉ thấy warning của file vừa compile"))

    if not issues:
        dirty.unlink(missing_ok=True)
        blocks.unlink(missing_ok=True)
        print(json.dumps({"systemMessage": f"build-check: {action} sạch, 0 issue ({elapsed:.0f}s)"}))
        return 0

    n_err = sum(i[3] == "error" for i in issues)
    n_warn = len(issues) - n_err
    count = int(blocks.read_text() or 0) + 1 if blocks.exists() else 1
    if count > MAX_BLOCKS:
        blocks.unlink(missing_ok=True)
        dirty.unlink(missing_ok=True)        # lượt sau chỉ kiểm lại khi lại có sửa code
        print(json.dumps({"systemMessage":
                          f"build-check: còn {n_err} error, {n_warn} warning sau {MAX_BLOCKS} lượt sửa — "
                          f"nhả cho dừng. Log: build/hook/last-build.log"}))
        return 0
    blocks.write_text(str(count))

    lines = [fmt(i) for i in issues]
    shown = lines[:MAX_LINES]
    if len(lines) > MAX_LINES:
        shown.append(f"... và {len(lines) - MAX_LINES} issue nữa (build/hook/last-build.log)")
    print(f"build-check ({action}, {elapsed:.0f}s, lượt {count}/{MAX_BLOCKS}): "
          f"{'BUILD FAILED' if status else 'build ok'} — {n_err} error, {n_warn} warning trong Issue "
          "navigator của Xcode. Sửa hết (warning cũng vậy, kể cả file không do bạn sửa), build lại, rồi mới dừng. "
          "Warning nào không nên sửa thì nói rõ lý do với người dùng.\n" + "\n".join(shown), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
