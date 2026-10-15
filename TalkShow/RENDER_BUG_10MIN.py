# -*- coding: utf-8 -*-
"""
Rend le Bug V2 pendant 15 secondes puis assemble 40 copies sans ré-encodage
pour créer un MOV 10 minutes destiné au DSK.

Le renderer TalkShow existant reste la source de vérité pour :
- Playwright
- supersampling x3
- Lanczos
- qtrle RGBA
- 1080i50 TFF
"""
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile

PROJECT = Path(r"F:\spark\TalkShow")
os.chdir(PROJECT)
sys.path.insert(0, str(PROJECT))

import render_talkshow as rt

name = " ".join(sys.argv[1:]).strip() or "TALK SHOW"

print("=" * 62)
print(" BUG EMISSION V2 — UN SEUL NOM — MASTER DSK 10 MIN")
print("=" * 62)
print("Emission :", name)
print()
print("[1/2] Rendu du cycle maître de 15 secondes...")

mov, _mp4, _total, _qc = rt.run_render(
    "bug",
    {"texte": name},
    frames=15 * rt.FPS,
    skip_preview=True
)

mov = Path(mov)
if not mov.exists():
    raise SystemExit("ERREUR : le MOV maître 15 s n'a pas été créé.")

safe = re.sub(r"[^A-Za-z0-9_-]+", "_", name).strip("_") or "EMISSION"
final = PROJECT / "EXPORTS" / f"TalkShow_Bug_{safe}_10MIN.mov"

print()
print("[2/2] Assemblage 15 s x 40 = 10 minutes...")
print("Aucune nouvelle capture navigateur : assemblage vidéo sans ré-encodage.")

with tempfile.NamedTemporaryFile(
    mode="w",
    encoding="utf-8",
    suffix=".txt",
    delete=False,
    dir=str(PROJECT)
) as f:
    concat_file = Path(f.name)
    escaped = str(mov.resolve()).replace("\\", "/").replace("'", r"'\''")
    for _ in range(40):
        f.write(f"file '{escaped}'\n")

try:
    cmd = [
        "ffmpeg", "-y",
        "-f", "concat",
        "-safe", "0",
        "-i", str(concat_file),
        "-c", "copy",
        str(final),
    ]
    p = subprocess.run(cmd)
    if p.returncode != 0:
        raise SystemExit("ERREUR FFmpeg pendant l'assemblage 10 minutes.")
finally:
    try:
        concat_file.unlink()
    except OSError:
        pass

print()
print("=" * 62)
print(" TERMINE")
print("=" * 62)
print("Master 15 s :", mov)
print("DSK 10 min   :", final)
print()
print("Le cartouche reste fixe ; la lumière passe environ toutes les 15 s.")
print("Le raccord DSK principal n'arrive qu'au bout de 10 minutes.")
