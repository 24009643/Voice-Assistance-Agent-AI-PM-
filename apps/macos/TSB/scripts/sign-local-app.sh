#!/bin/zsh

set -euo pipefail

app=${1:?"usage: sign-local-app.sh /absolute/path/to/TSB.app"}
[[ "$app" == /* && "$app" == *.app && -d "$app/Contents/MacOS" ]] || {
  print -u2 "expected an absolute macOS app path"
  exit 1
}

frameworks="$app/Contents/Frameworks"
onnx="$frameworks/onnxruntime.framework"
[[ -f "$onnx/Versions/A/onnxruntime" && -d "$onnx/Versions/A/Resources" ]] || {
  print -u2 "missing embedded onnxruntime version A"
  exit 1
}

/bin/rm -rf "$onnx/Versions/Current" "$onnx/onnxruntime" "$onnx/Resources"
/bin/ln -s A "$onnx/Versions/Current"
/bin/ln -s Versions/Current/onnxruntime "$onnx/onnxruntime"
/bin/ln -s Versions/Current/Resources "$onnx/Resources"
/bin/chmod +x "$onnx/Versions/A/onnxruntime"

while IFS= read -r -d '' dylib; do
  /usr/bin/codesign --force --sign - --timestamp=none "$dylib"
done < <(/usr/bin/find "$app/Contents/MacOS" -maxdepth 1 -type f -name '*.dylib' -print0)

while IFS= read -r -d '' framework; do
  /usr/bin/codesign --force --sign - --timestamp=none "$framework"
done < <(/usr/bin/find "$frameworks" -maxdepth 1 -type d -name '*.framework' -print0)

/usr/bin/codesign --force --sign - --timestamp=none "$app"
/usr/bin/codesign --verify --deep --strict --verbose=4 "$app"

print "$app"
