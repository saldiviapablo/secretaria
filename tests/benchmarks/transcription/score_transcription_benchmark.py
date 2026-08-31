#!/usr/bin/env python3
"""Aggregate sanitized benchmark metrics. Does not read raw audio or secrets."""
import json,sys
from pathlib import Path

WEIGHTS={
 "names":0.20,
 "dates_times_numbers":0.20,
 "literal_accuracy":0.20,
 "timestamps":0.10,
 "diarization":0.10,
 "noise_accent":0.10,
 "latency":0.05,
 "cost":0.05,
}

def main():
    if len(sys.argv)!=2:
        print("usage: score_transcription_benchmark.py <sanitized_metrics.json>")
        return 2
    data=json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    if not data.get("ground_truth_human"): raise SystemExit("ground_truth_human must be true")
    out=[]
    for c in data["candidates"]:
        m=c["normalized_scores_0_to_1"]
        missing=set(WEIGHTS)-set(m)
        if missing: raise SystemExit(f"missing metrics: {sorted(missing)}")
        score=sum(float(m[k])*w for k,w in WEIGHTS.items())
        out.append((score,int(c.get("critical_errors",999999)),float(c.get("cost_usd",1e99)),float(c.get("latency_ms_p50",1e99)),c["provider"],c["model"]))
    out.sort(key=lambda x:(-x[0],x[1],x[2],x[3]))
    for x in out:
        print(f"{x[4]}:{x[5]} weighted={x[0]:.6f} critical_errors={x[1]} cost={x[2]} latency_p50_ms={x[3]}")
    if len(out)>=2 and abs(out[0][0]-out[1][0]) < 0.01:
        print("NEAR_TIE: apply tie-break = fewer critical errors, then cost, then latency.")
    return 0
if __name__=="__main__": raise SystemExit(main())
