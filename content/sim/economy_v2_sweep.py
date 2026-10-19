"""Economy v2 sweep: pocket money 200, prices × P, move = 2.5 × weekly rent, shift pay × W.

Builds a candidate economy from content/economy.json in memory (the file is not changed), runs the same
simulator and checks as economy_sim.py and prints one line per (P, W). With --write P W it writes the
candidate to an output path, so the Dart A8 test can be run on it.

    python content/sim/economy_v2_sweep.py
    python content/sim/economy_v2_sweep.py --write 1.25 1.4 --out /tmp/economy.json
"""

from __future__ import annotations

import argparse
import copy
import math
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import economy_sim as sim  # noqa: E402

POCKET = 200
MOVE_RENTS = 2.5  # Denis: a move costs 2.5 weekly rents of the new home


def tens(x: float) -> int:
    return sim.dtens(x)


def fifties(x: float) -> int:
    return sim.dround(x / 50) * 50


def build(raw_full: dict, price_x: float, pay_x: float, goal_x: float | None = None, pocket: int = POCKET,
          move_rents: float = MOVE_RENTS) -> dict:
    """Return a full economy.json (with notes) for the variant; numbers only, structure untouched.

    price_x scales living costs (food, rent, pet food, leisure, clothes, decor, snack); goal_x scales goal prices
    (pets, transport, tech; defaults to price_x). Moves are always move_rents × the new weekly rent.
    """
    goal_x = price_x if goal_x is None else goal_x
    r = copy.deepcopy(raw_full)
    r["pocket_money"]["base"] = pocket
    for f in r["food"]["options"]:
        f["price"] = tens(f["price"] * price_x)
    for h in r["homes"]["options"]:
        h["weekly_cost"] = tens(h["weekly_cost"] * price_x)
        if h.get("is_goal"):
            h["price"] = fifties(move_rents * h["weekly_cost"])
    for p in r["pets"]["roster"]:
        p["price"] = fifties(p["price"] * goal_x)
        p["food_per_week"] = tens(p["food_per_week"] * price_x)
    for l in r["leisure"]["options"]:
        l["price"] = tens(l["price"] * price_x)
    for c in r["clothing"]["items"]:
        c["price"] = tens(c["price"] * price_x)
    for d in r.get("decor", {}).get("items", []):
        if "price" in d:
            d["price"] = tens(d["price"] * price_x)
    r["energy"]["snack"]["price"] = tens(r["energy"]["snack"]["price"] * price_x)
    r["transport"]["price"] = fifties(r["transport"]["price"] * goal_x)
    for t in r.get("tech", {}).get("options", []):
        t["price"] = fifties(t["price"] * goal_x)
    for jid, j in r["jobs"].items():
        if jid.startswith("_") or not isinstance(j, dict):
            continue  # notes
        if "tiers" in j:
            for t in j["tiers"]:
                t["pay"] = tens(t["pay"] * pay_x)
        else:
            j["pay"] = tens(j["pay"] * pay_x)
    return r


def simplify(r: dict, food_round: str) -> dict:
    """Simpler economy (Sasha's review, 15.10): whole ⚡ everywhere and no 😊 multipliers.

    - 😊 no longer scales pay or the ⚡ price of actions (per_point = 0), so the UI has no multipliers to show;
    - half-⚡ values become whole: a good shift's extra ⚡ and the transport discount → 1, food ⚡ rounded by
      food_round ("floor": 0.5 → 0, 1.5 → 1; "ceil": 0.5 → 1, 1.5 → 2).
    """
    r = copy.deepcopy(r)
    r["happiness"]["pay_mult"]["per_point"] = 0
    r["happiness"]["energy_cost_mult"]["per_point"] = 0
    r["jobs_pay_growth"]["good_shift_energy_extra"] = 1
    for e in r["transport"]["effects"]:
        if e.get("type") == "shift_energy_delta":
            e["value"] = -1
    rnd = math.floor if food_round == "floor" else math.ceil
    for f in r["food"]["options"]:
        f["energy_now"] = int(rnd(f["energy_now"]))
    return r


def evaluate(raw_full: dict, weeks: int, seed: int) -> tuple[list[str], dict]:
    eco = sim.Economy(sim.strip_notes(raw_full))
    results = {sid: sim.simulate(eco, sid, weeks, seed) for sid in sim.STYLES}
    problems = sim.analytic_checks(eco, weeks) + sim.result_checks(results, eco)
    cp, _ = sim.content_checks(eco, sim.load("jobs.json"), sim.load("events.json"))
    return problems + cp, results


def summary(results: dict) -> str:
    b = results["balanced"]
    s = results["saver"]
    st = sim.STYLES
    return (f"баланс: питомец н{sim.fmt_week(b['first_pet_week'])}, большая н{sim.fmt_week(b['first_big_week'])}, "
            f"стадия2 н{sim.fmt_week(b['stage_weeks'].get('stage_2'))}, стадия3 н{sim.fmt_week(b['stage_weeks'].get('stage_3'))}; "
            f"копилка: стадия3 н{sim.fmt_week(s['stage_weeks'].get('stage_3'))}; "
            f"транжира: нехватка {sum(1 for l in results['spender']['logs'] if l.shortfall)} нед, "
            f"семья {sum(1 for l in results['spender']['logs'] if l.family_help)}")


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("--weeks", type=int, default=10)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--prices", default="1.0,1.25,1.5")
    ap.add_argument("--pays", default="1.0,1.1,1.2,1.3,1.4,1.5,1.6,1.8,2.0")
    ap.add_argument("--goals", default="", help="через запятую; пусто — как цены")
    ap.add_argument("--write", nargs=3, type=float, metavar=("P", "W", "G"))
    ap.add_argument("--simple", choices=["none", "floor", "ceil"], default="none",
                    help="упрощённая экономика: целые ⚡, без множителей 😊; floor/ceil — как округлять ⚡ еды")
    ap.add_argument("--out", type=Path)
    args = ap.parse_args()

    raw_full = json.loads((sim.CONTENT / "economy.json").read_text(encoding="utf-8"))
    if args.write:
        v = build(raw_full, *args.write)
        if args.simple != "none":
            v = simplify(v, args.simple)
        out = args.out or Path("economy.json")
        out.write_text(json.dumps(v, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"записано: {out}")
        return 0

    goals = [float(x) for x in args.goals.split(",")] if args.goals else [None]
    for p in (float(x) for x in args.prices.split(",")):
        for g in goals:
            for w in (float(x) for x in args.pays.split(",")):
                v = build(raw_full, p, w, g)
                if args.simple != "none":
                    v = simplify(v, args.simple)
                problems, results = evaluate(v, args.weeks, args.seed)
                mark = "OK" if not problems else f"{len(problems)} пробл."
                gl = f"цели ×{g if g is not None else p:<4}"
                print(f"цены ×{p:<4} {gl} оплата ×{w:<4} {mark:<9} {summary(results)}")
                for pr in problems:
                    print("      ⚠", pr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
