"""The Nugen alignment pipeline for UrbanPulse Travel-Risk.

    base model (llama-v3p2-3b-reasoning)
      -> upload the domain documents (handbook + worked examples)
      -> upload the held-out benchmark
      -> align the base model on the documents
      -> deploy the aligned model
      -> evaluate aligned vs base on the benchmark

Every step records its ids in nugen/results/state.json, so the pipeline can be
resumed and the app can be pointed at the aligned model. The API key is read
from the NUGEN_API_KEY environment variable and never written anywhere.

    python nugen/pipeline.py upload      # documents + benchmark
    python nugen/pipeline.py align       # start the alignment run
    python nugen/pipeline.py status      # alignment / deployment / evaluation status
    python nugen/pipeline.py deploy      # deploy the aligned model once trained
    python nugen/pipeline.py evaluate    # aligned vs base on the benchmark
    python nugen/pipeline.py results     # fetch evaluation results
    python nugen/pipeline.py all         # everything, waiting between steps
"""

import json
import os
import sys
import time

import requests

API = "https://api.nugen.in/api/v3"
BASE_MODEL = "llama-v3p2-3b-reasoning"
HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
STATE = os.path.join(HERE, "results", "state.json")
DOCS = ["handbook.txt", "train_access.txt", "train_impact.txt", "train_events.txt"]


def key():
    k = os.environ.get("NUGEN_API_KEY")
    if not k:
        sys.exit("Set NUGEN_API_KEY first.")
    return k


def headers(json_body=True):
    h = {"Authorization": f"Bearer {key()}", "accept": "application/json"}
    if json_body:
        h["Content-Type"] = "application/json"
    return h


def load():
    if os.path.exists(STATE):
        with open(STATE, encoding="utf-8") as f:
            return json.load(f)
    return {"base_model_id": BASE_MODEL}


def save(state):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w", encoding="utf-8", newline="\n") as f:
        json.dump(state, f, indent=2)


def call(method, path, **kw):
    for attempt in range(4):
        r = requests.request(method, API + path, timeout=120, **kw)
        if r.status_code in (502, 503, 504) and attempt < 3:
            time.sleep(10 * (attempt + 1))
            continue
        if r.status_code >= 400:
            raise SystemExit(f"{method} {path} -> {r.status_code}: {r.text[:800]}")
        return r.json() if r.text else {}


def wait(what, fetch, done, failed=("FAILED", "ERROR", "STOPPED"), every=30, limit=6 * 3600):
    start = time.time()
    last = None
    while True:
        s = fetch()
        status = str(s.get("status") or s.get("state") or "").upper()
        if status != last:
            print(f"[{time.strftime('%H:%M:%S')}] {what}: {status} {json.dumps(s)[:300]}", flush=True)
            last = status
        if status in done:
            return s
        if status in failed:
            raise SystemExit(f"{what} failed: {json.dumps(s)[:1500]}")
        if time.time() - start > limit:
            raise SystemExit(f"{what}: still {status} after {limit // 3600} h")
        time.sleep(every)


# --------------------------------------------------------------------------


def upload(state):
    if not state.get("document_ids"):
        files = [("files", (name, open(os.path.join(DATA, name), "rb"), "text/plain")) for name in DOCS]
        data = [("categories", "urbanpulse-travel-risk")] * len(DOCS) + [("names", n.replace(".txt", "")) for n in DOCS]
        r = call("POST", "/documents/create", headers=headers(False), files=files, data=data)
        state["document_ids"] = r.get("document_ids") or r.get("documents")
        save(state)
        print("documents:", state["document_ids"])
    for d in state["document_ids"]:
        wait(f"document {d}", lambda d=d: call("GET", f"/documents/{d}/status", headers=headers()), {"READY", "COMPLETED", "PROCESSED"}, every=10)
    if not state.get("benchmark_id"):
        with open(os.path.join(DATA, "benchmark.json"), "rb") as f:
            r = call("POST", "/benchmarks/upload", headers=headers(False),
                     files={"file": ("benchmark.json", f, "application/json")},
                     data={"benchmark_name": "UrbanPulse Travel-Risk held-out", "document_id": state["document_ids"][0],
                           "description": "Held-out access_claims, weather_impact and weather_event samples (other cities, places and phrasings than the training documents)."})
        state["benchmark_id"] = r["benchmark_id"]
        state["benchmark_samples"] = r.get("n_samples")
        save(state)
        print("benchmark:", state["benchmark_id"], r.get("n_samples"), "samples")


def align(state):
    if state.get("alignment_id"):
        print("alignment already started:", state["alignment_id"])
        return
    r = call("POST", "/alignment-projects/create", headers=headers(), json={
        "alignment_name": "UrbanPulse Travel-Risk",
        "base_model_id": state["base_model_id"],
        "document_ids": state["document_ids"],
        "benchmark_id": state["benchmark_id"],
        "description": "Aligns Llama 3.2 3B to Indian travel risk: wheelchair-access facts from reviews (never guessed), "
                       "weather impact on places using IMD rainfall and heat classes, and weather disruptions from social posts. "
                       "Used by the UrbanPulse app (Khoji review checks and the weather digital twin).",
    })
    state["alignment_id"] = r["alignment_id"]
    save(state)
    print("alignment:", r)


def alignment_status(state):
    return call("GET", f"/alignment-projects/{state['alignment_id']}/status", headers=headers())


