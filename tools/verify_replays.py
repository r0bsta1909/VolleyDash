#!/usr/bin/env python3
"""Verify the reference replays under tests/replays/ (M0-03).

Checks, per rally, that the recording actually contains the phenomenon it is
supposed to protect (07_TEST_PLAN section 2). A file that parses is not a
reference; a file that hits the net cap is.

Additionally compares the two passes against each other: same inputs, same
start state, once with the prototype's variable step and once with a constant
1/60. That is the numeric answer to step 3 of 07_TEST_PLAN section 2.

Usage:
    python tools/verify_replays.py [--replay-dir tests/replays]

Exit code 0 if every present rally passes, 1 otherwise.
"""

import argparse
import json
import math
import os
import sys

MODES = ("variable", "fixed60")

# Geometry constants of the prototype, defaults from main.lua.
BALL_RADIUS = 30.0
WORLD_W = 800.0
NET_X, NET_W = 395.0, 10.0
NET_CAP = (400.0, 345.0)          # centre of the net cap
NET_CAP_DIST = BALL_RADIUS + 5.0  # ball centre distance while resting on it
GROUND_Y = 500.0
MAX_BALL_SPEED = 1400.0

BIT_SMASH, BIT_DASH = 8, 16


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

def load(path):
    with open(path, encoding="utf-8") as fh:
        doc = json.load(fh)
    for frame in doc["frames"]:
        for key in ("ball", "p1", "p2"):
            frame[key] = [float(v) for v in frame[key]]
        frame["dt"] = float(frame["dt"])
    return doc


def contacts(frames):
    """Ticks at which a blob touched the ball.

    A frame holds the state BEFORE its own step, so a contact during step t is
    visible in frame t+1. Returned index is that of the post-contact frame.
    """
    out = []
    for i in range(1, len(frames)):
        prev_p, prev_c = frames[i - 1]["touch"]
        cur_p, cur_c = frames[i]["touch"]
        if cur_c > 0 and (cur_c > prev_c or cur_p != prev_p):
            out.append(i)
    return out


def speeds(frames):
    return [math.hypot(f["ball"][2], f["ball"][3]) for f in frames]


def near(a, b, eps=1e-6):
    return abs(a - b) <= eps


# ---------------------------------------------------------------------------
# Per-rally criteria
# ---------------------------------------------------------------------------

def c_r01(doc, fr):
    first, last = fr[0]["score"], fr[-1]["score"]
    ok = last[0] == first[0] + 1 and last[1] == first[1]
    return ok, f"Punkt fuer P1: {first} -> {last}"


def c_r02(doc, fr):
    n = len(contacts(fr))
    return n >= 15, f"{n} Blob-Ball-Kontakte (>= 15)"


def c_r03(doc, fr):
    left = sum(1 for f in fr if near(f["ball"][0], BALL_RADIUS))
    right = sum(1 for f in fr if near(f["ball"][0], WORLD_W - BALL_RADIUS))
    return left >= 1 and right >= 1, f"Wandkontakte links={left} rechts={right}"


def c_r04(doc, fr):
    hits = []
    for i, f in enumerate(fr):
        bx, by = f["ball"][0], f["ball"][1]
        if by < NET_CAP[1] and near(math.hypot(bx - NET_CAP[0], by - NET_CAP[1]),
                                    NET_CAP_DIST, 0.5):
            hits.append(i)
    flip = any(fr[i - 1]["ball"][3] > 0 > fr[i]["ball"][3] for i in hits if i > 0)
    return bool(hits) and flip, f"Netzkappen-Kontakte={len(hits)}, vy kehrt um={flip}"


def c_r05(doc, fr):
    n = sum(1 for f in fr
            if near(f["ball"][0], NET_X - BALL_RADIUS)
            or near(f["ball"][0], NET_X + NET_W + BALL_RADIUS))
    return n >= 1, f"Netzflanken-Kontakte={n}"


def c_r06(doc, fr):
    best = 0.0
    for i in contacts(fr):
        if fr[i]["touch"][0] == 1:
            best = max(best, abs(fr[i - 1]["p1"][2]))
    return best >= 500.0, f"schnellster P1-Kontakt |vx|={best:.1f} (>= 500)"


def c_r07(doc, fr):
    found = False
    for i in contacts(fr):
        if fr[i]["touch"][0] != 1:
            continue
        p = fr[i - 1]["p1"]
        if near(p[2], 0.0) and near(p[3], 0.0) and near(p[1], GROUND_Y):
            found = True
    return found, "Kontakt mit stehendem, geerdetem P1"


