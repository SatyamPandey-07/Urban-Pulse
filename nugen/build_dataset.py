"""Builds the UrbanPulse Travel-Risk alignment data.

Writes to nugen/data/:
  handbook.txt            the domain rules (accessibility, IMD weather classes,
                          what each place type is sensitive to, event types)
  train_access.txt        worked access_claims examples
  train_impact.txt        worked weather_impact examples
  train_events.txt        worked weather_event examples
  benchmark.json          held-out samples for Nugen's evaluation (never in
                          the training files: different places, phrasings
                          and posts)
  golden.json             a small fixed set for the base-vs-aligned comparison
                          and for the app's tests

Every example is labelled by rule (travel_risk_rules.py) or by construction
(each snippet is assembled from fragments whose facts are known), so the labels
are consistent. Run: python nugen/build_dataset.py
"""

import json
import os
import random

from travel_risk_rules import (
    PROFILES,
    access_prompt,
    category_from_name,
    dump,
    event_prompt,
    impact_prompt,
    to_wire,
    weather_impact,
)

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "data")

# --------------------------------------------------------------------------
# places (train / held-out)
# --------------------------------------------------------------------------

SIGHTS = {
    "Jaipur": ["Amber Fort", "Nahargarh Fort", "Jaigarh Fort", "City Palace", "Hawa Mahal", "Jantar Mantar",
               "Albert Hall Museum", "Jal Mahal", "Birla Mandir", "Panna Meena ka Kund", "Johari Bazaar",
               "Galtaji Temple", "Sisodia Rani Garden", "Central Park Jaipur", "Patrika Gate", "World Trade Park"],
    "Goa": ["Baga Beach", "Calangute Beach", "Palolem Beach", "Basilica of Bom Jesus", "Fort Aguada",
            "Dudhsagar Falls", "Anjuna Flea Market", "Chapora Fort", "Mandovi River Cruise", "Goa State Museum",
            "Se Cathedral", "Mapusa Market", "Colva Beach", "Salim Ali Bird Sanctuary"],
    "Munnar": ["Eravikulam National Park", "Mattupetty Dam Lake", "Top Station", "Tea Museum Munnar",
               "Attukal Waterfalls", "Echo Point", "Kolukkumalai Tea Estate", "Anamudi Peak Trek", "Kundala Lake"],
    "Mumbai": ["Gateway of India", "Marine Drive", "Elephanta Caves Ferry", "Chhatrapati Shivaji Maharaj Vastu Sangrahalaya",
               "Juhu Beach", "Colaba Causeway Market", "Siddhivinayak Temple", "Haji Ali Dargah", "Sanjay Gandhi National Park",
               "Phoenix Palladium Mall", "Crawford Market", "Kanheri Caves Trail"],
    "Delhi": ["Red Fort", "Qutub Minar", "India Gate", "Humayun's Tomb", "Lodhi Garden", "Chandni Chowk",
              "National Museum Delhi", "Akshardham Temple", "Agrasen ki Baoli", "Dilli Haat", "Select Citywalk Mall",
              "Lotus Temple", "Delhi Zoo"],
    "Varanasi": ["Dashashwamedh Ghat", "Assi Ghat", "Kashi Vishwanath Temple", "Ganga Boat Ride", "Sarnath Stupa",
                 "Ramnagar Fort", "Banaras Hindu University Museum", "Vishwanath Gali Market"],
    "Udaipur": ["City Palace Udaipur", "Lake Pichola", "Sajjangarh Monsoon Palace", "Saheliyon ki Bari",
                "Fateh Sagar Lake", "Bagore ki Haveli", "Jagdish Temple", "Hathi Pol Bazaar"],
    "Agra": ["Taj Mahal", "Agra Fort", "Mehtab Bagh", "Itmad-ud-Daulah Tomb", "Kinari Bazaar", "Fatehpur Sikri Ruins"],
    "Rishikesh": ["Laxman Jhula", "Triveni Ghat", "Neer Garh Waterfall", "Kunjapuri Temple Trek", "Beatles Ashram",
                  "Ganga River Rafting Boat"],
    "Shimla": ["The Ridge Viewpoint", "Jakhu Temple Trek", "Mall Road Market", "Kufri Viewpoint", "Christ Church Shimla",
               "Himachal State Museum"],
}
HELD_OUT_SIGHTS = {
    "Hampi": ["Virupaksha Temple", "Vittala Temple Ruins", "Hampi Bazaar", "Tungabhadra Coracle Boat", "Matanga Hill Trek"],
    "Kochi": ["Fort Kochi Beach", "Mattancherry Palace", "Jew Town Market", "Kerala Backwater Houseboat", "Lulu Mall Kochi"],
    "Jodhpur": ["Mehrangarh Fort", "Umaid Bhawan Palace Museum", "Toorji ka Jhalra Stepwell", "Sardar Market", "Mandore Garden"],
    "Coorg": ["Abbey Falls", "Raja's Seat Viewpoint", "Dubare Elephant Camp", "Tadiandamol Peak Trek"],
    "Kolkata": ["Victoria Memorial", "Howrah Bridge", "Indian Museum Kolkata", "New Market Kolkata", "Princep Ghat Boat"],
}
HOTELS = ["Hotel Pearl Palace", "Zostel Jaipur", "Taj Rambagh Palace", "Treebo Trend Aamod", "ITC Rajputana",
          "Hotel Sea Breeze", "Casa Anjuna", "Tea Valley Resort", "Hotel Residency Fort", "Ganges View Homestay",
          "Hotel Lake View Udaipur", "Moustache Hostel", "FabHotel Prime", "Hotel Clarks Shiraz", "Radisson Blu"]
