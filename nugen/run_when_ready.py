"""Runs the alignment once Nugen's training backend is reachable, then deploys,
evaluates and compares. Used when the backend was returning 502s: it probes
cheaply every 10 minutes and starts training only when inference answers.
At most 3 alignment attempts, so a broken backend cannot burn credits.

    NUGEN_API_KEY=... python nugen/run_when_ready.py
"""

import json
import time

import requests

import pipeline

MAX_ATTEMPTS = 3
PROBE_EVERY = 600
GIVE_UP_AFTER = 9 * 3600


def log(*a):
    print(f"[{time.strftime('%H:%M:%S')}]", *a, flush=True)


def backend_up(model):
    try:
        r = requests.post(
            "https://api.nugen.in/api/v3/inference/chat/completions",
            headers={"Authorization": f"Bearer {pipeline.key()}", "Content-Type": "application/json"},
            json={"model": model, "messages": [{"role": "user", "content": "Reply OK"}], "max_tokens": 5, "stream": False},
            timeout=60,
        )
        return r.status_code == 200 and "choices" in r.text, f"{r.status_code} {r.text[:120]}"
    except requests.RequestException as e:
        return False, str(e)


def infra_failure(detail):
    err = (detail.get("error") or "") + " ".join(detail.get("stage_failures") or [])
    return any(w in err for w in ("502", "503", "504", "Bad Gateway", "job creation failed", "timed out"))


def main():
    state = pipeline.load()
    started = time.time()
    attempts = sum(1 for f in state.get("failed_alignments", []) if "502" in f.get("error", ""))
    while True:
        if time.time() - started > GIVE_UP_AFTER:
            log("giving up: backend not ready in time")
            return
        if not state.get("alignment_id"):
            ok, why = backend_up(state["base_model_id"])
            if not ok:
                log("backend not ready:", why)
                time.sleep(PROBE_EVERY)
                continue
            if attempts >= MAX_ATTEMPTS:
                log("attempt limit reached")
                return
            attempts += 1
            log(f"backend up; starting alignment attempt {attempts}")
            pipeline.align(state)
        s = pipeline.alignment_status(state)
        st = str(s.get("status", "")).upper()
        if st == "FAILED":
            detail = pipeline.call("GET", f"/alignment-projects/{state['alignment_id']}", headers=pipeline.headers())
            log("alignment failed:", detail.get("error"), detail.get("stage_failures"))
            state.setdefault("failed_alignments", []).append({"alignment_id": state.pop("alignment_id"), "error": detail.get("error")})
            pipeline.save(state)
            if not infra_failure(detail):
                log("not an infrastructure failure; stopping for a fix")
                return
            time.sleep(PROBE_EVERY)
            continue
        if st in ("QUEUED", "PROCESSING"):
            log("alignment:", st, json.dumps({k: s.get(k) for k in ("progress", "eta_seconds", "queue_position")}))
            time.sleep(120)
            continue
        break

    pipeline.wait_alignment(state)
    pipeline.deploy(state)
    try:
        pipeline.evaluate(state)
    except SystemExit as e:
        log("comparison evaluation failed:", e)
    import compare
    compare.main()
    log("done")


if __name__ == "__main__":
    main()
