"""Bounded JSON-lines protocol shared by the process and pure unit tests."""
MAX_FRAME = 32768
MAX_CHOICES = 19
ALLOWED = {'open_whatsapp', 'open_safari', 'open_notes', 'open_finder', 'unsupported'}

def validate(request):
    if not isinstance(request, dict) or not isinstance(request.get('id'), str):
        raise ValueError('invalid_request')
    if request.get('op') in {'status', 'unload', 'prepare'}:
        return request
    if request.get('op') != 'choose':
        raise ValueError('unsupported_operation')
    state, choices = request.get('state'), request.get('choices')
    if not isinstance(state, str) or len(state) > 1024:
        raise ValueError('invalid_state')
    if not isinstance(choices, dict) or not 2 <= len(choices) <= MAX_CHOICES:
        raise ValueError('invalid_choices')
    if not set(choices).issubset(ALLOWED) or any(not isinstance(v, str) or len(v) > 120 for v in choices.values()):
        raise ValueError('invalid_choice')
    return request

def gate(label, confidence, margin, calibration):
    # Never derive safety from action.act_probability. Unvalidated models abstain.
    return bool(calibration.get('validated') and label in ALLOWED and label != 'unsupported'
                and confidence >= calibration.get('threshold', 1.01)
                and margin >= calibration.get('margin', 1.01))