HELD_OUT_HOTELS = ["Hotel Sunrise Hampi", "Brunton Boatyard", "Raas Jodhpur", "Coorg Cliff Resort", "The Oberoi Grand"]
RESTAURANTS = ["Laxmi Mishthan Bhandar", "Britto's", "Saravana Bhavan", "Bademiya", "Karim's", "Blue Lassi Shop",
               "Ambrai Restaurant", "Pinch of Spice", "Chitale Bandhu"]
HELD_OUT_RESTAURANTS = ["Mango Tree Hampi", "Kashi Art Cafe", "Gypsy Restaurant", "Peter Cat"]

# --------------------------------------------------------------------------
# access_claims: fragments with known facts
# --------------------------------------------------------------------------
# Each fragment: (text, facts). facts keys: step_free, lift, ramp, toilet, stairs.

ACCESS_FACTS = {
    "sight": [
        ("There are about {n} steep steps up to the main palace", dict(step_free="no", stairs="n")),
        ("You have to climb {n} steps to reach the temple", dict(step_free="no", stairs="n")),
        ("No ramp anywhere, only stairs", dict(step_free="no", ramp="no")),
        ("The path up is cobbled and very steep, impossible with a wheelchair", dict(step_free="no")),
        ("Seedhiyan bahut hain, wheelchair le jaana mushkil hai", dict(step_free="no")),
        ("There is a ramp at the main gate and the ground floor galleries are flat", dict(step_free="yes", ramp="yes")),
        ("My father went round in his wheelchair without any trouble, the paths are paved and level", dict(step_free="yes")),
        ("Wheelchairs are available free at the ticket counter and the whole route is ramped", dict(step_free="yes", ramp="yes")),
        ("Accessible toilet near the entrance", dict(toilet="yes")),
        ("The only washrooms are down a flight of stairs", dict(toilet="no")),
        ("A lift takes you up to the upper floors", dict(lift="yes")),
        ("The upper levels can only be reached by narrow stairs", dict(step_free="no", lift="no")),
        ("Entry level hai, koi seedhi nahi", dict(step_free="yes")),
        ("Wheelchair users can enter through the side gate which has a ramp", dict(step_free="yes", ramp="yes")),
        ("The golf cart from the parking to the gate is helpful for elderly visitors, but inside there are {n} steps", dict(step_free="no", stairs="n")),
        ("Sand everywhere, no boardwalk, so a wheelchair will get stuck", dict(step_free="no")),
        ("There is a boardwalk ramp down to the beach", dict(step_free="yes", ramp="yes")),
        ("Lift was not working when we visited, so we had to use the stairs", dict(lift="no", step_free="no")),
        ("Ghat ki seedhiyan steep hain, around {n} steps till the water", dict(step_free="no", stairs="n")),
    ],
    "hotel": [
        ("The hotel has a lift to all floors", dict(lift="yes")),
        ("No lift, and our room was on the second floor", dict(lift="no", step_free="no")),
        ("Lift hai, but the entrance has {n} steps and no ramp", dict(lift="yes", step_free="no", ramp="no", stairs="n")),
        ("Step-free entrance with a gentle ramp from the drop-off", dict(step_free="yes", ramp="yes")),
        ("They gave us a ground floor room with a roll-in shower and grab bars", dict(toilet="yes", step_free="yes")),
        ("The bathroom has a high step into the shower, not good for wheelchair users", dict(toilet="no")),
        ("The lift was out of order for two days", dict(lift="no")),
        ("Reception is up a flight of stairs from the street", dict(step_free="no")),
        ("Wide doors and an accessible bathroom in the room", dict(toilet="yes")),
        ("Heritage building, rooms are reached by a spiral staircase only", dict(step_free="no", lift="no")),
        ("There is a ramp next to the steps at the entrance", dict(ramp="yes", step_free="yes")),
    ],
    "restaurant": [
        ("Seating is on the first floor and there is no lift", dict(lift="no", step_free="no")),
        ("Ground floor seating, easy to get in with a wheelchair", dict(step_free="yes")),
        ("{n} steps at the entrance and no ramp", dict(step_free="no", ramp="no", stairs="n")),
        ("The staff put down a portable ramp for my mother's wheelchair", dict(ramp="yes", step_free="yes")),
        ("Washroom is tiny and up some stairs", dict(toilet="no")),
        ("Rooftop only, reached by stairs", dict(step_free="no", lift="no")),
    ],
}
HELD_OUT_ACCESS = {
    "sight": [
        ("Almost {n} stone steps to climb before the first courtyard", dict(step_free="no", stairs="n")),
        ("Ramped entry and smooth floors throughout, we used a wheelchair all day", dict(step_free="yes", ramp="yes")),
        ("Toilets for disabled visitors are available beside the cloakroom", dict(toilet="yes")),
        ("Bahut saari seedhiyan, buzurgon ke liye mushkil", dict(step_free="no")),
        ("The viewing deck has a lift", dict(lift="yes")),
    ],
    "hotel": [
        ("Lift available and the corridors are wide", dict(lift="yes")),
        ("You enter through {n} steps, there is no ramp", dict(step_free="no", ramp="no", stairs="n")),
        ("Room had a wheelchair-friendly bathroom with rails", dict(toilet="yes")),
    ],
    "restaurant": [
        ("Entrance is level with the road", dict(step_free="yes")),
        ("Dining hall is upstairs, no elevator", dict(lift="no", step_free="no")),
    ],
}
FILLER = [
    "Stunning sunset views over the city",
    "The staff were very polite and helpful",
    "Food was average but the lassi was great",
    "It gets very crowded on weekends",
    "Parking is limited so take an auto",
    "Bahut sundar jagah hai",
    "Great value for money",
    "Go early to avoid the queues",
    "The light and sound show in the evening is worth it",
    "Guides at the gate charge too much, negotiate",
    "Clean rooms and a good breakfast",
    "Paneer tikka was the best we had",
    "Photography is allowed inside",
    "Very accommodating staff, they helped us a lot",
    "Perfect for families",
    "Monsoon mein aur bhi khoobsurat lagta hai",
    "Ramps are apparently being planned for next year",
    "Good for elderly people",
]
HELD_OUT_FILLER = [
    "Amazing architecture and history",
    "Waiters were friendly, service was quick",
    "Ticket prices are fair",
    "Mast jagah, zaroor jaana",
    "Wheelchair accessibility is something they say they are working on",
]

