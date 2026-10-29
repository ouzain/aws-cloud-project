#!/usr/bin/env python3
"Vérifier chiffrement, audit, budget et déclenchement réel d’une alarme."
import argparse
import datetime
import gzip
import json
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__, add_help=False)
    parser._optionals.title = "Options"
    parser.add_argument("-h", "--help", action="help", help="Afficher cette aide et quitter.")
    parser.add_argument('--profile', default='vitalora')
    parser.add_argument('--region', default='eu-west-3')
    options = parser.parse_args()

    def aws(*arguments):
        return json.loads(subprocess.check_output(['aws', '--profile', options.profile,
            '--region', options.region, *arguments, '--output', 'json'], text=True))

    identity = aws('sts', 'get-caller-identity')
    assert not identity['Arn'].endswith(':root'), "Utiliser le profil IAM de déploiement pour la vérification."
    outputs = json.loads(subprocess.check_output(['python3', str(ROOT / 'scripts/terraform.py'),
        '--profile', options.profile, '--region', options.region, 'output', '-json'], text=True))
    outputs = {key: item['value'] for key, item in outputs.items()}

    dashboard = aws('cloudwatch', 'get-dashboard', '--dashboard-name', outputs['dashboard_name'])
    assert len(json.loads(dashboard['DashboardBody'])['widgets']) == 6
    alarms = aws('cloudwatch', 'describe-alarms', '--alarm-names', *outputs['alarm_names'].values())['MetricAlarms']
    assert len(alarms) == 4
    bucket = outputs['assets_bucket_name']
    block = aws('s3api', 'get-public-access-block', '--bucket', bucket)['PublicAccessBlockConfiguration']
    assert all(block.values())
    rules = aws('s3api', 'get-bucket-encryption', '--bucket', bucket)['ServerSideEncryptionConfiguration']['Rules']
    assert rules[0]['ApplyServerSideEncryptionByDefault']['SSEAlgorithm'] == 'aws:kms'
    products = json.loads((ROOT / 'catalog/products.json').read_text())
    image = aws('s3api', 'head-object', '--bucket', bucket, '--key', products[0]['image_key'])
    assert image['ServerSideEncryption'] == 'aws:kms' and image['BucketKeyEnabled']
    key = aws('kms', 'describe-key', '--key-id', image['SSEKMSKeyId'])['KeyMetadata']
    assert key['KeyManager'] == 'AWS'
    database = aws('rds', 'describe-db-instances', '--db-instance-identifier', 'vitalora-db')['DBInstances'][0]
    assert database['StorageEncrypted'] and not database['PubliclyAccessible']
    try:
        urllib.request.urlopen(f'https://{bucket}.s3.{options.region}.amazonaws.com/{products[0]["image_key"]}', timeout=20)
        raise AssertionError("Une requête sans signature a pu lire une image privée.")
    except urllib.error.HTTPError as error:
        assert error.code == 403
    print("OK : S3 privé, chiffrement KMS géré par AWS, RDS privé chiffré, tableau de bord et quatre alarmes.", flush=True)

    trail = outputs['audit_trail_arn']
    status = aws('cloudtrail', 'get-trail-status', '--name', trail)
    selectors = aws('cloudtrail', 'get-event-selectors', '--trail-name', trail)
    assert status['IsLogging'] and not status.get('LatestDeliveryError')
    assert any(item.get('IncludeManagementEvents') and item['ReadWriteType'] == 'All' for item in selectors['EventSelectors'])
    notifications = aws('budgets', 'describe-notifications-for-budget', '--account-id', identity['Account'],
        '--budget-name', outputs['budget_name'])['Notifications']
    assert sorted(item['Threshold'] for item in notifications) == [20.0, 50.0, 80.0]
    assert all(item.get('ThresholdType', 'PERCENTAGE') == 'PERCENTAGE' for item in notifications)
    for notification in notifications:
        subscribers = aws('budgets', 'describe-subscribers-for-notification', '--account-id', identity['Account'],
            '--budget-name', outputs['budget_name'], '--notification', json.dumps(notification))['Subscribers']
        assert subscribers, "La notification budgétaire n’a aucun abonné."
    print("OK : audit de gestion actif et trois seuils budgétaires avec abonnés.", flush=True)

    # Lire les événements d’audit livrés dans le compartiment S3 déjà autorisé.
    # Ne conserver que les métadonnées de gestion utiles aux preuves.
    trails = aws('cloudtrail', 'describe-trails', '--trail-name-list', trail)['trailList']
    audit_bucket = trails[0]['S3BucketName']
    date = datetime.datetime.now(datetime.timezone.utc).strftime('%Y/%m/%d')
    prefix = f'AWSLogs/{identity["Account"]}/CloudTrail/{options.region}/{date}/'
    objects = aws('s3api', 'list-objects-v2', '--bucket', audit_bucket, '--prefix', prefix).get('Contents', [])
    audit_event = None
    with tempfile.TemporaryDirectory(prefix='vitalora-audit-') as directory:
        for item in sorted(objects, key=lambda item: item['LastModified'], reverse=True)[:20]:
            target = str(Path(directory) / 'record.json.gz')
            aws('s3api', 'get-object', '--bucket', audit_bucket, '--key', item['Key'], target)
            with gzip.open(target, 'rt') as handle:
                records = json.load(handle)['Records']
            match = next((event for event in records if event['eventName'].startswith(
                ('CreateFunction', 'CreateDBInstance', 'CreateVpc', 'PutDashboard', 'PutMetricAlarm'))
                and 'vitalora' in json.dumps(event.get('requestParameters', {})).lower()), None)
            if match:
                audit_event = {key: match[key] for key in ['eventTime', 'eventName', 'eventSource']}
                audit_event['actor'] = match['userIdentity'].get('arn')
                break
    assert audit_event, "Aucun événement de gestion VITALORA livré n’a été trouvé."
    print("OK : un événement CloudTrail livré identifie un changement d’infrastructure du projet.", flush=True)

    target = ROOT / 'test-results'
    target.mkdir(exist_ok=True)
    invocation_file = str(target / 'monitoring-invocation.json')
    bad = {'Records': [{'messageId': 'phase-5-controlled-failure', 'body': 'invalid-json'}]}
    aws('lambda', 'invoke', '--function-name', outputs['order_worker_function'], '--cli-binary-format',
        'raw-in-base64-out', '--payload', json.dumps(bad), invocation_file)
    response = json.loads(Path(invocation_file).read_text())
    assert response['batchItemFailures'] == [{'itemIdentifier': 'phase-5-controlled-failure'}]
    alarm_name = outputs['alarm_names']['processing_failures']
    print("Attente de l’alarme réelle d’échec de traitement…", flush=True)
    for attempt in range(40):
        alarm = aws('cloudwatch', 'describe-alarms', '--alarm-names', alarm_name)['MetricAlarms'][0]
        if alarm['StateValue'] == 'ALARM':
            break
        if attempt == 39:
            raise AssertionError("L’erreur contrôlée n’a pas déclenché l’alarme.")
        time.sleep(10)
    result = {
        'verified_at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'phase': 5,
        'dashboard': outputs['dashboard_name'], 'encryption': {'s3': "KMS géré par AWS", 'rds': True},
        'private_bucket': True, 'audit_event': audit_event, 'budget_thresholds': [20, 50, 80],
        'alarm': {'name': alarm_name, 'state': alarm['StateValue'], 'reason': alarm['StateReason']},
    }
    (target / 'phase-5.json').write_text(json.dumps(result, indent=2) + '\n')
    print("OK : l’erreur injectée a fait passer l’alarme CloudWatch à ALARM. Phase 5 validée.", flush=True)


if __name__ == '__main__':
    main()
