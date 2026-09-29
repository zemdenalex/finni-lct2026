"""Economy simulator for «Питомец Финни».

Reads content/economy.json (and validates jobs.json / events.json when present),
plays N weeks for four play styles and prints a balance table plus a list of
balance problems. Standard library only.

    python content/sim/economy_sim.py [--weeks 10] [--seed 7] [--verbose]
"""

from __future__ import annotations

import argparse
import json
import math
import random
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

CONTENT = Path(__file__).resolve().parent.parent


def strip_notes(obj):
    """Drop every key that starts with '_' (comments), recursively."""
    if isinstance(obj, dict):
        return {k: strip_notes(v) for k, v in obj.items() if not k.startswith("_")}
    if isinstance(obj, list):
        return [strip_notes(v) for v in obj]
    return obj


def dround(x: float) -> int:
    """Round half away from zero, like Dart's num.round() in the domain."""
    return int(math.floor(abs(x) + 0.5)) * (1 if x >= 0 else -1)


def dtens(x: float) -> int:
    """Shift pay and bonus the child sees: to tens, like roundTens in the domain."""
    return dround(x / 10) * 10


def load(name: str):
    path = CONTENT / name
    if not path.exists():
        return None
    return strip_notes(json.loads(path.read_text(encoding="utf-8")))


# ---------------------------------------------------------------- economy view


class Economy:
    def __init__(self, raw: dict):
        self.raw = raw
        self.pm = raw["pocket_money"]
        self.food = {f["id"]: f for f in raw["food"]["options"]}
        # Meals (Denis 29.09, 938): Finni eats meals_per_week times a week; meals the child did not pick are
        # eaten at home at the week end (home menu × meals left) — their ⚡ goes to the next week.
        self.meals_per_week = raw["food"]["meals_per_week"]
        self.homes = {h["id"]: h for h in raw["homes"]["options"]}
        self.pets = {p["id"]: p for p in raw["pets"]["roster"]}
        self.leisure = {l["id"]: l for l in raw["leisure"]["options"]}
        self.clothing = {c["id"]: c for c in raw["clothing"]["items"]}
        self.jobs = raw["jobs"]
        self.hap = raw["happiness"]
        self.en = raw["energy"]
        self.transport = raw["transport"]
        # Tech goals (Denis 29.09, 941 #5): a laptop unlocks the programmer, a better one the hard tasks.
        self.tech = {t["id"]: t for t in raw.get("tech", {}).get("options", [])}
        self.abilities = {a for t in self.tech.values() for a in t["unlocks"]}
        self.growth = raw["growth"]
        self.pay_growth = raw.get("jobs_pay_growth", {})
        self.decor = raw.get("decor", {"items": []})
        # P7 (Denis 28.09): every game day drains 😊 like ⚡; the week-end growth check.
        self.day_drain = self.hap.get("day_drain", 0)
        self.week_growth = self.hap.get("week_growth", {})

    def pay_step(self, stage_id: str) -> float:
        """P1: small stage pay step after moving (growth.stages[].pay_step)."""
        for s in self.growth["stages"]:
            if s["id"] == stage_id:
                return s.get("pay_step", 1)
        return 1

    def experience_mult(self, good_shifts: int) -> float:
        """P1: pay × experience_mult_per_shift ^ well-done shifts over the whole game."""
        return self.pay_growth.get("experience_mult_per_shift", 1.0) ** good_shifts

    def is_good(self, score: float) -> bool:
        """P1: a shift is well done when the mini-game score reaches good_score_min."""
        return score >= self.pay_growth.get("good_score_min", 0.0) - 1e-9

    def efficiency_bonus(self, rate: int, score: float) -> int:
        """P6: up to efficiency_bonus_max_share of the rate, scaled by score, good shifts only."""
        if not self.is_good(score):
            return 0
        top = dtens(rate * self.pay_growth.get("efficiency_bonus_max_share", 0.0))  # JobOffer.efficiencyBonusMax
        return dtens(top * score)  # JobOffer.bonusFor

    def shift_energy(self, base: float, h: float, transport: bool, drain: float) -> float:
        """Same order as the domain: base × mood, then transport delta with min_cost, then +living."""
        e = base * self.energy_mult(h)
        if transport:
            eff = next(x for x in self.transport["effects"] if x["type"] == "shift_energy_delta")
            e = max(eff["min_cost"], e + eff["value"])
        return round(e + drain, 2)

    def index(self, week: int) -> float:
        curve = self.pm["index_curve"]
        if week <= len(curve):
            return curve[week - 1]
        after = self.pm["index_after_curve"]
        steps = (week - len(curve)) // after["every_weeks"] + 1
        return min(after["cap"], curve[-1] + steps * after["step"])

    def ix(self, value: float, week: int) -> int:
        return int(round(value * self.index(week)))

    def pocket(self, week: int) -> int:
        return self.ix(self.pm["base"], week)

    def goal_price(self, goal: str) -> int:
        if goal == "transport":
            return self.transport["price"]
        if goal in self.pets:
            return self.pets[goal]["price"]
        if goal in self.tech:
            return self.tech[goal]["price"]
        return self.homes[goal]["price"]

    def pay_mult(self, h: float) -> float:
        m = self.hap["pay_mult"]
        return max(m["min"], min(m["max"], 1 + m["per_point"] * (h - self.hap["neutral"])))

    def energy_mult(self, h: float) -> float:
        m = self.hap["energy_cost_mult"]
        return max(m["min"], min(m["max"], 1 - m["per_point"] * (h - self.hap["neutral"])))

    def job_options(self):
        """Yield (job_id, tier_id, pay, energy, unlocked_by)."""
        for jid, j in self.jobs.items():
            if "tiers" in j:
                for t in j["tiers"]:
                    yield jid, t["id"], t["pay"], t["energy"], t.get("unlocked_by", j.get("unlocked_by"))
            else:
                yield jid, None, j["pay"], j["energy"], j.get("unlocked_by")



