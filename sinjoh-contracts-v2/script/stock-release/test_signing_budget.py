"""Signing budget tests use mocked commands; they never access a wallet or RPC."""
import ast
from pathlib import Path
import unittest
from unittest.mock import Mock

class SigningBudgetTests(unittest.TestCase):
    def setUp(self):
        source = ast.parse(Path(__file__).with_name('sign_mainnet.py').read_text())
        function = next(node for node in source.body if isinstance(node, ast.FunctionDef) and node.name == 'send')
        self.command = Mock(return_value='{"transactionHash":"0x123"}')
        self.rpc = Mock(side_effect=lambda method, params: '0x5208' if method == 'eth_estimateGas' else hex(10**18))
        self.scope = dict(rpc=self.rpc, fee=lambda: 2, command=self.command, verify_receipt=lambda hash_: hash_, DEPLOYER='deployer', CAST='cast', json=__import__('json'))
        exec(compile(ast.Module(body=[function], type_ignores=[]), '<send>', 'exec'), self.scope)

    def test_worker_value_is_in_estimate_and_signed_command(self):
        self.assertEqual(self.scope['send']('0x', 'worker', 'local-password', 100000, 1234), '0x123')
        self.assertEqual(self.rpc.call_args_list[0].args[1][0]['value'], hex(1234))
        args = self.command.call_args.args[0]
        self.assertEqual(args[args.index('--value') + 1], '1234')
        self.assertNotIn('local-password', args)

    def test_value_plus_fee_must_fit_budget(self):
        with self.assertRaises(RuntimeError): self.scope['send']('0x', 'worker', 'local-password', 52500, 1)
        self.command.assert_not_called()

    def test_governance_sends_remain_zero_value(self):
        self.scope['send']('0xabc', 'governance', 'local-password', 100000)
        self.assertEqual(self.rpc.call_args_list[0].args[1][0]['value'], '0x0')

if __name__ == '__main__': unittest.main()
