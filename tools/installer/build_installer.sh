#!/usr/bin/env bash
# Exports SPECTRAL RUN for Windows and packs it into an NSIS installer.
#   GODOT=/path/to/godot-4.3 tools/installer/build_installer.sh
# Needs the Godot 4.3 export templates (windows_release_x86_64.exe) and makensis.
# Output: export/windows/SpectralRun.{exe,pck} and
#         export/installer/SpectralRun-Setup-<version>.exe   (export/ is not committed)
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
VERSION=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)
mkdir -p export/windows export/installer
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Windows Desktop" export/windows/SpectralRun.exe
test -s export/windows/SpectralRun.exe && test -s export/windows/SpectralRun.pck
makensis -V2 -DVERSION="$VERSION" -DSRC="$(pwd)/export/windows" \
  -DOUTFILE="$(pwd)/export/installer/SpectralRun-Setup-$VERSION.exe" tools/installer/spectral_run.nsi
ls -l export/installer/SpectralRun-Setup-"$VERSION".exe
