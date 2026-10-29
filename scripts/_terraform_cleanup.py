"""Reprendre une suppression après le seul défaut de lecture Lambda connu."""
from dataclasses import dataclass
import json
import re
import subprocess
import sys
import time
import uuid

MAPPING_ADDRESS = 'module.messaging.aws_lambda_event_source_mapping.consumer'
FUNCTION_ADDRESS = 'module.messaging.aws_lambda_function.consumer'
QUEUE_ADDRESS = 'module.messaging.aws_sqs_queue.order_processing'


def recovery_options_supported(arguments, environment):
    """Conserver le comportement Terraform pour les suppressions partielles ou personnalisées."""
    if not arguments or arguments[0] != 'destroy':
        return False
    if any(environment.get(key) for key in (
            'TF_CLI_ARGS', 'TF_CLI_ARGS_destroy', 'TF_CLI_ARGS_show', 'TF_CLI_ARGS_state')):
        return False
    for argument in arguments[1:]:
        flag, _, value = argument.partition('=')
        if flag in {'-target', '-json', '-state', '-state-out', '-backup', '-help', '--help'}:
            return False
        if flag == '-lock' and value.lower() not in {'true', '1', 't'}:
            return False
    return True


@dataclass(frozen=True)
class MappingTarget:
    identifier: str
    function_arn: str
    source_arn: str
    project: str


def managed_resources(state):
    """Lire le format public de terraform show, sans afficher son contenu sensible."""
    if not isinstance(state, dict):
        raise RuntimeError('État JSON Terraform invalide ; récupération refusée.')
    version = state.get('format_version', '')
    if not isinstance(version, str) or version.split('.')[0] != '1':
        raise RuntimeError('Format JSON Terraform non reconnu ; récupération refusée.')
    found = {}

    def visit(module):
        if (not isinstance(module, dict) or not isinstance(module.get('resources', []), list)
                or not isinstance(module.get('child_modules', []), list)):
            raise RuntimeError('Structure de l’état Terraform invalide ; récupération refusée.')
        for resource in module.get('resources', []):
            if not isinstance(resource, dict):
                raise RuntimeError('Ressource Terraform invalide ; récupération refusée.')
            if resource.get('mode') == 'managed':
                address = resource.get('address')
                if not isinstance(address, str) or not address or address in found:
                    raise RuntimeError('Adresse Terraform ambiguë ; récupération refusée.')
                found[address] = resource
        for child in module.get('child_modules', []):
            visit(child)

    values = state.get('values', {})
    if not isinstance(values, dict):
        raise RuntimeError('Valeurs de l’état Terraform invalides ; récupération refusée.')
    visit(values.get('root_module', {}))
    return found


def require(condition):
    # Ne pas utiliser assert : les contrôles doivent rester actifs avec python -O.
    if not condition:
        raise ValueError('Contrôle de cohérence non satisfait.')


def mapping_target(state, identity, region):
    resources = managed_resources(state)
    if MAPPING_ADDRESS not in resources:
        return None
    try:
        mapping = resources[MAPPING_ADDRESS]
        function = resources[FUNCTION_ADDRESS]
        queue = resources[QUEUE_ADDRESS]
        require(mapping['type'] == 'aws_lambda_event_source_mapping')
        require(function['type'] == 'aws_lambda_function')
        require(queue['type'] == 'aws_sqs_queue')
        values, function_values, queue_values = mapping['values'], function['values'], queue['values']
        identifier = values['id']
        require(str(uuid.UUID(identifier)) == identifier)
        function_arn, source_arn = values['function_name'], values['event_source_arn']
        require(function_arn == function_values['arn'])
        require(source_arn == queue_values['arn'])
        account = identity['Account']
        require(re.fullmatch(r'\d{12}', account))
        principal = identity['Arn'].split(':', 5)
        require(principal[0] == 'arn' and principal[4] == account and not identity['Arn'].endswith(':root'))
        function_name = function_values['function_name']
        require(function_name.endswith('-order-processor'))
        project = function_name[:-len('-order-processor')]
        require(project and queue_values['name'] == project + '-order-processing')
        require(function_values['tags_all']['Project'] == project)
        require(queue_values['tags_all']['Project'] == project)
        require(function_arn == f'arn:{principal[1]}:lambda:{region}:{account}:function:{function_name}')
        require(source_arn == f'arn:{principal[1]}:sqs:{region}:{account}:{queue_values["name"]}')
        return MappingTarget(identifier, function_arn, source_arn, project)
    except (AttributeError, KeyError, TypeError, ValueError, IndexError):
        raise RuntimeError('Identité, fonction, file ou UUID incohérent dans l’état ; récupération refusée.') from None


