"""Signing budget tests use mocked commands; they never access a wallet or RPC."""
import ast
import json
import os
from pathlib import Path
import re
import tempfile
import time
import unittest
from unittest.mock import Mock

class SigningBudgetTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / 'deployments').mkdir()
        source = ast.parse(Path(__file__).with_name('sign_mainnet.py').read_text())
        function = next(node for node in source.body if isinstance(node, ast.FunctionDef) and node.name == 'send')
        self.hash = '0x' + 'ab' * 32
        self.raw = '0x' + 'cd' * 200
        self.command = Mock(side_effect=lambda args, *rest: self.raw if args[1]=='mktx' else self.hash)
        def rpc(method, params):
            if method == 'eth_estimateGas': return '0x5208'
            if method == 'eth_getBalance': return hex(10**18)
            if method == 'eth_getTransactionCount': return '0x3'
            if method == 'eth_sendRawTransaction':
                record = json.loads((self.root/'deployments/stock-signed-submissions.jsonl').read_text())
                self.assertEqual(record['signedTransaction'], params[0])
                self.assertEqual(record['transactionHash'], self.hash)
                return self.hash
            if method == 'eth_getTransactionReceipt': return {'status':'0x1'}
            raise AssertionError(method)
        self.rpc = Mock(side_effect=rpc)
        self.scope = dict(rpc=self.rpc, fee=lambda: 2, command=self.command, verify_receipt=lambda hash_: hash_, DEPLOYER='deployer', CAST='cast', ROOT=self.root, json=json, os=os, re=re, time=time)
        exec(compile(ast.Module(body=[function], type_ignores=[]), '<send>', 'exec'), self.scope)

    def test_worker_value_is_journaled_before_submission(self):
        self.assertEqual(self.scope['send']('0x', 'worker', 'local-password', 100000, 1234), self.hash)
        self.assertEqual(self.rpc.call_args_list[0].args[1][0]['value'], hex(1234))
        args = self.command.call_args_list[0].args[0]
        self.assertEqual(args[args.index('--value') + 1], '1234')
        self.assertNotIn('local-password', args)
        self.assertNotIn('local-password',(self.root/'deployments/stock-signed-submissions.jsonl').read_text())

    def test_value_plus_fee_must_fit_budget(self):
        with self.assertRaises(RuntimeError): self.scope['send']('0x', 'worker', 'local-password', 52500, 1)
        self.command.assert_not_called()

    def test_governance_sends_remain_zero_value(self):
        self.scope['send']('0xabc', 'governance', 'local-password', 100000)
        self.assertEqual(self.rpc.call_args_list[0].args[1][0]['value'], '0x0')

if __name__ == '__main__': unittest.main()
