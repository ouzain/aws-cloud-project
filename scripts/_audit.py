"""Attendre une preuve CloudTrail livrée, sans masquer les erreurs de permissions."""
import datetime
import gzip
import json
from pathlib import Path
import tempfile
import time


def wait_for_audit_event(aws, bucket, account, region, since, timeout=600,
                         clock=time.monotonic, sleep=time.sleep, now=None):
    now = now or (lambda: datetime.datetime.now(datetime.timezone.utc))
    deadline = clock() + timeout
    seen = set()
    with tempfile.TemporaryDirectory(prefix='vitalora-audit-') as directory:
        while True:
            # Inclure la veille si le déploiement traverse minuit UTC.
            dates = {now().date(), since.date()}
            objects = []
            for day in sorted(dates):
                prefix = f'AWSLogs/{account}/CloudTrail/{region}/{day:%Y/%m/%d}/'
                response = aws('s3api', 'list-objects-v2', '--bucket', bucket, '--prefix', prefix)
                if response.get('IsTruncated') or response.get('NextToken'):
                    raise RuntimeError('Inventaire CloudTrail incomplet ; arrêt.')
                objects.extend(response.get('Contents', []))
            for item in sorted(objects, key=lambda item: item['LastModified'], reverse=True):
                if item['Key'] in seen:
                    continue
                target = str(Path(directory) / 'record.json.gz')
                aws('s3api', 'get-object', '--bucket', bucket, '--key', item['Key'], target)
                with gzip.open(target, 'rt') as handle:
                    records = json.load(handle)['Records']
                seen.add(item['Key'])
                for event in records:
                    if (event['eventName'].startswith(('CreateFunction', 'CreateDBInstance',
                            'CreateVpc', 'PutDashboard', 'PutMetricAlarm'))
                            and datetime.datetime.fromisoformat(event['eventTime'].replace('Z', '+00:00')) >= since
                            and event.get('userIdentity', {}).get('accountId') == account
                            and 'vitalora' in json.dumps(event.get('requestParameters', {})).lower()):
                        result = {key: event[key] for key in ['eventTime', 'eventName', 'eventSource']}
                        result['actor'] = event['userIdentity'].get('arn')
                        return result
            if clock() >= deadline:
                raise RuntimeError('Aucun événement CloudTrail livré pour ce déploiement. '
                    'La livraison est différée ; relancer verify-monitoring.py après quelques minutes.')
            sleep(min(15, max(0, deadline - clock())))
