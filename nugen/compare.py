"""Base vs aligned: runs the golden set (nugen/data/golden.json, held out from
training) through the base model and the aligned model, scores each field, and
writes nugen/results/compare.md and compare.json.

    NUGEN_API_KEY=... python nugen/compare.py
"""

import json
import os
import re
import time

import requests

from travel_risk_rules import ACCESS_SCHEMA, from_wire

HERE = os.path.dirname(os.path.abspath(__file__))
URL = "https://api.nugen.in/api/v3/inference/chat/completions"

# The Jaipur wheelchair run's failure: nothing in this review is about access,
# yet a general model called the fort accessible.
EXTRA = [
    {
        "instruction": (
            "TASK: access_claims\n"
            "Place: Nahargarh Fort (sight), Jaipur\n"
            'Snippet: "Stunning sunset views over the city, the cafe on top is lovely. Very accommodating staff, they helped us a lot. Good for elderly people."\n'
            "Answer with JSON only: " + ACCESS_SCHEMA
        ),
        "expected": {"step_free": "unknown", "lift": "unknown", "ramp": "unknown", "accessible_toilet": "unknown", "stairs": None, "evidence": []},
    }
]


def ask(model, instruction, key):
    body = {
        "model": model,
        "messages": [{"role": "user", "content": instruction}],
        "max_tokens": 700,
        "temperature": 0.0,
        "stream": False,
    }
    h = {"Authorization": f"Bearer {key}", "Content-Type": "application/json", "accept": "application/json"}
    for attempt in range(4):
        t = time.time()
        try:
            r = requests.post(URL, headers=h, json=body, timeout=120)
        except requests.RequestException as e:
            err = str(e)
            time.sleep(5 * (attempt + 1))
            continue
        ms = int((time.time() - t) * 1000)
        if r.status_code == 200:
            j = r.json()
            try:
                return j["choices"][0]["message"]["content"] or "", ms, None
            except (KeyError, IndexError, TypeError):
                return "", ms, f"unexpected body: {r.text[:200]}"
        err = f"{r.status_code}: {r.text[:200]}"
        if r.status_code not in (429, 500, 502, 503, 504):
            break
        time.sleep(8 * (attempt + 1))
    return "", 0, err


def parse(text):
    """The first JSON object in the answer, after any <think> block."""
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.S)
    start = text.find("{")
    while start != -1:
        depth, in_str, esc = 0, False, False
        for i in range(start, len(text)):
            c = text[i]
            if in_str:
                if esc:
                    esc = False
                elif c == "\\":
                    esc = True
                elif c == '"':
                    in_str = False
            elif c == '"':
                in_str = True
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    try:
                        return json.loads(text[start:i + 1])
                    except json.JSONDecodeError:
                        break
        start = text.find("{", start + 1)
    return None


def task_of(instruction):
    return instruction.split("\n", 1)[0].replace("TASK:", "").strip()


def snippet_of(instruction):
    m = re.search(r'Snippet: "(.*)"\n', instruction)
    return m.group(1) if m else ""


def score(task, instruction, exp, got):
    """(fields right, fields checked, notes)."""
    if not isinstance(got, dict):
        return 0, 1, ["no valid JSON"]
    notes = []
    if task == "access_claims":
        keys = ["step_free", "lift", "ramp", "accessible_toilet", "stairs"]
        right = sum(1 for k in keys if got.get(k) == exp.get(k))
        snippet = snippet_of(instruction)
        ev = got.get("evidence") or []
        bad = [q for q in ev if not isinstance(q, str) or q.strip().rstrip(".") not in snippet]
        if bad:
            notes.append(f"{len(bad)} quote(s) not in the snippet")
        guessed = [k for k in keys[:4] if exp.get(k) == "unknown" and got.get(k) in ("yes", "no")]
        if guessed:
            notes.append("guessed " + ", ".join(guessed))
        return right + (0 if bad else 1), len(keys) + 1, notes
    if task == "weather_impact":
        checks = [got.get("impact") == exp["impact"], got.get("best_time") == exp["best_time"],
                  sorted(got.get("sensitive_to") or []) == sorted(exp["sensitive_to"])]
        return sum(checks), len(checks), notes
    checks = [got.get("is_weather_event") == exp["is_weather_event"], got.get("event") == exp["event"],
              got.get("severity") == exp["severity"],
              (got.get("place") or None) == (exp.get("place") or None)]
    return sum(checks), len(checks), notes