NUMBERS = [12, 20, 25, 30, 40, 45, 60, 80, 100, 120, 150, 200, 250]


def build_access(rng, n, facts_pool, filler_pool, places):
    out = []
    for _ in range(n):
        kind = rng.choice(["sight", "sight", "sight", "hotel", "hotel", "restaurant"])
        city, place = places[kind](rng)
        facts = facts_pool[kind]
        # ~30% no access facts at all: the answer must be all unknown
        k = 0 if rng.random() < 0.3 else rng.choice([1, 1, 2, 2, 3])
        chosen = rng.sample(facts, min(k, len(facts)))
        sentences, evidence = [], []
        ans = {"step_free": "unknown", "lift": "unknown", "ramp": "unknown", "accessible_toilet": "unknown", "stairs": None}
        consistent = True
        for text, f in chosen:
            num = rng.choice(NUMBERS)
            t = text.replace("{n}", str(num))
            for key, v in f.items():
                key2 = "accessible_toilet" if key == "toilet" else key
                if key2 == "stairs":
                    ans["stairs"] = num
                    continue
                if ans[key2] not in ("unknown", v):
                    consistent = False
                ans[key2] = v
            sentences.append(t)
            evidence.append(t)
        if not consistent:
            continue
        # a ramp that exists does not make a place step-free by itself unless said
        fill = rng.sample(filler_pool, rng.choice([1, 2, 2, 3]))
        parts = sentences + fill
        rng.shuffle(parts)
        snippet = ". ".join(parts) + "."
        answer = dict(ans)
        answer["evidence"] = sorted(evidence, key=snippet.index)
        out.append((access_prompt(place, kind, city, snippet), answer))
    return out


