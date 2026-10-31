"""Stamps the exported Windows .exe with the SPECTRAL RUN icon and version details.

Godot 4.3 can only do this through rcedit (a Windows tool); this does the same
with LIEF so the build works anywhere:  python3 stamp_exe.py <exe> <icon.png> <version>
Every icon image in the template is replaced size for size, and the version
strings/numbers name the game instead of the engine."""
import io
import struct
import sys

import lief
from PIL import Image


def _pad(b):
    return b + b"\0" * ((4 - len(b) % 4) % 4)


def _node(key, value=b"", wtype=1, children=(), value_len=None):
    """One VS_VERSIONINFO-style block: header, key, value, children (32-bit aligned)."""
    body = _pad(struct.pack("<HHH", 0, 0, 0) + (key + "\0").encode("utf-16-le"))
    body = _pad(body + value)
    for ch in children:
        body = _pad(body) + ch
    vlen = value_len if value_len is not None else len(value)
    return struct.pack("<HHH", len(body), vlen, wtype) + body[6:]


def _string(key, text):
    val = (text + "\0").encode("utf-16-le")
    return _node(key, val, 1, (), len(text) + 1)


def version_info(version, strings, lang="040904b0"):
    p = [int(x) for x in (version.split(".") + ["0", "0", "0"])[:4]]
    ms, ls = (p[0] << 16) | p[1], (p[2] << 16) | p[3]
    fixed = struct.pack("<13I", 0xFEEF04BD, 0x00010000, ms, ls, ms, ls, 0x3F, 0, 0x40004, 1, 0, 0, 0)
    table = _node(lang, b"", 1, [_pad(_string(k, v)) for k, v in strings.items()])
    sfi = _node("StringFileInfo", b"", 1, [table])
    vfi = _node("VarFileInfo", b"", 1, [_node("Translation", struct.pack("<HH", 0x0409, 0x04B0), 0)])
    return _node("VS_VERSION_INFO", fixed, 0, [_pad(sfi), vfi])


def main(exe, icon_png, version):
    b = lief.PE.parse(exe)
    m = b.resources_manager
    src = Image.open(icon_png).convert("RGBA")
    for old in list(m.icons):
        w = old.width or 256   # 0 means 256 in an icon directory
        buf = io.BytesIO()
        src.resize((w, w), Image.LANCZOS).save(buf, format="ICO", sizes=[(w, w)])
        new = lief.PE.ResourceIcon.from_serialization(buf.getvalue())
        new.id, new.lang, new.sublang = old.id, old.lang, old.sublang
        m.change_icon(old, new)
    strings = {"CompanyName": "SPECTRAL RUN", "FileDescription": "SPECTRAL RUN", "FileVersion": version,
               "InternalName": "SpectralRun", "LegalCopyright": "SPECTRAL RUN. Made with Godot Engine (MIT licence).",
               "OriginalFilename": "SpectralRun.exe", "ProductName": "SPECTRAL RUN", "ProductVersion": version}
    for d in b.resources.childs:
        if d.id == 16:   # RT_VERSION
            for name_dir in d.childs:
                for leaf in name_dir.childs:
                    leaf.content = version_info(version, strings)
    cfg = lief.PE.Builder.config_t()
    cfg.resources = True
    b.write(exe, cfg)
    # Verify.
    chk = lief.PE.parse(exe).resources_manager
    got = {e.key: e.value for v in chk.version for t in v.string_file_info.children for e in t.entries}
    assert got.get("ProductName") == "SPECTRAL RUN" and got.get("ProductVersion") == version, got
    print("stamped %s: %d icons, version %s" % (exe, len(list(chk.icons)), version))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
