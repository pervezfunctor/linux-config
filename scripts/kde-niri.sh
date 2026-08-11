#!/usr/bin/env bash
#
# kde-niri — apply the Karousel/KDE shortcut set mirroring ~/cnc niri binds.
#
# Idempotent: safe to re-run any time (e.g. after a KDE settings reset or
# when switching systems). For changes to take effect live, restart the
# compositor:
#
#     ~/.fgc/kde-niri.sh --restart
#
set -euo pipefail

BK=${KDE_NIRI_BACKUP_DIR:-$HOME/kde-settings-backup}
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p "$BK" ~/.local/share/applications

# ---------------------------------------------------------------- spectacle
# Local .desktop override: strip every Meta+R-family record/screenshot bind
# (they steal Meta+R / Meta+Shift+R / Meta+Alt+R / Meta+Ctrl+R from Karousel).
if [[ -f /usr/share/applications/org.kde.spectacle.desktop ]]; then
    python3 - "$BK" "$TS" <<'PY'
import re, shutil, sys
from pathlib import Path
bk, ts = sys.argv[1], sys.argv[2]
dst = Path.home() / ".local/share/applications/org.kde.spectacle.desktop"
sysf = Path("/usr/share/applications/org.kde.spectacle.desktop")
text = sysf.read_text()
if dst.exists():
    shutil.copy(dst, Path.home() / bk / f"spectacle.desktop-local-{ts}")
kept = [l for l in text.splitlines(keepends=True)
        if not (l.startswith("X-KDE-Shortcuts=") and re.search(r"Meta\+(?:(?:Shift|Alt|Ctrl)\+)?R", l))]
dst.write_text("".join(kept))
PY
    echo "[ok] spectacle: local .desktop override (Meta+R-family dropped)"
else
    echo "[warn] system spectacle .desktop not found; skipping"
fi

# --------------------------------------------------------------- fuzzel key
if [[ ! -f ~/.local/share/applications/fuzzel.desktop ]]; then
    cat > ~/.local/share/applications/fuzzel.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Fuzzel
GenericName=Launcher
Comment=Wayland launcher (niri Mod+d equivalent)
Exec=fuzzel
TryExec=fuzzel
Terminal=false
Categories=Utility;
X-KDE-Shortcuts=Meta+d
EOF
    echo "[ok] fuzzel.desktop created (Meta+d)"
fi

# --------------------------------------------------------------- presets
kwriteconfig6 --file kwinrc --group Script-karousel --key presetWidths "0.33333, 0.5, 0.66667"
echo "[ok] kwinrc: karousel presetWidths=0.33333, 0.5, 0.66667"

# --------------------------------------------------------------- shortcuts
python3 - "$BK" "$TS" <<'PY'
import re, shutil, sys
from pathlib import Path

bk, ts = sys.argv[1], sys.argv[2]
ks = Path.home() / ".config" / "kglobalshortcutsrc"
text = ks.read_text() if ks.exists() else ""
shutil.copy(ks, Path.home() / bk / f"kglobalshortcutsrc.pre-kdeniri-{ts}")

PARKED_NATIVES = {
    "Show Desktop":              "Meta+Alt+D",
    "Window Quick Tile Left":    "Ctrl+Alt+Left",
    "Window Quick Tile Right":   "Ctrl+Alt+Right",
    "Window Quick Tile Top":     "Ctrl+Alt+Up",
    "Window Quick Tile Bottom":  "Ctrl+Alt+Down",
    "Window to Next Screen":     "Ctrl+Alt+Shift+Right",
    "Window to Previous Screen": "Ctrl+Alt+Shift+Left",
    "Switch Window Left":        "Meta+Alt+Shift+Left",
    "Switch Window Right":       "Meta+Alt+Shift+Right",
    "Switch Window Up":          "Meta+Alt+Shift+Up",
    "Switch Window Down":        "Meta+Alt+Shift+Down",
}

