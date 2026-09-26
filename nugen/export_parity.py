"""Writes urbanpulse_flutter/test/fixtures/travel_risk_parity.json: prompts and
weather-impact answers from the Python side, which the app's Dart tests check
character for character, so the app asks the aligned model exactly what it was
trained on and its offline rules answer exactly like the training labels.

    python nugen/export_parity.py
"""

import json
import os
import random

from build_dataset import HELD_OUT_SIGHTS, SIGHTS, WEATHER_KINDS, normalize_weather
from travel_risk_rules import PROFILES, access_prompt, category_from_name, event_prompt, impact_prompt, weather_impact

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "urbanpulse_flutter", "test", "fixtures", "travel_risk_parity.json")


def main():
    rng = random.Random(99)
    impacts = []
    cats = list(PROFILES) + ["unknown"]
    for i in range(400):
        _, gen = WEATHER_KINDS[i % len(WEATHER_KINDS)]
        w = normalize_weather(gen(rng))
        cat = cats[i % len(cats)]
        real = cat if cat != "unknown" else "monument"
        impacts.append({"category": real, "weather": w, "expected": weather_impact(real, w)})

    names = [n for c in list(SIGHTS.values()) + list(HELD_OUT_SIGHTS.values()) for n in c]
    categories = [{"name": n, "category": category_from_name(n)} for n in names]

    prompts = []
    for i in range(20):
        _, gen = WEATHER_KINDS[i % len(WEATHER_KINDS)]
        w = normalize_weather(gen(rng))
        place = names[i * 3 % len(names)]
        date = f"2026-{(i % 12) + 1:02d}-{(i % 27) + 1:02d}"
        prompts.append({"task": "weather_impact", "place": place, "category": "unknown" if i % 3 == 0 else category_from_name(place),
                        "city": "Jaipur", "date": date, "weather": w,
                        "prompt": impact_prompt(place, "unknown" if i % 3 == 0 else category_from_name(place), "Jaipur", date, w)})
    prompts.append({"task": "access_claims", "place": "Amber Fort", "kind": "sight", "city": "Jaipur",
                    "snippet": "There are about 40 steep steps up to the main palace. Great views.",
                    "prompt": access_prompt("Amber Fort", "sight", "Jaipur", "There are about 40 steep steps up to the main palace. Great views.")})
    prompts.append({"task": "weather_event", "city": "Mumbai", "post": "Knee-deep water at Andheri Subway, cars stuck, avoid the route!",
                    "prompt": event_prompt("Mumbai", "Knee-deep water at Andheri Subway, cars stuck, avoid the route!")})

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump({"impacts": impacts, "categories": categories, "prompts": prompts}, f, ensure_ascii=False, indent=1)
    print(f"wrote {len(impacts)} impact cases, {len(categories)} names, {len(prompts)} prompts to {os.path.relpath(OUT)}")


if __name__ == "__main__":
    main()