# ---------------------------------------------------------------- play styles

STYLES = {
    "saver": {
        "label": "Копилка",
        "food": "food_simple",
        "meals": [],
        "max_shifts": 2,
        "leisure": [["park"]],
        "pet_play": True,
        "sleep_early": True,
        "reserve_required": True,
        "save_share": 1.0,
        "keep_buffer": 0,
        "goals": ["pet_hamster", "home_flat", "transport", "pet_turtle", "home_house"],
        "clothes_every": 0,
        "snacks": 0,
        "scores": [1.0],
    },
    "spender": {
        "label": "Транжира",
        "food": "food_tasty",
        "meals": ["food_tasty", "food_burger", "food_tasty"],
        "max_shifts": 2,
        "leisure": [["cinema"], ["cafe"]],
        "pet_play": True,
        "sleep_early": True,
        "reserve_required": False,
        # Lessons after shifts offer "put part of the pay to the goal" (jobs.json -> lessons); the spender takes it
        # now and then — a fifth of what is left. Without it the style never reaches any goal (criteria §1 p. 4).
        "save_share": 0.3,
        "keep_buffer": 0,
        "goals": ["pet_fish", "pet_hamster"],
        "clothes_every": 5,
        "snacks": 0,
        "scores": [0.5, 1.0],
    },
    "worker": {
        "label": "Трудяга",
        "food": "food_regular",
        "meals": ["food_fish", "food_fish", "food_soup"],
        "max_shifts": 99,
        "leisure": [[]],
        "pet_play": False,
        "sleep_early": False,
        "reserve_required": True,
        "save_share": 1.0,
        "keep_buffer": 0,
        "goals": ["home_flat", "transport", "home_house", "tech_laptop", "pet_kitten", "pet_dog"],
        "clothes_every": 0,
        "snacks": 2,
        "scores": [1.0],
    },
    "stagnant": {
        "label": "На месте",
        "food": "food_regular",
        "meals": [],
        "max_shifts": 2,
        "leisure": [["park"]],
        "pet_play": False,
        "sleep_early": True,
        "reserve_required": True,
        "save_share": 0.0,
        "keep_buffer": 0,
        "goals": [],
        "clothes_every": 0,
        "snacks": 0,
        "scores": [0.5],
    },
    "balanced": {
        "label": "Баланс",
        "food": "food_regular",
        "meals": ["food_soup", "food_syrniki"],
        "max_shifts": 2,
        "leisure": [["park"], ["cafe"]],
        "pet_play": True,
        "sleep_early": True,
        "reserve_required": True,
        "save_share": 0.9,
        "save_first": True,
        "keep_buffer": 5,
        "goals": ["pet_hamster", "home_flat", "transport", "home_house"],
        "clothes_every": 4,
        "snacks": 0,
        "scores": [1.0, 0.75, 0.5],
    },
}


# ---------------------------------------------------------------- simulation


@dataclass
class State:
    cash: float = 0
    savings: float = 0
    happiness: float = 50
    carry: float = 0
    home: str = "home_room"
    pets: list = field(default_factory=list)
    transport: bool = False
    tech: list = field(default_factory=list)  # tech goals bought (laptop …)
    clothes: list = field(default_factory=list)  # (week_bought, fade list)
    growth_points: int = 0
    stage: str = "stage_1"
    goal_idx: int = 0
    experience: int = 0  # P1: well-done shifts over the whole game
    shifts_total: int = 0  # every shift, drives the style's score cycle
    earned_last: int | None = None  # P7: last week's earnings (None before the first closed week)
    flat_weeks: int = 0  # P7: weeks without growth in a row


@dataclass
class WeekLog:
    week: int
    pocket: int
    earned: int
    shifts: int
    required: int
    shortfall: int
    family_help: int
    withdrawn: int
    deposited: int
    cash: int
    savings: int
    happiness: float
    energy_start: float
    ended_by: str
    bought: list
    stage: str
    experience: int
    good_shifts: int
    growth: str  # P7 verdict: "up" / "flat" / "" (week 1 has nothing to compare with)
    growth_why: list


def perks(st: State, eco: Economy, ptype: str):
    for pid in st.pets:
        perk = eco.pets[pid].get("perk", {})
        if perk.get("type") == ptype:
            yield perk


def required_cost(st: State, eco: Economy, week: int, food_id: str, meals_left: int) -> tuple[int, int, int]:
    food = eco.ix(eco.food[food_id]["price"], week) * meals_left
    home = eco.ix(eco.homes[st.home]["weekly_cost"], week)
    pets = sum(eco.ix(eco.pets[p]["food_per_week"], week) for p in st.pets)
    return food, home, pets


def growth_verdict(eco: Economy, earned: int, earned_last: int | None, saved_regularly: bool,
                   goal_bought: bool, stage_up: bool) -> tuple[str, list]:
    """P7 (Denis 28.09): growth this week vs the last one — same rule as WorldGame.payBills.

    Week 1 has nothing to compare with: no verdict. Otherwise the week grew when at least one holds:
    earned (shifts + event money, no stipend) ≥ last week × (1 + income_min_share) and > 0; saved
    ≥ saved_regularly_min_share of the week's income; a goal was bought; Finni moved to a new stage.
    """
    if earned_last is None:
        return "", []
    why = []
    share = eco.week_growth.get("income_min_share", 0.0)
    if earned > 0 and earned >= earned_last * (1 + share) - 1e-9:
        why.append("income")
    if saved_regularly:
        why.append("saved")
    if goal_bought:
        why.append("goal")
    if stage_up:
        why.append("stage")
    return ("up" if why else "flat"), why


def stagnation_penalty(eco: Economy, flat_weeks: int) -> int:
    """P7: a week without growth costs stagnation_step × weeks without growth in a row, up to stagnation_max."""
    wg = eco.week_growth
    step = wg.get("stagnation_step", 0)
    return min(wg.get("stagnation_max", step), step * flat_weeks)


