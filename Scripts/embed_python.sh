#!/bin/bash
set -euo pipefail
case "$CODESIGNING_FOLDER_PATH" in *.app|*.appex) ;; *) echo "Invalid product bundle path"; exit 1 ;; esac
runtime="Vendor/Python.xcframework"
identity="$(printenv EXPANDED_CODE_SIGN_IDENTITY || true)"
if [ -z "$identity" ]; then identity="-"; fi
export EXPANDED_CODE_SIGN_IDENTITY="$identity"
export EXPANDED_CODE_SIGN_IDENTITY_NAME="Embedded Python"
export OTHER_CODE_SIGN_FLAGS="$(printenv OTHER_CODE_SIGN_FLAGS || true)"
export PLATFORM_FAMILY_NAME="iOS"
if [ "$EFFECTIVE_PLATFORM_NAME" = "-iphonesimulator" ]; then
  export ARCHS="$(uname -m)"
else
  export ARCHS="arm64"
fi
mkdir -p "$CODESIGNING_FOLDER_PATH/python_app" "$CODESIGNING_FOLDER_PATH/python_packages"
rsync -a --delete --exclude '__pycache__' --exclude '*.pyc' "$PROJECT_DIR/PythonApp/" "$CODESIGNING_FOLDER_PATH/python_app/"
rsync -a --delete --exclude '__pycache__' --exclude '*.pyc' "$PROJECT_DIR/Vendor/python_packages/" "$CODESIGNING_FOLDER_PATH/python_packages/"
source "$PROJECT_DIR/$runtime/build/utils.sh"
install_python "$runtime" python_packages
if [ "$TARGET_NAME" = "DownloadShare" ]; then
  python3 "$PROJECT_DIR/Scripts/relocate_share_frameworks.py" "$CODESIGNING_FOLDER_PATH"
fi
