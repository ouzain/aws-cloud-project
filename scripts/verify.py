#!/usr/bin/env python3
"Vérifier les phases 1 à 4 sur l’environnement AWS déployé."
import argparse
import json
from pathlib import Path
import subprocess
import time
import urllib.error
import urllib.request
import uuid

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

    raw = subprocess.check_output(['python3', str(ROOT / 'scripts/terraform.py'),
        '--profile', options.profile, '--region', options.region, 'output', '-json'], text=True)
    outputs = {key: item['value'] for key, item in json.loads(raw).items()}
    base = 'http://' + outputs['alb_dns_name']

    def request(path, body=None, key=None):
        headers = {'Content-Type': 'application/json'}
        if key:
            headers['Idempotency-Key'] = key
        data = json.dumps(body).encode() if body is not None else None
        with urllib.request.urlopen(urllib.request.Request(base + path, data=data, headers=headers), timeout=20) as response:
            return json.load(response)

    print("Attente du contrôle de disponibilité ALB…", flush=True)
    for attempt in range(80):
        try:
            assert request('/ready')['status'] == 'ready'
            break
        except (urllib.error.URLError, AssertionError, TimeoutError):
            if attempt == 79:
                raise
            time.sleep(5)
    assert request('/health')['status'] == 'ok'
    products = request('/products')
    counts = {}
    for product in products:
        counts[product['category']] = counts.get(product['category'], 0) + 1
        with urllib.request.urlopen(product['image_url'], timeout=20) as image:
            assert b'<svg' in image.read()
    assert len(counts) == 4 and all(count >= 10 for count in counts.values())
    print("OK : ALB, base disponible, 40 produits et 40 images S3 privées.", flush=True)

    selected = []
    for product in products:
        if product['category'] not in [item['category'] for item in selected]:
            selected.append(product)
        if len(selected) == 2:
            break
    payload = {'customer_email': 'verification@example.com',
        'items': [{'product_id': product['product_id'], 'qty': 2} for product in selected]}
    key = 'verification-' + uuid.uuid4().hex
    created = request('/orders', payload, key)
    repeated = request('/orders', payload, key)
    assert repeated['order_id'] == created['order_id']
    assert created['total_cents'] == sum(product['price_cents'] * 2 for product in selected)
    for product in selected:
        assert request('/products/' + str(product['product_id']))['stock_qty'] == product['stock_qty'] - 2
    rejected = {**payload, 'items': [
        {'product_id': selected[0]['product_id'], 'qty': 1}, {'product_id': 999999, 'qty': 1}]}
    try:
        request('/orders', rejected)
        raise AssertionError("Un produit invalide a été accepté.")
    except urllib.error.HTTPError as error:
        assert error.code == 400
    assert request('/products/' + str(selected[0]['product_id']))['stock_qty'] == selected[0]['stock_qty'] - 2
    print("OK : commande, total serveur, mise à jour du stock et reprises HTTP idempotentes.", flush=True)

    for attempt in range(90):
        order = request('/orders/' + str(created['order_id']))
        if order['status'] == 'shipped':
            break
        if attempt == 89:
            raise AssertionError("Le traitement n’a pas enregistré le statut shipped.")
        time.sleep(2)
    assert [item['status'] for item in order['history']] == ['received', 'confirmed', 'processing', 'shipped']
    assert len(order['items']) == 2
    print("OK : SNS, SQS et Lambda ont enregistré l’historique complet de la commande.", flush=True)

    group = aws('autoscaling', 'describe-auto-scaling-groups', '--auto-scaling-group-names', outputs['asg_name'])
    instance_id = group['AutoScalingGroups'][0]['Instances'][0]['InstanceId']
    for attempt in range(45):
        information = aws('ssm', 'describe-instance-information', '--filters', 'Key=InstanceIds,Values=' + instance_id)
        if any(item['PingStatus'] == 'Online' for item in information['InstanceInformationList']):
            break
        if attempt == 44:
            raise AssertionError("L’instance EC2 ne s’est pas enregistrée dans Systems Manager.")
        time.sleep(2)
    # Lire RDS depuis EC2 sans copier les identifiants sur cette machine.
    script = """set -eu
set -a
. /opt/vitalora/.env
set +a
cd /opt/vitalora
/usr/bin/node-22 <<'NODE'
const { createPool } = require('./app/lib/database');
(async () => {
 const pool = createPool();
 const [[order]] = await pool.query('SELECT order_id, status, total_cents FROM orders WHERE order_id = ?', [ORDER_ID]);
 const [[items]] = await pool.query('SELECT COUNT(*) AS count FROM order_items WHERE order_id = ?', [ORDER_ID]);
 const [[event]] = await pool.query('SELECT published_at FROM outbox WHERE order_id = ?', [ORDER_ID]);
 console.log(JSON.stringify({order, item_count: items.count, event_published: Boolean(event.published_at)}));
 await pool.end();
})().catch(error => { console.error(error.message); process.exitCode = 1; });
NODE
""".replace('ORDER_ID', str(created['order_id']))
    command = aws('ssm', 'send-command', '--document-name', 'AWS-RunShellScript',
        '--instance-ids', instance_id, '--parameters', json.dumps({'commands': [script]}))
    command_id = command['Command']['CommandId']
    invocation = None
    for attempt in range(30):
        time.sleep(2)
        invocation = aws('ssm', 'get-command-invocation', '--command-id', command_id, '--instance-id', instance_id)
        if invocation['Status'] in ['Success', 'Failed', 'Cancelled', 'TimedOut']:
            break
    assert invocation['Status'] == 'Success', invocation.get('StandardErrorContent')
    evidence = json.loads(invocation['StandardOutputContent'])
    assert evidence['order']['status'] == 'shipped' and evidence['item_count'] == 2 and evidence['event_published']
    for log_group in [outputs['application_log_group'], outputs['order_consumer_log_group']]:
        # La livraison des journaux peut être différée après la validation en base.
        for attempt in range(30):
            logs = aws('logs', 'filter-log-events', '--log-group-name', log_group,
                '--filter-pattern', '{ $.orderId = ' + str(created['order_id']) + ' }')
            if logs.get('events'):
                break
            if attempt == 29:
                raise AssertionError("Les journaux de commande sont absents de " + log_group)
            time.sleep(2)
    result = {'verified_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'phases': [1, 2, 3, 4], 'product_counts': counts, 'order': order,
        'direct_database_check': evidence, 'log_groups': [outputs['application_log_group'], outputs['order_consumer_log_group']]}
    target = ROOT / 'test-results'
    target.mkdir(exist_ok=True)
    (target / 'phase-1-4.json').write_text(json.dumps(result, indent=2) + '\n')
    print("OK : lecture directe RDS et journaux CloudWatch EC2/Lambda. Phases 1 à 4 validées.", flush=True)


if __name__ == '__main__':
    main()