def main():
    key = os.environ["NUGEN_API_KEY"]
    with open(os.path.join(HERE, "results", "state.json"), encoding="utf-8") as f:
        state = json.load(f)
    with open(os.path.join(HERE, "data", "golden.json"), encoding="utf-8") as f:
        golden = EXTRA + json.load(f)
    models = [("base", state["base_model_id"])]
    if state.get("model_id"):
        models.append(("aligned", state["model_id"]))

    rows, totals = [], {}
    for case in golden:
        task = task_of(case["instruction"])
        row = {"task": task, "instruction": case["instruction"], "expected": case["expected"], "answers": {}}
        for label, model in models:
            text, ms, err = ask(model, case["instruction"], key)
            got = from_wire(task, parse(text))
            right, of, notes = score(task, case["instruction"], case["expected"], got)
            row["answers"][label] = {"model": model, "raw": text, "parsed": got, "ms": ms, "error": err,
                                     "right": right, "of": of, "notes": notes}
            t = totals.setdefault(label, {"right": 0, "of": 0, "json": 0, "n": 0, "guesses": 0, "bad_quotes": 0, "ms": []})
            t["right"] += right
            t["of"] += of
            t["n"] += 1
            t["json"] += 1 if isinstance(got, dict) else 0
            t["guesses"] += 1 if any(n.startswith("guessed") for n in notes) else 0
            t["bad_quotes"] += 1 if any("not in the snippet" in n for n in notes) else 0
            if ms:
                t["ms"].append(ms)
        rows.append(row)
        print(task, {k: f"{v['right']}/{v['of']}" for k, v in row["answers"].items()}, flush=True)

    out = {"models": dict(models), "totals": totals, "rows": rows, "at": time.strftime("%Y-%m-%d %H:%M")}
    with open(os.path.join(HERE, "results", "compare.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)

    lines = ["# Base vs aligned: UrbanPulse Travel-Risk", "",
             f"Run {out['at']}. {len(rows)} held-out cases (other cities, places and phrasings than the training data), "
             "plus the Jaipur fort review that a general model called wheelchair-accessible.", "",
             "| | " + " | ".join(label for label, _ in models) + " |", "|---|" + "---|" * len(models)]
    def cell(label, f):
        t = totals.get(label)
        return f(t) if t else "-"
    lines.append("| Model | " + " | ".join(f"`{m}`" for _, m in models) + " |")
    lines.append("| Fields correct | " + " | ".join(cell(l, lambda t: f"{t['right']}/{t['of']} ({100 * t['right'] // max(1, t['of'])}%)") for l, _ in models) + " |")
    lines.append("| Valid JSON | " + " | ".join(cell(l, lambda t: f"{t['json']}/{t['n']}") for l, _ in models) + " |")
    lines.append("| Access answers that guessed (said yes/no with no evidence) | " + " | ".join(cell(l, lambda t: str(t['guesses'])) for l, _ in models) + " |")
    lines.append("| Quotes not found in the snippet | " + " | ".join(cell(l, lambda t: str(t['bad_quotes'])) for l, _ in models) + " |")
    lines.append("| Median latency | " + " | ".join(cell(l, lambda t: f"{sorted(t['ms'])[len(t['ms']) // 2] / 1000:.1f} s" if t['ms'] else "-") for l, _ in models) + " |")
    lines += ["", "## Cases", ""]
    for i, r in enumerate(rows, 1):
        lines += [f"### {i}. {r['task']}", "", "```", r["instruction"].split("\nAnswer with JSON only")[0], "```", "",
                  "Expected: `" + json.dumps(r["expected"], ensure_ascii=False) + "`", ""]
        for label, a in r["answers"].items():
            shown = json.dumps(a["parsed"], ensure_ascii=False) if a["parsed"] is not None else (a["error"] or a["raw"][:300].replace("\n", " "))
            lines.append(f"- **{label}** ({a['right']}/{a['of']}{', ' + '; '.join(a['notes']) if a['notes'] else ''}): `{shown}`")
        lines.append("")
    with open(os.path.join(HERE, "results", "compare.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print("\n".join(lines[:14]))


if __name__ == "__main__":
    main()