def pick_place(sights, hotels, restaurants):
    cities = list(sights)

    def sight(rng):
        c = rng.choice(cities)
        return c, rng.choice(sights[c])

    def hotel(rng):
        return rng.choice(cities), rng.choice(hotels)

    def rest(rng):
        return rng.choice(cities), rng.choice(restaurants)

    return {"sight": sight, "hotel": hotel, "restaurant": rest}


# --------------------------------------------------------------------------
# weather_impact
# --------------------------------------------------------------------------

WEATHER_KINDS = [
    # (label, generator) for a spread of normal and extreme days
    ("clear", lambda r: dict(temp_max_c=r.randint(24, 33), rain_mm=0, rain_prob=r.randint(0, 15), wind_kmh=r.randint(5, 20), alert="none", alert_for="")),
    ("warm", lambda r: dict(temp_max_c=r.randint(34, 38), rain_mm=0, rain_prob=r.randint(0, 20), wind_kmh=r.randint(5, 20), alert="none", alert_for="")),
    ("heatwave", lambda r: dict(temp_max_c=r.randint(40, 44), rain_mm=0, rain_prob=r.randint(0, 10), wind_kmh=r.randint(8, 25), alert=r.choice(["none", "yellow", "orange"]), alert_for="heat")),
    ("severe_heat", lambda r: dict(temp_max_c=r.randint(45, 48), rain_mm=0, rain_prob=r.randint(0, 5), wind_kmh=r.randint(8, 25), alert=r.choice(["orange", "red"]), alert_for="heat")),
    ("light_rain", lambda r: dict(temp_max_c=r.randint(24, 31), rain_mm=round(r.uniform(2.5, 15), 1), rain_prob=r.randint(40, 80), wind_kmh=r.randint(8, 25), alert="none", alert_for="")),
    ("moderate_rain", lambda r: dict(temp_max_c=r.randint(23, 30), rain_mm=round(r.uniform(16, 60), 1), rain_prob=r.randint(60, 90), wind_kmh=r.randint(10, 35), alert=r.choice(["none", "yellow"]), alert_for="heavy rain")),
    ("heavy_rain", lambda r: dict(temp_max_c=r.randint(22, 29), rain_mm=round(r.uniform(65, 115), 1), rain_prob=r.randint(80, 100), wind_kmh=r.randint(15, 45), alert=r.choice(["yellow", "orange"]), alert_for="heavy rain")),
    ("very_heavy_rain", lambda r: dict(temp_max_c=r.randint(21, 28), rain_mm=round(r.uniform(116, 240), 1), rain_prob=r.randint(90, 100), wind_kmh=r.randint(20, 55), alert=r.choice(["orange", "red"]), alert_for="heavy rain")),
    ("thunderstorm", lambda r: dict(temp_max_c=r.randint(26, 36), rain_mm=round(r.uniform(5, 40), 1), rain_prob=r.randint(60, 90), wind_kmh=r.randint(45, 70), alert=r.choice(["yellow", "orange"]), alert_for="thunderstorm")),
    ("cyclone", lambda r: dict(temp_max_c=r.randint(24, 30), rain_mm=round(r.uniform(80, 220), 1), rain_prob=100, wind_kmh=r.randint(70, 120), alert=r.choice(["orange", "red"]), alert_for="cyclone")),
]


