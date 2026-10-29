# Reproduction du déploiement

## Reconstruction dans le compte actuel

Attendre la fin de la suppression précédente et vérifier que l’état applicatif
est vide. Une commande compile, déploie et contrôle un nouvel environnement :

```sh
python3 scripts/deploy.py --profile vitalora --expect-account 573199225243 --require-empty --yes --verify
```

Le script installe les dépendances verrouillées, prépare le paquet Node.js,
exécute les tests locaux, initialise le stockage de l’état, valide et affiche
le plan Terraform, l’applique puis vérifie les phases 1 à 5. Il supprime son
plan temporaire sensible et conserve les résultats dans `test-results/`.
Aucune création manuelle de ressource dans la console n’a été nécessaire lors
de la reconstruction déjà vérifiée.

Pour un déploiement ou une mise à jour ordinaires, omettre `--require-empty`.
Sans `--verify`, le script attend seulement que l’application et la base soient
prêtes, sans commandes fictives ni injection d’erreur. Sans `--yes`, une
confirmation est demandée après affichage du plan. `--plan-only` ne déploie pas
l’application ; l’initialisation peut créer le compartiment d’état s’il manque.

Le profil IAM doit être connecté et autorisé. Les autorisations, l’état distant
et les éventuels audit/budget préexistants constituent le socle conservé. Cette
reconstruction prouve la répétabilité dans ce compte, sans valider un autre
compte AWS. Une nouvelle langue d’interface ne transforme pas les preuves
historiques en preuves d’un nouveau déploiement.

## Exigence des comptes indépendants

La phase 6 de la feuille de route prévoit que chaque membre déploie la même révision dans
son propre compte. Une reconstruction ou un plan sans changement dans un seul
compte ne remplace pas ce contrôle. Si l’équipe choisit un périmètre limité au
compte actuel, elle doit mettre à jour ce critère de la feuille de route.

### Préparer le code et le profil

1. Partager une révision revue contenant les corrections et les fichiers de
   verrouillage npm/Terraform. La branche `feat/hybrid-validation-fr` regroupe le code et les preuves AWS.
   Après intégration, utiliser la révision retenue par l’équipe et noter son SHA.
2. Installer Node.js 22+, npm, Python 3.9+ et AWS CLI. Le script peut télécharger
   Terraform 1.13.5 avec vérification de sa somme de contrôle.
3. Se connecter avec le profil IAM du membre et vérifier le compte :
   `aws --profile TEAM_PROFILE sts get-caller-identity`.
   Root est réservé à l’initialisation des autorisations approuvées par le
   propriétaire ; le déploiement utilise le profil IAM.
4. Revoir les permissions du nouveau compte. Les politiques `ops/iam/` ciblent
   le compte actuel et complètent un socle d’audit/budget existant. Un compte
   neuf doit aussi autoriser la création/suppression de son audit, de son budget,
   de son stockage d’état et la lecture de ses journaux d’audit. Le propriétaire
   doit approuver ces droits avant le déploiement.

Utiliser une copie propre du dépôt sur chaque machine. Ne pas copier les
identifiants d’un autre membre, `.tools/`, `.terraform/`, l’état, les plans,
les paramètres de gouvernance générés ou les fichiers `.tfvars` privés.
Après un changement de compte dans une copie existante, exécuter explicitement
`init`. Ne pas déployer simultanément deux comptes depuis la même copie.
Une seule opération Terraform doit travailler sur un même état à la fois.

### Configurer et déployer

Copier `envs/vm-based/terraform.tfvars.example` vers
`envs/vm-based/terraform.tfvars`. Renseigner une adresse appartenant au titulaire
du compte dans `budget_alert_email` en l’absence de budget VITALORA préexistant.
Conserver `project_name = "vitalora"` et `eu-west-3` pour les scripts de contrôle
de l’équipe. Les notifications de commande par e-mail sont désactivées par défaut.

Remplacer `TEAM_PROFILE` par le vrai nom du profil :

```sh
python3 scripts/deploy.py --profile TEAM_PROFILE --yes --verify
```

Les étapes séparées sont également disponibles :

```sh
node scripts/build.mjs
npm test --prefix app
python3 -m unittest discover -s tests -p 'test_*.py'
python3 scripts/terraform.py --profile TEAM_PROFILE init
python3 scripts/terraform.py --profile TEAM_PROFILE validate
python3 scripts/terraform.py --profile TEAM_PROFILE plan -out=deployment.tfplan
python3 scripts/terraform.py --profile TEAM_PROFILE apply deployment.tfplan
python3 scripts/verify.py --profile TEAM_PROFILE
python3 scripts/verify-monitoring.py --profile TEAM_PROFILE
```

L’état utilise `tfstate-vitalora-ACCOUNT_ID-eu-west-3`, chiffré, versionné et
verrouillé par S3. `init` reconfigure ce stockage sans migrer l’état d’un autre
compte. Il détecte les ressources de gouvernance externes et conserve celles
que l’état gère déjà. Les identifiants temporaires AWS CLI sont actualisables.

Pour un nouveau journal CloudTrail, laisser le temps aux premiers événements
de gestion du projet d’être livrés avant le contrôle de supervision. Ce contrôle
injecte volontairement un message fictif invalide : une alarme est attendue.
Les images restent privées et utilisent des URL présignées.

### Vérifier la répétabilité et nettoyer

```sh
node scripts/build.mjs
python3 scripts/terraform.py --profile TEAM_PROFILE plan -detailed-exitcode
python3 scripts/terraform.py --profile TEAM_PROFILE init
python3 scripts/terraform.py --profile TEAM_PROFILE plan -detailed-exitcode
python3 scripts/terraform.py --profile TEAM_PROFILE destroy
```

Les deux plans doivent retourner 0 et ne signaler aucun changement. Conserver
les deux résultats JSON de `test-results/`, le compte, la région, la révision,
les dates, les plans sans changement et la confirmation de suppression. Ne pas
partager un état complet, un plan sensible, un mot de passe, des identifiants
exportés ou des journaux d’audit privés bruts.

La suppression retire la base, les commandes, images, files, calcul et
supervision gérés par ce déploiement. Le compartiment d’état indépendant reste.
La gouvernance préexistante est conservée ; celle créée par cet état est
supprimée avec l’environnement. Noter séparément les ressources conservées.

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

### Bilan de validation

| Environnement | Fonctionnel et supervision | Recompilation et réinitialisation | Suppression |
| --- | --- | --- | --- |
| Compte 573199225243, eu-west-3 | Deux exécutions réussies le 29/10/2026, dont une depuis un état vide | Réussies | Deux environnements entièrement supprimés |
| Autres comptes indépendants | Accès du propriétaire ou preuves des membres attendus | À vérifier | À vérifier |

La validation multi-compte reste ouverte selon le périmètre initial de la feuille de route.