def simulate(eco: Economy, style_id: str, weeks: int, seed: int, verbose: bool = False):
    style = STYLES[style_id]
    rng = random.Random(seed)
    st = State(happiness=eco.hap["start"])
    gift = eco.raw.get("start_gift")
    if gift and gift.get("to") == "goal":
        st.savings += gift["amount"]  # P2: start gift straight into the goal envelope
    logs: list[WeekLog] = []
    first_pet_week = None
    first_big_week = None
    stage_weeks: dict[str, int] = {}
    limits_shift = eco.raw["week"]["max_shifts_per_job_per_week"]
    drain = eco.en["living_drain_per_action"]
    goals = style["goals"]

    for week in range(1, weeks + 1):
        pocket = eco.pocket(week)
        st.cash += pocket
        energy = eco.en["base_per_week"] + st.carry  # carry = early sleep + home meals of the last week
        energy += eco.homes[st.home]["energy_per_week"]
        energy = min(energy, eco.en.get("max_per_week", math.inf))
        st.carry = 0
        energy_start = energy
        food_id = style["food"]
        hap_week = 0.0
        earned = 0
        shifts = 0
        bought: list[str] = []
        per_job: dict[str, int] = {}
        leisure_h = 0.0
        # P7: prices of the week (⚡ and pay multipliers) come from 😊 at the week start, like the domain.
        h0 = st.happiness
        pets_at_start = list(st.pets)
        home_at_start = st.home
        stage_at_start = st.stage
        goals_bought = 0
        meals_left = eco.meals_per_week

        def goal_keep(buffer: bool = False) -> int:
            # "save_first": the style keeps 10 % of the week's income for the goal before any treat
            # (leisure, clothes) — the plan comes first. Rounded up so the deposit really reaches 10 %;
            # a treat also leaves the style's keep_buffer, which the deposit never takes.
            if not style.get("save_first"):
                return 0
            return math.ceil(0.1 * (pocket + earned)) + (style["keep_buffer"] if buffer else 0)

        def reserve() -> int:
            return sum(required_cost(st, eco, week, food_id, meals_left)) if style["reserve_required"] else 0

        # --- meals the child picks during the week: paid now (НУЖНО), ⚡ and 😊 right away, not a game day
        for mid in style["meals"][:eco.meals_per_week]:
            dish = eco.food[mid]
            price = eco.ix(dish["price"], week)
            if price > st.cash:
                continue  # not enough: Finni eats at home at the week end
            st.cash -= price
            energy = min(energy + dish["energy_now"], eco.en.get("max_per_week", math.inf))
            hap_week += dish["happiness"]
            meals_left -= 1
            bought.append(mid)

        def action_cost(base_energy: float, is_shift: bool) -> float:
            if is_shift:
                return eco.shift_energy(base_energy, h0, st.transport, drain)
            return base_energy * eco.energy_mult(h0) + drain

        def best_shift():
            best = None
            for jid, tier, pay, en, unlocked_by in eco.job_options():
                if unlocked_by == "transport" and not st.transport:
                    continue
                if unlocked_by and unlocked_by.startswith("pet_") and unlocked_by not in st.pets:
                    continue
                if unlocked_by in eco.abilities and not any(unlocked_by in eco.tech[t]["unlocks"] for t in st.tech):
                    continue
                if per_job.get(jid, 0) >= limits_shift:
                    continue
                cost = action_cost(en, True)
                if cost > energy + 1e-9:
                    continue
                mult = eco.pay_mult(h0)
                for perk in perks(st, eco, "pay_mult"):
                    if perk["job"] == jid:
                        mult *= 1 + perk["value"]  # same as the domain: a share, multiplied
                p = eco.ix(pay, week) * mult * eco.experience_mult(st.experience) * eco.pay_step(st.stage)
                value = p / cost
                if best is None or value > best[0]:
                    best = (value, jid, dtens(p), cost)
            return best

        good_shifts = 0

        def do_shift(b) -> None:
            """One shift: the rate is fixed before the game, the score decides the rest (P1, P4, P6)."""
            nonlocal energy, earned, shifts, hap_week, good_shifts
            _, jid, rate, cost = b
            scores = style["scores"]
            score = scores[st.shifts_total % len(scores)]
            st.shifts_total += 1
            pay = rate + eco.efficiency_bonus(rate, score)
            energy -= cost
            hap_week -= eco.day_drain  # P7: a shift is a game day
            if eco.is_good(score):
                extra = eco.pay_growth.get("good_shift_energy_extra", 0.0)
                energy -= min(extra, max(0.0, energy))  # never below zero; the shift is not undone
                hap_week += eco.pay_growth.get("good_shift_happiness", 0)
                st.experience += 1
                good_shifts += 1
            energy = round(energy, 2)
            st.cash += pay
            earned += pay
            shifts += 1
            per_job[jid] = per_job.get(jid, 0) + 1

        # --- shifts
        week_cap = min(style["max_shifts"], eco.raw["week"].get("max_shifts_per_week", 99))
        while shifts < week_cap:
            b = best_shift()
            if b is None:
                break
            do_shift(b)

        # --- snacks (💰 → ⚡), then maybe one more shift for the worker
        snack = eco.en["snack"]
        for _ in range(min(style["snacks"], snack["max_per_week"])):
            price = eco.ix(snack["price"], week)
            if st.cash - price < reserve():
                break
            st.cash -= price
            energy += snack["energy_now"]
            bought.append("snack")
            if style_id == "worker" and shifts < week_cap:
                b = best_shift()
                if b:
                    do_shift(b)

        # --- leisure
        plan = style["leisure"][(week - 1) % len(style["leisure"])]
        todo = list(plan)
        if style["pet_play"] and st.pets:
            todo.append("pet_play")
        for lid in todo:
            l = eco.leisure[lid]
            price = eco.ix(l["price"], week)
            cost = l["energy"] * eco.energy_mult(h0) + drain
            if cost > energy + 1e-9:
                continue
            if price and st.cash - price - goal_keep(buffer=True) < reserve():
                continue
            if price > st.cash:
                continue
            energy -= cost
            st.cash -= price
            h = l["happiness"]
            if lid == "pet_play":
                h += l.get("per_extra_pet", 0) * (len(st.pets) - 1)
            for perk in perks(st, eco, "leisure_happiness_delta"):
                if perk["leisure"] == lid:
                    h += perk["value"]
            room = eco.hap["leisure_weekly_cap"] - leisure_h
            h = max(0, min(h, room))
            leisure_h += h
            hap_week += h - eco.day_drain  # P7: leisure is a game day too; the drain is outside the leisure cap
            bought.append(lid)

        # --- clothes (optional, not indexed)
        if style["clothes_every"] and week % style["clothes_every"] == 0:
            for cid, c in sorted(eco.clothing.items(), key=lambda kv: -kv[1]["price"]):
                # "save_first": the style keeps 10 % of the week's income for the goal before a treat (the plan).
                if st.cash - c["price"] - goal_keep(buffer=True) >= reserve() and c["price"] <= st.cash:
                    st.cash -= c["price"]
                    st.clothes.append((week, c["fade"]))
                    bought.append(cid)
                    break

        # --- pet touch: first tap of each game day gives 😊 (one active pet, shared daily counter)
        if st.pets:
            days = shifts + sum(1 for b in bought if b in eco.leisure)
            hap_week += eco.raw["pets"]["daily_touch_happiness"] * days

        # --- week end: sleep or exhausted
        cheapest = min(
            [action_cost(en, True) for _, _, _, en, ub in eco.job_options() if not ub]
            + [action_cost(eco.leisure["park"]["energy"], False)]
        )
        if style["sleep_early"] and energy >= eco.en["sleep"]["min_left_for_bonus"]:
            ended_by = "sleep"
            st.carry = eco.en["sleep"]["carry_next_week"] + sum(p["value"] for p in perks(st, eco, "sleep_carry_delta"))
            hap_week += eco.en["sleep"]["happiness"] + sum(p["value"] for p in perks(st, eco, "sleep_happiness_delta"))
        else:
            ended_by = "exhausted" if energy < cheapest else "sleep-late"
            if ended_by == "exhausted":
                hap_week += eco.en["exhausted"]["happiness"]

        # --- required costs with the shortfall rule
        f_cost, h_cost, p_cost = required_cost(st, eco, week, food_id, meals_left)
        shortfall = family = withdrawn = 0
        # 1. pet food first
        pay = min(st.cash, p_cost)
        st.cash -= pay
        family += p_cost - pay
        # 2. downgrade food if needed
        if meals_left and st.cash < f_cost + h_cost and food_id != "food_simple":
            food_id = "food_simple"
            shortfall += 1
            f_cost = eco.ix(eco.food[food_id]["price"], week) * meals_left
        need = f_cost + h_cost
        if st.cash < need:
            shortfall += 1
            gap = need - st.cash
            # 3. offer savings withdrawal (every style accepts in the sim)
            take = min(st.savings, gap)
            st.savings -= take
            withdrawn = int(take)
            st.cash += take
            gap -= take
            # 4. family help covers the rest
            family += gap
            st.cash += gap
        st.cash -= need
        if family:
            hap_week += eco.raw["shortfall_rule"]["order"][3]["happiness"]
        assert st.cash >= -1e-9, "negative balance"
        required_total = f_cost + h_cost + p_cost

        # --- deposit to the goal (slider after shifts; sim does it once at week end)
        deposit = 0
        if style["save_share"] > 0:
            free = st.cash - style["keep_buffer"]
            deposit = int(max(0, free) * style["save_share"])
            # "save_first": the 10 % kept for the goal all week goes in whole, not × save_share.
            deposit = max(deposit, min(max(0, free), goal_keep()))
            st.cash -= deposit
            st.savings += deposit

        # --- buy goals when savings reach the price (in the game this happens during the week)
        while st.goal_idx < len(goals):
            goal = goals[st.goal_idx]
            price = eco.goal_price(goal)
            if st.savings < price:
                break
            # Stage = rent (Denis 29.09, 941 #3): a move opens with the growth points of its stage.
            if goal in eco.homes and eco.growth.get("stage_by_rent") and eco.homes[goal].get("stage"):
                need = next(s["min_points"] for s in eco.growth["stages"] if s["place"] == eco.homes[goal]["stage"])
                if st.growth_points < need:
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
            # A big purchase: at least the transport price, or a move (renting a better home is the big step).
            if price >= eco.transport["price"] or goal in eco.homes:
                first_big_week = first_big_week or week

        # --- growth points (proposal)
        g = eco.growth
        income = pocket + earned
        if family == 0:
            st.growth_points += g["points"]["required_covered"]
        if shortfall == 0:
            st.growth_points += g["points"]["plan_kept"]
        net_saved = deposit - withdrawn  # like the domain: money taken from the goal is subtracted
        saved_regularly = bool(income and net_saved > 0 and net_saved >= g["saved_regularly_min_share"] * income)
        if saved_regularly:
            st.growth_points += g["points"]["saved_regularly"]
        home_place = eco.homes[st.home].get("stage")
        for s in g["stages"]:
            if st.growth_points >= s["min_points"]:
                if g.get("stage_by_rent") and home_place:
                    order = [x["place"] for x in g["stages"]]
                    if order.index(s["place"]) > order.index(home_place):
                        break  # points are there, the move is not: stage = the rented home
                if s["id"] not in stage_weeks:
                    stage_weeks[s["id"]] = week
                st.stage = s["id"]

        # --- P7 growth check: did Finni grow this week compared with the last one?
        growth, why = growth_verdict(eco, earned, st.earned_last, saved_regularly, goals_bought > 0,
                                     st.stage != stage_at_start)
        wg = eco.week_growth
        if growth == "up":
            st.flat_weeks = 0
            hap_week += wg.get("growth_bonus", 0)
        elif growth == "flat":
            st.flat_weeks += 1
            hap_week -= stagnation_penalty(eco, st.flat_weeks)
        st.earned_last = earned

        # --- weekly happiness: food, home and pets of the week start, clothes, decay from 😊 at the week start
        hap_week += eco.food[food_id]["happiness"] * meals_left  # meals eaten at home at the week end
        hap_week += eco.homes[home_at_start]["happiness_per_week"]
        pet_h = sum(eco.pets[p]["happiness_per_week"] for p in pets_at_start)
        hap_week += min(pet_h, eco.raw["pets"]["happiness_total_cap"])
        for wb, fade in st.clothes:
            age = week - wb
            if 0 <= age < len(fade):
                hap_week += fade[age]
        d = eco.hap["weekly_decay"]
        decay = d["base"] + d["k"] * (h0 - eco.hap["neutral"])
        decay += sum(eco.pets[p].get("perk", {}).get("value", 0) for p in pets_at_start
                     if eco.pets[p].get("perk", {}).get("type") == "happiness_decay_delta")
        st.happiness = max(eco.hap["min"], min(eco.hap["max"], st.happiness + hap_week - dround(decay)))

        st.carry += eco.food[food_id]["energy_now"] * meals_left  # home meals: ⚡ goes to the next week
        logs.append(WeekLog(week, pocket, earned, shifts, required_total, shortfall, int(family), withdrawn,
                            deposit, int(st.cash), int(st.savings), round(st.happiness, 1), round(energy_start, 1),
                            ended_by, bought, st.stage, st.experience, good_shifts, growth, why))
        if verbose:
            print(f"  [{style_id}] w{week}: pocket {pocket} earned {earned} ({shifts} sh, {good_shifts} good, "
                  f"exp {st.experience}) req {required_total} "
                  f"short {shortfall} fam {int(family)} cash {int(st.cash)} sav {int(st.savings)} "
                  f"😊 {st.happiness:.0f} ⚡0 {energy_start:.1f} {ended_by} {bought} рост {growth or '—'} {why}")

    return {
        "style": style_id,
        "logs": logs,
        "first_pet_week": first_pet_week,
        "first_big_week": first_big_week,
        "stage_weeks": stage_weeks,
    }