def c_r08(doc, fr):
    found = False
    for i in contacts(fr):
        if fr[i]["touch"][0] != 1:
            continue
        if fr[i - 1]["in"][0] & BIT_SMASH and fr[i - 1]["p1"][1] < GROUND_Y:
            found = True
    return found, "Kontakt mit smash-Bit und P1 in der Luft"


def c_r09(doc, fr, window=30):
    dash_ticks = [i for i, f in enumerate(fr) if f["in"][0] & BIT_DASH]
    cs = [i for i in contacts(fr) if fr[i]["touch"][0] == 1]
    saved = any(any(d < c <= d + window for c in cs) for d in dash_ticks)
    return saved, f"dash-Bits={len(dash_ticks)}, Rettung innerhalb {window} Ticks={saved}"


def c_r10(doc, fr):
    top = max(f["touch"][1] for f in fr)
    return top >= 4, f"hoechster Beruehrungszaehler={top} (>= 4 = Fehler)"


def c_r11(doc, fr):
    top = max(speeds(fr))
    return top >= MAX_BALL_SPEED - 0.1, f"max |v|={top:.1f} (Deckel {MAX_BALL_SPEED:.0f})"


# Deviations that are documented rather than fixed. They are printed, but they
# do not fail the run -- see docs/handoffs/CC-01_REPORT.md.
KNOWN = {
    ("variable", "R-11"):
        "im gespielten Lauf wurde der Deckel nie erreicht (max 1156);"
        " die Referenz dafuer ist die Szene in fixed60",
}

CRITERIA = {
    "R-01": c_r01, "R-02": c_r02, "R-03": c_r03, "R-04": c_r04,
    "R-05": c_r05, "R-06": c_r06, "R-07": c_r07, "R-08": c_r08,
    "R-09": c_r09, "R-10": c_r10, "R-11": c_r11,
}
RALLIES = sorted(CRITERIA)


# ---------------------------------------------------------------------------
# Cross checks between the two passes
# ---------------------------------------------------------------------------

def input_roundtrip(src, dst):
    """The replayed pass must have consumed exactly the recorded inputs."""
    n = min(len(src["frames"]), len(dst["frames"]))
    bad = [t for t in range(n) if src["frames"][t]["in"] != dst["frames"][t]["in"]]
    return len(bad), (bad[0] if bad else None), n


def divergence(src, dst):
    """Max ball deviation and first tick above 0.5 px."""
    n = min(len(src["frames"]), len(dst["frames"]))
    worst, worst_t, first = 0.0, 0, None
    for t in range(n):
        a, b = src["frames"][t]["ball"], dst["frames"][t]["ball"]
        d = math.hypot(a[0] - b[0], a[1] - b[1])
        if d > worst:
            worst, worst_t = d, t
        if first is None and d > 0.5:
            first = t
    return worst, worst_t, first, n


# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--replay-dir", default="tests/replays")
    args = ap.parse_args()

    docs = {}
    failures = 0

    for mode in MODES:
        print(f"\n=== {mode} ===")
        for rid in RALLIES:
            path = os.path.join(args.replay_dir, mode, rid + ".json")
            if not os.path.exists(path):
                print(f"  {rid}  --  fehlt")
                failures += 1
                continue
            doc = load(path)
            docs[(mode, rid)] = doc
            ok, detail = CRITERIA[rid](doc, doc["frames"])
            driver = doc.get("driver", "human")
            known = KNOWN.get((mode, rid)) if not ok else None
            label = "PASS" if ok else ("bekannt" if known else "FAIL")
            print(f"  {rid}  {label:7} {doc['tick_count']:5} Ticks  "
                  f"{driver:22} {detail}")
            if known:
                print(f"           -> {known}")
            elif not ok:
                failures += 1

    both = [r for r in RALLIES if ("variable", r) in docs and ("fixed60", r) in docs]
    if both:
        print("\n=== variable vs fixed60 (gleiche Eingaben, gleicher Startzustand) ===")
        print("  ID     Ticks  Input-Roundtrip      max Abweichung   ab Tick > 0.5 px")
        for rid in both:
            src, dst = docs[("variable", rid)], docs[("fixed60", rid)]
            if str(dst.get("driver", "")).startswith("scripted"):
                print(f"  {rid}  synthetische Szene, kein Vergleich mit dem gespielten Lauf")
                continue
            bad, first_bad, n_in = input_roundtrip(src, dst)
            worst, worst_t, first, n = divergence(src, dst)
            rt = "identisch" if bad == 0 else f"{bad} Abw. ab {first_bad}"
            if bad:
                failures += 1
            print(f"  {rid}  {n:5}  {rt:20} {worst:9.2f} px @ {worst_t:<5} "
                  f"{first if first is not None else '-'}")

    print(f"\n{'OK' if failures == 0 else str(failures) + ' Befund(e)'}")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
