#!/usr/bin/env python3
"""One offline model, one inference at a time, inherited private stdio pipes only."""
import json
import os
from pathlib import Path
import sys
import time

# App bundle resources are sealed by code signing and must remain read-only.
sys.dont_write_bytecode = True
os.environ.update(USE_TF='0', HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1',
                  HF_HUB_DISABLE_TELEMETRY='1', TOKENIZERS_PARALLELISM='false')
sys.path.insert(0, str(Path(__file__).parent / 'vendor'))
from protocol import MAX_FRAME, validate, gate

class DecisionService:
    def __init__(self, config):
        self.config = config
        self.agent = None
        self.last_used = 0

    def load(self):
        if self.agent is not None:
            return
        from mlx_laya import MLXLaya
        model = Path(self.config['model']).resolve()
        if not model.is_dir():
            raise ValueError('model_unavailable')
        self.agent = MLXLaya(model, device=self.config.get('backend', 'gpu'))

    def respond(self, request):
        request = validate(request)
        if request['op'] == 'unload':
            self.agent = None
            import mlx.core as mx
            mx.clear_cache()
            return {'id': request['id'], 'status': 'unloaded'}
        if request['op'] == 'prepare':
            self.load()
            return {'id': request['id'], 'status': 'ready', 'summary': self.config.get('model_name', 'Laya') + ' / MLX ' + self.config.get('backend', 'gpu') + (' / validated gate' if self.config.get('calibration', {}).get('validated') else ' / conservative abstention')}
        if request['op'] == 'status':
            return {'id': request['id'], 'status': 'ready' if self.agent else 'cold'}
        self.load()
        begin = time.perf_counter()
        answer = self.agent.predict({'command': request['state']},
            'Select the explicitly requested supported application action. Otherwise choose unsupported.', request['choices'])
        probabilities = sorted(answer['probabilities'].values(), reverse=True)
        label = answer['choice']
        confidence = float(answer['confidence'])
        margin = probabilities[0] - probabilities[1]
        accepted = gate(label, confidence, margin, self.config.get('calibration', {}))
        self.last_used = time.monotonic()
        return {'id': request['id'], 'status': 'choice' if accepted else 'abstain',
                'label': label if accepted else 'unsupported', 'confidence': confidence,
                'milliseconds': (time.perf_counter() - begin) * 1000}

def main():
    config = json.loads(Path(sys.argv[1]).read_text())
    service = DecisionService(config)
    for line in iter(lambda: sys.stdin.buffer.readline(MAX_FRAME + 1), b''):
        if len(line) > MAX_FRAME or not line.endswith(b'\n'):
            break
        request_id = ''
        try:
            request = json.loads(line)
            request_id = request.get('id', '') if isinstance(request, dict) else ''
            response = service.respond(request)
        except Exception:
            # Do not emit exception strings; third-party errors may embed input.
            response = {'id': request_id, 'status': 'unavailable'}
        sys.stdout.write(json.dumps(response, allow_nan=False) + '\n')
        sys.stdout.flush()

if __name__ == '__main__':
    main()
