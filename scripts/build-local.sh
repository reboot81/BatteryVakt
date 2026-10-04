#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Keep this identity between builds; never silently generate a replacement.
signer="work/tools/apple-codesign-0.29.0-aarch64-apple-darwin/rcodesign"
certificate="work/signing/root-certificate.pem"
private_key="work/signing/private-key.pk8.pem"
for required in "$signer" "$certificate" "$private_key"; do
    if [[ ! -f "$required" ]]; then
        echo "Missing local signing file: $required. Restore the original identity before building."
        exit 1
    fi
done

mkdir -p work
swiftc -module-cache-path work/ModuleCache Sources/BatteryWatch/Models.swift \
    Sources/BatteryWatch/BatteryProvider.swift Sources/BatteryWatch/HIDPPWire.swift \
    Tests/HIDPPWireTests.swift -o work/hidpp-wire-tests
work/hidpp-wire-tests

# A fresh build directory avoids obsolete bundle resources from earlier builds.
build_dir=$(mktemp -d "$PWD/work/build.XXXXXX")
xcodebuild -project BatteryWatch.xcodeproj -scheme BatteryVakt -configuration Debug \
    -derivedDataPath "$build_dir" CODE_SIGNING_ALLOWED=NO build >"$build_dir/build.log" 2>&1
app="$build_dir/Build/Products/Debug/BatteryVakt.app"
# Finder metadata may be attached automatically in a synced Documents folder.
xattr -r -d com.apple.FinderInfo "$app" 2>/dev/null || true
"$signer" sign --pem-file "$certificate" --pem-file "$private_key" \
    --timestamp-url none --code-signature-flags runtime "$app"

# Do not publish automatically unless Apple's validator accepts the bundle.
codesign --verify --deep --strict --verbose=2 "$app"
codesign -d -r- "$app"
mkdir -p outputs
if [[ -e outputs/BatteryVakt.app ]]; then
    backup_dir=$(mktemp -d "$PWD/work/previous-app.XXXXXX")
    mv outputs/BatteryVakt.app "$backup_dir/BatteryVakt.app"
    echo "Previous app saved in $backup_dir"
fi
ditto --norsrc --noextattr "$app" outputs/BatteryVakt.app
xattr -r -d com.apple.FinderInfo outputs/BatteryVakt.app 2>/dev/null || true
codesign --verify --deep --strict --verbose=2 outputs/BatteryVakt.app
echo "Ready: $PWD/outputs/BatteryVakt.app"