# ---------------------------------------------------------------- checks


def analytic_checks(eco: Economy, weeks: int) -> list[str]:
    problems = []
    pay = eco.jobs["consultant"]["pay"]
    for w in range(1, weeks + 1):
        pocket = eco.pocket(w)
        room = eco.ix(eco.homes["home_room"]["weekly_cost"], w)
        meals = eco.meals_per_week
        # «Неделя без работы» (ревью df2164a §1.3): на одних карманных всё не купить — даже
        # самое дешёвое блюдо из меню (не только food_simple) и комната дороже стипендии.
        cheapest = min(eco.ix(f["price"], w) for f in eco.food.values())
        mn = cheapest * meals + room
        normal = eco.ix(eco.food["food_regular"]["price"], w) * meals + room
        if pocket >= mn:
            problems.append(f"неделя {w} без работы: карманные {pocket} покрывают минимальное обязательное {mn} "
                            f"(самое дешёвое блюдо {cheapest}) — смены не нужны")
        need = math.ceil(max(0, normal - pocket) / eco.ix(pay, w))
        if need > 2:
            problems.append(f"неделя {w}: на обычное обязательное ({normal}) нужно {need} смен консультанта (> 2)")
    # energy: can two shifts + required fit in a neutral week?
    shift_cost = eco.jobs["consultant"]["energy"] + eco.en["living_drain_per_action"]
    if 2 * shift_cost > eco.en["base_per_week"]:
        problems.append("две смены консультанта не помещаются в базовый запас ⚡")
    if any(l.get("price", 0) > 0 and "payout_table" in l for l in eco.raw["leisure"]["options"]):
        problems.append("в досуге есть платная случайная награда — ТЗ §3.5 это запрещает")
    return problems


