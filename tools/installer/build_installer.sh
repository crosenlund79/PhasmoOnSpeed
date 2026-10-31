#!/usr/bin/env bash
# Exports SPECTRAL RUN for Windows and packs it into an NSIS installer.
#   GODOT=/path/to/godot-4.3 tools/installer/build_installer.sh
# Needs the Godot 4.3 export templates (windows_release_x86_64.exe), makensis and
# Python with LIEF + Pillow (pip install lief pillow) to stamp the game icon and
# version into the .exe (Godot 4.3 itself would need rcedit for that).
# Output: export/windows/SpectralRun.{exe,pck} and
#         export/installer/TheWitcheningTales-Setup-<version>.exe   (export/ is not committed)
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
VERSION=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)
mkdir -p export/windows export/installer
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Windows Desktop" export/windows/SpectralRun.exe
test -s export/windows/SpectralRun.exe && test -s export/windows/SpectralRun.pck
python3 tools/icon/make_icon.py >/dev/null
python3 tools/installer/stamp_exe.py export/windows/SpectralRun.exe icon.png "$VERSION"
makensis -V2 -DVERSION="$VERSION" -DSRC="$(pwd)/export/windows" \
  -DOUTFILE="$(pwd)/export/installer/TheWitcheningTales-Setup-$VERSION.exe" -DICON="$(pwd)/icon.ico" tools/installer/spectral_run.nsi
ls -l export/installer/TheWitcheningTales-Setup-"$VERSION".exe
