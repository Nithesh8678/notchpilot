#!/usr/bin/env python3
"""Sequential MLX CPU/GPU benchmark and synthetic reference parity check."""
import argparse
import json
import os
from pathlib import Path
import resource
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent
CACHE = Path(os.environ.get('NOTCHPILOT_MODEL_DIR', Path.home() / 'Library/Application Support/NotchPilot/models'))
CHOICES = {'open_whatsapp': 'Launch or focus WhatsApp', 'open_safari': 'Launch or focus Safari web browser', 'open_notes': 'Launch or focus Apple Notes', 'open_finder': 'Launch or focus Finder', 'unsupported': 'Any other action or no explicit request to open an application'}
INSTRUCTIONS = 'Select the explicitly requested supported application action. Otherwise choose unsupported.'

def worker(model, backend):
    begin = time.perf_counter()
    from mlx_laya import MLXLaya
    import mlx.core as mx
    agent = MLXLaya(CACHE / model, device=backend)
    load_ms = (time.perf_counter() - begin) * 1000
    data = json.loads((ROOT / 'fixtures/decisions.json').read_text())
    reference = json.loads((ROOT / 'fixtures/mlx_reference.json').read_text()) if model == 'multilingual' else None
    times, correct, same, delta = [], 0, 0, 0.
    cpu = time.process_time()
    for index, item in enumerate(data):
        state = {'command': item['text']}
        if reference:
            ids, markers = agent.sequence(state, INSTRUCTIONS, CHOICES)
            assert ids == reference[index]['ids'] and markers == reference[index]['markers'], 'Token sequence mismatch'
        start = time.perf_counter()
        answer = agent.predict(state, INSTRUCTIONS, CHOICES)
        times.append((time.perf_counter() - start) * 1000)
        correct += answer['choice'] == item['label']
        if reference:
            same += answer['choice'] == reference[index]['answer']['choice']
            delta = max(delta, max(abs(answer['probabilities'][k] - reference[index]['answer']['probabilities'][k]) for k in CHOICES))
    result = {'runtime': 'mlx', 'model': model, 'backend': backend, 'precision': 'float32; MLX_ENABLE_TF32=0', 'load_ms': load_ms, 'first_ms': times[0], 'warm_p50_ms': statistics.median(times[1:]), 'warm_p95_ms': sorted(times[1:])[int(.95 * (len(times)-2))], 'sample_count':len(data), 'accuracy':correct/len(data), 'peak_rss_mb':resource.getrusage(resource.RUSAGE_SELF).ru_maxrss/1048576, 'metal_peak_mb':mx.get_peak_memory()/1048576, 'cpu_seconds':time.process_time()-cpu, 'torch_imported':'torch' in sys.modules}
    if reference:
        result.update(reference_choices_matching=same, maximum_probability_difference=delta, parity_passed=same == len(data) and delta < .0002)
    print(json.dumps(result), flush=True)
    if reference and not result['parity_passed']:
        raise SystemExit(1)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--worker', action='store_true')
    parser.add_argument('--model', default='multilingual', choices=['multilingual', 'english'])
    parser.add_argument('--backend', default='gpu', choices=['cpu', 'gpu'])
    args=parser.parse_args()
    if args.worker: return worker(args.model,args.backend)
    output=ROOT.parent/'benchmark-results';output.mkdir(exist_ok=True)
    results=[]
    for model in ['multilingual','english']:
        for backend in ['cpu','gpu']:
            run=subprocess.run([sys.executable,__file__,'--worker','--model',model,'--backend',backend],text=True,capture_output=True,timeout=240)
            if run.stdout.strip():
                try: result=json.loads(run.stdout.splitlines()[-1])
                except ValueError: result={'model':model,'backend':backend,'error':'invalid benchmark output'}
            else: result={'model':model,'backend':backend,'error':'worker failed'}
            result['passed']=run.returncode == 0
            results.append(result)
            print(json.dumps(result),flush=True)
            (output/'mlx.json').write_text(json.dumps(results,indent=2)+'\n')
    if not all(r['passed'] for r in results): raise SystemExit(1)

if __name__=='__main__': main()