def find_model(state):
    """The aligned model id, from the project detail or the aligned-model list."""
    if state.get("model_id"):
        return state["model_id"]
    detail = call("GET", f"/alignment-projects/{state['alignment_id']}", headers=headers())
    state["alignment_detail"] = detail
    model = detail.get("model")
    mid = detail.get("model_id") or detail.get("aligned_model_id") or (model.get("model_id") if isinstance(model, dict) else None)
    if not mid:
        models = call("GET", "/models/aligned", headers=headers())
        for m in models.get("models", models if isinstance(models, list) else []):
            if m.get("alignment_id") == state["alignment_id"] or m.get("alignment_project_id") == state["alignment_id"]:
                mid = m.get("model_id")
    if mid:
        state["model_id"] = mid
    save(state)
    return mid


def wait_alignment(state):
    """Training, then Nugen's automatic evaluation on the attached benchmark:
    QUEUED -> PROCESSING -> READY -> DEPLOYING -> EVALUATING -> UNDEPLOYED -> EVALUATED.
    A run that stays READY (no automatic evaluation) counts as done after 15 min."""
    ready_since = None

    def fetch():
        nonlocal ready_since
        s = alignment_status(state)
        st = str(s.get("status", "")).upper()
        if st == "READY":
            ready_since = ready_since or time.time()
            if time.time() - ready_since > 900:
                s = dict(s, status="READY_STABLE")
        else:
            ready_since = None
        return s

    s = wait("alignment", fetch, {"EVALUATED", "READY_STABLE"}, every=60, limit=10 * 3600)
    detail = call("GET", f"/alignment-projects/{state['alignment_id']}", headers=headers())
    with open(os.path.join(HERE, "results", "alignment_detail.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(detail, f, indent=2)
    state["alignment_detail"] = detail
    save(state)
    return s


def deploy(state):
    mid = find_model(state)
    if not mid:
        raise SystemExit("No aligned model yet; check `status`.")
    for attempt in range(3):
        st = call("GET", f"/models/{mid}/deployment/status", headers=headers())
        status = str(st.get("status", "")).upper()
        if status == "DEPLOYED":
            break
        if status in ("UNDEPLOYED", ""):
            try:
                call("POST", f"/models/{mid}/deployment", headers=headers())
            except SystemExit as e:
                if "409" in str(e):
                    call("POST", f"/models/{mid}/deployment?early=true", headers=headers())
                elif "already" not in str(e).lower():
                    raise
        seen_deploying = False
        start = time.time()
        while time.time() - start < 45 * 60:
            st = call("GET", f"/models/{mid}/deployment/status", headers=headers())
            status = str(st.get("status", "")).upper()
            print(f"[{time.strftime('%H:%M:%S')}] deployment: {status} {st.get('error') or ''}", flush=True)
            if status == "DEPLOYED":
                break
            if status == "DEPLOYING":
                seen_deploying = True
            if status == "UNDEPLOYED" and (seen_deploying or st.get("error")):
                print("deployment attempt failed:", st.get("error"), flush=True)
                break
            time.sleep(30)
        if status == "DEPLOYED":
            break
    if status != "DEPLOYED":
        raise SystemExit(f"deployment did not complete: {status}")
    state["deployed"] = True
    save(state)


def evaluate(state):
    mid = find_model(state)
    if not state.get("evaluation_id"):
        r = call("POST", "/evaluations/create", headers=headers(), json={
            "model_id": mid,
            "baseline_model_id": state["base_model_id"],
            "benchmark_id": state["benchmark_id"],
            "evaluation_name": "Travel-Risk aligned vs base",
        })
        state["evaluation_id"] = r["evaluation_id"]
        save(state)
        print("evaluation:", r)
    wait("evaluation", lambda: call("GET", f"/evaluations/{state['evaluation_id']}/status", headers=headers()), {"COMPLETED", "DONE", "SUCCEEDED", "READY", "EVALUATED"}, every=30, limit=4 * 3600)
    results(state)


def results(state):
    r = call("GET", f"/evaluations/{state['evaluation_id']}/results", headers=headers())
    with open(os.path.join(HERE, "results", "evaluation.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(r, f, indent=2)
    print(json.dumps(r, indent=2)[:3000])


def status(state):
    out = {}
    if state.get("alignment_id"):
        out["alignment"] = alignment_status(state)
    mid = state.get("model_id")
    if mid:
        out["deployment"] = call("GET", f"/models/{mid}/deployment/status", headers=headers())
    if state.get("evaluation_id"):
        out["evaluation"] = call("GET", f"/evaluations/{state['evaluation_id']}/status", headers=headers())
    print(json.dumps(out, indent=2))
    return out


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    state = load()
    if cmd == "upload":
        upload(state)
    elif cmd == "align":
        align(state)
    elif cmd == "status":
        status(state)
    elif cmd == "wait":
        wait_alignment(state)
    elif cmd == "deploy":
        deploy(state)
    elif cmd == "evaluate":
        evaluate(state)
    elif cmd == "results":
        results(state)
    elif cmd == "all":
        upload(state)
        align(state)
        wait_alignment(state)
        deploy(state)
        try:
            evaluate(state)
        except SystemExit as e:
            print("comparison evaluation failed:", e, flush=True)
        import compare
        compare.main()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
