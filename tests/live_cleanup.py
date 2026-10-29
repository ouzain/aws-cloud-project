#!/usr/bin/env python3
"""Créer puis supprimer un banc AWS minimal pour vérifier la récupération réelle."""
import argparse
import datetime
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from _terraform_cleanup import TerraformCleanupCLI, destroy_with_recovery, managed_resources

spec = importlib.util.spec_from_file_location('terraform_helper', ROOT / 'scripts/terraform.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


def main():
    parser = argparse.ArgumentParser(description=__doc__, add_help=False)
    parser._optionals.title = 'Options'
    parser.add_argument('-h', '--help', action='help', help='Afficher cette aide et quitter.')
    parser.add_argument('--profile', default='vitalora', help='Profil IAM déjà autorisé.')
    parser.add_argument('--region', default='eu-west-3', help='Région du banc temporaire.')
    parser.add_argument('--expect-account', required=True, help='Compte AWS attendu, obligatoire.')
    options = parser.parse_args()
    os.umask(0o077)
    identity = json.loads(helper.aws(options.profile, '--region', options.region,
        'sts', 'get-caller-identity', '--output', 'json'))
    if identity['Account'] != options.expect_account or identity['Arn'].endswith(':root'):
        raise RuntimeError('Compte inattendu ou profil root ; aucune ressource ne sera créée.')

    binary = helper.terraform_binary()
    environment = helper.terraform_environment(options.profile, options.region)
    # Garder l’état de la boutique séparé ; ne jamais modifier son stockage distant.
    production = TerraformCleanupCLI(binary, helper.ENVIRONMENT, environment)
    if managed_resources(production.state()):
        raise RuntimeError('Le banc exige un état applicatif vide ; boutique existante conservée.')
    project = 'vitalora-cleanup-' + uuid.uuid4().hex[:10]
    directory = ROOT / '.tools' / project
    shutil.copytree(ROOT / 'tests/fixtures/cleanup', directory)
    shutil.copy2(helper.ENVIRONMENT / '.terraform.lock.hcl', directory / '.terraform.lock.hcl')
    with zipfile.ZipFile(directory / 'worker.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('index.js', 'exports.handler = async () => ({ batchItemFailures: [] });\n')
    environment['TF_VAR_project_name'] = project
    cli = TerraformCleanupCLI(binary, directory, environment)
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    print(f'Banc isolé : {project}. État privé conservé dans {directory} en cas d’échec.', flush=True)

    def describe(target):
        return json.loads(helper.aws(options.profile, '--region', options.region, 'lambda',
            'list-event-source-mappings', '--function-name', target.function_arn,
            '--event-source-arn', target.source_arn, '--output', 'json'))

    arguments = ['destroy', '-auto-approve', '-input=false']
    initialized = False
    cleanup_started = False
    try:
        subprocess.run([binary, 'init', '-input=false', '-no-color'], cwd=directory,
            env=environment, check=True)
        initialized = True
        subprocess.run([binary, 'validate', '-no-color'], cwd=directory, env=environment, check=True)
        subprocess.run([binary, 'apply', '-auto-approve', '-input=false', '-no-color'],
            cwd=directory, env=environment, check=True)
        cleanup_started = True
        result = destroy_with_recovery(cli, arguments, identity, options.region, describe)
        if result['code_retour'] != 0:
            raise RuntimeError('La suppression du banc a échoué ; état privé conservé.')
        repeated = destroy_with_recovery(cli, arguments, identity, options.region, describe)
        if repeated['code_retour'] != 0:
            raise RuntimeError('La seconde suppression vide a échoué.')
        # Conserver le résultat intermédiaire si l’inventaire AWS devient indisponible.
        (directory / 'cleanup-progress.json').write_text(json.dumps({
            'demarre_le': started, 'projet_temporaire': project,
            'suppression': result, 'deuxieme_suppression': repeated}, ensure_ascii=False, indent=2) + '\n')

        # Contrôler les ressources exactes, sans déduire leur absence d’un refus IAM.
        for service, operation, name_option, name, missing_code in [
            ('lambda', 'get-function', '--function-name', project + '-order-processor', 'ResourceNotFoundException'),
            ('iam', 'get-role', '--role-name', project + '-order-processor-role', 'NoSuchEntity')]:
            response = subprocess.run(['aws', '--profile', options.profile, '--region', options.region,
                service, operation, name_option, name], capture_output=True, text=True)
            if response.returncode != 254 or f'({missing_code})' not in response.stderr:
                raise RuntimeError(f'Absence de {service} non confirmée ; état privé conservé.')
        queues = json.loads(helper.aws(options.profile, '--region', options.region,
            'sqs', 'list-queues', '--queue-name-prefix', project,
            '--query', '{QueueUrls: QueueUrls, NextToken: NextToken}', '--output', 'json'))
        if (not isinstance(queues, dict) or 'QueueUrls' not in queues
                or queues['QueueUrls'] not in (None, []) or queues.get('NextToken')):
            raise RuntimeError('Une file du banc reste présente ou la réponse est incomplète.')
        logs = json.loads(helper.aws(options.profile, '--region', options.region, 'logs',
            'describe-log-groups', '--log-group-name-prefix', '/aws/lambda/' + project, '--output', 'json'))
        if 'logGroups' not in logs or logs['logGroups'] or logs.get('nextToken'):
            raise RuntimeError('Un groupe de journaux du banc reste présent ou la réponse est incomplète.')
        if managed_resources(production.state()):
            raise RuntimeError('L’état de la boutique a changé ; arrêter toute autre opération.')

        result.update(compte=identity['Account'], principal=identity['Arn'], region=options.region,
            projet_temporaire=project, demarre_le=started,
            termine_le=datetime.datetime.now(datetime.timezone.utc).isoformat(),
            version_fournisseur_aws='5.100.0', deuxieme_suppression=repeated,
            absences_aws={'lambda': True, 'sqs': True, 'role_iam': True, 'groupe_journaux': True},
            etat_boutique_reste_vide=True,
            portee='Banc Lambda/SQS isolé ; aucune validation fonctionnelle de la boutique.',
            resultat='PASS' if result['recuperation_automatique'] else 'NON_REPRODUIT')
        results = ROOT / 'test-results'
        results.mkdir(exist_ok=True)
        (results / 'cleanup-live.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
        shutil.rmtree(directory)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        if not result['recuperation_automatique']:
            raise RuntimeError('Nettoyage réussi, mais défaut Lambda non reproduit ; récupération non certifiée.')
    except (RuntimeError, subprocess.CalledProcessError, json.JSONDecodeError):
        if initialized and not cleanup_started:
            print('Échec du déploiement du banc : tentative de nettoyage du seul banc.', flush=True)
            destroy_with_recovery(cli, arguments, identity, options.region, describe)
        raise


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