def normalize_weather(w):
    if w["alert"] == "none":
        w["alert_for"] = ""
    if isinstance(w["rain_mm"], float) and w["rain_mm"].is_integer():
        w["rain_mm"] = int(w["rain_mm"])
    return w


def build_impact(rng, n, sights, unknown_share=0.3):
    out = []
    cities = list(sights)
    for _ in range(n):
        city = rng.choice(cities)
        place = rng.choice(sights[city])
        true_cat = category_from_name(place)
        shown = "unknown" if rng.random() < unknown_share else true_cat
        label, gen = rng.choice(WEATHER_KINDS)
        w = normalize_weather(gen(rng))
        month = rng.choice(["04", "05", "06", "07", "08", "09", "10", "12", "01"])
        date = f"2026-{month}-{rng.randint(1, 28):02d}"
        ans = weather_impact(true_cat, w)
        out.append((impact_prompt(place, shown, city, date, w), ans))
    return out


# --------------------------------------------------------------------------
# weather_event
# --------------------------------------------------------------------------

AREAS = {
    "Mumbai": ["Andheri Subway", "Hindmata", "Sion", "Kurla", "Milan Subway", "Marine Drive", "Dadar TT", "Western Express Highway"],
    "Jaipur": ["MI Road", "Tonk Road", "Johari Bazaar", "Amer Road", "Sindhi Camp", "Malviya Nagar"],
    "Delhi": ["Minto Bridge", "ITO", "Pragati Maidan tunnel", "Ring Road", "Connaught Place", "Yamuna Bazaar"],
    "Goa": ["Panjim market", "Porvorim", "Mapusa", "Calangute junction", "Margao station road"],
    "Munnar": ["Munnar-Top Station road", "Mattupetty road", "Devikulam", "Old Munnar"],
    "Varanasi": ["Dashashwamedh Ghat", "Assi Ghat", "Lanka", "Godowlia"],
    "Shimla": ["Cart Road", "Kufri road", "Mall Road", "Dhalli tunnel"],
}
HELD_OUT_AREAS = {
    "Kolkata": ["Park Street", "Thanthania", "EM Bypass", "Howrah station"],
    "Chennai": ["T Nagar", "Velachery", "Anna Salai", "Marina Beach road"],
    "Kochi": ["MG Road Kochi", "Kaloor", "Edappally"],
}
ATTRACTIONS = {
    "Mumbai": ["Elephanta Caves ferry", "Juhu Beach", "Gateway of India"],
    "Jaipur": ["Amber Fort", "Nahargarh Fort", "Jal Mahal"],
    "Delhi": ["Qutub Minar", "Red Fort", "India Gate lawns"],
    "Goa": ["Dudhsagar Falls", "Baga Beach", "Palolem Beach"],
    "Munnar": ["Eravikulam National Park", "Attukal Waterfalls", "Top Station"],
    "Varanasi": ["Ganga boat rides", "Ganga Aarti at Dashashwamedh"],
    "Shimla": ["Jakhu Temple ropeway", "Kufri"],
}
HELD_OUT_ATTRACTIONS = {
    "Kolkata": ["Victoria Memorial", "Princep Ghat boats"],
    "Chennai": ["Marina Beach", "Kapaleeshwarar Temple"],
    "Kochi": ["Fort Kochi beach", "backwater houseboats"],
}