def is_deleted_mapping_error(stderr, target):
    """Ne reconnaître que les diagnostics du UUID prévu et de GetEventSourceMapping."""
    text = stderr.strip()
    if not text.startswith('Error:'):
        return False
    errors = re.split(r'(?m)^Error:', text)[1:]
    header = rf'^\s*(?:waiting for|reading) Lambda Event Source Mapping \({re.escape(target.identifier)}\)(?: delete)?:'
    return bool(errors) and all(
        re.search(header, error) and 'GetEventSourceMapping' in error
        and 'AccessDeniedException' in error and 'StatusCode: 403' in error
        for error in errors)


def confirm_absence(describe, target, sleep=time.sleep):
    """Exiger deux listes complètes concordantes ; une erreur ne signifie jamais absent."""
    for attempt in range(2):
        response = describe(target)
        if (not isinstance(response, dict) or response.get('NextMarker')
                or response.get('NextToken') or not isinstance(response.get('EventSourceMappings'), list)):
            raise RuntimeError('Réponse Lambda incomplète ; aucune entrée d’état ne sera retirée.')
        for item in response['EventSourceMappings']:
            if (not isinstance(item, dict) or not item.get('UUID')
                    or item.get('FunctionArn') != target.function_arn
                    or item.get('EventSourceArn') != target.source_arn):
                raise RuntimeError('Liste Lambda incohérente ; aucune entrée d’état ne sera retirée.')
            if item['UUID'] == target.identifier:
                raise RuntimeError('Le déclencheur existe encore ; aucune entrée d’état ne sera retirée.')
        if attempt == 0:
            sleep(2)


class TerraformCleanupCLI:
    def __init__(self, binary, directory, environment):
        self.binary, self.directory, self.environment = binary, directory, environment

    def state(self):
        result = subprocess.run([self.binary, 'show', '-json'], cwd=self.directory,
            env=self.environment, capture_output=True, text=True, check=True)
        return json.loads(result.stdout)

    def destroy(self, arguments):
        command = [self.binary, *arguments]
        if '-no-color' not in arguments:
            command.append('-no-color')
        result = subprocess.run(command, cwd=self.directory, env=self.environment,
            stderr=subprocess.PIPE, text=True)
        if result.stderr:
            sys.stderr.write(result.stderr)
        return result

    def forget_deleted_mapping(self):
        # Conserver le verrouillage, échouer immédiatement si l’état est occupé.
        subprocess.run([self.binary, 'state', 'rm', '-lock-timeout=0s', MAPPING_ADDRESS],
            cwd=self.directory, env=self.environment, check=True)


def destroy_with_recovery(cli, arguments, identity, region, describe, sleep=time.sleep):
    """Limiter la récupération à une entrée supprimée et à une seule reprise."""
    initial = cli.state()
    target = mapping_target(initial, identity, region)
    record = {'ressources_initiales': len(managed_resources(initial)),
        'recuperation_automatique': False, 'entree_retiree': False, 'verifications_absence': 0}
    result = cli.destroy(arguments)
    if result.returncode == 1 and target and is_deleted_mapping_error(result.stderr or '', target):
        print('Contrôle du déclencheur Lambda déjà supprimé : deux vérifications AWS ciblées…', flush=True)
        confirm_absence(describe, target, sleep)
        current = mapping_target(cli.state(), identity, region)
        if current is not None and current != target:
            raise RuntimeError('Le déclencheur a changé pendant la suppression ; récupération refusée.')
        record.update(recuperation_automatique=True, verifications_absence=2,
            adresse=MAPPING_ADDRESS, uuid=target.identifier)
        if current is not None:
            cli.forget_deleted_mapping()
            record['entree_retiree'] = True
            if MAPPING_ADDRESS in managed_resources(cli.state()):
                raise RuntimeError('L’entrée reste présente après la récupération ; arrêt de sécurité.')
        print('Absence confirmée. Reprise de la suppression avec les mêmes options.', flush=True)
        result = cli.destroy(arguments)
    record['code_retour'] = result.returncode
    if result.returncode == 0:
        remaining = managed_resources(cli.state())
        record.update(ressources_restantes=len(remaining), etat_applicatif_vide=not remaining)
        if remaining:
            raise RuntimeError('Terraform a terminé, mais des ressources applicatives restent dans l’état.')
    return record
