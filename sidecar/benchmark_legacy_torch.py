#!/usr/bin/env python3
"""Sequential, isolated CPU/MPS benchmark using only committed synthetic commands."""
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

def quantile(values, percentile):
    return sorted(values)[min(len(values)-1, int((len(values)-1)*percentile))]

def worker(model, device, threads):
    os.environ.update(USE_TF='0', HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1', TOKENIZERS_PARALLELISM='false', HF_HUB_DISABLE_TELEMETRY='1')
    sys.path.insert(0, str(ROOT / 'vendor'))
    start = time.perf_counter()
    import torch
    torch.set_num_threads(threads)
    torch.set_num_interop_threads(1)
    from laya import Agent
    agent = Agent(str(CACHE / model), device=device)
    load_ms = (time.perf_counter() - start)*1000
    data = json.loads((ROOT / 'fixtures/decisions.json').read_text())
    times, records = [], []
    cpu = time.process_time()
    for item in data:
        before = time.perf_counter()
        answer = agent.predict({'command': item['text']}, {'intent': {'type': 'choice', 'instructions': INSTRUCTIONS, 'criteria': CHOICES}})['answers']['intent']
        elapsed = (time.perf_counter() - before)*1000
        times.append(elapsed)
        probs = sorted(answer['probabilities'].values(), reverse=True)
        records.append({'split': item['split'], 'correct': answer['choice'] == item['label'], 'expected': item['label'], 'label': answer['choice'], 'confidence': answer['confidence'], 'margin': probs[0] - probs[1]})
    rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / (1024*1024 if sys.platform == 'darwin' else 1024)
    result = {'model': model, 'backend': device, 'threads': threads, 'load_ms': load_ms,
              'first_inference_ms': times[0], 'warm_p50_ms': statistics.median(times[1:]),
              'warm_p95_ms': quantile(times[1:], .95), 'peak_rss_mb': rss,
              'cpu_seconds': time.process_time()-cpu, 'accuracy': sum(r['correct'] for r in records)/len(records),
              'sample_count': len(records), 'records': records}
    print(json.dumps(result), flush=True)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--worker', action='store_true')
    parser.add_argument('--model', default='english')
    parser.add_argument('--backend', default='cpu')
    parser.add_argument('--threads', type=int, default=2)
    args = parser.parse_args()
    if args.worker:
        worker(args.model, args.backend, args.threads)
        return
    output = ROOT.parent / 'benchmark-results'; output.mkdir(exist_ok=True)
    results = []
    for model in ['english', 'multilingual']:
        for backend, threads in [('cpu', 1), ('cpu', 2), ('cpu', 4), ('mps', 2)]:
            try:
                run = subprocess.run([sys.executable, __file__, '--worker', '--model', model, '--backend', backend, '--threads', str(threads)], capture_output=True, text=True, timeout=240)
                if run.returncode:
                    result = {'model': model, 'backend': backend, 'threads': threads, 'error': run.stderr[-3000:]}
                else:
                    result = json.loads(run.stdout.splitlines()[-1])
            except subprocess.TimeoutExpired:
                result = {'model': model, 'backend': backend, 'threads': threads, 'error': 'timeout after 240 seconds'}
            results.append(result)
            (output / 'laya.json').write_text(json.dumps(results, indent=2)+'\n')
            print(json.dumps({k:v for k,v in result.items() if k != 'records'}), flush=True)
    valid = [r for r in results if 'accuracy' in r]
    if not valid:
        return
    # Accuracy first, then measured p95, within the memory budget if available.
    fitting = [r for r in valid if r['peak_rss_mb'] < 2560] or valid
    best_accuracy = max(r['accuracy'] for r in fitting)
    selected = min((r for r in fitting if r['accuracy'] >= best_accuracy), key=lambda r:r['warm_p95_ms'])
    # Calibrate on a separate split, then audit the held-out split. Conservative abstention.
    calibration = {'validated': False, 'threshold': 1.01, 'margin': 1.01}
    for threshold in [.7, .8, .9, .95, .98]:
        accepted = [r for r in selected['records'] if r['split']=='calibration' and r['confidence']>=threshold and r['margin']>=.25 and r['label']!='unsupported']
        test = [r for r in selected['records'] if r['split']=='test' and r['confidence']>=threshold and r['margin']>=.25 and r['label']!='unsupported']
        if len(accepted)>=10 and len(test)>=10 and all(r['correct'] for r in accepted+test):
            calibration = {'validated': True, 'threshold': threshold, 'margin': .25, 'scope': 'synthetic app-launch smoke dataset only', 'test_accepted': len(test)}
            break
    config = {'python': sys.executable, 'model': str(CACHE / selected['model']), 'model_name': selected['model'], 'backend': selected['backend'], 'threads': selected['threads'], 'calibration': calibration}
    destination = CACHE.parent / 'runtime.json'
    # Historical reference only: never replace the installed MLX configuration.
    print('Selected: '+ selected['model']+' / '+selected['backend']+' / '+str(selected['threads'])+' threads; gate='+str(calibration['validated']), flush=True)

if __name__ == '__main__': main()
