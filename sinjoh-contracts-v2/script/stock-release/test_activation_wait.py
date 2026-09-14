"""Read-only activation waiting tests. No wallet, credentials, network or real sleeps."""
import ast
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock
from urllib.error import URLError


class ActivationWaitTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.ready = Path(self.directory.name) / 'ready.json'
        self.preparation = {'manifestHash': 'manifest'}
        self.pin = {'scriptBytecodeSha256': 'bytecode'}
        self.ready.write_text(json.dumps({**self.preparation, **self.pin}))
        self.common = {'operationId': 'operation', 'readyAt': 100, 'spentWei': '123'}
        self.cycle = 0
        self.behavior = lambda endpoint: 100
        def rpc(method, params, endpoint):
            self.assertIn(method, ['eth_chainId', 'eth_getBlockByNumber'])
            timestamp = self.behavior(endpoint)
            if method == 'eth_chainId': return '0x1237'
            return {'timestamp': hex(timestamp)}
        def sleep(seconds):
            self.assertEqual(seconds, 30)
            self.cycle += 1
            self.assertLess(self.cycle, 5, 'Wait did not recover')
        self.rpc = Mock(side_effect=rpc)
        self.status = Mock()
        self.sleep = Mock(side_effect=sleep)
        self.scope = dict(rpc=self.rpc, status=self.status, time=SimpleNamespace(sleep=self.sleep),
                          READY=self.ready, primary='primary', secondary='secondary', json=json)
        source = ast.parse(Path(__file__).with_name('sign_mainnet.py').read_text())
        function = next(n for n in source.body if isinstance(n, ast.FunctionDef) and n.name == 'wait_for_activation')
        exec(compile(ast.Module(body=[function], type_ignores=[]), '<wait>', 'exec'), self.scope)

    def run_wait(self):
        self.scope['wait_for_activation'](self.preparation, self.pin, 100, self.common)

    def test_dns_outage_retains_schedule_and_recovers_without_signing(self):
        def behavior(endpoint):
            if self.cycle == 0 and endpoint == 'primary': raise URLError('temporary DNS failure')
            return 100
        self.behavior = behavior
        self.run_wait()
        self.assertEqual(self.cycle, 1)
        self.assertEqual([c.args[0] for c in self.status.call_args_list],
                         ['waiting-for-rpc-recovery', 'queued-for-existing-timelock'])
        for call in self.status.call_args_list: self.assertEqual(call.kwargs, self.common)

    def test_secondary_must_also_reach_timelock_time(self):
        self.behavior = lambda endpoint: 99 if endpoint == 'secondary' and self.cycle == 0 else 100
        self.run_wait()
        self.assertEqual(self.cycle, 1)

    def test_missing_readiness_never_allows_activation(self):
        self.ready.unlink()
        def sleep(seconds):
            self.assertEqual(seconds, 30)
            raise InterruptedError('test ends while readiness is held')
        self.sleep.side_effect = sleep
        with self.assertRaises(InterruptedError): self.run_wait()

    def test_wrong_chain_is_terminal(self):
        self.rpc.side_effect = lambda method, params, endpoint: '0x1' if method == 'eth_chainId' else {'timestamp': '0x64'}
        with self.assertRaisesRegex(RuntimeError, 'Wrong chain'): self.run_wait()
        self.sleep.assert_not_called()


if __name__ == '__main__': unittest.main()