def result_checks(results: dict, eco: Economy, demo_weeks: int = 5) -> list[str]:
    problems = []
    for sid, r in results.items():
        logs = r["logs"]
        if min(l.cash for l in logs) < 0:
            problems.append(f"{sid}: баланс ушёл в минус (ТЗ 2.5.6.4)")
        hs = [l.happiness for l in logs]
        top = sum(1 for h in hs if h >= eco.hap["max"] - 0.5)
        if top >= 3:
            problems.append(f"{sid}: 😊 {top} недель на потолке {eco.hap['max']} — снежный ком")
        if sum(1 for h in hs if h <= 10) >= 3:
            problems.append(f"{sid}: 😊 застряло у нуля")
        if len(logs) >= 3 and logs[-1].savings + logs[-1].cash > 3 * sum(l.pocket for l in logs):
            problems.append(f"{sid}: денег к концу больше трёх сумм карманных — рост без предела")
    # Criteria §1 p. 8: pay grows, but weekly earnings do not double over the run (stage steps and experience included).
    for sid, r in results.items():
        logs = r["logs"]
        if len(logs) >= 5 and logs[0].earned > 0 and logs[-1].earned >= 2 * logs[0].earned:
            problems.append(f"{sid}: заработок недели вырос ×{logs[-1].earned / logs[0].earned:.2f} (≥ ×2)")
    # Criteria §1 p. 4: every style that saves at all reaches its first goal within the run.
    for sid, r in results.items():
        st_goals = STYLES[sid]["goals"]
        if st_goals and len(r["logs"]) >= 10 and not any(any(b.startswith("GOAL:") for b in l.bought) for l in r["logs"]):
            problems.append(f"{sid}: ни одной цели за {len(r['logs'])} недель")
    # P7: standing still makes Finni sadder slowly; growing keeps him up.
    stay = results.get("stagnant")
    if stay:
        hs = [l.happiness for l in stay["logs"]]
        if len(hs) >= 5 and hs[-1] > max(hs) - 10:
            problems.append(f"stagnant: 😊 не падает, хотя Финни стоит на месте (макс {max(hs):.0f}, конец {hs[-1]:.0f})")
        if len(hs) >= 5 and not any(l.growth == "flat" for l in stay["logs"]):
            problems.append("stagnant: ни одной недели без роста — проверка роста ничего не ловит")
    for sid in ("saver", "balanced"):
        r = results.get(sid)
        if r and len(r["logs"]) >= 5:
            end = r["logs"][-1].happiness
            flat = sum(1 for l in r["logs"] if l.growth == "flat")
            if end < 60:
                problems.append(f"{sid}: 😊 {end:.0f} к концу, хотя Финни растёт (ожидали ≥ 60)")
            if flat:
                problems.append(f"{sid}: {flat} недель «без роста», хотя стиль откладывает и покупает цели")
    b = results.get("balanced")
    if b:
        fp = b["first_pet_week"]
        if fp is None or not (2 <= fp <= 4):
            problems.append(f"balanced: первый питомец на неделе {fp} (цель 2–4)")
        big = b["first_big_week"]
        s2 = b["stage_weeks"].get("stage_2")
        if not ((big and big <= 6) or (s2 and s2 <= 6)):
            problems.append(f"balanced: нет большой покупки или стадии к 6-й неделе (покупка {big}, стадия 2 {s2})")
        if big is None or big > 8:
            problems.append(f"balanced: большая цель (≥ транспорта) только на неделе {big} (> 8)")
    s = results.get("saver")
    if s and (s["first_pet_week"] is None or s["first_pet_week"] > 4):
        problems.append(f"saver: первый питомец на неделе {s['first_pet_week']} (> 4)")
    sp = results.get("spender")
    if sp:
        n = len(sp["logs"])
        shortfalls = sum(1 for l in sp["logs"] if l.shortfall)
        fam = sum(1 for l in sp["logs"] if l.family_help)
        if shortfalls == 0:
            problems.append("spender: ни разу не столкнулся с нехваткой — последствий не видно")
        if fam > n // 2:
            problems.append(f"spender: семья выручала {fam} недель из {n} — слишком жёстко, игра превращается в наказание")
    for sid, r in results.items():
        if sid == "spender":
            continue
        fam = sum(1 for l in r["logs"] if l.family_help)
        if fam:
            problems.append(f"{sid}: семье пришлось помогать {fam} раз(а) при разумной игре")
    return problems


