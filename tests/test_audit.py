"""Tester la livraison différée CloudTrail, le délai et les erreurs bloquantes."""
import datetime
import gzip
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from _audit import wait_for_audit_event

NOW = datetime.datetime(2026, 10, 29, 0, 1, tzinfo=datetime.timezone.utc)
SINCE = NOW - datetime.timedelta(minutes=5)
ACCOUNT = '123456789012'


class AuditDeliveryTests(unittest.TestCase):
    def run_wait(self, delay=False, missing=False, denied=False, old=False, foreign=False):
        self.elapsed = 0
        self.prefixes = set()
        def sleep(seconds):
            self.elapsed += seconds
        def aws(service, operation, *args):
            if denied:
                raise RuntimeError('AccessDenied')
            if operation == 'list-objects-v2':
                self.prefixes.add(args[-1])
                if missing or (delay and self.elapsed == 0):
                    return {}
                return {'Contents': [{'Key': 'record.gz', 'LastModified': NOW.isoformat()}]}
            record = {'eventName': 'CreateVpc', 'eventSource': 'ec2.amazonaws.com',
                'eventTime': (SINCE - datetime.timedelta(seconds=1) if old else NOW).isoformat(),
                'userIdentity': {'accountId': '999999999999' if foreign else ACCOUNT,
                    'arn': f'arn:aws:iam::{ACCOUNT}:user/deployer'},
                'requestParameters': {'tag': 'vitalora'}}
            with gzip.open(args[-1], 'wt') as handle:
                json.dump({'Records': [record]}, handle)
            return {}
        return wait_for_audit_event(aws, 'audit', ACCOUNT, 'eu-west-3', SINCE,
            timeout=30, clock=lambda: self.elapsed, sleep=sleep, now=lambda: NOW)

    def test_delayed_delivery_retries_and_crosses_midnight(self):
        event = self.run_wait(delay=True)
        self.assertEqual(event['eventName'], 'CreateVpc')
        self.assertEqual(self.elapsed, 15)
        self.assertTrue(any('2026/10/28' in prefix for prefix in self.prefixes))
        self.assertTrue(any('2026/10/29' in prefix for prefix in self.prefixes))

    def test_absence_timeout_and_old_or_foreign_events_do_not_pass(self):
        for kwargs in [{'missing': True}, {'old': True}, {'foreign': True}]:
            with self.subTest(kwargs=kwargs), self.assertRaisesRegex(RuntimeError, 'Aucun événement'):
                self.run_wait(**kwargs)
            self.assertEqual(self.elapsed, 30)

    def test_permission_error_is_immediate(self):
        with self.assertRaisesRegex(RuntimeError, 'AccessDenied'):
            self.run_wait(denied=True)
        self.assertEqual(self.elapsed, 0)


if __name__ == '__main__':
    unittest.main()