# (template, event, severity, affects, needs) ; needs: "area" or "attraction" or None
EVENT_TEMPLATES = [
    ("Ankle-deep water at {area} since morning, traffic crawling #rains", "waterlogging", "low", ["roads"], "area"),
    ("Knee-deep water at {area}, cars stuck, avoid the route!", "waterlogging", "moderate", ["roads", "transport"], "area"),
    ("{area} completely flooded, water up to the waist, buses diverted", "flooding", "high", ["roads", "transport"], "area"),
    ("{area} mein paani bhar gaya hai, gaadi mat lana", "waterlogging", "moderate", ["roads"], "area"),
    ("Local trains suspended between stations near {area} due to water on tracks", "flooding", "high", ["transport"], "area"),
    ("Landslide on {area}, road blocked both ways, stay where you are", "landslide", "high", ["roads", "transport"], "area"),
    ("Tree fell on {area} in the storm, one lane closed", "storm", "moderate", ["roads"], "area"),
    ("Police have closed {area} because of rising water", "road_closed", "high", ["roads"], "area"),
    ("{attraction} closed today due to heavy rain, officials say", "attraction_closed", "moderate", ["attraction"], "attraction"),
    ("Aaj {attraction} band hai, barish ki wajah se", "attraction_closed", "moderate", ["attraction"], "attraction"),
    ("{attraction} shut for tourists till further notice after red alert", "attraction_closed", "high", ["attraction"], "attraction"),
    ("It is 46 degrees today, {area} is deserted by noon, stay indoors", "heat", "high", ["attraction"], "area"),
    ("Scorching heat at {attraction}, stone floor burning, we left in 20 minutes", "heat", "moderate", ["attraction"], "attraction"),
    ("Power cut for 5 hours around {area} after the storm, hotels on generators", "power_cut", "moderate", ["power", "hotel"], "area"),
    ("Thunderstorm with strong winds hit {area}, hoardings down", "storm", "high", ["roads"], "area"),
    ("Hotel lobby near {area} flooded, guests moved to upper floors", "flooding", "high", ["hotel"], "area"),
    ("Slight drizzle at {area}, roads fine, no problem", "none", "none", [], None),
]
HELD_OUT_EVENT_TEMPLATES = [
    ("Water entered shops at {area}, knee high, traffic stopped", "waterlogging", "moderate", ["roads"], "area"),
    ("{attraction} closed for visitors today because of the storm warning", "attraction_closed", "moderate", ["attraction"], "attraction"),
    ("Bijli gayi hai 4 ghante se {area} mein, storm ke baad", "power_cut", "moderate", ["power"], "area"),
    ("Road caved in at {area} after the rain, diversion in place", "road_closed", "high", ["roads"], "area"),
]
NON_EVENTS = [
    "Lovely weather today, perfect for chai and pakode",
    "Monsoon vibes! Clouds over the hills look magical",
    "Best biryani in town, rain or shine #foodie",
    "Anyone know a good hotel near the station? Travelling next week",
    "The sunset tonight was unreal",
    "Kitna accha mausam hai aaj",
    "Carry an umbrella this week, forecast says showers",
    "Flat 50% off on monsoon collection, visit our store",
    "Traffic is normal today, reached office in 20 minutes",
]
HELD_OUT_NON_EVENTS = [
    "Rainy days and filter coffee, nothing better",
    "Mausam suhana hai, long drive pe chalte hain",
    "Book your monsoon getaway with 30% off",
]


def build_events(rng, n, areas, attractions, templates, non_events):
    out = []
    cities = list(areas)
    for _ in range(n):
        city = rng.choice(cities)
        if rng.random() < 0.3:
            post = rng.choice(non_events)
            ans = {"is_weather_event": False, "event": "none", "place": None, "severity": "none", "affects": []}
        else:
            tpl, ev, sev, affects, need = rng.choice(templates)
            place = None
            if need == "area":
                place = rng.choice(areas[city])
            elif need == "attraction":
                place = rng.choice(attractions[city])
            post = tpl.replace("{area}", place or "").replace("{attraction}", place or "")
            is_ev = ev != "none"
            ans = {"is_weather_event": is_ev, "event": ev, "place": place if is_ev else None,
                   "severity": sev, "affects": affects}
        out.append((event_prompt(city, post), ans))
    return out


# --------------------------------------------------------------------------
# handbook
# --------------------------------------------------------------------------

