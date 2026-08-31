from pathlib import Path
import subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
cmds=[
    [sys.executable,str(ROOT/"tests/security/test_f3_package_config.py")],
    ["node",str(ROOT/"tests/workflows/test_workflow_import.js")],
    ["node",str(ROOT/"tests/integration/test_f3_media_drive.js")],
]
for cmd in cmds:
    print(">>>"," ".join(cmd))
    r=subprocess.run(cmd,cwd=ROOT)
    if r.returncode: raise SystemExit(r.returncode)
print("F3 STATIC SUITE: PASS")
