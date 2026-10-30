; SPECTRAL RUN — Windows installer (NSIS 3).
; Built by tools/installer/build_installer.sh, which exports the game first and
; passes VERSION and SRC (the folder holding SpectralRun.exe / SpectralRun.pck).
;
; Identity: per-user install (no admin rights) into
;   %LOCALAPPDATA%\Programs\SpectralRun
; registered under HKCU ...\Uninstall\SpectralRun. Running a newer installer
; finds the previous folder through that key and updates it in place.
; Player data (saves, settings, statistics, leaderboards, replays) lives in
;   %APPDATA%\Godot\app_userdata\SPECTRAL RUN
; and is never touched — not by updates, not by the uninstaller.

Unicode true
!ifndef VERSION
  !error "pass /DVERSION=x.y.z"
!endif
!ifndef SRC
  !error "pass /DSRC=<export folder>"
!endif
!ifndef OUTFILE
  !define OUTFILE "SpectralRun-Setup-${VERSION}.exe"
!endif

!define APPNAME "SPECTRAL RUN"
!define APPID "SpectralRun"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPID}"

Name "${APPNAME} ${VERSION}"
OutFile "${OUTFILE}"
InstallDir "$LOCALAPPDATA\Programs\${APPID}"
InstallDirRegKey HKCU "${UNINST_KEY}" "InstallLocation"
RequestExecutionLevel user
SetCompressor /SOLID lzma
VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${APPNAME}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "FileDescription" "${APPNAME} installer"
VIAddVersionKey "LegalCopyright" "SPECTRAL RUN"

!include "MUI2.nsh"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\SpectralRun.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Play ${APPNAME} now"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

; A running game keeps SpectralRun.exe locked: ask the player to close it, then retry.
!macro WAIT_FOR_GAME_CLOSED
  ; (A running .exe can still be renamed, but not opened for writing.)
  retry_close:
    IfFileExists "$INSTDIR\SpectralRun.exe" 0 closed_ok
    ClearErrors
    FileOpen $0 "$INSTDIR\SpectralRun.exe" a
    IfErrors 0 open_ok
      MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "${APPNAME} is still running.$\r$\nClose the game, then press Retry." IDRETRY retry_close
      Abort
  open_ok:
    FileClose $0
  closed_ok:
!macroend

Section "Install"
  SetOutPath "$INSTDIR"
  !insertmacro WAIT_FOR_GAME_CLOSED
  ; Replace the game files (an update overwrites the previous version's).
  File "${SRC}\SpectralRun.exe"
  File "${SRC}\SpectralRun.pck"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\${APPNAME}"
  CreateShortcut "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk" "$INSTDIR\SpectralRun.exe"
  CreateShortcut "$SMPROGRAMS\${APPNAME}\Uninstall ${APPNAME}.lnk" "$INSTDIR\Uninstall.exe"
  CreateShortcut "$DESKTOP\${APPNAME}.lnk" "$INSTDIR\SpectralRun.exe"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "${APPNAME}"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINST_KEY}" "Publisher" "${APPNAME}"
  WriteRegStr HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\SpectralRun.exe"
  WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  !insertmacro WAIT_FOR_GAME_CLOSED
  Delete "$INSTDIR\SpectralRun.exe"
  Delete "$INSTDIR\SpectralRun.pck"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk"
  Delete "$SMPROGRAMS\${APPNAME}\Uninstall ${APPNAME}.lnk"
  RMDir "$SMPROGRAMS\${APPNAME}"
  Delete "$DESKTOP\${APPNAME}.lnk"
  DeleteRegKey HKCU "${UNINST_KEY}"
  ; Saves, settings and statistics in %APPDATA%\Godot\app_userdata\SPECTRAL RUN are kept.
SectionEnd
