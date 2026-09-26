"""The UrbanPulse Travel-Risk tasks: their prompt formats and the reference
rules that label the training data.

The app sends exactly these prompts (see
`urbanpulse_flutter/lib/services/nugen/travel_risk_prompts.dart`), and its
offline fallback (`travel_risk_rules.dart`) implements the same weather-impact
rules, so a model answer and a fallback answer mean the same thing.

Three tasks:
  access_claims  - wheelchair-access facts quoted from one review snippet
  weather_impact - how a day's weather affects visiting one place
  weather_event  - the travel disruption (if any) one social post reports
"""

import json

# --------------------------------------------------------------------------
# Prompt formats (keep in sync with travel_risk_prompts.dart)
# --------------------------------------------------------------------------

# Every value in an answer is a string (lists are joined, numbers written as
# digits in quotes): simple for a small model to produce, and Nugen's
# synthetic-data step accepts only string answers.

ACCESS_SCHEMA = (
    '{"step_free": "yes|no|unknown", "lift": "yes|no|unknown", "ramp": "yes|no|unknown", '
    '"accessible_toilet": "yes|no|unknown", "stairs": "number of steps or unknown", '
    '"evidence": "exact quotes from the snippet joined by | or none"}'
)

IMPACT_SCHEMA = (
    '{"impact": "none|low|moderate|high|closed", "sensitive_to": "heat, rain, wind, flood or none", '
    '"best_time": "morning|afternoon|evening|any|avoid", "reason": "one short sentence"}'
)

EVENT_SCHEMA = (
    '{"is_weather_event": "yes|no", "event": "waterlogging|flooding|heat|storm|landslide|'
    'road_closed|attraction_closed|power_cut|none", "place": "name or none", '
    '"severity": "none|low|moderate|high", "affects": "roads, transport, attraction, hotel, power or none"}'
)


def access_prompt(place, kind, city, snippet):
    return (
        "TASK: access_claims\n"
        f"Place: {place} ({kind}), {city}\n"
        f'Snippet: "{snippet}"\n'
        f"Answer with JSON only: {ACCESS_SCHEMA}"
    )


def weather_line(w):
    alert = w["alert"]
    if alert != "none":
        alert = f'{alert} for {w["alert_for"]}'
    return (
        f'max {w["temp_max_c"]}°C, rain {w["rain_mm"]} mm ({w["rain_prob"]}% chance), '
        f'wind {w["wind_kmh"]} km/h, alert: {alert}'
    )


def impact_prompt(place, category, city, date, w):
    return (
        "TASK: weather_impact\n"
        f"Place: {place} (category: {category}), {city}\n"
        f"Date: {date}\n"
        f"Weather: {weather_line(w)}\n"
        f"Answer with JSON only: {IMPACT_SCHEMA}"
    )


def event_prompt(city, post):
    return (
        "TASK: weather_event\n"
        f"City: {city}\n"
        f'Post: "{post}"\n'
        f"Answer with JSON only: {EVENT_SCHEMA}"
    )


def dump(obj):
    return json.dumps(obj, ensure_ascii=False)


def _join(items, sep=", "):
    return sep.join(items) if items else "none"


def _split(v, sep=","):
    if isinstance(v, list):
        return [str(x).strip() for x in v if str(x).strip()]
    if v is None:
        return []
    s = str(v).strip()
    if not s or s.lower() in ("none", "null", "[]", "unknown"):
        return []
    return [x.strip() for x in s.split(sep) if x.strip()]


def to_wire(task, ans):
    """A structured answer as the all-string JSON the model is taught."""
    a = dict(ans)
    if task == "access_claims":
        a["stairs"] = "unknown" if a.get("stairs") is None else str(a["stairs"])
        a["evidence"] = _join(a.get("evidence") or [], " | ")
    elif task == "weather_impact":
        a["sensitive_to"] = _join(a.get("sensitive_to") or [])
    else:
        a["is_weather_event"] = "yes" if a.get("is_weather_event") else "no"
        a["place"] = a.get("place") or "none"
        a["affects"] = _join(a.get("affects") or [])
    return dump(a)