KAROUSEL = {
    "karousel-column-move-end": "Meta+Ctrl+Shift+End",
    "karousel-column-move-left": "Meta+Shift+H\tMeta+Shift+Left",
    "karousel-column-move-right": "Meta+Shift+L\tMeta+Shift+Right",
    "karousel-column-move-start": "Meta+Ctrl+Shift+Home",
    "karousel-column-move-to-column-1": "Meta+Ctrl+Shift+1",
    "karousel-column-move-to-column-2": "Meta+Ctrl+Shift+2",
    "karousel-column-move-to-column-3": "Meta+Ctrl+Shift+3",
    "karousel-column-move-to-column-4": "Meta+Ctrl+Shift+4",
    "karousel-column-move-to-column-5": "Meta+Ctrl+Shift+5",
    "karousel-column-move-to-column-6": "Meta+Ctrl+Shift+6",
    "karousel-column-move-to-column-7": "Meta+Ctrl+Shift+7",
    "karousel-column-move-to-column-8": "Meta+Ctrl+Shift+8",
    "karousel-column-move-to-column-9": "Meta+Ctrl+Shift+9",
    "karousel-column-move-to-desktop-1": "Meta+Shift+1",
    "karousel-column-move-to-desktop-2": "Meta+Shift+2",
    "karousel-column-move-to-desktop-3": "Meta+Shift+3",
    "karousel-column-move-to-desktop-4": "Meta+Shift+4",
    "karousel-column-move-to-desktop-5": "Meta+Shift+5",
    "karousel-column-move-to-desktop-6": "Meta+Shift+6",
    "karousel-column-move-to-desktop-7": "Meta+Shift+7",
    "karousel-column-move-to-desktop-8": "Meta+Shift+8",
    "karousel-column-move-to-desktop-9": "Meta+Shift+9",
    "karousel-column-toggle-stacked": "Meta+X",
    "karousel-column-width-decrease": "Meta+Alt+Left",
    "karousel-column-width-increase": "Meta+Alt+Right",
    "karousel-columns-squeeze-left": "Meta+Ctrl+A",
    "karousel-columns-squeeze-right": "Meta+Ctrl+D",
    "karousel-columns-width-equalize": "Meta+Ctrl+X",
    "karousel-cycle-preset-widths": "Meta+R",
    "karousel-cycle-preset-widths-reverse": "Meta+Shift+R",
    "karousel-focus-1": "Meta+1",
    "karousel-focus-2": "Meta+2",
    "karousel-focus-3": "Meta+3",
    "karousel-focus-4": "Meta+4",
    "karousel-focus-5": "Meta+5",
    "karousel-focus-6": "Meta+6",
    "karousel-focus-7": "Meta+7",
    "karousel-focus-8": "Meta+8",
    "karousel-focus-9": "Meta+9",
    "karousel-focus-down": "Meta+Down",
    "karousel-focus-end": "Meta+End",
    "karousel-focus-left": "Meta+Left",
    "karousel-focus-right": "Meta+Right",
    "karousel-focus-start": "Meta+Home",
    "karousel-focus-up": "Meta+Up",
    "karousel-grid-scroll-end": "Meta+Alt+End",
    "karousel-grid-scroll-focused": "Meta+Alt+Return",
    "karousel-grid-scroll-left": "Meta+Alt+PgUp",
    "karousel-grid-scroll-left-column": "Meta+Alt+A",
    "karousel-grid-scroll-right": "Meta+Alt+PgDown",
    "karousel-grid-scroll-right-column": "Meta+Alt+D",
    "karousel-grid-scroll-start": "Meta+Alt+Home",
    "karousel-screen-switch": "Meta+Ctrl+Return",
    "karousel-window-height-increase-down": "Meta+Alt+Down",
    "karousel-window-height-increase-up": "Meta+Alt+Up",
    "karousel-window-move-down": "Meta+Shift+J\tMeta+Shift+Down",
    "karousel-window-move-end": "Meta+Shift+End",
    "karousel-window-move-left": "Meta+Shift+A",
    "karousel-window-move-right": "Meta+Shift+D",
    "karousel-window-move-start": "Meta+Shift+Home",
    "karousel-window-move-to-column-1": "Meta+Alt+Shift+1",
    "karousel-window-move-to-column-2": "Meta+Alt+Shift+2",
    "karousel-window-move-to-column-3": "Meta+Alt+Shift+3",
    "karousel-window-move-to-column-4": "Meta+Alt+Shift+4",
    "karousel-window-move-to-column-5": "Meta+Alt+Shift+5",
    "karousel-window-move-to-column-6": "Meta+Alt+Shift+6",
    "karousel-window-move-to-column-7": "Meta+Alt+Shift+7",
    "karousel-window-move-to-column-8": "Meta+Alt+Shift+8",
    "karousel-window-move-to-column-9": "Meta+Alt+Shift+9",
    "karousel-window-move-up": "Meta+Shift+K\tMeta+Shift+Up",
    "karousel-window-toggle-floating": "Meta+T",
    # explicitly unbound (not part of the niri set)
    "karousel-column-move-to-next-desktop": "", "karousel-column-move-to-previous-desktop": "",
    "karousel-tail-move-to-next-desktop": "", "karousel-tail-move-to-previous-desktop": "",
    "karousel-window-move-next": "", "karousel-window-move-previous": "",
    "karousel-focus-next": "", "karousel-focus-previous": "",
    "karousel-column-width-maximize": "", "karousel-column-width-minimize": "",
}

