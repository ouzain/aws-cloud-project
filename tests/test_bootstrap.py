"""Vérifier le périmètre du compte et les garde-fous d’initialisation IAM."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('bootstrap', Path(__file__).resolve().parents[1] / 'scripts/bootstrap.py')
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)
ACCOUNT = '123456789012'


class BootstrapTests(unittest.TestCase):
    def test_rendering_two_independent_accounts_has_no_original_account(self):
        for account in [ACCOUNT, '987654321098']:
            policies = bootstrap.render_policies(account, 'eu-west-3')
            self.assertEqual(len(policies), 5)
            text = json.dumps(policies)
            self.assertNotIn('573199225243', text)
            self.assertNotIn('${', text)
            self.assertIn(account, text)
            for policy in policies.values():
                self.assertLessEqual(len(json.dumps(policy, separators=(',', ':'))), 6144)
                for statement in policy['Statement']:
                    if 'iam:PassRole' in statement['Action']:
                        self.assertEqual(statement['Resource'], [f'arn:aws:iam::{account}:role/vitalora-*'])

    def test_invalid_account_and_unverified_region_are_rejected(self):
        for account, region in [('123', 'eu-west-3'), ('*', 'eu-west-3'), (ACCOUNT, 'us-east-1')]:
            with self.assertRaises(RuntimeError):
                bootstrap.render_policies(account, region)

    def test_default_generation_never_calls_aws(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(sys, 'argv', ['bootstrap.py', '--account-id', ACCOUNT,
                    '--output-dir', directory]), patch.object(bootstrap, 'aws') as aws, \
                    contextlib.redirect_stdout(io.StringIO()):
                bootstrap.main()
            aws.assert_not_called()
            self.assertEqual(len(list(Path(directory).glob('vitalora-*.json'))), 5)

    def fake_aws(self, account=ACCOUNT, findings=None, existing=False, drift=False):
        self.calls = []
        policies = bootstrap.render_policies(ACCOUNT, 'eu-west-3')
        def call(service, operation, *args):
            self.calls.append((service, operation, args))
            if operation == 'get-user':
                return {'User': {'Arn': f'arn:aws:iam::{account}:user/deployer'}}
            if operation == 'validate-policy':
                return {'findings': findings or []}
            if operation == 'list-policies':
                return {'Policies': [{'Arn': f'arn:aws:iam::{ACCOUNT}:policy/vitalora/{name}',
                    'DefaultVersionId': 'v1'} for name in policies] if existing else []}
            if operation == 'get-policy-version':
                name = args[args.index('--policy-arn') + 1].split('/')[-1]
                return {'PolicyVersion': {'Document': {} if drift else policies[name]}}
            return {}
        return call

    def test_apply_creates_five_reviewed_policies_and_attaches_only_target(self):
        call = self.fake_aws()
        bootstrap.install_policies(call, ACCOUNT, bootstrap.render_policies(ACCOUNT, 'eu-west-3'), user='deployer')
        self.assertEqual(sum(op == 'create-policy' for _, op, _ in self.calls), 5)
        attachments = [args for _, op, args in self.calls if op == 'attach-user-policy']
        self.assertEqual(len(attachments), 5)
        self.assertTrue(all(args[0:2] == ('--user-name', 'deployer') for args in attachments))

    def test_existing_matching_policies_are_reused(self):
        call = self.fake_aws(existing=True)
        bootstrap.install_policies(call, ACCOUNT, bootstrap.render_policies(ACCOUNT, 'eu-west-3'), user='deployer')
        self.assertNotIn('create-policy', [op for _, op, _ in self.calls])

    def test_wrong_target_validation_failure_and_policy_drift_write_nothing(self):
        cases = [{'account': '999999999999'}, {'findings': [{'findingType': 'ERROR'}]},
            {'findings': [{'findingType': 'SECURITY_WARNING'}]}, {'existing': True, 'drift': True}]
        for kwargs in cases:
            with self.subTest(kwargs=kwargs):
                call = self.fake_aws(**kwargs)
                with self.assertRaises(RuntimeError):
                    bootstrap.install_policies(call, ACCOUNT,
                        bootstrap.render_policies(ACCOUNT, 'eu-west-3'), user='deployer')
                self.assertFalse(any(op in ['create-policy', 'attach-user-policy'] for _, op, _ in self.calls))


if __name__ == '__main__':
    unittest.main()
