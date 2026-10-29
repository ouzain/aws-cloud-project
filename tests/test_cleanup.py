"""Éviter de perdre le suivi d’une ressource lors de la récupération de suppression."""
import copy
import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import _terraform_cleanup as cleanup

ACCOUNT = '123456789012'
IDENTITY = {'Account': ACCOUNT, 'Arn': f'arn:aws:iam::{ACCOUNT}:user/vitalora/deployer'}
REGION = 'eu-west-3'
UUID = '12345678-1234-4234-8234-123456789abc'
FUNCTION_ARN = f'arn:aws:lambda:{REGION}:{ACCOUNT}:function:vitalora-order-processor'
QUEUE_ARN = f'arn:aws:sqs:{REGION}:{ACCOUNT}:vitalora-order-processing'
ERROR = (f'Error: waiting for Lambda Event Source Mapping ({UUID}) delete: '
    'operation error Lambda: GetEventSourceMapping, https response error StatusCode: 403, '
    'AccessDeniedException: access denied on resource: *\n')
ARGUMENTS = ['destroy', '-auto-approve']


def state(mapping=True):
    resources = [
        {'address': cleanup.FUNCTION_ADDRESS, 'mode': 'managed', 'type': 'aws_lambda_function',
         'values': {'arn': FUNCTION_ARN, 'function_name': 'vitalora-order-processor',
                    'tags_all': {'Project': 'vitalora'},
                    'environment': [{'variables': {'DB_PASSWORD': 'SECRET_NOT_TO_EXPORT'}}]}},
        {'address': cleanup.QUEUE_ADDRESS, 'mode': 'managed', 'type': 'aws_sqs_queue',
         'values': {'arn': QUEUE_ARN, 'name': 'vitalora-order-processing',
                    'tags_all': {'Project': 'vitalora'}}}]
    if mapping:
        resources.append({'address': cleanup.MAPPING_ADDRESS, 'mode': 'managed',
            'type': 'aws_lambda_event_source_mapping', 'values': {
                'id': UUID, 'function_name': FUNCTION_ARN, 'event_source_arn': QUEUE_ARN}})
    return {'format_version': '1.0', 'values': {'root_module': {'child_modules': [
        {'address': 'module.messaging', 'resources': resources}]}}}


EMPTY = {'format_version': '1.0'}
ABSENT = {'EventSourceMappings': []}
PRESENT = {'EventSourceMappings': [{'UUID': UUID, 'FunctionArn': FUNCTION_ARN,
    'EventSourceArn': QUEUE_ARN}]}


class FakeTerraform:
    def __init__(self, states, results, forget_error=None):
        self.states = iter(copy.deepcopy(states))
        self.results = iter(results)
        self.calls = []
        self.forget_error = forget_error

    def state(self):
        self.calls.append('state')
        return next(self.states)

    def destroy(self, arguments):
        self.calls.append(('destroy', list(arguments)))
        code, diagnostic = next(self.results)
        return subprocess.CompletedProcess(arguments, code, stderr=diagnostic)

    def forget_deleted_mapping(self):
        self.calls.append(('forget', cleanup.MAPPING_ADDRESS))
        if self.forget_error:
            raise self.forget_error