def from_wire(task, obj):
    """A model answer (all-string, or with real lists/numbers) as a structured answer."""
    if not isinstance(obj, dict):
        return None
    a = dict(obj)
    if task == "access_claims":
        st = a.get("stairs")
        try:
            a["stairs"] = int(str(st).strip()) if st is not None and str(st).strip().isdigit() else (st if isinstance(st, int) else None)
        except ValueError:
            a["stairs"] = None
        a["evidence"] = _split(a.get("evidence"), "|")
    elif task == "weather_impact":
        a["sensitive_to"] = _split(a.get("sensitive_to"))
    else:
        ev = a.get("is_weather_event")
        a["is_weather_event"] = ev is True or str(ev).strip().lower() in ("yes", "true")
        place = a.get("place")
        a["place"] = None if place is None or str(place).strip().lower() in ("none", "null", "") else str(place).strip()
        a["affects"] = _split(a.get("affects"))
    return a


# --------------------------------------------------------------------------
# weather_impact reference rules
# --------------------------------------------------------------------------

# exposure: 0 indoor, 1 partly outdoor, 2 outdoor.
# heat/rain/wind/flood: how much that hazard matters there (0-2).
# hill: on a slope or cliff (rain adds landslide and slippery-path risk).
# water: on the sea, a lake or a river (closed in storms and heavy rain).
PROFILES = {
    "fort":        dict(exposure=2, heat=2, rain=1, wind=0, flood=0, hill=True,  water=False),
    "palace":      dict(exposure=1, heat=1, rain=0, wind=0, flood=0, hill=False, water=False),
    "museum":      dict(exposure=0, heat=0, rain=0, wind=0, flood=0, hill=False, water=False),
    "temple":      dict(exposure=1, heat=2, rain=1, wind=0, flood=0, hill=False, water=False),
    "monument":    dict(exposure=2, heat=2, rain=1, wind=0, flood=0, hill=False, water=False),
    "stepwell":    dict(exposure=2, heat=2, rain=1, wind=0, flood=1, hill=False, water=False),
    "beach":       dict(exposure=2, heat=1, rain=2, wind=2, flood=2, hill=False, water=True),
    "lake":        dict(exposure=2, heat=1, rain=1, wind=2, flood=1, hill=False, water=True),
    "boat_ride":   dict(exposure=2, heat=1, rain=2, wind=2, flood=2, hill=False, water=True),
    "garden":      dict(exposure=2, heat=1, rain=1, wind=0, flood=0, hill=False, water=False),
    "zoo":         dict(exposure=2, heat=1, rain=1, wind=0, flood=0, hill=False, water=False),
    "market":      dict(exposure=1, heat=1, rain=1, wind=0, flood=1, hill=False, water=False),
    "mall":        dict(exposure=0, heat=0, rain=0, wind=0, flood=0, hill=False, water=False),
    "waterfall":   dict(exposure=2, heat=0, rain=2, wind=0, flood=2, hill=True,  water=True),
    "trek":        dict(exposure=2, heat=2, rain=2, wind=1, flood=1, hill=True,  water=False),
    "viewpoint":   dict(exposure=2, heat=1, rain=1, wind=1, flood=0, hill=True,  water=False),
    "tea_estate":  dict(exposure=2, heat=0, rain=1, wind=0, flood=0, hill=True,  water=False),
    "restaurant":  dict(exposure=0, heat=0, rain=0, wind=0, flood=0, hill=False, water=False),
    "hotel":       dict(exposure=0, heat=0, rain=0, wind=0, flood=0, hill=False, water=False),
}

