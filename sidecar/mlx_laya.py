"""MLX inference port of Laya v0.3.7's choice head and ModernBERT encoder.

Apache-2.0 derivative; see THIRD_PARTY_NOTICES.md. No Torch or Transformers
imports, training, generated text, remote requests, or act_probability gating.
"""
import json
import math
import os
from pathlib import Path
# Preserve float32 reference behavior on M5; MLX otherwise permits reduced precision.
os.environ['MLX_ENABLE_TF32'] = '0'
import mlx.core as mx
import mlx.nn as nn
from tokenizers import Tokenizer


class MLXLaya:
    def __init__(self, directory, device='gpu'):
        directory = Path(directory)
        self.cfg = json.loads((directory / 'rl_agent_config.json').read_text())
        self.enc = json.loads((directory / 'encoder/config.json').read_text())
        if self.enc.get('model_type') != 'modernbert':
            raise ValueError('unsupported_encoder')
        mx.set_default_device(mx.cpu if device == 'cpu' else mx.gpu)
        mx.set_cache_limit(64 * 1024 * 1024)
        mx.set_memory_limit(2560 * 1024 * 1024)
        self.weights = {k: v.astype(mx.float32) for k, v in mx.load(str(directory / 'model.safetensors')).items()
                        if not k.startswith('act_head.')}
        mx.eval(self.weights)
        self.tokenizer = Tokenizer.from_file(str(directory / 'tokenizer/tokenizer.json'))
        self.tokenizer.no_padding()
        self.tokenizer.no_truncation()
        special = json.loads((directory / 'tokenizer/tokenizer_config.json').read_text())
        def token(name):
            value = special[name]
            return value['content'] if isinstance(value, dict) else value
        self.mask = token('mask_token')
        self.mask_id = self.tokenizer.token_to_id(self.mask)
        self.cls_id = self.tokenizer.token_to_id(token('cls_token'))
        self.sep_id = self.tokenizer.token_to_id(token('sep_token'))
        if None in [self.mask_id, self.cls_id, self.sep_id]:
            raise ValueError('invalid_tokenizer')

    def encode(self, text):
        return self.tokenizer.encode(text.replace(self.mask, ' '), add_special_tokens=False).ids

    def sequence(self, state, instructions, choices):
        # Adapted from Laya common.build_sequence; same ordering and truncation.
        maximum, head_max = self.cfg.get('max_len', 512), self.cfg.get('head_max_len', 192)
        head = self.encode('choice question: ' + instructions)
        options = [[self.mask_id] + self.encode(' ' + k + ': ' + v)[:48] for k, v in choices.items()]
        budget = head_max - sum(map(len, options))
        if budget < 16:
            per = max(4, (head_max - 16) // max(1, len(options)))
            options = [o[:per] for o in options]
            budget = head_max - sum(map(len, options))
        ids = [self.cls_id] + head[:max(8, budget)] + [self.sep_id]
        markers = []
        for option in options:
            markers.append(len(ids)); ids.extend(option)
        ids.append(self.sep_id)
        text = state if isinstance(state, str) else json.dumps(state, ensure_ascii=False)
        ids += self.encode(text)[:max(0, maximum - len(ids) - 1)] + [self.sep_id]
        if len(ids) > maximum or any(m >= maximum for m in markers):
            raise ValueError('too_many_options')
        return ids, markers

    def linear(self, x, key):
        y = x @ self.weights[key + '.weight'].T
        bias = self.weights.get(key + '.bias')
        return y if bias is None else y + bias

    def norm(self, x, key, epsilon=1e-5):
        return mx.fast.layer_norm(x, self.weights[key + '.weight'], self.weights.get(key + '.bias'), epsilon)

    def attention(self, qkv, heads, mask=None, theta=None):
        batch, length, _ = qkv.shape
        dim = qkv.shape[-1] // (3 * heads)
        q, k, v = [qkv.reshape(batch, length, 3, heads, dim)[:, :, i].transpose(0, 2, 1, 3) for i in range(3)]
        if theta is not None:
            q = mx.fast.rope(q, dims=dim, traditional=False, base=theta, scale=1.0, offset=0)
            k = mx.fast.rope(k, dims=dim, traditional=False, base=theta, scale=1.0, offset=0)
        y = mx.fast.scaled_dot_product_attention(q, k, v, scale=dim ** -0.5, mask=mask)
        return y.transpose(0, 2, 1, 3).reshape(batch, length, heads * dim)

    def logits(self, ids, markers):
        c = self.enc
        x = self.weights['encoder.embeddings.tok_embeddings.weight'][mx.array([ids])]
        x = self.norm(x, 'encoder.embeddings.norm', c.get('norm_eps', 1e-5))
        positions = mx.arange(len(ids))
        half_window = c.get('local_attention', 128) // 2
        local = mx.abs(positions[:, None] - positions[None, :]) <= half_window
        for i in range(c['num_hidden_layers']):
            key = f'encoder.layers.{i}'
            kind = c.get('layer_types', [])[i] if c.get('layer_types') else ('full_attention' if i % c.get('global_attn_every_n_layers', 3) == 0 else 'sliding_attention')
            rope = c.get('rope_parameters', {}).get(kind, {})
            theta = rope.get('rope_theta', c.get('global_rope_theta', 160000) if kind == 'full_attention' else c.get('local_rope_theta', 10000))
            h = x if i == 0 else self.norm(x, key + '.attn_norm', c.get('norm_eps', 1e-5))
            h = self.attention(self.linear(h, key + '.attn.Wqkv'), c['num_attention_heads'], None if kind == 'full_attention' else local, theta)
            x = x + self.linear(h, key + '.attn.Wo')
            a, gate = mx.split(self.linear(self.norm(x, key + '.mlp_norm', c.get('norm_eps', 1e-5)), key + '.mlp.Wi'), 2, axis=-1)
            x = x + self.linear(nn.gelu(a) * gate, key + '.mlp.Wo')
        x = self.norm(x, 'encoder.final_norm', c.get('norm_eps', 1e-5)) + self.weights['type_emb.weight'][0]
        for i in range(self.cfg.get('head_layers', 2)):
            key = f'head.layers.{i}'
            h = self.norm(x, key + '.norm1')
            qkv = h @ self.weights[key + '.self_attn.in_proj_weight'].T + self.weights[key + '.self_attn.in_proj_bias']
            x = x + self.linear(self.attention(qkv, max(1, c['hidden_size'] // 64)), key + '.self_attn.out_proj')
            h = nn.relu(self.linear(self.norm(x, key + '.norm2'), key + '.linear1'))
            x = x + self.linear(h, key + '.linear2')
        selected = x[:, mx.array(markers), :]
        return self.linear(nn.gelu(self.linear(self.norm(selected, 'scorer.0'), 'scorer.1')), 'scorer.3')[0, :, 0]

    def predict(self, state, instructions, choices):
        ids, markers = self.sequence(state, instructions, choices)
        logits = self.logits(ids, markers)
        n = len(choices)
        bucket = '2' if n <= 2 else '3-5' if n <= 5 else '6-10' if n <= 10 else '11+'
        temperature = self.cfg.get('temperature_by_options', {}).get('choice:' + bucket, self.cfg.get('temperature', [1])[0])
        temperature = float(temperature)
        temperature = max(.5, min(5., temperature)) if math.isfinite(temperature) else 1.
        p = mx.softmax(logits / temperature)
        mx.eval(p)
        probabilities = p.tolist()
        confidence = max(0., min(1., 1 + sum(v * math.log(max(v, 1e-12)) for v in probabilities) / math.log(n)))
        index = max(range(n), key=probabilities.__getitem__)
        return {'choice': list(choices)[index], 'probabilities': dict(zip(choices, probabilities)), 'confidence': confidence}