def content_checks(eco: Economy, jobs, events) -> list[str]:
    problems = []
    raw = eco.raw
    required = len(raw["food"]["options"]) + 1 + 1  # food options, rent, pet food
    optional = (1 + len(raw["clothing"]["items"]) + sum(1 for l in raw["leisure"]["options"] if l["price"] > 0) + 1
                + len(eco.decor["items"]))
    goals = sum(1 for p in raw["pets"]["roster"] if p["tier"] == "demo") + 1 + sum(1 for h in raw["homes"]["options"] if h.get("is_goal"))
    goals += len(eco.tech)
    optional += len(eco.tech)
    if required + optional < 8 or required == 0 or optional == 0:
        problems.append(f"покупок {required}+{optional} — меньше 8 двух типов (ТЗ 2.6)")
    if goals < 3:
        problems.append(f"целей накопления {goals} < 3 (ТЗ 2.6)")
    if len(raw["growth"]["stages"]) < 3:
        problems.append("стадий роста меньше 3 (ТЗ 2.6)")
    info = f"покупок: {required} обязательных + {optional} необязательных; целей: {goals}; стадий: {len(raw['growth']['stages'])}"

    if jobs is not None:
        for jid in jobs.get("jobs", {}):
            if jid not in raw["jobs"]:
                problems.append(f"jobs.json: профессия {jid} не описана в economy.json → jobs")
        cons = jobs["jobs"].get("consultant", {})
        for s in cons.get("sets", []):
            prices = [i["price"] for i in s["items"]]
            if len(s["items"]) != 3 or prices != sorted(prices) or len(set(prices)) != 3:
                problems.append(f"консультант/{s['id']}: нужно 3 товара с разными ценами по возрастанию")
            c = s.get("customer", {})
            fit = [i for i in s["items"] if i["id"] == c.get("best_fit")]
            if not fit or fit[0]["price"] > c.get("budget", 0) or fit[0]["price"] == max(prices):
                problems.append(f"консультант/{s['id']}: best_fit должен укладываться в бюджет и не быть самым дорогим")
        cash = jobs["jobs"].get("cashier", {})
        coins = sorted(cash.get("coins", []), reverse=True)
        for p in cash.get("purchases", []):
            change = p["paid_with"] - p["price"]
            if change <= 0:
                problems.append(f"кассир/{p['id']}: сдача ≤ 0")
                continue
            if p.get("change") is not None and p["change"] != change:
                problems.append(f"кассир/{p['id']}: указана сдача {p['change']}, а должна быть {change}")
            rest = change
            for c in coins:
                rest -= (rest // c) * c
            if rest:
                problems.append(f"кассир/{p['id']}: сдачу {change} нельзя собрать монетами {coins}")
            if p["paid_with"] not in cash.get("bills", []) + cash.get("coins", []):
                problems.append(f"кассир/{p['id']}: покупатель платит {p['paid_with']}, такой купюры нет")
        prog = jobs["jobs"].get("programmer", {})
        for t in prog.get("tasks", []):
            ids = {b["id"] for b in t["blocks"]}
            if not set(t["solution"]) <= ids:
                problems.append(f"программист/{t['id']}: решение ссылается на несуществующий блок")
        info += f"; наборов консультанта: {len(cons.get('sets', []))}; покупок кассира: {len(cash.get('purchases', []))}; задач программиста: {len(prog.get('tasks', []))}"

    if events is not None:
        evs = events.get("events", [])
        raw_events = json.loads((CONTENT / "events.json").read_text(encoding="utf-8"))
        flags = {k for k in raw_events.get("_flags", {}) if not k.startswith("_")}
        topics = {}
        for e in evs:
            topics[e["topic"]] = topics.get(e["topic"], 0) + 1
            if e["topic"] not in ("planning", "savings"):
                problems.append(f"событие {e['id']}: тема {e['topic']} не planning/savings")
            if not 2 <= len(e["options"]) <= 3:
                problems.append(f"событие {e['id']}: вариантов {len(e['options'])}, нужно 2–3")
            def costs(o):
                ef = o.get("effects", {})
                leisure_price = eco.leisure.get(ef.get("leisure"), {}).get("price", 0)
                return (ef.get("money_pocket_x", 0) < 0 or ef.get("savings_pocket_x", 0) < 0
                        or ef.get("required_extra_pocket_x", 0) > 0 or leisure_price > 0
                        or "buy" in ef or "goal_discount" in ef)
            if all(costs(o) for o in e["options"]):
                problems.append(f"событие {e['id']}: нет бесплатного варианта — при нехватке денег выбор пропадёт")
            for o in e["options"]:
                ef = o.get("effects", {})
                if "leisure" in ef and ef["leisure"] not in eco.leisure:
                    problems.append(f"событие {e['id']}/{o['id']}: досуга {ef['leisure']} нет в economy.json")
                if "buy" in ef and ef["buy"] not in eco.clothing:
                    problems.append(f"событие {e['id']}/{o['id']}: товара {ef['buy']} нет в economy.json")
                if "shift" in ef and ef["shift"] not in eco.jobs:
                    problems.append(f"событие {e['id']}/{o['id']}: профессии {ef['shift']} нет в economy.json → jobs")
                if "flag" in ef and ef["flag"] not in flags:
                    problems.append(f"событие {e['id']}/{o['id']}: метка {ef['flag']} не описана в _flags — её никто не читает")
                gd = ef.get("goal_discount")
                cond = e.get("conditions", {}).get("savings_min_share_of_goal")
                if gd and (not cond or cond["goal"] != gd["goal"] or cond["share"] < 1 - gd["share"] - 1e-9):
                    problems.append(f"событие {e['id']}/{o['id']}: скидка {gd['share']:.0%}, но событие появляется раньше, чем копилки хватает на цену со скидкой")
                t = o["finni"]
                if "{nick}" not in t:
                    problems.append(f"событие {e['id']}/{o['id']}: нет {{nick}} в реплике Финни")
                n_sent = len([s for s in re.split(r"[.!?…]+", t) if s.strip()])
                if n_sent > 2 or len(t) > 170:
                    problems.append(f"событие {e['id']}/{o['id']}: реплика длиннее 2 предложений / 170 знаков")
        if len(evs) < 8:
            problems.append(f"событий {len(evs)} < 8")
        info += f"; событий: {len(evs)} {topics}"
    return problems, info


ACCESSORY_WINDOW = (3, 15)  # Denis 26.09: never before the 3rd spin, guaranteed by the 15th


def run_slot_sim(sim: dict, rng: random.Random) -> tuple[int, int, int | None]:
    """One 'pretend' run of the slot machine task. Returns (spent, won, accessory_spin)."""
    spent = won = 0
    acc_spin = None
    ra = sim["rare_accessory"]
    for spin in range(1, sim["spins"] + 1):
        spent += sim["virtual_price_per_spin"]
        roll, acc, win = rng.random(), 0.0, 0
        for row in sim["payout_table"]:
            acc += row["chance"]
            if roll < acc:
                win = row["coins"]
                break
        won = min(won + win, int(spent * sim["max_win_share"]))
        if acc_spin is None and spin >= ra["min_spin"]:
            if rng.random() < ra["chance"] or spin >= ra["guaranteed_by_spin"]:
                acc_spin = spin
    return spent, won, acc_spin


def slot_checks(events, runs: int, seed: int) -> tuple[list[str], str]:
    problems = []
    if events is None:
        return problems, ""
    sims = [e["simulation"] for e in events.get("events", []) if "simulation" in e]
    if not sims:
        return ["нет задания-симуляции автомата"], ""
    sim = sims[0]
    rng = random.Random(seed)
    bad_loss = bad_acc = 0
    spent_sum = won_sum = 0
    acc_spins = []
    for _ in range(runs):
        spent, won, acc_spin = run_slot_sim(sim, rng)
        spent_sum += spent
        won_sum += won
        if spent - won < won:
            bad_loss += 1
        if acc_spin is None or not (ACCESSORY_WINDOW[0] <= acc_spin <= ACCESSORY_WINDOW[1]):
            bad_acc += 1
        else:
            acc_spins.append(acc_spin)
    if bad_loss:
        problems.append(f"автомат: в {bad_loss} из {runs} прогонов проигрыш меньше выигрыша")
    if bad_acc:
        problems.append(f"автомат: в {bad_acc} из {runs} прогонов аксессуар выпал вне [3..15]")
    info = (f"Симуляция автомата ({runs} прогонов по {sim['spins']}): в среднем потрачено бы {spent_sum / runs:.0f}, "
            f"выиграно бы {won_sum / runs:.0f}; проигрыш ≥ выигрыша — {runs - bad_loss}/{runs}; "
            f"аксессуар в [3..15] — {runs - bad_acc}/{runs}, в среднем на {sum(acc_spins) / max(1, len(acc_spins)):.1f}-м вращении")
    return problems, info


# ---------------------------------------------------------------- output


def fmt_week(w):
    return "—" if w is None else str(w)


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("--weeks", type=int, default=10)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--slot-runs", type=int, default=10000, help="прогонов симуляции автомата для проверки правил")
    ap.add_argument("--pay-growth", choices=["full", "experience", "off"], default="full",
                    help="рост оплаты P1 для сравнения: full — опыт и ступень стадии (как в файле), "
                         "experience — только опыт, off — без роста")
    ap.add_argument("--decay", type=float, default=None,
                    help="переопределить happiness.weekly_decay.base для сравнения; файл не меняется")
    ap.add_argument("--set", action="append", default=[], metavar="ПУТЬ=ЧИСЛО",
                    help="переопределить любое число economy.json для сравнения, например "
                         "--set happiness.day_drain=2 --set week.max_shifts_per_week=3; файл не меняется")
    args = ap.parse_args()

    raw = load("economy.json")
    if args.decay is not None:
        raw["happiness"]["weekly_decay"]["base"] = args.decay
    for item in args.set:
        path, _, value = item.partition("=")
        node = raw
        keys = path.split(".")
        for k in keys[:-1]:
            node = node[k]
        if keys[-1] not in node:
            ap.error(f"--set {item}: в economy.json нет ключа {path}")
        node[keys[-1]] = float(value) if "." in value else int(value)
    if args.pay_growth != "full":
        for s in raw["growth"]["stages"]:
            s["pay_step"] = 1
        if args.pay_growth == "off":
            raw.get("jobs_pay_growth", {})["experience_mult_per_shift"] = 1.0
    eco = Economy(raw)
    jobs = load("jobs.json")
    events = load("events.json")

    pg = eco.pay_growth
    print(f"Экономика v{eco.raw['version']} · {args.weeks} недель · seed {args.seed} · рост оплаты: {args.pay_growth}")
    print(f"P1: ступени {[s.get('pay_step', 1) for s in eco.growth['stages']]} · опыт ×{pg.get('experience_mult_per_shift', 1)} "
          f"за хорошую смену (оценка ≥ {pg.get('good_score_min', 0)}) · хорошая смена +{pg.get('good_shift_energy_extra', 0)}⚡ "
          f"{pg.get('good_shift_happiness', 0)}😊 · бонус до {pg.get('efficiency_bonus_max_share', 0):.0%}")
    d, wg = eco.hap["weekly_decay"], eco.week_growth
    print(f"P7: −{eco.day_drain}😊 за игровой день · остывание {d['base']:g} + {d['k']:g} × (😊₀ − 50) · "
          f"рост недели +{wg.get('growth_bonus', 0)}😊 (доход ≥ +{wg.get('income_min_share', 0):.0%}, "
          f"отложено, цель, стадия) · без роста −{wg.get('stagnation_step', 0)}😊 × недель подряд, "
          f"до −{wg.get('stagnation_max', 0)} · лимит смен {eco.raw['week']['max_shifts_per_week']} в неделю")
    print("Карманные по неделям:", [eco.pocket(w) for w in range(1, args.weeks + 1)])
    print()

    results = {sid: simulate(eco, sid, args.weeks, args.seed, args.verbose) for sid in STYLES}

    head = f"{'стиль':<10}{'💰 кошелёк':>11}{'копилка':>9}{'😊 кон/мин/макс':>17}{'1-й питомец':>12}{'большая':>9}{'стадия 2/3':>11}{'нехватка':>9}{'семья':>7}"
    print(head)
    print("-" * len(head))
    for sid, r in results.items():
        L = r["logs"]
        hs = [l.happiness for l in L]
        short = sum(1 for l in L if l.shortfall)
        fam = sum(1 for l in L if l.family_help)
        sw = r["stage_weeks"]
        print(f"{STYLES[sid]['label']:<10}{L[-1].cash:>11}{L[-1].savings:>9}"
              f"{f'{hs[-1]:.0f}/{min(hs):.0f}/{max(hs):.0f}':>17}{fmt_week(r['first_pet_week']):>12}"
              f"{fmt_week(r['first_big_week']):>9}{fmt_week(sw.get('stage_2')) + '/' + fmt_week(sw.get('stage_3')):>11}"
              f"{short:>9}{fam:>7}")
    print()
    print("Покупки целей по неделям:")
    for sid, r in results.items():
        goals = [f"н{l.week}:{b[5:]}" for l in r["logs"] for b in l.bought if b.startswith("GOAL:")]
        shifts = [l.shifts for l in r["logs"]]
        print(f"  {STYLES[sid]['label']:<9} {', '.join(goals) or '—'} · смен/нед {shifts}")
    print()
    print("😊 на конец недели и рост недели (↑ рост · = без роста · пусто — неделя 1):")
    for sid, r in results.items():
        marks = {"up": "↑", "flat": "=", "": ""}
        print(f"  {STYLES[sid]['label']:<9} " + " ".join(f"{l.happiness:.0f}{marks[l.growth]}" for l in r["logs"]))
    print()
    print("Заработок по неделям (без карманных) и опыт к концу:")
    for sid, r in results.items():
        L = r["logs"]
        good = sum(l.good_shifts for l in L)
        total = sum(l.shifts for l in L)
        print(f"  {STYLES[sid]['label']:<9} {[l.earned for l in L]} · хороших смен {good}/{total} · "
              f"опыт {L[-1].experience} (×{eco.experience_mult(L[-1].experience):.2f}) · {L[-1].stage}")
    print()

    problems = analytic_checks(eco, args.weeks) + result_checks(results, eco)
    cproblems, info = content_checks(eco, jobs, events)
    print("Контент:", info)
    problems += cproblems
    sproblems, sinfo = slot_checks(events, args.slot_runs, args.seed)
    print(sinfo)
    problems += sproblems
    print()
    if problems:
        print(f"Проблемы баланса ({len(problems)}):")
        for p in problems:
            print("  ⚠", p)
    else:
        print("Проблем баланса не найдено.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