OTHER = {
    "krunner": {"RunCommand": ("Alt+F2\tMeta+Space", "Run Command")},
    "plasmashell": {"activate application launcher": ("Meta\tAlt+F1", "Activate Application Launcher")},
}

sections, cur = {}, None
for line in (text.splitlines() if text else []):
    if line.startswith("["):
        cur = line.strip("[]")
        sections.setdefault(cur, [])
    elif cur is not None and "=" in line:
        sections[cur].append(line)
for name in ("kwin", "krunner", "plasmashell", "org.kde.spectacle.desktop"):
    sections.setdefault(name, [])

out = ["# KDE niri shortcut set -- applied by ~/.fgc/kde-niri.sh"]
for name, entries in sections.items():
    out.append(f"[{name}]")
    seen = set()
    for e in entries:
        k = e.split("=", 1)[0].strip()
        parts = e.split(",", 2)
        desc = parts[2].strip() if len(parts) == 3 else ""
        if name == "kwin" and k in PARKED_NATIVES:
            val = PARKED_NATIVES[k]
            out.append(f"{k}={val},{val},{desc}")
            seen.add(("kwin", k))
        elif name == "kwin" and k in KAROUSEL:
            val = KAROUSEL[k]
            out.append(f"{k}={val if val else 'none'},{val if val else 'none'},{desc}")
            seen.add(("kwin", k))
        elif name in OTHER and k in OTHER[name]:
            val, d = OTHER[name][k]
            out.append(f"{k}={val},{val},{d}")
            seen.add((name, k))
        else:
            out.append(e)
    for k, val in KAROUSEL.items():
        if ("kwin", k) not in seen:
            out.append(f"{k}={val if val else 'none'},{val if val else 'none'},Karousel action")
    for k, (val, d) in OTHER.get(name, {}).items():
        if (name, k) not in seen:
            out.append(f"{k}={val},{val},{d}")

ks.write_text("\n".join(out) + "\n")
print("[ok] kglobalshortcutsrc rewritten (karousel binds + parked natives + launcher/krunner)")
PY

kbuildsycoca6 || true

if [[ " $* " == *" --restart "* ]]; then
    echo "[restart] restarting plasma-kwin_wayland... (screen may blink)"
    systemctl --user restart plasma-kwin_wayland.service
else
    echo
    echo "Done. To apply changes in the running session (kwin re-registers from the file):"
    echo "    ~/.fgc/kde-niri.sh --restart"
fi