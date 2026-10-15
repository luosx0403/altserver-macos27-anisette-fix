#!/bin/bash
set -euo pipefail

recipe_root="$(cd "$(dirname "$0")/.." && pwd)"
source_root="$(cd "${1:?Usage: build_v1_3_0_ci.sh SOURCE DERIVED_DATA OUTPUT}" && pwd)"
derived_data="${2:?Missing absolute DerivedData path}"
output_dir="${3:?Missing absolute output directory}"
[[ "$derived_data" = /* && "$output_dir" = /* ]]
mkdir -p "$derived_data" "$output_dir"

cd "$source_root"
test "$(git rev-parse HEAD)" = ddb4415cc6aeeb3145de33a29f7064292a45d895
test "$(git -C Dependencies/AltSign rev-parse HEAD)" = 832d9cec339ea6ef6891011833dbb7227b028a29

for patch in "$recipe_root"/compatibility/v1.3.0/patches/*.patch; do
    git apply --check --ignore-whitespace "$patch"
    git apply --ignore-whitespace "$patch"
done
python3 - "$derived_data" <<'PY'
import pathlib, sys
p = pathlib.Path('Dependencies/AltSign/Package.swift')
text = p.read_text()
assert text.count('<ALTSTORE_DERIVED_DATA>') == 1
p.write_text(text.replace('<ALTSTORE_DERIVED_DATA>', sys.argv[1]))
PY

{
    echo 'AltServer v1.3.0 source candidate; not an official AltServer release'
    echo "Workflow: https://github.com/${GITHUB_REPOSITORY:-local}/actions/runs/${GITHUB_RUN_ID:-local}"
    echo "Recipe commit: ${GITHUB_SHA:-local}"
    echo "AltStore: $(git rev-parse HEAD)"
    git submodule status --recursive
    sw_vers
    xcodebuild -version
} > "$output_dir/build-info.txt"

xcodebuild -workspace AltStore.xcworkspace -scheme AltServer \
    -configuration Release -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$derived_data" \
    MACOSX_DEPLOYMENT_TARGET=13.0 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
    MARKETING_VERSION=1.8-pr1834-test CURRENT_PROJECT_VERSION=1834 \
    CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
    ENABLE_USER_SCRIPT_SANDBOXING=NO build 2>&1 | tee "$output_dir/build.log"

app="$derived_data/Build/Products/Release/AltServer.app"
test -x "$app/Contents/MacOS/AltServer"
test -d "$app/Contents/Frameworks/OpenSSL.framework"
codesign --verify --deep --strict --verbose=2 "$app"
lipo -verify_arch arm64 "$app/Contents/MacOS/AltServer"
otool -L "$app/Contents/MacOS/AltServer" > "$output_dir/dependencies.txt"
nm "$app/Contents/MacOS/AltServer" > "$output_dir/symbols.txt"
grep -q 'alt_ccsrp_' "$output_dir/symbols.txt"
rm "$output_dir/symbols.txt"
shasum -a 256 "$app/Contents/MacOS/AltServer" | awk '{print $1 "  AltServer.app/Contents/MacOS/AltServer"}' > "$output_dir/executable-sha256.txt"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output_dir/AltServer-v1.3.0-arm64.zip"
cd "$output_dir"
shasum -a 256 AltServer-v1.3.0-arm64.zip > SHA256SUMS.txt