HANDBOOK = """UrbanPulse Travel-Risk handbook

UrbanPulse plans trips in India for travellers with and without access needs (wheelchair users, elderly people, people who cannot walk far). This handbook defines three tasks and the rules for answering them. Answers are always a single JSON object and nothing else, and every value in it is a string in double quotes: numbers are written as digits in quotes ("40"), several items are joined in one string ("heat, rain"), and a missing value is "none" or "unknown".

1. access_claims: wheelchair-access facts from one review snippet

Read the snippet and report only what it states. Never guess from the type of place, its fame or its star rating.
- step_free: "yes" when the snippet says you can get in and around without steps (level entry, a ramp to the entrance, paved level paths, someone used a wheelchair without trouble). "no" when it mentions steps, stairs, a climb, cobbles, sand or anything that stops a wheelchair. Otherwise "unknown".
- lift: "yes" when a working lift or elevator is mentioned. "no" when it says there is no lift, the lift was broken or out of order, or floors are reached only by stairs. Otherwise "unknown".
- ramp: "yes" when a ramp (fixed, portable or a boardwalk) is mentioned as available now. "no" when it says there is no ramp. Planned or future ramps are "unknown".
- accessible_toilet: "yes" for an accessible, disabled or wheelchair-friendly toilet, washroom or bathroom (roll-in shower, grab bars). "no" when the only toilets are up or down stairs, tiny, or have a high step. Otherwise "unknown".
- stairs: the number of steps as a string when the snippet gives one ("about 40 steps" gives "40"), otherwise "unknown".
- evidence: the exact sentences from the snippet that support each non-unknown answer, copied word for word and joined with " | ". "none" when everything is unknown.
Politeness, "helpful staff", "good for families" and "good for elderly people" are not access facts. A snippet with no access facts gets "unknown" for every field and evidence "none". Hinglish counts: "seedhiyan" means stairs, "koi seedhi nahi" means no steps, "lift hai" means there is a lift.

Why this matters: an itinerary for a wheelchair user must never treat a guess as confirmed access. A fort with 40 steps described as "wheelchair friendly" by a guess sends a traveller to a place they cannot enter.

Accessibility references used in India: the Harmonised Guidelines and Standards for Universal Accessibility in India (2021) and the Rights of Persons with Disabilities Act, 2016. Ramps should be no steeper than 1:12 and have handrails; doors need a clear width of about 900 mm; an accessible toilet has space to turn a wheelchair, grab bars and a level entry.

2. weather_impact: how one day's weather affects visiting one place

Rainfall classes (India Meteorological Department, 24-hour rainfall): light 2.5 to 15.5 mm, moderate 15.6 to 64.4 mm, heavy 64.5 to 115.5 mm, very heavy 115.6 to 204.4 mm, extremely heavy 204.5 mm or more.
Heat: 36 to 39 °C is hot; 40 to 44 °C is a heat wave in the plains; 45 °C or more is severe heat.
Wind: 40 to 59 km/h is gusty; 60 km/h or more is a storm.
IMD colour warnings: yellow means be aware, orange means be prepared (disruption likely), red means take action (dangerous; closures and evacuations happen).

Place categories and what they are sensitive to:
- Indoors (museum, mall, restaurant, hotel): not affected by heat or rain inside; only very heavy rain affects getting there. On heat-wave days they are the best places for the afternoon.
- Partly outdoor (palace, temple, market): courtyards and open lanes. Temples are especially heat-sensitive because floors are walked barefoot and stone gets very hot by midday.
- Outdoor (fort, monument, stepwell, garden, zoo): exposed to sun and rain. Forts are exposed climbs with little shade.
- Hill places (trek, viewpoint, tea estate, fort on a hill, waterfall): rain makes slopes slippery, brings fog and landslides.
- Water places (beach, lake, boat ride, waterfall): closed in heavy rain, storms and cyclone warnings; boats stop in strong wind.
When the category is "unknown", infer it from the name: Fort, Garh, Qila mean fort; Mahal, Palace, Haveli mean palace; Mandir, Temple, Masjid, Church, Dargah mean a place of worship; Baori, Baoli, Vav mean a stepwell; Bagh, Garden, Park mean a garden; Bazaar, Market, Chowk mean a market; Ghat, Lake, Sagar, Talab mean a lakeside or riverside; Falls mean a waterfall; Trek, Trail, Peak mean a trek; Point, Top Station, Viewpoint mean a viewpoint.

Answer fields:
- impact: none, low, moderate, high, or closed (when the place is shut or unsafe that day).
- sensitive_to: the hazards that matter that day, from heat, rain, wind, flood, joined with commas ("heat, rain"), or "none".
- best_time: morning, afternoon, evening, any, or avoid. Outdoor places in heat: morning (markets, lakes, beaches and viewpoints: evening). Indoor places on hot days: afternoon. Rainy days: morning, before afternoon storms; avoid in heavy rain.
- reason: one short sentence a traveller understands.

3. weather_event: the travel disruption one social post reports

Decide whether the post reports a weather disruption that affects travel: is_weather_event is "yes" or "no". Weather chat, forecasts, adverts and nice-weather posts are not events ("no", event "none", place "none", severity "none", affects "none").
Event types: waterlogging (standing water on roads), flooding (water entering buildings, tracks, or waist-deep water), heat (dangerous heat at a place), storm (wind or thunderstorm damage), landslide, road_closed, attraction_closed, power_cut, none.
Severity: ankle-deep water or slow traffic is low; knee-deep water, stuck cars, a closed attraction or one lane closed is moderate; waist-deep water, suspended trains, blocked roads, landslides and red alerts are high.
place: the road, area or attraction named in the post, or "none".
affects: which parts of a trip it touches, joined with commas: roads, transport, attraction, hotel, power; or "none".

These signals feed the UrbanPulse weather digital twin: a closed attraction removes a visit, a waterlogged road slows the legs that use it, and a flooded hotel area puts the stay at risk.
"""


