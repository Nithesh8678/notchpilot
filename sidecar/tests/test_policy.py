"""Privacy and wire protocol tests are expanded alongside the sidecar."""
import unittest
from pathlib import Path

class AttributionTests(unittest.TestCase):
    def test_vendor_is_independent(self):
        root = Path(__file__).resolve().parents[2]
        self.assertFalse((root / 'sidecar/vendor/laya/.git').exists())
        self.assertIn('010bacef009c855ccba814b51f7c8e1d38ab5e3f', (root / 'THIRD_PARTY_NOTICES.md').read_text())

import json
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from protocol import validate, gate, MAX_FRAME

class ProtocolTests(unittest.TestCase):
    def test_bounded_choices(self):
        with self.assertRaises(ValueError):
            validate({'id':'x','op':'choose','state':'test','choices':{str(i):'label' for i in range(20)}})
    def test_rejects_arbitrary_actions(self):
        with self.assertRaises(ValueError):
            validate({'id':'x','op':'choose','state':'test','choices':{'send':'send message','delete':'delete file'}})
    def test_unvalidated_abstains(self):
        self.assertFalse(gate('open_safari', 1, 1, {}))
    def test_act_probability_not_a_gate(self):
        self.assertFalse(gate('open_safari', .2, .1, {'validated':True,'threshold':.9,'margin':.3,'act_probability':1}))
    def test_supported_status(self):
        self.assertEqual(validate({'id':'x','op':'status'})['op'], 'status')
    def test_no_model_import_for_validation(self):
        self.assertNotIn('torch', sys.modules)
    def test_rejects_oversized_state(self):
        with self.assertRaises(ValueError):
            validate({'id':'x','op':'choose','state':'x'*1025,'choices':{'open_safari':'Safari','unsupported':'Other'}})