# Words in a place's name that give away its category when the category is
# not given ("unknown"). Checked in order; first match wins.
NAME_HINTS = [
    ("waterfall", ["falls", "waterfall", "jharna"]),
    ("trek", ["trek", "trail", "peak", "summit", "hike"]),
    ("beach", ["beach", "shore"]),
    ("boat_ride", ["boat", "cruise", "ferry", "houseboat", "backwater"]),
    ("lake", ["lake", "sagar", "talab", "ghat", "sarovar", "jheel"]),
    ("stepwell", ["stepwell", "baori", "bawdi", "baoli", "vav"]),
    ("fort", ["fort", "garh", "qila", "killa"]),
    ("palace", ["palace", "mahal", "haveli"]),
    ("museum", ["museum", "gallery", "sangrahalaya", "planetarium"]),
    ("temple", ["temple", "mandir", "church", "mosque", "masjid", "gurudwara", "dargah", "cathedral", "basilica"]),
    ("garden", ["garden", "bagh", "park", "botanical"]),
    ("zoo", ["zoo", "safari", "sanctuary", "biological park"]),
    ("market", ["market", "bazaar", "bazar", "chowk", "haat"]),
    ("mall", ["mall", "plaza", "arcade"]),
    ("viewpoint", ["viewpoint", "view point", "point", "tower", "top station", "sunset"]),
    ("tea_estate", ["tea estate", "tea garden", "plantation"]),
    ("monument", ["gate", "minar", "tomb", "memorial", "mantar", "observatory", "ruins", "stupa"]),
    ("restaurant", ["restaurant", "cafe", "dhaba", "kitchen", "bistro"]),
    ("hotel", ["hotel", "resort", "inn", "lodge", "homestay"]),
]


def category_from_name(name):
    n = name.lower()
    for cat, words in NAME_HINTS:
        for w in words:
            if w in n:
                return cat
    return "monument"  # an unnamed sight is treated as an open-air monument


def rain_level(mm):
    """IMD daily rainfall classes: 0 none, 1 light (2.5-15.5 mm), 2 moderate
    (15.6-64.4), 3 heavy (64.5-115.5), 4 very heavy (115.6-204.4), 5 extremely
    heavy (204.5+)."""
    if mm >= 204.5:
        return 5
    if mm >= 115.6:
        return 4
    if mm >= 64.5:
        return 3
    if mm >= 15.6:
        return 2
    if mm >= 2.5:
        return 1
    return 0


def heat_level(t):
    """0 normal, 1 hot (36-39 °C), 2 heat wave (40-44), 3 severe (45+)."""
    if t >= 45:
        return 3
    if t >= 40:
        return 2
    if t >= 36:
        return 1
    return 0


def wind_level(k):
    """0 calm, 1 gusty (40-59 km/h), 2 storm (60+)."""
    if k >= 60:
        return 2
    if k >= 40:
        return 1
    return 0


LEVELS = ["none", "low", "moderate", "high"]


