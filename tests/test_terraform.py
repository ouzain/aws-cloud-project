"Préserver la propriété Terraform lors d’une nouvelle initialisation."
import importlib.util
import contextlib
import io
import json
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import _terraform_cleanup as cleanup

spec = importlib.util.spec_from_file_location('terraform_helper',
    Path(__file__).resolve().parents[1] / 'scripts/terraform.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class GovernanceOwnershipTests(unittest.TestCase):
    def test_empty_account_creates_governance(self):
        self.assertEqual(helper.governance_settings([], [], []), {
            'existing_audit_trail_name': None, 'existing_budget_name': None})

    def test_external_baseline_is_reused(self):
        self.assertEqual(helper.governance_settings(
            [{'Name': 'vitalora-existing'}], [{'BudgetName': 'vitalora-existing'}], []), {
            'existing_audit_trail_name': 'vitalora-existing',
            'existing_budget_name': 'vitalora-existing'})

    def test_reinitialization_preserves_owned_governance(self):
        managed = ['module.monitoring.aws_cloudtrail.management[0]',
            'module.monitoring.aws_budgets_budget.monthly[0]']
        self.assertEqual(helper.governance_settings(
            [{'Name': 'vitalora-management'}], [{'BudgetName': 'vitalora-monthly'}], managed), {
            'existing_audit_trail_name': None, 'existing_budget_name': None})

    def test_mixed_ownership_is_handled_independently(self):
        self.assertEqual(helper.governance_settings(
            [{'Name': 'vitalora-management'}], [{'BudgetName': 'vitalora-existing'}],
            ['module.monitoring.aws_cloudtrail.management[0]']), {
            'existing_audit_trail_name': None, 'existing_budget_name': 'vitalora-existing'})


class FreshStateTests(unittest.TestCase):
    def test_public_state_list_accepts_first_deployment_without_creating_resources(self):
        with tempfile.TemporaryDirectory() as directory:
            environment = Path(directory)
            (environment / '.terraform').mkdir()
            (environment / '.terraform/terraform.tfstate').write_text('{}')
            with patch.object(helper, 'ENVIRONMENT', environment), \
                    patch.object(helper, 'terraform_binary', return_value='terraform'), \
                    patch.object(helper, 'terraform_environment', return_value={}), \
                    patch.object(helper, 'state_addresses', return_value=[]) as addresses, \
                    patch.object(helper, 'aws') as aws, \
                    patch.object(sys, 'argv', ['terraform.py', 'state', 'list']), \
                    contextlib.redirect_stdout(io.StringIO()) as output:
                helper.main()
            self.assertEqual(output.getvalue(), '')
            addresses.assert_called_once_with('terraform', environment, {})
            aws.assert_not_called()

    def test_only_exact_absent_state_diagnostic_is_an_empty_environment(self):
        diagnostic = ('No state file was found!\n\n'
            'State management commands require a state file. Run this command\n'
            'in a directory where Terraform has been run or use the -state flag\n'
            'to point the command to a specific state location.\n')
        with patch.object(helper.subprocess, 'run', return_value=
                subprocess.CompletedProcess([], 1, stdout='', stderr=diagnostic)):
            self.assertEqual(helper.state_addresses('terraform', '/test', {}), [])
        for error in ['AccessDenied: s3:GetObject', 'Error: Backend initialization required',
                      diagnostic + 'AccessDenied', 'Error acquiring the state lock']:
            with self.subTest(error=error), patch.object(helper.subprocess, 'run', return_value=
                    subprocess.CompletedProcess([], 1, stdout='', stderr=error)):
                with self.assertRaises(RuntimeError):
                    helper.state_addresses('terraform', '/test', {})

    def test_existing_addresses_are_preserved(self):
        with patch.object(helper.subprocess, 'run', return_value=subprocess.CompletedProcess(
                [], 0, stdout='module.network.aws_vpc.this\n', stderr='')):
            self.assertEqual(helper.state_addresses('terraform', '/test', {}),
                ['module.network.aws_vpc.this'])


class CleanupEntryPointTests(unittest.TestCase):
    def test_public_destroy_entry_uses_recovery_and_writes_sanitized_result(self):
        identity = {'Account': '123456789012', 'Arn': 'arn:aws:iam::123456789012:user/deployer'}
        result = {'code_retour': 0, 'ressources_restantes': 0, 'etat_applicatif_vide': True}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            environment = root / 'env'
            (environment / '.terraform').mkdir(parents=True)
            (environment / '.terraform/terraform.tfstate').write_text('{}')
            with patch.object(helper, 'ROOT', root), patch.object(helper, 'ENVIRONMENT', environment), \
                    patch.object(helper, 'terraform_binary', return_value='terraform'), \
                    patch.object(helper, 'terraform_environment', return_value={}), \
                    patch.object(helper, 'aws', return_value=json.dumps(identity)), \
                    patch.object(sys, 'argv', ['terraform.py', '--profile', 'team', 'destroy', '-auto-approve']), \
                    patch.object(cleanup, 'destroy_with_recovery', return_value=result) as recover:
                with self.assertRaises(SystemExit) as exit_code:
                    helper.main()
            self.assertEqual(exit_code.exception.code, 0)
            recover.assert_called_once()
            self.assertEqual(recover.call_args.args[0].directory, environment)
            self.assertEqual(recover.call_args.args[1:4], (['destroy', '-auto-approve'], identity, 'eu-west-3'))
            report = json.loads((root / 'test-results/cleanup.json').read_text())
            self.assertTrue(report['etat_applicatif_vide'])
            self.assertEqual(report['compte'], identity['Account'])


if __name__ == '__main__':
    unittest.main()
