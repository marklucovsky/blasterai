#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Build an interactive HTML review page for tile image sets.

Usage:
    python3 tools/build_review_page.py --set playful_3d
    python3 tools/build_review_page.py --set high_contrast
    python3 tools/build_review_page.py --set both

Opens in browser automatically. Features:
- Side-by-side shipping sets (Playful-3D, Classic) vs the new tile
- Approve / Reject / Comment per tile
- Filter by category, status, search
- Lightbox zoom on click
- Export reject list as JSON (paste into review_tiles.py reject command)
- State persists in localStorage (survives browser refresh)
"""

import hashlib
import json
import os
import shutil
import sys
import webbrowser
from pathlib import Path

VOCAB_FILE = Path("claudeBlast/Resources/vocabulary.json")
ASSETS_DIR = Path("claudeBlast/Assets.xcassets")
TILE_IMAGE_SETS = Path("claudeBlast/TileImageSets")
OUTPUT_BASE = Path("tools/tile_sets")


def img_to_relative_path(path: Path, html_dir: Path) -> str:
    """Return a relative path from the HTML file's directory to the image."""
    if not path.exists():
        return ""
    try:
        return os.path.relpath(path.resolve(), html_dir.resolve())
    except ValueError:
        return ""


def image_stamp(path: Path) -> str:
    """Short content hash of a tile image, used to expire stale verdicts."""
    return hashlib.sha1(path.read_bytes()).hexdigest()[:12]


def build_page(set_name: str) -> Path:
    vocab = json.loads(VOCAB_FILE.read_text())
    set_dir = OUTPUT_BASE / set_name
    html_dir = OUTPUT_BASE  # HTML lives in tools/tile_sets/
    res = VOCAB_FILE.parent  # claudeBlast/Resources

    import shutil

    # Combined tile list: base vocabulary + vocab-pack words, each tagged with its
    # pack ("base" for core vocab). Pack words extend the vocabulary and need
    # review too, even though they aren't in vocabulary.json.
    entries = [(t["key"], t.get("wordClass", "unknown"), "base") for t in vocab]
    base_keys = {t["key"] for t in vocab}
    try:
        catalog = json.loads((res / "packs.json").read_text())
    except Exception:
        catalog = []
    for entry in catalog:
        try:
            pj = json.loads((res / f"{entry['file']}.json").read_text())
        except Exception:
            continue
        for w in pj.get("words", []):
            if w["key"] not in base_keys:
                entries.append((w["key"], w.get("wordClass", "unknown"), entry["slug"]))

    # Local copies of the two shipping sets so the browser can load them.
    # The comparison baseline is Playful-3D + Classic — the sets a user can
    # actually pick. ARASAAC used to hold the second column, but it is
    # isShippable: false, a legacy external corpus we never generate against,
    # and it permanently lags the vocabulary. Comparing new work against art
    # nobody can select was measuring the wrong thing.
    current_dir = OUTPUT_BASE / "current_p3d"; current_dir.mkdir(parents=True, exist_ok=True)
    classic_dir = OUTPUT_BASE / "current_classic"; classic_dir.mkdir(parents=True, exist_ok=True)
    for key, _wc, _pk in entries:
        p3d = TILE_IMAGE_SETS / f"p3d_{key}.png"
        if p3d.exists():
            shutil.copy2(p3d, current_dir / f"{key}.png")
        cls = TILE_IMAGE_SETS / f"cls_{key}.png"
        if cls.exists():
            shutil.copy2(cls, classic_dir / f"{key}.png")

    tiles_json = []
    for i, (key, wc, pack) in enumerate(entries):
        current_path = current_dir / f"{key}.png"
        classic_path = classic_dir / f"{key}.png"
        new_path = set_dir / f"{key}.png"

        new_img = img_to_relative_path(new_path, html_dir)
        current_img = img_to_relative_path(current_path, html_dir)
        has_new = new_path.exists()

        tiles_json.append({
            "key": key,
            "wordClass": wc,
            "pack": pack,
            "index": i,
            "currentImg": current_img,
            "classicImg": img_to_relative_path(classic_path, html_dir),
            "newImg": new_img if has_new else current_img,
            "hasNew": has_new,
            # Content fingerprint, so a saved verdict can be matched to the
            # exact image it was given for. Regenerating a handful of rejected
            # tiles then invalidates only those verdicts and leaves the rest of
            # the review intact.
            "stamp": image_stamp(new_path) if has_new else "",
        })

    # Outstanding rejects, so a review picked up in a different browser (or
    # after localStorage was cleared) still opens with the to-do list. A tile
    # whose art is newer than the rejection has already been regenerated and
    # is flagged for a fresh look rather than left looking untouched.
    seed_rejects: dict[str, dict] = {}
    rejected_file = set_dir / "rejected.json"
    if rejected_file.exists():
        try:
            rejected = json.loads(rejected_file.read_text())
            cutoff = rejected_file.stat().st_mtime
            for key, entry in rejected.items():
                art = set_dir / f"{key}.png"
                seed_rejects[key] = {
                    "reason": entry.get("reason", ""),
                    "refreshed": art.exists() and art.stat().st_mtime > cutoff,
                }
        except Exception as e:
            print(f"  (could not read {rejected_file}: {e})")

    categories = sorted(set(t["wordClass"] for t in tiles_json))
    packs = ["base"] + sorted({e[2] for e in entries if e[2] != "base"})

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Blaster Tile Review — {set_name}</title>
<style>
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f7; color: #1d1d1f; }}

