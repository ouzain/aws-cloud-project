# Déployer depuis une nouvelle machine dans un nouveau compte

Remplacer `ACCOUNT_ID`, `ADMIN_PROFILE`, `DEPLOY_USER`, `TEAM_PROFILE` et
`OWNER_EMAIL` par les valeurs du membre. Le compte d’une preuve historique
ne doit jamais être réutilisé comme paramètre. Ne pas copier les identifiants,
`.tools/`, `.terraform/`, les plans ou l’état d’un autre membre.

## Préparer la machine et la connexion

Utiliser macOS ou Linux ; sous Windows, utiliser Ubuntu dans WSL2. Installer
Git, Node.js 22+, npm, Python 3.9+ et AWS CLI v2 à jour. Le script peut télécharger
Terraform 1.13.5 en vérifiant sa somme de contrôle officielle.

Cloner le dépôt dans un dossier neuf et utiliser la révision revue par l’équipe.
Le propriétaire prépare un utilisateur IAM ou un rôle de déploiement, puis
configure un profil local pour cette identité. Le profil administrateur sert
uniquement à l’initialisation des permissions. Le déploiement refuse root.

```sh
git clone https://github.com/ouzain/aws-cloud-project.git
cd aws-cloud-project
python3 scripts/bootstrap.py --account-id ACCOUNT_ID
```

Revoir les cinq politiques générées, puis le propriétaire les applique :

```sh
python3 scripts/bootstrap.py --account-id ACCOUNT_ID \
  --admin-profile ADMIN_PROFILE --user-name DEPLOY_USER --apply
aws --profile TEAM_PROFILE sts get-caller-identity
```

Pour un rôle, remplacer `--user-name DEPLOY_USER` par `--role-name DEPLOY_ROLE`.
L’ARN et le compte affichés doivent correspondre au destinataire IAM préparé.
Voir [le détail des permissions et des garde-fous](../ops/iam/README.md).

## Déployer

Les valeurs par défaut utilisent `vitalora` dans `eu-west-3`, sans clé SSH ni
notification de commande par e-mail. Un fichier `terraform.tfvars` n’est pas
nécessaire pour ces valeurs. Pour les adapter, partir du fichier exemple,
sans modifier le préfixe ou la région pris en charge par cette démonstration.

```sh
python3 scripts/deploy.py --profile TEAM_PROFILE --expect-account ACCOUNT_ID \
  --budget-alert-email OWNER_EMAIL --require-empty --yes --verify
```

L’adresse doit appartenir au titulaire du compte. Elle configure les alertes du
nouveau budget et peut aussi être fournie par `TF_VAR_budget_alert_email` ou
dans un fichier privé `terraform.tfvars`. Le script détecte un audit/budget
VITALORA existant ou laisse Terraform créer ceux du projet. Le compartiment
d’état dépend du compte et est chiffré, versionné et verrouillé par S3.

L’absence d’état au premier déploiement est normale. Ne jamais créer un état
fictif ni copier celui d’un autre compte. Après une interruption, relancer la
même commande, en retirant `--require-empty` si des ressources ont déjà été
créées. Un refus d’accès ou de verrouillage reste bloquant.

Le contrôle attend jusqu’à dix minutes un événement CloudTrail livré pour ce
déploiement. Si ce délai est dépassé, attendre puis relancer seulement :

```sh
python3 scripts/verify-monitoring.py --profile TEAM_PROFILE --audit-timeout 900
```

Le contrôle injecte une erreur fictive pour vérifier une vraie alarme. Une
erreur IAM interrompt la vérification immédiatement. Un succès local ou un
plan réussi ne remplace pas cette validation fonctionnelle sur AWS.

## Prouver la répétabilité et nettoyer

Tester le catalogue et une commande dans le navigateur, puis conserver la
révision Git, le compte, la région, les dates et les JSON de `test-results/`.
Après reconstruction du paquet et réinitialisation, le plan doit rester vide :

```sh
node scripts/build.mjs
python3 scripts/terraform.py --profile TEAM_PROFILE init
python3 scripts/terraform.py --profile TEAM_PROFILE plan -detailed-exitcode
python3 scripts/terraform.py --profile TEAM_PROFILE destroy
python3 scripts/terraform.py --profile TEAM_PROFILE state list
```

Le plan doit retourner 0 et le dernier inventaire doit être vide. Le stockage
d’état indépendant reste ; audit et budget sont conservés s’ils préexistaient,
sinon supprimés avec l’environnement. Les politiques de déploiement restent
attachées. Vérifier séparément les coûts et les ressources conservées.

Le 2 novembre 2026, l’équipe a confirmé un déploiement réussi depuis une autre
machine dans un nouveau compte AWS indépendant. Voir le
[compte rendu de reproduction](evidence/2026-11-02-reproduction/README.md).
Les contrôles locaux du 29 octobre restent distincts de cette reproduction réelle.