def weather_impact(category, w):
    """The reference answer for one place on one day."""
    cat = category if category in PROFILES else "monument"
    p = PROFILES[cat]
    t, mm, wind = w["temp_max_c"], w["rain_mm"], w["wind_kmh"]
    alert, alert_for = w["alert"], w.get("alert_for", "")
    rl, hl, wl = rain_level(mm), heat_level(t), wind_level(wind)
    wet_alert = alert in ("orange", "red") and alert_for in ("heavy rain", "thunderstorm", "cyclone")
    hot_alert = alert in ("orange", "red") and alert_for == "heat"

    # closed: water and hill places in dangerous rain or storms
    closed_reason = None
    if p["water"] and (rl >= 3 or wl >= 2 or (wet_alert and alert == "red") or alert_for == "cyclone" and alert != "none"):
        closed_reason = "Water activities and shores are usually shut in heavy rain or strong wind."
    elif cat in ("trek", "waterfall") and (rl >= 3 or wet_alert):
        closed_reason = "Hill trails and falls are closed or unsafe in heavy rain: landslides and flash floods."
    elif p["exposure"] == 2 and alert == "red" and alert_for == "cyclone":
        closed_reason = "Outdoor sites close during a cyclone warning."
    if closed_reason:
        sens = ["rain"] if rl >= 1 or wet_alert else []
        if wl >= 1 or alert_for in ("cyclone", "thunderstorm"):
            sens.append("wind")
        if p["flood"] and (rl >= 3 or wet_alert):
            sens.append("flood")
        return {"impact": "closed", "sensitive_to": sens or ["rain"], "best_time": "avoid", "reason": closed_reason}

    exp = p["exposure"]
    # heat: only where you are out in the sun
    heat = 0
    if hl and exp:
        heat = min(3, hl + (p["heat"] - 1)) if p["heat"] else 0
        if hot_alert:
            heat = min(3, heat + 1)
        if exp == 1:
            heat = min(heat, 2)
    # rain: outdoor places suffer most; indoor ones only on the way there
    rain = 0
    if rl:
        if exp == 0:
            rain = 1 if rl >= 3 else 0
        else:
            rain = min(3, max(0, rl - 1) + p["rain"] + (1 if p["hill"] and rl >= 2 else 0))
            if exp == 1:
                rain = min(rain, 2)
        if wet_alert:
            rain = min(3, rain + 1)
    wind_s = 0
    if wl and exp:
        wind_s = min(3, wl + p["wind"] - 1) if p["wind"] else (1 if wl >= 2 else 0)
    flood = 0
    if p["flood"] and rl >= 3:
        flood = min(3, p["flood"] + rl - 3)
    elif exp == 0 and rl >= 4:
        flood = 1

    scores = {"heat": heat, "rain": rain, "wind": wind_s, "flood": flood}
    top = max(scores.values())
    sens = [k for k in ("heat", "rain", "wind", "flood") if scores[k] > 0]
    impact = LEVELS[top]

    if top == 0:
        if hl >= 2 and exp == 0:
            return {"impact": "none", "sensitive_to": [], "best_time": "afternoon",
                    "reason": "Indoors, so a good place to spend the hottest hours."}
        return {"impact": "none", "sensitive_to": [], "best_time": "any", "reason": "The weather should not affect this visit."}

    dominant = max(scores, key=lambda k: (scores[k], ["flood", "wind", "rain", "heat"].index(k)))
    if dominant == "heat":
        if top >= 3 and cat in ("trek",):
            best, reason = "avoid", "Severe heat on an exposed trail; heat stroke risk."
        else:
            best = "evening" if cat in ("market", "viewpoint", "lake", "beach") else "morning"
            reason = {
                "temple": "Stone floors get too hot to walk barefoot by midday; go early.",
                "fort": "An exposed climb with little shade; go before 10 am.",
            }.get(cat, "Little shade and high heat; avoid 11 am to 4 pm.")
            if top >= 3:
                reason = "Severe heat: " + reason[0].lower() + reason[1:]
    elif dominant == "rain":
        if exp == 0:
            best, reason = "any", "Indoors, but roads there may be waterlogged; allow extra travel time."
        elif top >= 3:
            best, reason = "avoid", "Heavy rain makes this outdoor visit slippery and unpleasant; move it to a drier day."
        elif cat == "fort" and rl >= 2:
            best, reason = "morning", "Wet ramparts and stone paths get slippery; go early and carry rain gear."
        elif p["hill"] and rl >= 2:
            best, reason = "morning", "Rain makes the slopes slippery and brings fog; go early and carry rain gear."
        else:
            best, reason = "morning", "Showers are likely; go early and carry rain gear."
    elif dominant == "wind":
        best, reason = ("avoid" if top >= 3 else "morning"), "Strong wind; boats and exposed spots may be unsafe."
    else:
        best, reason = "avoid", "Low-lying and likely to flood in this rain."
    return {"impact": impact, "sensitive_to": sens, "best_time": best, "reason": reason}
