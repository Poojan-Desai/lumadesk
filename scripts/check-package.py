#!/usr/bin/env python3
"""Exercise package publication/failure handling with isolated tool doubles.

This checks filesystem behavior, not Swift compilation, archive validity, or an
Apple signature. Run the real package script and codesign for those separately.
"""
from pathlib import Path
import os
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts/package-app.sh"
checks = 0


def check(name, condition):
    global checks
    if not condition:
        raise AssertionError(name)
    checks += 1


with tempfile.TemporaryDirectory(prefix="Luma package checks ") as temporary:
    folder = Path(temporary)
    commands = folder / "tools"
    commands.mkdir()
    binary = folder / "binary"
    binary.mkdir()
    (binary / "LumaDesk").write_bytes(b"fresh-test-binary")
    destination = folder / "output with spaces"
    destination.mkdir()
    app = destination / "LumaDesk.app"
    archive = destination / "LumaDesk-macOS.zip"

    doubles = {
        "swift": '''#!/bin/bash
set -eu
if [[ "${1:-}" == build ]]; then
  if [[ "${LUMA_TEST_FAIL_BUILD:-0}" == 1 ]]; then exit 21; fi
  if [[ "$*" == *--show-bin-path* ]]; then printf '%s\\n' "$LUMA_TEST_BIN"; fi
else
  mkdir -p "$2"
fi
''',
        "iconutil": '''#!/bin/bash
set -eu
printf 'test-icon' > "$5"
''',
        "codesign": '''#!/bin/bash
set -eu
if [[ "${LUMA_TEST_FAIL_SIGN:-0}" == 1 ]]; then exit 22; fi
''',
        "ditto": '''#!/bin/bash
set -eu
printf 'fresh-test-archive' > "${@: -1}"
''',
        "mv": '''#!/bin/bash
set -eu
if [[ "${LUMA_TEST_FAIL_INSTALL:-0}" == 1 && "$1" == */.lumadesk-package.*/LumaDesk-macOS.zip && "$2" == "$LUMA_TEST_DESTINATION/LumaDesk-macOS.zip" ]]; then exit 23; fi
exec /bin/mv "$@"
''',
    }
    for name, content in doubles.items():
        path = commands / name
        path.write_text(content)
        path.chmod(0o755)
    environment = {
        **os.environ,
        "PATH": f"{commands}:{os.environ['PATH']}",
        "LUMA_TEST_BIN": str(binary),
        "LUMA_TEST_DESTINATION": str(destination),
    }

    def run(**options):
        return subprocess.run(["bash", str(SCRIPT), str(destination)], cwd=ROOT,
                              env={**environment, **options}, capture_output=True, text=True)

    def plant_old_outputs():
        (app / "Contents/Resources").mkdir(parents=True, exist_ok=True)
        (app / "Contents/Resources/obsolete.txt").write_bytes(b"prior-private-test-resource")
        archive.write_bytes(b"previous-test-archive")

    plant_old_outputs()
    for failure in ("LUMA_TEST_FAIL_BUILD", "LUMA_TEST_FAIL_SIGN", "LUMA_TEST_FAIL_INSTALL"):
        result = run(**{failure: "1"})
        check(f"{failure} is reported", result.returncode != 0)
        check(f"{failure} preserves previous app", (app / "Contents/Resources/obsolete.txt").read_bytes() == b"prior-private-test-resource")
        check(f"{failure} preserves previous archive", archive.read_bytes() == b"previous-test-archive")
        check(f"{failure} leaves no private staging files", not list(destination.glob(".lumadesk-package.*")))

    lock = destination / ".lumadesk-package.lock"
    lock.mkdir()
    result = run()
    check("concurrent package lock is respected", result.returncode != 0)
    check("another invocation's lock is preserved", lock.is_dir())
    check("lock conflict preserves existing outputs", (app / "Contents/Resources/obsolete.txt").exists() and archive.read_bytes() == b"previous-test-archive")
    lock.rmdir()
    check("lock conflict leaves no staging artifacts", not list(destination.glob(".lumadesk-package.*")))

    result = run()
    check("successful package command", result.returncode == 0)
    check("obsolete files excluded from clean bundle", not (app / "Contents/Resources/obsolete.txt").exists())
    check("current binary installed", (app / "Contents/MacOS/LumaDesk").read_bytes() == b"fresh-test-binary")
    check("new archive installed", archive.read_bytes() == b"fresh-test-archive")
    metadata = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    check("preview version is accurate", metadata["CFBundleShortVersionString"] == "0.2.0")
    check("source provenance is explicit", (len(metadata["LumaDeskSourceCommit"]) == 40 and metadata["LumaDeskSourceState"] in {"clean", "modified"}) or (metadata["LumaDeskSourceCommit"] == "unavailable" and metadata["LumaDeskSourceState"] == "unavailable"))
    check("successful package leaves no staging files", not list(destination.glob(".lumadesk-package.*")))
    (app / "Contents/Resources/obsolete-again.txt").write_bytes(b"second-run-resource")
    result = run()
    check("repeated packaging succeeds without retaining stale files", result.returncode == 0 and not (app / "Contents/Resources/obsolete-again.txt").exists())

print(f"{checks} package staging/failure-recovery checks passed (tool doubles; not native signing validation)")
