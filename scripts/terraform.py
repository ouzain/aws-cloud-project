#!/usr/bin/env python3
"Exécuter Terraform avec des identifiants temporaires et un état propre au compte."
import argparse
import datetime
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import shutil
import shlex
import subprocess
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ENVIRONMENT = ROOT / 'envs' / 'vm-based'
VERSION = '1.13.5'


def aws(profile, *arguments):
    result = subprocess.run(['aws', '--profile', profile, *arguments], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return result.stdout


def terraform_binary():
    existing = os.environ.get('TERRAFORM_BIN') or shutil.which('terraform')
    if existing:
        return existing
    system = {'Darwin': 'darwin', 'Linux': 'linux', 'Windows': 'windows'}[platform.system()]
    architecture = 'arm64' if platform.machine().lower() in ['arm64', 'aarch64'] else 'amd64'
    executable = 'terraform.exe' if system == 'windows' else 'terraform'
    target = ROOT / '.tools' / executable
    if not target.exists():
        target.parent.mkdir(exist_ok=True)
        filename = f'terraform_{VERSION}_{system}_{architecture}.zip'
        base = f'https://releases.hashicorp.com/terraform/{VERSION}/'
        payload = urllib.request.urlopen(base + filename).read()
        checksums = urllib.request.urlopen(base + f'terraform_{VERSION}_SHA256SUMS').read().decode()
        expected = next(line.split()[0] for line in checksums.splitlines() if line.split()[1].lstrip('*') == filename)
        if hashlib.sha256(payload).hexdigest() != expected:
            raise RuntimeError("La somme de contrôle du téléchargement Terraform est invalide.")
        target.write_bytes(zipfile.ZipFile(io.BytesIO(payload)).read(executable))
        target.chmod(0o755)
    return str(target)


def governance_settings(trails, budgets, managed_addresses):
    "Réutiliser la gouvernance externe sans abandonner les ressources de cet état."
    owns_trail = 'module.monitoring.aws_cloudtrail.management[0]' in managed_addresses
    owns_budget = 'module.monitoring.aws_budgets_budget.monthly[0]' in managed_addresses
    return {
        'existing_audit_trail_name': None if owns_trail else next(
            (item['Name'] for item in trails if item['Name'].startswith('vitalora-')), None),
        'existing_budget_name': None if owns_budget else next(
            (item['BudgetName'] for item in budgets if item['BudgetName'].startswith('vitalora-')), None),
    }


def state_addresses(binary, directory, environment):
    """Un stockage neuf n’a pas encore d’état ; une erreur d’accès reste bloquante."""
    result = subprocess.run([binary, 'state', 'list', '-no-color'], cwd=directory,
        env=environment, capture_output=True, text=True)
    if result.returncode == 0:
        return result.stdout.splitlines()
    missing_state = (
        'No state file was found! '
        'State management commands require a state file. Run this command '
        'in a directory where Terraform has been run or use the -state flag '
        'to point the command to a specific state location.')
    if (result.returncode == 1 and not result.stdout.strip()
            and ' '.join(result.stderr.split()) == missing_state):
        return []
    raise RuntimeError(result.stderr.strip() or 'Impossible de lire l’état Terraform.')


def initialize_backend(profile, region, account, binary, environment):
    bucket = f'tfstate-vitalora-{account}-{region}'
    buckets = json.loads(aws(profile, 's3api', 'list-buckets', '--output', 'json'))['Buckets']
    if bucket not in [item['Name'] for item in buckets]:
        arguments = ['s3api', 'create-bucket', '--bucket', bucket, '--region', region]
        if region != 'us-east-1':
            arguments += ['--create-bucket-configuration', f'LocationConstraint={region}']
        aws(profile, *arguments)
    # Reprendre aussi une initialisation interrompue après la création du bucket.
    aws(profile, 's3api', 'put-bucket-versioning', '--bucket', bucket,
        '--versioning-configuration', 'Status=Enabled')
    aws(profile, 's3api', 'put-public-access-block', '--bucket', bucket,
        '--public-access-block-configuration',
        'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true')
    aws(profile, 's3api', 'put-bucket-encryption', '--bucket', bucket,
        '--server-side-encryption-configuration',
        '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}')
    subprocess.run([binary, 'init', '-input=false', '-no-color', '-reconfigure',
        f'-backend-config=bucket={bucket}', '-backend-config=key=hybrid/terraform.tfstate',
        f'-backend-config=region={region}', '-backend-config=encrypt=true', '-backend-config=use_lockfile=true'],
        cwd=ENVIRONMENT, env=environment, check=True)
    managed = state_addresses(binary, ENVIRONMENT, environment)
    trails = json.loads(aws(profile, 'cloudtrail', 'describe-trails', '--no-include-shadow-trails',
        '--region', region))['trailList']
    budgets = json.loads(aws(profile, 'budgets', 'describe-budgets', '--account-id', account, '--region', 'us-east-1'))['Budgets']
    names = governance_settings(trails, budgets, managed)
    (ENVIRONMENT / 'governance.auto.tfvars.json').write_text(json.dumps(names, indent=2) + '\n')


def terraform_environment(profile, region):
    """Préparer le relais d’identifiants sans changer le compte ni créer de ressources."""
    environment = os.environ.copy()
    for variable in ['AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_SESSION_TOKEN', 'AWS_SECURITY_TOKEN']:
        environment.pop(variable, None)
    original_config = os.environ.get('AWS_CONFIG_FILE', str(Path.home() / '.aws/config'))
    original_credentials = os.environ.get('AWS_SHARED_CREDENTIALS_FILE', str(Path.home() / '.aws/credentials'))
    tools = ROOT / '.tools'
    tools.mkdir(exist_ok=True)
    process_arguments = [sys.executable, str(Path(__file__).resolve()), '--profile', profile,
        '--credential-process', '--source-config', original_config, '--source-credentials', original_credentials]
    process = subprocess.list2cmdline(process_arguments) if os.name == 'nt' else shlex.join(process_arguments)
    bridge_id = hashlib.sha256((profile + region + original_config).encode()).hexdigest()[:12]
    bridge = tools / ('aws-config-' + bridge_id)
    temporary_bridge = bridge.with_name(bridge.name + '-' + str(os.getpid()) + '.tmp')
    temporary_bridge.write_text(f'[profile terraform-session]\nregion = {region}\ncredential_process = {process}\n')
    temporary_bridge.replace(bridge)
    empty_credentials = tools / 'empty-credentials'
    empty_credentials.write_text('')
    environment.update(AWS_CONFIG_FILE=str(bridge), AWS_SHARED_CREDENTIALS_FILE=str(empty_credentials),
        AWS_PROFILE='terraform-session', AWS_SDK_LOAD_CONFIG='1')
    environment.update(AWS_REGION=region, AWS_DEFAULT_REGION=region,
        TF_VAR_aws_region=region, TF_VAR_aws_profile='terraform-session')
    cache = ROOT / '.tools' / 'plugin-cache'
    cache.mkdir(parents=True, exist_ok=True)
    environment['TF_PLUGIN_CACHE_DIR'] = str(cache)
    return environment


def main():
    parser = argparse.ArgumentParser(description=__doc__, add_help=False)
    parser._optionals.title = "Options"
    parser.add_argument("-h", "--help", action="help", help="Afficher cette aide et quitter.")
    parser.add_argument('--profile', default='vitalora')
    parser.add_argument('--region', default='eu-west-3')
    parser.add_argument('--credential-process', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--source-config', help=argparse.SUPPRESS)
    parser.add_argument('--source-credentials', help=argparse.SUPPRESS)
    options, arguments = parser.parse_known_args()
    if options.credential_process:
        source_environment = os.environ.copy()
        source_environment['AWS_CONFIG_FILE'] = options.source_config
        source_environment['AWS_SHARED_CREDENTIALS_FILE'] = options.source_credentials
        raise SystemExit(subprocess.run(['aws', '--profile', options.profile, 'configure',
            'export-credentials', '--format', 'process'], env=source_environment).returncode)
    if options.region != 'eu-west-3':
        raise RuntimeError('Région prise en charge par cette démonstration : eu-west-3.')
    if not arguments:
        parser.error("Indiquer une commande Terraform, par exemple plan, apply, output ou destroy.")
    if arguments[0] in ['apply', 'destroy', 'import']:
        identity = json.loads(aws(options.profile, '--region', options.region, 'sts', 'get-caller-identity'))
        if identity['Arn'].endswith(':root'):
            raise RuntimeError("Utiliser un profil IAM pour modifier l’infrastructure. Root est réservé à l’initialisation des permissions.")
    os.umask(0o077)
    binary = terraform_binary()
    environment = terraform_environment(options.profile, options.region)
    if arguments[0] == 'init':
        account = json.loads(aws(options.profile, 'sts', 'get-caller-identity'))['Account']
        initialize_backend(options.profile, options.region, account, binary, environment)
        return
    if arguments[0] not in ['fmt', 'validate', 'version', 'providers'] and not (ENVIRONMENT / '.terraform/terraform.tfstate').exists():
        account = json.loads(aws(options.profile, 'sts', 'get-caller-identity'))['Account']
        initialize_backend(options.profile, options.region, account, binary, environment)
    if arguments == ['state', 'list']:
        addresses = state_addresses(binary, ENVIRONMENT, environment)
        if addresses:
            print('\n'.join(addresses))
        return
    from _terraform_cleanup import TerraformCleanupCLI, destroy_with_recovery, recovery_options_supported
    if recovery_options_supported(arguments, environment):

        def describe(target):
            return json.loads(aws(options.profile, '--region', options.region, 'lambda',
                'list-event-source-mappings', '--function-name', target.function_arn,
                '--event-source-arn', target.source_arn, '--output', 'json'))

        record = destroy_with_recovery(TerraformCleanupCLI(binary, ENVIRONMENT, environment),
            arguments, identity, options.region, describe)
        record.update(compte=identity['Account'], region=options.region,
            verifie_le=datetime.datetime.now(datetime.timezone.utc).isoformat())
        target = ROOT / 'test-results'
        target.mkdir(exist_ok=True)
        (target / 'cleanup.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
        raise SystemExit(record['code_retour'])
    raise SystemExit(subprocess.run([binary, *arguments], cwd=ENVIRONMENT, env=environment).returncode)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
