#!/usr/bin/env python3
"""Sign this ad-hoc test app with the permissions its bundled libraries need."""
import pathlib
import plistlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1]).resolve()
diagnostics = pathlib.Path(sys.argv[2]).resolve()
diagnostics.mkdir(parents=True, exist_ok=True)


def sign_local_executable(target, label):
    original = subprocess.run(
        ['codesign', '-d', '--entitlements', ':-', str(target)],
        check=True, capture_output=True,
    ).stdout
    entitlements = plistlib.loads(original) if original.strip() else {}
    # Ad-hoc code has no Team ID. Hardened Runtime's default library validation
    # rejects its own non-platform frameworks even when every signature verifies.
    entitlements['com.apple.security.cs.disable-library-validation'] = True
    path = diagnostics / f'{label}-entitlements.plist'
    path.write_bytes(plistlib.dumps(entitlements))
    subprocess.run([
        'codesign', '--force', '--sign', '-', '--options', 'runtime',
        '--timestamp=none', '--entitlements', str(path), str(target),
    ], check=True)


helper = app / 'Contents/Library/LoginItems/LaunchAtLoginHelper.app'
subprocess.run([
    'codesign', '--force', '--sign', '-', '--timestamp=none',
    '--preserve-metadata=entitlements,flags', str(helper),
], check=True)
sign_local_executable(app / 'Contents/MacOS/altjit', 'altjit')
sign_local_executable(app, 'altserver')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
