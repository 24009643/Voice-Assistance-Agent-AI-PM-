#!/bin/zsh

set -euo pipefail

app=${1:?"usage: test-local-signing.sh /path/to/TSB.app"}
framework="$app/Contents/Frameworks/onnxruntime.framework"

[[ -d "$app" ]] || { print -u2 "missing app: $app"; exit 1; }
[[ -d "$framework/Versions/A" ]] || { print -u2 "missing onnxruntime version A"; exit 1; }
[[ -L "$framework/Versions/Current" ]] || { print -u2 "onnxruntime Versions/Current must be a symlink"; exit 1; }
[[ "$(readlink "$framework/Versions/Current")" == "A" ]] || { print -u2 "onnxruntime Versions/Current must point to A"; exit 1; }
[[ -L "$framework/onnxruntime" ]] || { print -u2 "onnxruntime root executable must be a symlink"; exit 1; }
[[ "$(readlink "$framework/onnxruntime")" == "Versions/Current/onnxruntime" ]] || { print -u2 "onnxruntime root executable has the wrong target"; exit 1; }
[[ -L "$framework/Resources" ]] || { print -u2 "onnxruntime Resources must be a symlink"; exit 1; }
[[ "$(readlink "$framework/Resources")" == "Versions/Current/Resources" ]] || { print -u2 "onnxruntime Resources has the wrong target"; exit 1; }

codesign --verify --deep --strict --verbose=4 "$app"
signature=$(codesign -dvvv "$app" 2>&1)
[[ "$signature" == *$'\nSignature=adhoc\n'* ]] || { print -u2 "app is not ad hoc signed"; exit 1; }

print "local signing gate passed"