.header {{
    position: sticky; top: 0; z-index: 100; background: #fff; border-bottom: 1px solid #ddd;
    padding: 12px 20px; display: flex; flex-wrap: wrap; gap: 10px; align-items: center;
    box-shadow: 0 2px 8px rgba(0,0,0,0.06);
}}
.header h1 {{ font-size: 18px; font-weight: 600; margin-right: 20px; }}
.header select, .header input, .header button {{
    padding: 6px 12px; border: 1px solid #ccc; border-radius: 6px; font-size: 13px;
}}
.header button {{
    background: #007aff; color: white; border: none; cursor: pointer; font-weight: 500;
}}
.header button:hover {{ background: #0066d6; }}
.header button.danger {{ background: #ff3b30; }}
.header button.danger:hover {{ background: #d63028; }}
.header button.success {{ background: #34c759; }}
.stats {{ font-size: 13px; color: #666; margin-left: auto; }}

.grid {{
    display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
    gap: 12px; padding: 16px;
}}

.card {{
    background: #fff; border-radius: 12px; overflow: hidden;
    box-shadow: 0 1px 4px rgba(0,0,0,0.08); transition: box-shadow 0.2s;
}}
.card:hover {{ box-shadow: 0 4px 16px rgba(0,0,0,0.12); }}
.card.approved {{ border-left: 4px solid #34c759; }}
.card.rejected {{ border-left: 4px solid #ff3b30; }}
/* Rejected, and the art has since been regenerated — still rejected so it
   stays in that filter, but visibly awaiting a fresh look. */
.card.refreshed {{ border-left: 4px solid #ff9500; background: #fffaf2; }}
.refreshed-badge {{
    display: inline-block; margin-bottom: 4px; padding: 1px 7px;
    border-radius: 9px; background: #ff9500; color: #fff;
    font-size: 10px; font-weight: 700; text-transform: uppercase;
    letter-spacing: .4px;
}}

.card-images {{
    display: flex; gap: 2px; background: #eee; cursor: pointer;
}}
.card-images .img-col {{
    flex: 1; text-align: center; position: relative;
}}
.card-images .img-col img {{
    width: 100%; aspect-ratio: 1; object-fit: contain; display: block; background: #fff;
}}
.card-images .img-label {{
    display: block; font-size: 10px; color: #555; padding: 3px 0 5px;
    background: #fafafa; font-weight: 600; letter-spacing: 0.02em;
}}

.progress-bar {{
    height: 4px; background: #e5e5e5; border-radius: 2px; overflow: hidden; flex: 1; min-width: 100px;
}}
.progress-bar .fill {{
    height: 100%; border-radius: 2px; transition: width 0.3s;
    background: linear-gradient(90deg, #34c759, #007aff);
}}

.card-body {{ padding: 10px 12px; }}
.card-body .tile-key {{ font-weight: 600; font-size: 14px; }}
.card-body .tile-class {{ font-size: 12px; color: #888; margin-left: 6px; }}
.card-actions {{ display: flex; gap: 6px; margin-top: 8px; align-items: center; }}
.card-actions button {{
    padding: 4px 10px; border: 1px solid #ddd; border-radius: 6px; font-size: 12px;
    cursor: pointer; background: #f9f9f9;
}}
.card-actions button:hover {{ background: #eee; }}
.card-actions button.active-approve {{ background: #34c759; color: white; border-color: #34c759; }}
.card-actions button.active-reject {{ background: #ff3b30; color: white; border-color: #ff3b30; }}
.card-actions input {{
    flex: 1; padding: 4px 8px; border: 1px solid #ddd; border-radius: 6px; font-size: 12px;
}}

/* Lightbox */
.lightbox {{
    display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%;
    background: rgba(0,0,0,0.85); z-index: 200; justify-content: center; align-items: center;
    gap: 20px; padding: 40px;
}}
.lightbox.active {{ display: flex; }}
.lightbox img {{ max-height: 80vh; max-width: 30vw; border-radius: 8px; }}
.lightbox .label {{
    position: absolute; bottom: 40px; color: white; font-size: 16px; font-weight: 500;
}}
.lightbox .close {{
    position: absolute; top: 20px; right: 30px; color: white; font-size: 32px;
    cursor: pointer; line-height: 1;
}}

.hidden {{ display: none !important; }}
</style>
</head>
<body>

<div class="header">
    <h1>Tile Review: {set_name}</h1>
    <select id="filterCategory">
        <option value="all">All Categories</option>
        {"".join(f'<option value="{c}">{c}</option>' for c in categories)}
    </select>
    <select id="filterPack">
        <option value="all">All Packs</option>
        {"".join(f'<option value="{p}">{"base vocab" if p == "base" else p}</option>' for p in packs)}
    </select>
    <select id="filterStatus">
        <option value="all">All Status</option>
        <option value="unreviewed">Unreviewed</option>
        <option value="approved">Approved</option>
        <option value="rejected">Rejected</option>
        <option value="refreshed">Rejected &rarr; fixed, needs re-review</option>
    </select>
    <input type="text" id="searchBox" placeholder="Search tiles..." />
    <label style="font-size:13px;display:flex;align-items:center;gap:5px;white-space:nowrap">
        <input type="checkbox" id="onlyNew" checked style="width:auto"> Only generated
    </label>
    <button class="success" onclick="approveAll()">Approve All Visible</button>
    <button class="danger" onclick="exportRejects()">Export Rejects</button>
    <button onclick="exportAll()">Export Full Review</button>
    <div class="progress-bar"><div class="fill" id="progressFill"></div></div>
    <div class="stats" id="stats"></div>
</div>

<div class="grid" id="grid"></div>

<div class="lightbox" id="lightbox" onclick="closeLightbox()">
    <span class="close">&times;</span>
    <img id="lb-p3d" />
    <img id="lb-classic" />
    <img id="lb-new" />
</div>

<script>
const SET_NAME = "{set_name}";
const TILES = {json.dumps(tiles_json)};
const STORAGE_KEY = "blaster_review_" + SET_NAME;
// tools/tile_sets/<set>/rejected.json — the rejects handed off for regen.
// Seeds a verdict for any key the browser has no opinion on, so a review
// continued in another browser (or after the store was cleared) still starts
// with the outstanding to-do list rather than a blank slate.
const SEED_REJECTS = {json.dumps(seed_rejects)};

// Load state from localStorage
let state = {{}};
try {{ state = JSON.parse(localStorage.getItem(STORAGE_KEY)) || {{}}; }} catch(e) {{}}

function saveState() {{
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}}

const STAMPS = Object.fromEntries(TILES.map(t => [t.key, t.stamp]));

// A verdict belongs to the image it was given for, and the two verdicts want
// opposite things when the image changes underneath them.
//
//   approved + changed -> demote to unreviewed. An approval is permission to
//     ship, and it must never carry over to art nobody has looked at.
//   rejected + changed -> STAY rejected, flagged as refreshed. A rejection is
//     a to-do item. Clearing it would lose the very filter you need to check
//     the fixes, and a rejected tile ships nothing, so there is no risk in
//     keeping it.
let seeded = 0;
for (const [key, entry] of Object.entries(SEED_REJECTS)) {{
    if (state[key]) continue;                 // the browser's own verdict wins
    state[key] = {{
        status: "rejected",
        comment: entry.reason || "",
        stamp: STAMPS[key] || "",
        refreshed: !!entry.refreshed,
    }};
    seeded++;
}}
if (seeded) console.log(`${{seeded}} outstanding reject(s) restored from rejected.json.`);

let demoted = 0, refreshed = 0;
for (const [key, s] of Object.entries(state)) {{
    if (!s.stamp || !STAMPS[key] || s.stamp === STAMPS[key]) continue;
    if (s.status === "rejected") {{
        s.refreshed = true;
        s.stamp = STAMPS[key];
        refreshed++;
    }} else {{
        delete state[key];
        demoted++;
    }}
}}
if (demoted || refreshed) {{
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
    console.log(`${{refreshed}} rejected tile(s) regenerated and awaiting re-review; `
              + `${{demoted}} approval(s) cleared because the art changed.`);
}}

function getState(key) {{
    return state[key] || {{ status: "unreviewed", comment: "" }};
}}

function setState(key, updates) {{
    const next = {{ ...getState(key), ...updates, stamp: STAMPS[key] || "" }};
    // Judging it again is what clears the "fixed, needs re-review" marker —
    // including re-rejecting it, which starts the next round.
    if (updates.status !== undefined) next.refreshed = false;
    state[key] = next;
    saveState();
    renderCard(key);
    updateStats();
}}

function renderCard(key) {{
    const el = document.getElementById("card-" + key);
    if (!el) return;
    const s = getState(key);
    el.className = "card " + s.status + (s.refreshed ? " refreshed" : "");
    const approveBtn = el.querySelector(".btn-approve");
    const rejectBtn = el.querySelector(".btn-reject");
    const commentInput = el.querySelector(".comment-input");
    const badge = el.querySelector(".refreshed-badge");
    approveBtn.className = s.status === "approved" ? "btn-approve active-approve" : "btn-approve";
    rejectBtn.className = s.status === "rejected" ? "btn-reject active-reject" : "btn-reject";
    commentInput.value = s.comment || "";
    if (badge) badge.style.display = s.refreshed ? "" : "none";
}}

function updateStats() {{
    // During a pilot only some tiles are generated — measure progress against
    // the generated set, not the full 492-tile vocabulary.
    const present = TILES.filter(t => t.hasNew);
    const scope = present.length ? present : TILES;
    const total = scope.length;
    let approved = 0, rejected = 0;
    scope.forEach(t => {{
        const s = getState(t.key);
        if (s.status === "approved") approved++;
        if (s.status === "rejected") rejected++;
    }});
    const reviewed = approved + rejected;
    const pct = Math.round(reviewed / total * 100);
    document.getElementById("stats").textContent =
        `${{pct}}% reviewed (${{approved}} ok / ${{rejected}} redo / ${{total - reviewed}} left)`;
    document.getElementById("progressFill").style.width = pct + "%";
}}

const tileMap = {{}};
TILES.forEach(t => tileMap[t.key] = t);

function buildGrid() {{
    const grid = document.getElementById("grid");
    grid.innerHTML = "";
    TILES.forEach(t => {{
        const s = getState(t.key);
        const card = document.createElement("div");
        card.id = "card-" + t.key;
        card.className = "card " + s.status + (s.refreshed ? " refreshed" : "");
        card.dataset.key = t.key;
        card.dataset.wordclass = t.wordClass;
        card.dataset.pack = t.pack;
        card.dataset.hasnew = t.hasNew ? "1" : "0";
        const k = t.key.replace(/'/g, "\\\\'");

        card.innerHTML = `
            <div class="card-images" onclick="openLightbox('${{k}}')" style="position:relative">
                <div class="img-col">
                    ${{t.currentImg ? `<img src="${{t.currentImg}}" loading="lazy" />` : '<div style="aspect-ratio:1;background:#eee;display:flex;align-items:center;justify-content:center;color:#999;font-size:11px">no p3d</div>'}}
                    <span class="img-label">Playful-3D</span>
                </div>
                <div class="img-col">
                    ${{t.classicImg ? `<img src="${{t.classicImg}}" loading="lazy" />` : '<div style="aspect-ratio:1;background:#eee;display:flex;align-items:center;justify-content:center;color:#999;font-size:11px">no Classic</div>'}}
                    <span class="img-label">Classic</span>
                </div>
                <div class="img-col">
                    ${{t.hasNew ? `<img src="${{t.newImg}}" loading="lazy" />` : '<div style="aspect-ratio:1;background:#eee;display:flex;align-items:center;justify-content:center;color:#999;font-size:11px">Missing</div>'}}
                    <span class="img-label">NEW: ${{SET_NAME}}</span>
                </div>
            </div>
            <div class="card-body">
                <span class="refreshed-badge" style="${{s.refreshed ? '' : 'display:none'}}">redone &mdash; re-review</span>
                <span class="tile-key">${{t.key}}</span>
                <span class="tile-class">${{t.wordClass}}</span>
                ${{t.pack !== 'base' ? `<span class="tile-class" style="color:#7a5cff;font-weight:600">· ${{t.pack}}</span>` : ''}}
                <div class="card-actions">
                    <button class="btn-approve ${{s.status === 'approved' ? 'active-approve' : ''}}"
                            onclick="setState('${{k}}', {{status: getState('${{k}}').status === 'approved' ? 'unreviewed' : 'approved'}})">&#10003;</button>
                    <button class="btn-reject ${{s.status === 'rejected' ? 'active-reject' : ''}}"
                            onclick="setState('${{k}}', {{status: getState('${{k}}').status === 'rejected' ? 'unreviewed' : 'rejected'}})">&#10007;</button>
                    <div style="position:relative;flex:1">
                        <input class="comment-input" type="text" placeholder="Comment..." style="width:100%;padding-right:24px"
                               value="${{(s.comment || '').replace(/"/g, '&quot;')}}"
                               onchange="setState('${{k}}', {{comment: this.value}})" />
                        <span onclick="this.previousElementSibling.value='';setState('${{k}}',{{comment:''}})"
                              style="position:absolute;right:6px;top:50%;transform:translateY(-50%);cursor:pointer;color:#999;font-size:14px;line-height:1">&times;</span>
                    </div>
                </div>
            </div>
        `;
        grid.appendChild(card);
    }});
    updateStats();
}}

function applyFilters() {{
    const cat = document.getElementById("filterCategory").value;
    const pk = document.getElementById("filterPack").value;
    const status = document.getElementById("filterStatus").value;
    const search = document.getElementById("searchBox").value.toLowerCase();
    const onlyNew = document.getElementById("onlyNew").checked;

    document.querySelectorAll(".card").forEach(card => {{
        const key = card.dataset.key;
        const wc = card.dataset.wordclass;
        const s = getState(key);
        let show = true;
        if (onlyNew && card.dataset.hasnew !== "1") show = false;
        if (cat !== "all" && wc !== cat) show = false;
        if (pk !== "all" && card.dataset.pack !== pk) show = false;
        if (status === "refreshed") {{
            if (!s.refreshed) show = false;
        }} else if (status !== "all" && s.status !== status) {{
            show = false;
        }}
        if (search && !key.includes(search)) show = false;
        card.classList.toggle("hidden", !show);
    }});
}}

function approveAll() {{
    document.querySelectorAll(".card:not(.hidden)").forEach(card => {{
        const key = card.dataset.key;
        if (getState(key).status === "unreviewed") {{
            setState(key, {{ status: "approved" }});
        }}
    }});
}}

function exportRejects() {{
    const rejects = {{}};
    TILES.forEach(t => {{
        const s = getState(t.key);
        if (s.status === "rejected") {{
            rejects[t.key] = {{ reason: s.comment || "rejected in review", attempts: 1 }};
        }}
    }});
    const keys = Object.keys(rejects);
    if (keys.length === 0) {{ alert("No rejected tiles!"); return; }}

    const jsonText = JSON.stringify(rejects, null, 2);
    navigator.clipboard.writeText(jsonText).then(() => {{
        alert(`${{keys.length}} rejected tiles copied to clipboard as JSON. Paste to Claude.`);
    }}).catch(() => {{
        // Fallback: open in a new window so user can copy
        const w = window.open("", "_blank");
        w.document.write("<pre>" + jsonText + "</pre>");
    }});
}}

function exportAll() {{
    const review = {{}};
    TILES.forEach(t => {{
        review[t.key] = getState(t.key);
    }});
    const blob = new Blob([JSON.stringify(review, null, 2)], {{type: "application/json"}});
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `review_${{SET_NAME}}.json`;
    a.click();
}}

// Lightbox — tileMap is initialized earlier (before buildGrid)

function openLightbox(key) {{
    const t = tileMap[key];
    document.getElementById("lb-p3d").src = t.currentImg || "";
    document.getElementById("lb-classic").src = t.classicImg || "";
    document.getElementById("lb-new").src = t.hasNew ? t.newImg : "";
    document.getElementById("lightbox").classList.add("active");
}}
function closeLightbox() {{
    document.getElementById("lightbox").classList.remove("active");
}}
document.addEventListener("keydown", e => {{
    if (e.key === "Escape") closeLightbox();
}});

// Init
document.getElementById("filterCategory").addEventListener("change", applyFilters);
document.getElementById("filterPack").addEventListener("change", applyFilters);
document.getElementById("filterStatus").addEventListener("change", applyFilters);
document.getElementById("searchBox").addEventListener("input", applyFilters);
document.getElementById("onlyNew").addEventListener("change", applyFilters);
buildGrid();
applyFilters();
</script>
</body>
</html>"""

    out_path = OUTPUT_BASE / f"review_{set_name}.html"
    out_path.write_text(html)
    print(f"Review page: {out_path} ({len(html) // 1024} KB)")
    return out_path


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--set", required=True, help="Tile set name under tools/tile_sets/")
    parser.add_argument("--no-open", action="store_true", help="Don't auto-open in browser")
    args = parser.parse_args()

    print(f"\nBuilding review page for {args.set}...")
    path = build_page(args.set)
    if not args.no_open:
        webbrowser.open(f"file://{path.resolve()}")


if __name__ == "__main__":
    main()
