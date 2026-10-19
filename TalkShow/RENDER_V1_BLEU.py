# -*- coding: utf-8 -*-
"""
FAMILY V1 BLEUE — renderer dédié
- Logo V1 : MOV alpha 1080i50 TFF
- Background V1 : MP4 1080p50 ou 1920x516 50p
- Cycle source : 20 s
- Option : assembler le cycle jusqu'à 10 minutes sans recalcul navigateur
"""

from pathlib import Path
from urllib.parse import quote
import os, re, shutil, subprocess, sys, tempfile

from playwright.sync_api import sync_playwright

BASE = Path(__file__).resolve().parent
EXPORTS = BASE / "EXPORTS" / "V1"
EXPORTS.mkdir(parents=True, exist_ok=True)

FPS = 50
CYCLE_SEC = 20
FRAMES = FPS * CYCLE_SEC
MASTER_SEC = 600  # 10 minutes

def run(cmd):
    print(" ".join(str(x) for x in cmd))
    p = subprocess.run(cmd)
    if p.returncode:
        raise SystemExit("ERREUR FFmpeg.")

def safe_name(s):
    s = re.sub(r"[^A-Za-z0-9_-]+", "_", s.strip()).strip("_")
    return s or "VIDE"

def capture(html_name, width, height, out_dir, alpha=False, query=""):
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)

    html = BASE / html_name
    url = html.as_uri() + query

    print(f"Capture {width}x{height} / {FRAMES} frames...")
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, args=["--force-color-profile=srgb"])
        page = browser.new_page(
            viewport={"width": width, "height": height},
            device_scale_factor=1
        )
        page.goto(url, wait_until="load")
        page.wait_for_timeout(350)

        page.evaluate("""
        window.animationsReady = false;
        Promise.all(document.getAnimations().map(a => a.ready)).then(list => {
          window.__v1Animations = list;
          window.__v1Animations.forEach(a => {
            try { a.pause(); a.currentTime = 0; } catch(e) {}
          });
          window.__v1SetTime = function(ms) {
            window.__v1Animations.forEach(a => {
              try { a.currentTime = ms; } catch(e) {}
            });
          };
          window.animationsReady = true;
        });
        """)
        page.wait_for_function("window.animationsReady === true")

        for i in range(FRAMES):
            t = int(i * 1000 / FPS)
            page.evaluate(f"window.__v1SetTime({t})")
            page.screenshot(
                path=str(out_dir / f"frame_{i:04d}.png"),
                omit_background=alpha
            )
            if i % 100 == 0:
                print(f"  frame {i}/{FRAMES}")
        browser.close()

def repeat_to_10min(cycle_file, final_file):
    copies = MASTER_SEC // CYCLE_SEC
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", suffix=".txt", delete=False, dir=str(BASE)
    ) as f:
        lst = Path(f.name)
        p = str(Path(cycle_file).resolve()).replace("\\", "/").replace("'", r"'\''")
        for _ in range(copies):
            f.write(f"file '{p}'\n")
    try:
        run([
            "ffmpeg", "-y",
            "-f", "concat", "-safe", "0",
            "-i", str(lst),
            "-c", "copy",
            str(final_file),
        ])
    finally:
        try: lst.unlink()
        except OSError: pass

def render_logo(name=""):
    frames = BASE / "_frames_v1_logo"
    q = "?name=" + quote(name) if name.strip() else ""
    capture("v1_logo.html", 1920, 1080, frames, alpha=True, query=q)

    tag = safe_name(name)
    cycle = EXPORTS / f"V1_LOGO_{tag}_CYCLE_20S_1080i50.mov"
    final = EXPORTS / f"V1_LOGO_{tag}_10MIN_1080i50.mov"

    run([
        "ffmpeg", "-y",
        "-framerate", str(FPS),
        "-i", str(frames / "frame_%04d.png"),
        "-vf", "format=rgba,tinterlace=mode=interleave_top",
        "-field_order", "tt",
        "-c:v", "qtrle",
        "-pix_fmt", "rgba",
        str(cycle)
    ])
    repeat_to_10min(cycle, final)
    shutil.rmtree(frames, ignore_errors=True)
    print("\nLOGO TERMINE :", final)

def render_background(width=1920, height=1080, suffix="1080P50"):
    frames = BASE / f"_frames_v1_bg_{width}x{height}"
    capture("v1_background.html", width, height, frames, alpha=False)

    cycle = EXPORTS / f"V1_BACKGROUND_{suffix}_CYCLE_20S.mp4"
    final = EXPORTS / f"V1_BACKGROUND_{suffix}_10MIN.mp4"

    run([
        "ffmpeg", "-y",
        "-framerate", str(FPS),
        "-i", str(frames / "frame_%04d.png"),
        "-c:v", "libx264",
        "-preset", "medium",
        "-crf", "15",
        "-pix_fmt", "yuv420p",
        "-r", str(FPS),
        "-movflags", "+faststart",
        str(cycle)
    ])
    repeat_to_10min(cycle, final)
    shutil.rmtree(frames, ignore_errors=True)
    print("\nBACKGROUND TERMINE :", final)

def menu():
    print("=" * 64)
    print(" FAMILY V1 BLEUE — RENDER")
    print("=" * 64)
    print("1 - Logo V1 vide / nom optionnel — MOV alpha 1080i50")
    print("2 - Background V1 — 1920x1080 50p")
    print("3 - Background V1 mur LED — 1920x516 50p")
    print("4 - Tout")
    print()
    choice = input("Choix [1] : ").strip() or "1"

    if choice in ("1", "4"):
        name = input("Nom émission (laisser VIDE pour plaque vide) : ")
        render_logo(name)

    if choice in ("2", "4"):
        render_background(1920, 1080, "1920x1080_50P")

    if choice in ("3", "4"):
        render_background(1920, 516, "1920x516_50P")

if __name__ == "__main__":
    menu()
