#!/usr/bin/env python3
"""Préparer les permissions d’un compte neuf ; aucune modification sans --apply."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def render_policies(account, region):
    if not re.fullmatch(r'[0-9]{12}', account) or region != 'eu-west-3':
        raise RuntimeError('Compte de 12 chiffres requis ; région prise en charge : eu-west-3.')
    policies = {}
    for source in sorted((ROOT / 'ops/iam/templates').glob('*.json')):
        text = source.read_text().replace('${ACCOUNT_ID}', account).replace('${REGION}', region)
        if '${' in text:
            raise RuntimeError('Paramètre non résolu dans ' + source.name)
        document = json.loads(text)
        compact = json.dumps(document, separators=(',', ':'))
        if len(compact) > 6144:
            raise RuntimeError('Politique trop volumineuse : ' + source.name)
        policies[source.stem] = document
    if len(policies) != 5:
        raise RuntimeError('Les cinq modèles de permissions sont requis.')
    return policies


def aws(profile, region, *arguments):
    result = subprocess.run(['aws', '--profile', profile, '--region', region, *arguments,
        '--output', 'json'], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return json.loads(result.stdout) if result.stdout.strip() else {}


def install_policies(call, account, policies, user=None, role=None):
    # Résoudre le destinataire avant toute écriture ; ne créer aucun identifiant.
    kind, name = ('user', user) if user else ('role', role)
    target = call('iam', 'get-' + kind, '--' + kind + '-name', name)[kind.title()]
    if target['Arn'].split(':')[4] != account:
        raise RuntimeError('Le destinataire appartient à un autre compte.')
    # Valider toutes les politiques avant de créer ou attacher la première.
    for document in policies.values():
        findings = call('accessanalyzer', 'validate-policy', '--policy-type', 'IDENTITY_POLICY',
            '--policy-document', json.dumps(document))['findings']
        if any(item['findingType'] in ['ERROR', 'SECURITY_WARNING'] for item in findings):
            raise RuntimeError('Validation IAM refusée ; revoir les politiques avant application.')
    existing = {item['Arn']: item for item in call('iam', 'list-policies', '--scope', 'Local',
        '--path-prefix', '/vitalora/')['Policies']}
    # Refuser les mises à jour implicites de politiques déjà attachées ailleurs.
    for name, document in policies.items():
        arn = f'arn:aws:iam::{account}:policy/vitalora/{name}'
        if arn in existing:
            current = call('iam', 'get-policy-version', '--policy-arn', arn,
                '--version-id', existing[arn]['DefaultVersionId'])['PolicyVersion']['Document']
            if current != document:
                raise RuntimeError('Politique existante différente, mise à jour manuelle requise : ' + arn)
    for name, document in policies.items():
        arn = f'arn:aws:iam::{account}:policy/vitalora/{name}'
        if arn not in existing:
            call('iam', 'create-policy', '--path', '/vitalora/', '--policy-name', name,
                '--policy-document', json.dumps(document))
        call('iam', 'attach-' + kind + '-policy', '--' + kind + '-name',
            user if user else role, '--policy-arn', arn)
    return target['Arn']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--account-id', required=True)
    parser.add_argument('--region', default='eu-west-3')
    parser.add_argument('--output-dir', type=Path)
    parser.add_argument('--admin-profile', help='Profil du propriétaire autorisé à gérer IAM.')
    parser.add_argument('--apply', action='store_true', help='Valider, créer et attacher les politiques générées.')
    target = parser.add_mutually_exclusive_group()
    target.add_argument('--user-name')
    target.add_argument('--role-name')
    options = parser.parse_args()
    os.umask(0o077)
    policies = render_policies(options.account_id, options.region)
    directory = options.output_dir or ROOT / '.tools' / ('iam-' + options.account_id)
    directory.mkdir(parents=True, exist_ok=True)
    hashes = {}
    for name, document in policies.items():
        filename = directory / (name + '.json')
        filename.write_text(json.dumps(document, indent=2) + '\n')
        hashes[name] = hashlib.sha256(filename.read_bytes()).hexdigest()
    (directory / 'manifest.json').write_text(json.dumps({'account': options.account_id,
        'region': options.region, 'sha256': hashes}, indent=2) + '\n')
    print('Politiques à revoir : ' + str(directory), flush=True)
    if not options.apply:
        print('Génération locale uniquement ; aucune ressource AWS modifiée.')
        return
    if not options.admin_profile or not (options.user_name or options.role_name):
        parser.error('--apply exige --admin-profile et --user-name ou --role-name.')
    call = lambda *arguments: aws(options.admin_profile, options.region, *arguments)
    identity = call('sts', 'get-caller-identity')
    if identity['Account'] != options.account_id:
        raise RuntimeError('Le profil administrateur appartient à un autre compte ; arrêt.')
    arn = install_policies(call, options.account_id, policies, options.user_name, options.role_name)
    print('Permissions attachées à ' + arn + '. Aucun utilisateur ni clé d’accès créé.')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
