# UrbanPulse Travel-Risk: a Nugen-aligned model

**Base model → Nugen alignment → domain model → used in the app**

| Step | What |
|---|---|
| Base model | `llama-v3p2-3b-reasoning` (the text model Nugen offers for alignment) |
| Domain data | `data/handbook.txt` plus about 860 worked examples (`data/train_*.txt`) |
| Alignment | `pipeline.py`: upload the documents, attach a held-out benchmark, align, deploy, evaluate against the base model |
| Domain model | The aligned model id is recorded in `results/state.json` |
| In the app | `lib/agents/travel_risk/nugen_travel_risk.dart`, used by Khoji and by the weather digital twin |

## What the model does

The model does three narrow jobs, where a general model guesses and we need facts:

1. **`access_claims`**: reads one review snippet and reports step-free access, lifts, ramps, accessible toilets and stair counts.
   - Each fact comes with the exact sentence it relied on.
   - When the snippet says nothing about access, the answer is "unknown".
   - This fixes the Jaipur failure, where a general model called a fort with about 40 steps "wheelchair friendly".
   - Khoji uses it for travellers with mobility needs.
2. **`weather_impact`**: judges how one day's weather affects visiting one place (none / low / moderate / high / closed, plus the best time of day and a reason). It uses:
   - the India Meteorological Department (IMD) rainfall classes and heat-wave thresholds;
   - IMD's colour warnings;
   - what each kind of place is sensitive to, for example barefoot temples in heat, and waterfalls and boats in heavy rain.

   The weather digital twin uses it for every place in the trip.
3. **`weather_event`**: reads one social post or headline and reports whether it describes a travel disruption. If it does, it gives the type (waterlogging, flooding, road or attraction closure, power cut, storm, landslide, heat), the place, the severity and what it affects.
   - Hinglish is included ("MI Road mein paani bhar gaya hai").
   - The twin uses these reports as live signals.

## The data

`build_dataset.py` writes everything in `data/`. The labels are consistent because every example is built from known parts:

- **Access snippets** are assembled from sentences whose facts are known. 30% contain no access facts at all, so the model learns to answer "unknown". About 15% are Hinglish.
- **Weather-impact answers** come from the reference rules in `travel_risk_rules.py`. The app's offline fallback implements the same rules, and a test checks them against 400 of these cases.
- **Posts** come from templates for each event type and severity, plus non-events: weather chat, adverts and forecasts.
- **The benchmark** (`data/benchmark.json`, 76 samples) uses other cities, places, phrasings and posts than the training files. The build checks that none of its prompts appears in them.

Every value in an answer is a string (`"stairs": "40"`, `"affects": "roads, transport"`). This is easier for a 3B model to produce reliably. It is also required: Nugen's synthetic-data step rejected our first upload because one generated answer was the bare number `150`.

## Running it

```bash
export NUGEN_API_KEY=...                  # never committed
python nugen/build_dataset.py             # data/
python nugen/export_parity.py             # the app's parity fixture
python nugen/pipeline.py upload           # documents + benchmark
python nugen/pipeline.py align            # start the alignment
python nugen/pipeline.py status
python nugen/pipeline.py deploy           # once trained
python nugen/pipeline.py evaluate         # aligned vs base on the benchmark (Nugen's evaluation)
python nugen/compare.py                   # our own field-by-field comparison: results/compare.md
python nugen/run_when_ready.py            # all of the above, waiting for Nugen's backend
```

Then put the aligned model id in `urbanpulse_flutter/config.json` as `NUGEN_MODEL_ID`, next to `NUGEN_API_KEY`, and build with `--dart-define-from-file=config.json`. Without these two keys, the app answers the same three jobs with the offline rules.

## Results

- `results/state.json` holds the ids: documents, benchmark, alignment, model and evaluation.
- `results/evaluation.json` holds Nugen's evaluation of the aligned model against the base model.
- `results/compare.md` compares both models field by field on the held-out golden set. It includes guesses (a yes/no without evidence) and quotes that are not in the snippet.

## How the app uses the answers

- Access facts count only if the quoted sentence really appears in the snippet, from a page a search actually returned. A "fact" with no real quote becomes "unknown".
- If an answer is not valid JSON of the right shape, the app uses the offline rules instead and labels the result that way.
- Answers are cached per prompt, so the twin can re-simulate freely.
- The twin's uncertainty bands come from 200 rule-based simulated weather draws. The single estimate for each place comes from the aligned model.
