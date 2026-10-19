"""Day mode (variant A, 3 days a week) × economy variants: submitted numbers, the pocket-vs-bills gap fixes, v2.

Question 6 of docs/final/day-energy-model.md: build the day model on the submitted numbers or on v2?
And the gap: 400 pocket money a week against 460 of bills (room 250 + 3 home meals × 70), so even a perfect plan
does not cover the bills without a shift.

Every row is an economy built in memory (content/ is not changed) and run through day_sim (variant A). Per row:
  - simulator problems (economy_sim.result_checks + day checks);
  - weeks until each style buys a goal, each goal run on its own (the style keeps its spending, its goal list is
    replaced): fish 400, bike (transport) 1800, Moscow (flat, then the Moscow home);
  - the spender with petting Finni per action (the domain today), once a day, never;
  - with --write DIR, the row's economy.json goes to DIR/<row>.json for the Dart A8 run.

    python content/sim/day_economy_variants.py
    python content/sim/day_economy_variants.py --write /tmp/rows
"""

from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import day_sim  # noqa: E402
import economy_sim as sim  # noqa: E402
import economy_v2_sweep as v2  # noqa: E402

GOALS = {
    "рыбка": ["pet_fish"],
    "велосипед": ["transport"],
    "Москва": ["home_flat", "home_house"],
}


def rows(raw: dict) -> list[tuple[str, str, dict]]:
    """(key, label, economy) for every row of the table."""
    out = [("submitted", "сдано: карманные 400, счета 460", raw)]
    r = copy.deepcopy(raw)
    r["pocket_money"]["base"] = 460
    out.append(("pocket460", "карманные 460 (= стипендия +60 по деньгам)", r))
    r = copy.deepcopy(raw)
    for h in r["homes"]["options"]:
        if h["id"] == "home_room":
            h["weekly_cost"] = 190
    out.append(("bills400", "счета 400 (комната 190)", r))
    for n, (p, w) in enumerate([(1.0, 1.2), (1.2, 1.4), (1.5, 1.7)], 1):
        out.append((f"v2_{n}", f"v2·{n} (цены ×{p}, оплата ×{w}, карманные 200)", v2.build(raw, p, w, 1.0)))
    for n, (p, w) in enumerate([(1.0, 1.4), (1.2, 1.4), (1.5, 1.8)], 1):
        out.append((f"v2_{n}s", f"v2·{n} упрощённая (оплата ×{w})",
                    v2.simplify(v2.build(raw, p, w, 1.0), "floor")))
    return out


def bills(r: dict) -> int:
    room = next(h for h in r["homes"]["options"] if h["id"] == "home_room")["weekly_cost"]
    simple = next(f for f in r["food"]["options"] if f["id"] == "food_simple")["price"]
    return room + simple * r["food"]["meals_per_week"]


def goal_week(res: dict, goal: str) -> int | None:
    for log in res["logs"]:
        if "GOAL:" + goal in log.bought:
            return log.week
    return None


def run(raw: dict, v: dict, weeks: int) -> dict:
    problems, base = day_sim.evaluate(raw, v, weeks)
    eco = sim.Economy(day_sim.variant_economy(raw, v))
    goal_weeks: dict[str, dict[str, int | None]] = {}
    saved = copy.deepcopy(sim.STYLES)
    try:
        for name, goals in GOALS.items():
            goal_weeks[name] = {}
            for sid in saved:
                sim.STYLES[sid] = {**saved[sid], "goals": goals}
                res = day_sim.simulate_days(eco, sid, weeks, v)
                goal_weeks[name][sid] = goal_week(res, goals[-1])
                sim.STYLES[sid] = saved[sid]
    finally:
        sim.STYLES.clear()
        sim.STYLES.update(saved)
    spender = {}
    for mode in ("action", "day", "none"):
        res = day_sim.simulate_days(eco, "spender", weeks, {**v, "pet_mode": mode})
        L = res["logs"]
        spender[mode] = {
            "first_goal": next((l.week for l in L if any(b.startswith("GOAL:") for b in l.bought)), None),
            "family": sum(1 for l in L if l.family_help),
            "short": sum(1 for l in L if l.shortfall),
            "happy": L[-1].happiness,
        }
    return {"problems": problems, "goal_weeks": goal_weeks, "spender": spender, "base": base}


def fmt(w: int | None, weeks: int) -> str:
    return f"н{w}" if w else f"нет за {weeks}"


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("--weeks", type=int, default=10)
    ap.add_argument("--write", type=Path, help="папка для economy.json каждой строки (прогон A8 в Dart)")
    ap.add_argument("--days", default="A", help="варианты дня через запятую: A (3 дня), B (5), C (7)")
    ap.add_argument("--rows", default="", help="ключи строк через запятую; пусто — все")
    ap.add_argument("--summary", action="store_true", help="одна строка на (строка, вариант дня)")
    ap.add_argument("--set", action="append", default=[], metavar="KEY=VAL", help="переопределить число дня")
    args = ap.parse_args()
    raw_full = json.loads((sim.CONTENT / "economy.json").read_text(encoding="utf-8"))
    styles = list(sim.STYLES)
    keep = set(args.rows.split(",")) if args.rows else None
    for day_key in args.days.split(","):
        v = dict(day_sim.VARIANTS[day_key])
        for kv in args.set:
            k, _, val = kv.partition("=")
            v[k] = float(val) if "." in val else int(val)
        for key, label, r in rows(raw_full):
            if keep and key not in keep:
                continue
            if args.write:
                args.write.mkdir(parents=True, exist_ok=True)
                (args.write / f"{key}.json").write_text(json.dumps(r, ensure_ascii=False, indent=2) + "\n",
                                                       encoding="utf-8")
            out = run(sim.strip_notes(r), v, args.weeks)
            if args.summary:
                gw = out["goal_weeks"]
                base = out["base"]
                apd = sum(x["actions_per_day"] for x in base.values()) / len(base)
                idle = sum(x["idle_days"] for x in base.values())
                days = sum(x["days"] for x in base.values())
                sp = out["spender"]["action"]
                print(f"{day_key} | {key} | {len(out['problems'])} | "
                      f"{fmt(gw['рыбка']['balanced'], args.weeks)} · {fmt(gw['велосипед']['balanced'], args.weeks)} · "
                      f"{fmt(gw['Москва']['balanced'], args.weeks)} | "
                      f"{fmt(sp['first_goal'], args.weeks)}, семья {sp['family']} | {apd:.1f} | {idle}/{days}")
                continue
            print(f"\n## {day_key} · {key} · {label} · карманные {r['pocket_money']['base']} / счета {bills(r)}")
            print(f"проблем: {len(out['problems'])}")
            for p in out["problems"]:
                print("  ⚠", p)
            print("цель | " + " | ".join(sim.STYLES[s]["label"] for s in styles))
            for name, per in out["goal_weeks"].items():
                print(f"{name} | " + " | ".join(fmt(per[s], args.weeks) for s in styles))
            for mode, sp in out["spender"].items():
                print(f"транжира, поглаживание {mode}: 1-я цель {fmt(sp['first_goal'], args.weeks)}, "
                      f"нехватка {sp['short']} нед, семья {sp['family']} нед, 😊 к концу {sp['happy']:.0f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