class CleanupRecoveryTests(unittest.TestCase):
    def test_custom_state_partial_destroy_and_unlocked_modes_bypass_recovery(self):
        self.assertTrue(cleanup.recovery_options_supported(ARGUMENTS, {}))
        self.assertTrue(cleanup.recovery_options_supported(ARGUMENTS + ['-lock-timeout=30s'], {}))
        for options in [['-target=x'], ['-target', 'x'], ['-json'], ['-lock=false'],
                ['-lock=0'], ['-state=other.tfstate'], ['-state-out=other.tfstate'], ['-backup=other']]:
            with self.subTest(options=options):
                self.assertFalse(cleanup.recovery_options_supported(ARGUMENTS + options, {}))
        self.assertFalse(cleanup.recovery_options_supported(ARGUMENTS,
            {'TF_CLI_ARGS_destroy': '-target=x'}))

    def run_cleanup(self, cli, responses=(ABSENT, ABSENT), identity=IDENTITY, region=REGION):
        self.queries = []
        self.pauses = []
        values = iter(responses)

        def describe(target):
            self.queries.append(target)
            result = next(values)
            if isinstance(result, Exception):
                raise result
            return result

        with contextlib.redirect_stdout(io.StringIO()):
            return cleanup.destroy_with_recovery(cli, ARGUMENTS, identity, region, describe,
                sleep=self.pauses.append)

    def test_ordinary_destroy_does_not_query_or_forget(self):
        cli = FakeTerraform([state(), EMPTY], [(0, '')])
        result = self.run_cleanup(cli)
        self.assertFalse(result['recuperation_automatique'])
        self.assertTrue(result['etat_applicatif_vide'])
        self.assertEqual(self.queries, [])
        self.assertNotIn(('forget', cleanup.MAPPING_ADDRESS), cli.calls)

    def test_known_error_requires_two_checks_and_forgets_only_one_address(self):
        cli = FakeTerraform([state(), state(), state(False), EMPTY], [(1, ERROR), (0, '')])
        result = self.run_cleanup(cli)
        self.assertEqual(cli.calls, ['state', ('destroy', ARGUMENTS), 'state',
            ('forget', cleanup.MAPPING_ADDRESS), 'state', ('destroy', ARGUMENTS), 'state'])
        self.assertEqual(len(self.queries), 2)
        self.assertEqual(self.pauses, [2])
        self.assertEqual(result['verifications_absence'], 2)
        self.assertTrue(result['recuperation_automatique'])
        self.assertTrue(result['entree_retiree'])
        self.assertNotIn('SECRET_NOT_TO_EXPORT', json.dumps(result))

    def test_error_during_read_is_also_recognized(self):
        diagnostic = ERROR.replace('waiting for', 'reading').replace(') delete:', '):')
        cli = FakeTerraform([state(), state(), state(False), EMPTY], [(1, diagnostic), (0, '')])
        self.assertTrue(self.run_cleanup(cli)['etat_applicatif_vide'])

    def test_live_mapping_on_either_check_never_forgets_or_retries(self):
        for responses in [(PRESENT,), (ABSENT, PRESENT)]:
            with self.subTest(responses=responses):
                cli = FakeTerraform([state()], [(1, ERROR)])
                with self.assertRaisesRegex(RuntimeError, 'existe encore'):
                    self.run_cleanup(cli, responses)
                self.assertEqual(cli.calls, ['state', ('destroy', ARGUMENTS)])

    def test_unreliable_or_unscoped_responses_never_forget(self):
        cases = [None, {}, {'EventSourceMappings': None},
            {'EventSourceMappings': [], 'NextMarker': 'more'},
            {'EventSourceMappings': [], 'NextToken': 'more'},
            {'EventSourceMappings': [None]}, {'EventSourceMappings': [{'UUID': UUID}]},
            {'EventSourceMappings': [{'UUID': UUID, 'FunctionArn': 'other', 'EventSourceArn': QUEUE_ARN}]},
            {'EventSourceMappings': [{'UUID': UUID, 'FunctionArn': FUNCTION_ARN, 'EventSourceArn': 'other'}]},
            RuntimeError('AWS indisponible')]
        for response in cases:
            with self.subTest(response=response):
                cli = FakeTerraform([state()], [(1, ERROR)])
                with self.assertRaises(RuntimeError):
                    self.run_cleanup(cli, [response])
                self.assertEqual(cli.calls, ['state', ('destroy', ARGUMENTS)])

    def test_unrelated_errors_and_interruptions_never_recover(self):
        cases = [(130, ERROR), (1, ERROR.replace(UUID, 'aaaaaaaa-1234-4234-8234-123456789abc')),
            (1, ERROR.replace('GetEventSourceMapping', 'DeleteEventSourceMapping')),
            (1, ERROR.replace('StatusCode: 403', 'StatusCode: 500')),
            (1, ERROR + '\nError: reading RDS instance: access denied\n'),
            (1, 'Error: operation canceled\n')]
        for code, diagnostic in cases:
            with self.subTest(code=code, diagnostic=diagnostic):
                cli = FakeTerraform([state()], [(code, diagnostic)])
                result = self.run_cleanup(cli)
                self.assertEqual(result['code_retour'], code)
                self.assertFalse(result['recuperation_automatique'])
                self.assertEqual(self.queries, [])
                self.assertEqual(cli.calls, ['state', ('destroy', ARGUMENTS)])

    def test_wrong_identity_region_or_ownership_stops_before_destroy(self):
        altered = state()
        altered['values']['root_module']['child_modules'][0]['resources'][0]['values']['tags_all']['Project'] = 'other'
        cases = [(state(), {**IDENTITY, 'Account': '999999999999'}, REGION),
            (state(), {**IDENTITY, 'Arn': f'arn:aws:iam::{ACCOUNT}:root'}, REGION),
            (state(), IDENTITY, 'eu-west-1'), (altered, IDENTITY, REGION)]
        for snapshot, identity, region in cases:
            with self.subTest(identity=identity, region=region):
                cli = FakeTerraform([snapshot], [])
                with self.assertRaisesRegex(RuntimeError, 'récupération refusée'):
                    self.run_cleanup(cli, identity=identity, region=region)
                self.assertEqual(cli.calls, ['state'])

    def test_malformed_state_does_not_leak_values_or_change_resources(self):
        for snapshot in [None, {'format_version': '2.0'}, {'format_version': '1.0', 'values': None},
                {'format_version': '1.0', 'values': {'root_module': []}}]:
            with self.subTest(snapshot=snapshot):
                cli = FakeTerraform([snapshot], [])
                with self.assertRaises(RuntimeError) as caught:
                    self.run_cleanup(cli)
                self.assertNotIn('SECRET_NOT_TO_EXPORT', str(caught.exception))
                self.assertEqual(cli.calls, ['state'])

    def test_changed_uuid_during_destroy_is_not_forgotten(self):
        changed = state()
        changed['values']['root_module']['child_modules'][0]['resources'][2]['values']['id'] = 'aaaaaaaa-1234-4234-8234-123456789abc'
        cli = FakeTerraform([state(), changed], [(1, ERROR)])
        with self.assertRaisesRegex(RuntimeError, 'a changé'):
            self.run_cleanup(cli)
        self.assertEqual(cli.calls, ['state', ('destroy', ARGUMENTS), 'state'])

    def test_lock_failure_does_not_restart_destroy(self):
        cli = FakeTerraform([state(), state()], [(1, ERROR)],
            forget_error=subprocess.CalledProcessError(1, 'terraform state rm'))
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_cleanup(cli)
        self.assertEqual(cli.calls.count(('destroy', ARGUMENTS)), 1)

    def test_failed_retry_is_not_repeated(self):
        cli = FakeTerraform([state(), state(), state(False)], [(1, ERROR), (1, ERROR)])
        result = self.run_cleanup(cli)
        self.assertEqual(result['code_retour'], 1)
        self.assertEqual(cli.calls.count(('destroy', ARGUMENTS)), 2)
        self.assertEqual(cli.calls.count(('forget', cleanup.MAPPING_ADDRESS)), 1)

    def test_already_removed_state_is_not_forgotten_again(self):
        cli = FakeTerraform([state(), state(False), EMPTY], [(1, ERROR), (0, '')])
        result = self.run_cleanup(cli)
        self.assertTrue(result['recuperation_automatique'])
        self.assertFalse(result['entree_retiree'])
        self.assertNotIn(('forget', cleanup.MAPPING_ADDRESS), cli.calls)

    def test_success_with_remaining_resources_is_not_reported_as_clean(self):
        cli = FakeTerraform([state(), state(False)], [(0, '')])
        with self.assertRaisesRegex(RuntimeError, 'restent dans l’état'):
            self.run_cleanup(cli)


class TerraformAdapterTests(unittest.TestCase):
    def test_state_removal_uses_exact_address_and_retains_locking(self):
        cli = cleanup.TerraformCleanupCLI('terraform', '/private/test', {'KEY': 'VALUE'})
        with patch.object(cleanup.subprocess, 'run') as execute:
            cli.forget_deleted_mapping()
        execute.assert_called_once_with(['terraform', 'state', 'rm', '-lock-timeout=0s',
            cleanup.MAPPING_ADDRESS], cwd='/private/test', env={'KEY': 'VALUE'}, check=True)

    def test_destroy_keeps_requested_confirmation_and_options(self):
        cli = cleanup.TerraformCleanupCLI('terraform', '/private/test', {})
        with patch.object(cleanup.subprocess, 'run', return_value=
                subprocess.CompletedProcess([], 0, stderr='')) as execute:
            cli.destroy(['destroy', '-parallelism=2'])
        self.assertEqual(execute.call_args.args[0], ['terraform', 'destroy', '-parallelism=2', '-no-color'])


if __name__ == '__main__':
    unittest.main()