def wire(ins, ans):
    return to_wire(ins.split("\n", 1)[0].replace("TASK:", "").strip(), ans)


def write_examples(path, title, rows):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(f"{title}\n\n")
        for ins, ans in rows:
            f.write("### Instruction:\n" + ins + "\n### Response:\n" + wire(ins, ans) + "\n\n")


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = random.Random(2026)

    train_places = pick_place(SIGHTS, HOTELS, RESTAURANTS)
    test_places = pick_place(HELD_OUT_SIGHTS, HELD_OUT_HOTELS, HELD_OUT_RESTAURANTS)

    access_train = build_access(rng, 340, ACCESS_FACTS, FILLER, train_places)
    impact_train = build_impact(rng, 320, SIGHTS)
    events_train = build_events(rng, 280, AREAS, ATTRACTIONS, EVENT_TEMPLATES, NON_EVENTS)

    # held-out: other places, cities, phrasings and posts (and the training
    # fragments mixed in, since real reviews repeat common phrasings)
    mixed_access = {k: ACCESS_FACTS[k] + HELD_OUT_ACCESS[k] for k in ACCESS_FACTS}
    access_test = build_access(random.Random(7), 30, mixed_access, FILLER + HELD_OUT_FILLER, test_places)
    impact_test = build_impact(random.Random(8), 25, HELD_OUT_SIGHTS)
    events_test = build_events(random.Random(9), 25, HELD_OUT_AREAS, HELD_OUT_ATTRACTIONS,
                               EVENT_TEMPLATES + HELD_OUT_EVENT_TEMPLATES, NON_EVENTS + HELD_OUT_NON_EVENTS)

    with open(os.path.join(OUT, "handbook.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write(HANDBOOK)
    write_examples(os.path.join(OUT, "train_access.txt"), "UrbanPulse Travel-Risk: access_claims worked examples", access_train)
    write_examples(os.path.join(OUT, "train_impact.txt"), "UrbanPulse Travel-Risk: weather_impact worked examples", impact_train)
    write_examples(os.path.join(OUT, "train_events.txt"), "UrbanPulse Travel-Risk: weather_event worked examples", events_train)

    bench = access_test + impact_test + events_test
    samples = [{"sample_num": i + 1, "instruction": ins, "response": wire(ins, ans)} for i, (ins, ans) in enumerate(bench)]
    with open(os.path.join(OUT, "benchmark.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(samples, f, ensure_ascii=False, indent=1)

    # golden set: 8 access (incl. the no-facts case), 6 impact, 6 events
    golden = access_test[:8] + impact_test[:6] + events_test[:6]
    with open(os.path.join(OUT, "golden.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump([{"instruction": i, "expected": a} for i, a in golden], f, ensure_ascii=False, indent=1)

    # training data must not contain any benchmark instruction
    train_set = {i for i, _ in access_train + impact_train + events_train}
    leaks = [s for s in samples if s["instruction"] in train_set]
    print(f"train: access {len(access_train)}, impact {len(impact_train)}, events {len(events_train)}")
    print(f"benchmark: {len(samples)} samples, leaks into training: {len(leaks)}")
    unknown_all = sum(1 for _, a in access_train if a["evidence"] == [])
    print(f"access examples with no facts (all unknown): {unknown_all}")
    cats = {}
    for _, a in impact_train:
        cats[a["impact"]] = cats.get(a["impact"], 0) + 1
    print("impact label spread:", cats)


if __name__ == "__main__":
    main()
