# Reproduction et cycle de vie

Pour partir d’un compte et d’une machine neufs, suivre le
[guide de déploiement](new-account.md), puis conserver la révision et les
résultats de validation obtenus dans votre compte.

Une reproduction depuis une autre machine dans un nouveau compte AWS indépendant
a été confirmée par l’équipe le 2 novembre 2026. Le
[compte rendu](evidence/2026-11-02-reproduction/README.md) précise la portée de cette
confirmation et la distingue des résultats automatisés archivés.

## Opérations de maintenance

```sh
node scripts/build.mjs
python3 scripts/terraform.py --profile TEAM_PROFILE init
python3 scripts/terraform.py --profile TEAM_PROFILE plan -detailed-exitcode
python3 scripts/terraform.py --profile TEAM_PROFILE destroy
python3 scripts/terraform.py --profile TEAM_PROFILE state list
```

Remplacer TEAM_PROFILE par votre profil IAM. Un plan sans changement retourne
0. La suppression retire les ressources applicatives gérées par cet état.
Le stockage d’état reste ; un audit et un budget préexistants restent aussi.
Une seule opération Terraform doit travailler sur un état à la fois.
Après un changement de compte, utiliser une copie propre et ne jamais migrer
l’état du compte précédent.

## Premier déploiement sans état

Un compte neuf ne possède pas encore de fichier d’état applicatif. Le script
reconnaît le diagnostic exact `No state file was found!` comme une liste vide.
Les erreurs IAM, de stockage et de verrouillage restent bloquantes. Ne jamais
créer un état fictif ou copier celui d’un autre compte.

### Récupération du déclencheur Lambda

Avec le fournisseur AWS 5.100.0 et les permissions IAM limitées aux ARN, la
lecture d’un déclencheur déjà supprimé peut renvoyer `AccessDenied` sur `*` au
lieu de `ResourceNotFound`. Le script `scripts/terraform.py` traite ce cas précis
pendant une suppression complète :

1. Avant la suppression, relever l’UUID et vérifier la cohérence du compte IAM,
   de la région, de la fonction, de la file et des étiquettes du projet dans l’état.
2. Reconnaître uniquement le diagnostic 403 de `GetEventSourceMapping` pour cet
   UUID ; toute autre erreur reste une erreur.
3. Exiger deux réponses AWS complètes, espacées de deux secondes, filtrées par
   l’ARN exact de la fonction et de la file, sans cet UUID.
4. Relire l’état, refuser un UUID modifié et retirer uniquement
   `module.messaging.aws_lambda_event_source_mapping.consumer`, en gardant le
   verrouillage Terraform. Reprendre la suppression une seule fois avec les
   mêmes options.

Une requête AWS en échec, une réponse incomplète ou un déclencheur encore présent
interrompt la récupération. Ne pas retirer manuellement une autre ressource de
l’état. Les suppressions partielles (`-target`), JSON (`-json`), sans verrouillage,
avec un état personnalisé ou avec des arguments injectés par `TF_CLI_ARGS*`
gardent le comportement Terraform ordinaire, sans cette récupération. L’appel
direct du binaire Terraform ne bénéficie pas non plus du script.

Le bilan `test-results/cleanup.json` contient les comptes de ressources, l’UUID
éventuellement retiré et le résultat, sans état complet ni identifiants AWS.
Le délai de libération des interfaces réseau privées de Lambda reste géré par
le fournisseur Terraform ; ce mécanisme ne contourne pas cette attente.

Le [banc AWS minimal](evidence/2026-10-29-cleanup/README.md) teste ce défaut avec
six ressources temporaires séparées de la boutique. Son exécution est volontaire
et ne fait pas partie des tests locaux :

```sh
python3 tests/live_cleanup.py --profile TEAM_PROFILE --expect-account ACCOUNT_ID
```

Il utilise un état local privé sous `.tools/`, conserve ce dossier en cas
d’échec, puis le retire après validation des inventaires AWS vides. Il exige un
état de boutique vide et ne modifie ni le stockage distant ni les autorisations
du profil de déploiement.

Références : [liste Lambda filtrée](https://docs.aws.amazon.com/lambda/latest/api/API_ListEventSourceMappings.html),
[format JSON public de Terraform](https://developer.hashicorp.com/terraform/internals/json-format)
et [effet de `state rm`](https://developer.hashicorp.com/terraform/cli/commands/state/rm).
