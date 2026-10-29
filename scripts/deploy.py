#!/usr/bin/env python3
"Compiler, planifier, déployer et vérifier VITALORA en une commande."
import argparse
import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def run(arguments, capture=False):
    result = subprocess.run(arguments, cwd=ROOT, check=True, text=True,
        stdout=subprocess.PIPE if capture else None)
    return result.stdout if capture else None


def main():
    parser = argparse.ArgumentParser(description=__doc__, add_help=False)
    parser._optionals.title = "Options"
    parser.add_argument("-h", "--help", action="help", help="Afficher cette aide et quitter.")
    parser.add_argument('--profile', default='vitalora')
    parser.add_argument('--region', default='eu-west-3')
    parser.add_argument('--expect-account', help="Arrêter si le profil appartient à un autre compte.")
    parser.add_argument('--yes', action='store_true', help="Appliquer le plan affiché sans confirmation interactive.")
    parser.add_argument('--verify', action='store_true', help="Vérifier la chaîne de commande et injecter une erreur de supervision contrôlée.")
    parser.add_argument('--require-empty', action='store_true', help="Exiger un état applicatif vide avant le déploiement.")
    parser.add_argument('--plan-only', action='store_true', help="Compiler et valider le plan sans déployer l’application.")
    options = parser.parse_args()
    os.umask(0o077)
    started = datetime.datetime.now(datetime.timezone.utc)
    identity = json.loads(run(['aws', '--profile', options.profile, '--region', options.region,
        'sts', 'get-caller-identity', '--output', 'json'], capture=True))
    if identity['Arn'].endswith(':root'):
        raise RuntimeError("Utiliser un profil IAM de déploiement. Root est réservé à l’initialisation des permissions.")
    if options.expect_account and options.expect_account != identity['Account']:
        raise RuntimeError("Le profil appartient à un autre compte ; aucun déploiement n’a commencé.")
    print(f'Compte de déploiement : {identity["Account"]} ; région : {options.region}.', flush=True)
    terraform = [sys.executable, str(ROOT / 'scripts/terraform.py'),
        '--profile', options.profile, '--region', options.region]
    run(['node', str(ROOT / 'scripts/build.mjs')])
    run(['node', '--test', str(ROOT / 'tests/pipeline.test.js')])
    run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_*.py'])
    run(terraform + ['init'])
    run(terraform + ['validate', '-no-color'])
    addresses = run(terraform + ['state', 'list'], capture=True).splitlines()
    managed = [address for address in addresses if not address.startswith('data.') and '.data.' not in address]
    if options.require_empty and managed:
        raise RuntimeError("Des ressources applicatives sont encore dans l’état Terraform. Terminer la suppression avant une reconstruction depuis un état vide.")
    tools = ROOT / '.tools'
    with tempfile.TemporaryDirectory(prefix='deployment-plan-', dir=tools) as directory:
        plan = str(Path(directory) / 'deployment.tfplan')
        run(terraform + ['plan', '-input=false', '-no-color', '-out=' + plan])
        if options.plan_only:
            print("Plan validé. Aucune ressource applicative n’a été déployée.", flush=True)
            return
        if not options.yes:
            answer = input(f'Appliquer ce plan au compte {identity["Account"]} ? [o/N] ')
            if answer.strip().lower() not in ['o', 'oui', 'y', 'yes']:
                print("Déploiement annulé. Aucune ressource applicative n’a été déployée.")
                return
        run(terraform + ['apply', '-input=false', '-no-color', plan])
    hostname = run(terraform + ['output', '-raw', 'alb_dns_name'], capture=True).strip()
    if options.verify:
        for script in ['verify.py', 'verify-monitoring.py']:
            run([sys.executable, str(ROOT / 'scripts' / script),
                '--profile', options.profile, '--region', options.region])
    else:
        print("Attente de la disponibilité du site et de la base…", flush=True)
        for attempt in range(120):
            try:
                with urllib.request.urlopen('http://' + hostname + '/ready', timeout=15) as response:
                    if json.load(response).get('status') == 'ready':
                        break
            except (urllib.error.URLError, TimeoutError):
                pass
            if attempt == 119:
                raise RuntimeError("L’infrastructure existe, mais le contrôle de disponibilité a échoué. Consulter les journaux applicatifs.")
            time.sleep(5)
    target = ROOT / 'test-results' / ('deployment-' + started.strftime('%Y%m%dT%H%M%SZ'))
    target.mkdir(parents=True, exist_ok=True)
    if options.verify:
        for name in ['phase-1-4.json', 'phase-5.json']:
            shutil.copy2(ROOT / 'test-results' / name, target / name)
    result = {
        'started_at': started.isoformat(),
        'completed_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'account': identity['Account'], 'region': options.region, 'actor': identity['Arn'],
        'started_with_empty_application_state': not managed,
        'full_verification_passed': options.verify, 'application_url': 'http://' + hostname + '/',
        'retained_account_baseline': ["Autorisations IAM de déploiement", "Stockage de l’état Terraform",
            "Audit et budget préexistants du projet"],
    }
    (target / 'deployment.json').write_text(json.dumps(result, indent=2) + '\n')
    print("Site prêt : http://" + hostname + '/', flush=True)
    print("Dossier de validation : " + str(target), flush=True)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, EOFError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
