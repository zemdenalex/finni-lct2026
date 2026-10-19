"""Day-by-energy simulator: the week splits into days, each day has its own ⚡ bar, and a separate satiety bar.

Denis 16.10: «отдельно сытость, отдельно энергия» · «игровой период не неделя, а по энергии каждый день: сон даёт
энергию, дополнительная — от сытости, разной еды, отдыха; день кончается, когда кончается энергия».

The money cycle stays weekly (pocket money at the week start, bills at the week end, three envelopes, weekly
results, growth points) — lessons, events, the piggy bank and stages are all keyed to weeks. What changes:
  - the week has D days; every morning ⚡ = sleep + satiety bonus (+ home bonus), the day ends when ⚡ runs out
    or Finni goes to sleep;
  - satiety 0..100: every action burns it, the night burns more, a meal refills it; full → extra ⚡ in the
    morning, hungry → less ⚡ and −😊;
  - one meal a day (the style's dish if it picked one for that day, else the home menu billed at the week end).

Variants are dicts of numbers (VARIANTS); nothing in content/ is changed. Standard library only.

    python content/sim/day_sim.py                 # table of variants × styles
    python content/sim/day_sim.py --variant B -v  # one variant, week by week
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import economy_sim as sim  # noqa: E402

# Numbers are PROPOSALS for Denis, not content.
COMMON = {
    # Denis 15.10: sleep raises ⚡ «до уровня», the carry-over is limited; part of satiety flows into ⚡.
    "carry_max": 1,                     # ⚡ left in the evening carried into the morning, at most
    "full_at": 60, "full_bonus": 1,     # satiety ≥ full_at in the morning → +⚡ (satiety → energy, never back)
    "hungry_at": 25, "hungry_malus": 1, "hungry_happiness": -2,
    "satiety_start": 70, "satiety_per_action": 10, "satiety_night": 20,
    "satiety_per_meal": {"base": 30, "per_energy": 15},  # dish satiety = base + per_energy × energy_now
    "pet_mode": "action",  # petting Finni: "action" (domain: once per game day = per action) · "day" · "none"
}
VARIANTS = {
    "A": {**COMMON, "label": "A · неделя = 3 дня",
          "days": 3, "sleep_level": 4, "meals_per_day": 1, "meal_price_x": 1.0, "pay_x": 1.0,
          "max_shifts_per_day": 2, "week_shift_cap": 3, "leisure_repeat": 1},
    "B": {**COMMON, "label": "B · неделя = 5 дней",
          "days": 5, "sleep_level": 4, "meals_per_day": 1, "meal_price_x": 0.6, "pay_x": 0.7,
          "max_shifts_per_day": 1, "week_shift_cap": 5, "leisure_repeat": 2},
    "C": {**COMMON, "label": "C · неделя = 7 дней",
          "days": 7, "sleep_level": 4, "meals_per_day": 1, "meal_price_x": 0.45, "pay_x": 0.5,
          "max_shifts_per_day": 1, "week_shift_cap": 6, "leisure_repeat": 2},
}


def dish_satiety(v: dict, dish: dict) -> float:
    s = v["satiety_per_meal"]
    return s["base"] + s["per_energy"] * dish["energy_now"]


def simulate_days(eco: sim.Economy, style_id: str, weeks: int, v: dict, verbose: bool = False) -> dict:
    """Same money rules as economy_sim.simulate; the ⚡ pool and meals are per day, plus satiety."""
    style = sim.STYLES[style_id]
    st = sim.State(happiness=eco.hap["start"])
    gift = eco.raw.get("start_gift")
    if gift and gift.get("to") == "goal":
        st.savings += gift["amount"]
    logs: list[sim.WeekLog] = []
    first_pet_week = first_big_week = None
    stage_weeks: dict[str, int] = {}
    drain = eco.en["living_drain_per_action"]
    goals = style["goals"]
    satiety = v["satiety_start"]
    left = 0.0
    mpx = v["meal_price_x"]
    days_total = hungry_days = idle_days = no_energy_days = 0
    actions_per_day: list[int] = []

    def price_of(food_id: str) -> int:
        return sim.dtens(eco.food[food_id]["price"] * mpx)

    for week in range(1, weeks + 1):
        pocket = eco.pocket(week)
        st.cash += pocket
        hap_week = 0.0
        earned = shifts = 0
        bought: list[str] = []
        per_job: dict[str, int] = {}
        leisure_h = 0.0
        h0 = st.happiness
        pets_at_start = list(st.pets)
        home_at_start = st.home
        stage_at_start = st.stage
        goals_bought = 0
        good_shifts = 0
        food_id = style["food"]
        home_meals = 0  # billed at the week end, like the weekly sim
        # The style's weekly shift habit scales with the week length (2 of 3 days → 2 of 3 · days).
        habit = style["max_shifts"] if style["max_shifts"] >= 99 else math.ceil(style["max_shifts"] * v["days"] / 3)
        week_cap = min(habit, v["week_shift_cap"])
        plan = style["leisure"][(week - 1) % len(style["leisure"])]
        leisure_todo = (list(plan) + (["pet_play"] if style["pet_play"] and st.pets else [])) * v["leisure_repeat"]
        ended_by = "sleep"

        def reserve() -> int:
            if not style["reserve_required"]:
                return 0
            f, h, p = sim.required_cost(st, eco, week, food_id, 0)
            return f + h + p + price_of(food_id) * home_meals

        for day in range(1, v["days"] + 1):
            days_total += 1
            # sleep «до уровня»: the level plus what is left from the evening, limited
            energy = v["sleep_level"] + min(left, v["carry_max"])
            st.carry = 0
            if day == 1:
                energy += eco.homes[st.home]["energy_per_week"]
            if satiety >= v["full_at"]:
                energy += v["full_bonus"]
            elif satiety < v["hungry_at"]:
                energy -= v["hungry_malus"]
                hap_week += v["hungry_happiness"]
                hungry_days += 1
            energy = max(0.0, min(energy, eco.en.get("max_per_week", math.inf)))
            actions = 0
            # --- the day's meals: the style's dishes in order, else the home menu (billed at the week end)
            for m in range(v["meals_per_day"]):
                k = (day - 1) * v["meals_per_day"] + m
                meals = style["meals"]
                dish_id = meals[k] if k < len(meals) else None
                if dish_id and price_of(dish_id) <= st.cash:
                    st.cash -= price_of(dish_id)
                    dish = eco.food[dish_id]
                    bought.append(dish_id)
                else:
                    dish = eco.food[food_id]
                    home_meals += 1
                energy += dish["energy_now"]
                hap_week += dish["happiness"]
                satiety = min(100.0, satiety + dish_satiety(v, dish))

            def cost_of(base: float, shift: bool) -> float:
                if shift:
                    return eco.shift_energy(base, h0, st.transport, drain)
                return base * eco.energy_mult(h0) + drain

            # --- shifts of the day
            day_shifts = 0
            while shifts < week_cap and day_shifts < v["max_shifts_per_day"]:
                best = None
                for jid, tier, pay, en_, unlocked_by in eco.job_options():
                    if unlocked_by == "transport" and not st.transport:
                        continue
                    if unlocked_by and unlocked_by.startswith("pet_") and unlocked_by not in st.pets:
                        continue
                    if unlocked_by in eco.abilities and not any(unlocked_by in eco.tech[t]["unlocks"] for t in st.tech):
                        continue
                    if per_job.get(jid, 0) >= eco.raw["week"]["max_shifts_per_job_per_week"]:
                        continue
                    c = cost_of(en_, True)
                    if c > energy + 1e-9:
                        continue
                    p = eco.ix(pay, week) * eco.pay_mult(h0) * eco.experience_mult(st.experience) * eco.pay_step(st.stage)
                    if best is None or p / c > best[0]:
                        best = (p / c, jid, sim.dtens(p), c)
                if best is None:
                    break
                _, jid, rate, c = best
                score = style["scores"][st.shifts_total % len(style["scores"])]
                st.shifts_total += 1
                pay = rate + eco.efficiency_bonus(rate, score)
                energy -= c
                hap_week -= eco.day_drain
                if eco.is_good(score):
                    energy -= min(eco.pay_growth.get("good_shift_energy_extra", 0.0), max(0.0, energy))
                    hap_week += eco.pay_growth.get("good_shift_happiness", 0)
                    st.experience += 1
                    good_shifts += 1
                st.cash += pay
                earned += pay
                shifts += 1
                day_shifts += 1
                actions += 1
                per_job[jid] = per_job.get(jid, 0) + 1
            # --- leisure: whatever the week's plan still has, if ⚡ and money allow
            for lid in list(leisure_todo):
                l = eco.leisure[lid]
                c = cost_of(l["energy"], False)
                price = eco.ix(l["price"], week)
                if c > energy + 1e-9 or price > st.cash or (price and st.cash - price < reserve()):
                    continue
                energy -= c
                st.cash -= price
                h = l["happiness"] + (l.get("per_extra_pet", 0) * (len(st.pets) - 1) if lid == "pet_play" else 0)
                h = max(0, min(h, eco.hap["leisure_weekly_cap"] - leisure_h))
                leisure_h += h
                hap_week += h - eco.day_drain
                bought.append(lid)
                leisure_todo.remove(lid)
                actions += 1
            # --- pet touch and petting Finni: once per game day (actions)
            if st.pets:
                hap_week += eco.raw["pets"]["daily_touch_happiness"] * actions
            # petting Finni: the domain gives it once per game day = once per action ("action"); "day" = once
            # per day of the week whatever was done; "none" = never petted
            pet_mode = v.get("pet_mode", "action")
            hap_week += eco.hap.get("finni_pet", 0) * (actions if pet_mode == "action" else 1 if pet_mode == "day" else 0)
            satiety = max(0.0, satiety - v["satiety_per_action"] * actions - v["satiety_night"])
            left = max(0.0, energy)
            actions_per_day.append(actions)
            if actions == 0:
                cheapest = min([cost_of(en_, True) for _, _, _, en_, ub in eco.job_options() if not ub]
                               + [cost_of(eco.leisure["park"]["energy"], False)])
                if energy + 1e-9 >= cheapest:
                    idle_days += 1      # ⚡ was there, the style had nothing left to do
                else:
                    no_energy_days += 1
            # sleeping with ⚡ left: carry to the next week's first morning, like the weekly sleep bonus
            if day == v["days"]:
                if style["sleep_early"] and energy >= eco.en["sleep"]["min_left_for_bonus"]:
                    st.carry = eco.en["sleep"]["carry_next_week"]
                    hap_week += eco.en["sleep"]["happiness"]
                    ended_by = "sleep"
                else:
                    ended_by = "exhausted"
                    hap_week += eco.en["exhausted"]["happiness"]

        # --- clothes (as in the weekly sim)
        if style["clothes_every"] and week % style["clothes_every"] == 0:
            for cid, c in sorted(eco.clothing.items(), key=lambda kv: -kv[1]["price"]):
                if st.cash - c["price"] >= reserve() and c["price"] <= st.cash:
                    st.cash -= c["price"]
                    st.clothes.append((week, c["fade"]))
                    bought.append(cid)
                    break

        # --- bills: rent + pet food + home meals, with the shortfall rule
        f_cost = price_of(food_id) * home_meals
        _, h_cost, p_cost = sim.required_cost(st, eco, week, food_id, 0)
        shortfall = family = withdrawn = 0
        pay_p = min(st.cash, p_cost)
        st.cash -= pay_p
        family += p_cost - pay_p
        if home_meals and st.cash < f_cost + h_cost and food_id != "food_simple":
            food_id = "food_simple"
            shortfall += 1
            f_cost = price_of(food_id) * home_meals
        need = f_cost + h_cost
        if st.cash < need:
            shortfall += 1
            gap = need - st.cash
            take = min(st.savings, gap)
            st.savings -= take
            withdrawn = int(take)
            st.cash += take
            gap -= take
            family += gap
            st.cash += gap
        st.cash -= need
        if family:
            hap_week += eco.raw["shortfall_rule"]["order"][3]["happiness"]
        required_total = f_cost + h_cost + p_cost

        deposit = 0
        if style["save_share"] > 0:
            free = st.cash - style["keep_buffer"]
            deposit = int(max(0, free) * style["save_share"])
            if style.get("save_first"):
                deposit = max(deposit, min(max(0, free), math.ceil(0.1 * (pocket + earned))))
            st.cash -= deposit
            st.savings += deposit

        while st.goal_idx < len(goals):
            goal = goals[st.goal_idx]
            price = eco.goal_price(goal)
            if st.savings < price:
                break
            if goal in eco.homes and eco.growth.get("stage_by_rent") and eco.homes[goal].get("stage"):
                need_pts = next(s["min_points"] for s in eco.growth["stages"] if s["place"] == eco.homes[goal]["stage"])
                if st.growth_points < need_pts:
                    break
            st.savings -= price
            st.goal_idx += 1
            goals_bought += 1
            bought.append("GOAL:" + goal)
            hap_week += eco.hap["goal_reached_bonus"]
            if goal in eco.pets:
                st.pets.append(goal)
                first_pet_week = first_pet_week or week
            elif goal == "transport":
                st.transport = True
            elif goal in eco.tech:
                st.tech.append(goal)
            else:
                st.home = goal
            if price >= eco.transport["price"] or goal in eco.homes:
                first_big_week = first_big_week or week

        g = eco.growth
        income = pocket + earned
        if family == 0:
            st.growth_points += g["points"]["required_covered"]
        if shortfall == 0:
            st.growth_points += g["points"]["plan_kept"]
        net_saved = deposit - withdrawn
        saved_regularly = bool(income and net_saved > 0 and net_saved >= g["saved_regularly_min_share"] * income)
        if saved_regularly:
            st.growth_points += g["points"]["saved_regularly"]
        home_place = eco.homes[st.home].get("stage")
        for s in g["stages"]:
            if st.growth_points >= s["min_points"]:
                if g.get("stage_by_rent") and home_place:
                    order = [x["place"] for x in g["stages"]]
                    if order.index(s["place"]) > order.index(home_place):
                        break
                stage_weeks.setdefault(s["id"], week)
                st.stage = s["id"]

        growth, why = sim.growth_verdict(eco, earned, st.earned_last, saved_regularly, goals_bought > 0,
                                         st.stage != stage_at_start)
        wg = eco.week_growth
        if growth == "up":
            st.flat_weeks = 0
            hap_week += wg.get("growth_bonus", 0)
        elif growth == "flat":
            st.flat_weeks += 1
            hap_week -= sim.stagnation_penalty(eco, st.flat_weeks)
        st.earned_last = earned
        hap_week += eco.homes[home_at_start]["happiness_per_week"]
        hap_week += min(sum(eco.pets[p]["happiness_per_week"] for p in pets_at_start), eco.raw["pets"]["happiness_total_cap"])
        for wb, fade in st.clothes:
            age = week - wb
            if 0 <= age < len(fade):
                hap_week += fade[age]
        d = eco.hap["weekly_decay"]
        decay = d["base"] + d["k"] * (h0 - eco.hap["neutral"])
        st.happiness = max(eco.hap["min"], min(eco.hap["max"], st.happiness + hap_week - sim.dround(decay)))
        logs.append(sim.WeekLog(week, pocket, earned, shifts, required_total, shortfall, int(family), withdrawn,
                                deposit, int(st.cash), int(st.savings), round(st.happiness, 1), 0.0, ended_by,
                                bought, st.stage, st.experience, good_shifts, growth, why))
        if verbose:
            print(f"  [{style_id}] w{week}: earned {earned} ({shifts} sh) req {required_total} fam {int(family)} "
                  f"cash {int(st.cash)} sav {int(st.savings)} 😊 {st.happiness:.0f} сытость {satiety:.0f} {bought}")
    return {"style": style_id, "logs": logs, "first_pet_week": first_pet_week, "first_big_week": first_big_week,
            "stage_weeks": stage_weeks, "hungry_days": hungry_days, "days": days_total,
            "actions_per_day": sum(actions_per_day) / max(1, len(actions_per_day)),
            "idle_days": idle_days, "no_energy_days": no_energy_days}


def variant_economy(raw: dict, v: dict) -> dict:
    """Numbers of the variant: pay × pay_x, and the per-action rules rescaled to the week length.

    The submitted numbers are tuned for ~3 game days a week. With D days a week the same per-shift and
    per-meal rules fire D/3 times as often, so they are scaled by 3/D: experience growth per shift
    (×1.01 → ×1.01^(3/D)) and the 😊 of a dish (×3/D) — the weekly totals stay where they were.
    """
    r = sim.strip_notes(raw)
    k = 3 / v["days"]
    for j in r["jobs"].values():
        for t in j.get("tiers", [j]):
            t["pay"] = sim.dtens(t["pay"] * v["pay_x"])
    g = r["jobs_pay_growth"]
    g["experience_mult_per_shift"] = g["experience_mult_per_shift"] ** k
    for f in r["food"]["options"]:
        f["happiness"] = f["happiness"] * k / v["meals_per_day"] * r["food"]["meals_per_week"] / 3
    return r


def evaluate(raw: dict, v: dict, weeks: int = 10) -> tuple[list[str], dict]:
    eco = sim.Economy(variant_economy(raw, v))
    res = {sid: simulate_days(eco, sid, weeks, v) for sid in sim.STYLES}
    problems = sim.result_checks(res, eco)
    for sid, r in res.items():
        if r["hungry_days"] > r["days"] // 3:
            problems.append(f"{sid}: голоден {r['hungry_days']} дней из {r['days']} — сытость не держится")
        if r["no_energy_days"] > r["days"] // 3:
            problems.append(f"{sid}: {r['no_energy_days']} дней из {r['days']} без действия — сил не хватает")
        if r["idle_days"] > r["days"] // 3:
            problems.append(f"{sid}: {r['idle_days']} дней из {r['days']} без действия при силах — нечем заняться "
                            f"(лимит смен недели, досуг раз в неделю)")
    return problems, res


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", choices=sorted(VARIANTS), action="append")
    ap.add_argument("--weeks", type=int, default=10)
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--set", action="append", default=[], metavar="KEY=VAL", help="переопределить число варианта")
    args = ap.parse_args()
    raw = sim.load("economy.json")
    for key in args.variant or sorted(VARIANTS):
        v = dict(VARIANTS[key])
        for kv in args.set:
            k, _, val = kv.partition("=")
            v[k] = float(val) if "." in val else int(val) if val.lstrip("-").isdigit() else val
        problems, res = evaluate(raw, v, args.weeks)
        print(f"\n{v['label']}: {'🟢 проблем нет' if not problems else f'🔴 проблем {len(problems)}'}")
        print(f"  {'стиль':<10}{'действий/день':>14}{'голодных дней':>15}{'пустых дней':>12}{'смен/нед':>9}{'питомец':>8}{'большая':>8}"
              f"{'стадия 3':>9}{'семья':>6}{'😊 кон':>7}")
        for sid, r in res.items():
            L = r["logs"]
            if args.verbose:
                simulate_days(sim.Economy(variant_economy(raw, v)), sid, args.weeks, v, True)
            print(f"  {sim.STYLES[sid]['label']:<10}{r['actions_per_day']:>14.1f}{r['hungry_days']:>9}/{r['days']:<5}"
                  f"{str(r['idle_days']) + '+' + str(r['no_energy_days']):>12}"
                  f"{sum(l.shifts for l in L) / len(L):>9.1f}{sim.fmt_week(r['first_pet_week']):>8}"
                  f"{sim.fmt_week(r['first_big_week']):>8}{sim.fmt_week(r['stage_weeks'].get('stage_3')):>9}"
                  f"{sum(1 for l in L if l.family_help):>6}{L[-1].happiness:>7.0f}")
        for p in problems:
            print("  ⚠", p)
    return 0


if __name__ == "__main__":
    sys.exit(main())
