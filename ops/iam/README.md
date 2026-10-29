# Permissions d’un compte neuf

Les cinq fichiers `templates/*.json` utilisent `${ACCOUNT_ID}` et `${REGION}`.
Ils ne doivent pas être collés tels quels dans IAM. Le script génère des JSON
résolus pour un compte précis, sans remplacer le compte par un joker.
Le projet prend en charge le préfixe `vitalora` et la région `eu-west-3`.

## Générer et revoir

```sh
python3 scripts/bootstrap.py --account-id ACCOUNT_ID
```

Cette commande n’appelle pas AWS et ne modifie aucune permission. Les cinq
politiques et leurs empreintes sont enregistrées sous `.tools/iam-ACCOUNT_ID/`,
ignoré par Git. Le propriétaire doit les revoir avant application.

- `vitalora-deployment-1/2/3` : cycle de vie des ressources et validation.
- `vitalora-monitoring` : tableau de bord, alarmes et filtres du projet.
- `vitalora-governance` : audit CloudTrail du projet, lecture des budgets et
  gestion des budgets `vitalora-*`. Le stockage d’état est couvert par le socle S3.

Les quatre premiers modèles reprennent le socle précédemment généré avec IAM
Policy Autopilot à partir d’un plan, revu et validé sur AWS. Le complément de
gouvernance utilise les actions nommées de la référence officielle AWS.
Les cinq politiques résolues ont passé Access Analyzer sans erreur ni alerte de
sécurité. Une SCP ou une limite de permissions peut néanmoins les restreindre.

Après modification de l’infrastructure, produire un plan JSON privé et revoir
le socle avec la commande suivante ; ne jamais publier ce plan sensible :

```sh
uvx iam-policy-autopilot@latest generate-policies /absolute/path/plan.json \
  --region eu-west-3 --account ACCOUNT_ID --resource-cutoff 100 --pretty
```

## Appliquer après revue du propriétaire

Le propriétaire prépare un utilisateur IAM ou un rôle de déploiement existant
et sa connexion locale. Aucun utilisateur, mot de passe ou clé d’accès n’est
créé par le script. Utiliser un profil administrateur distinct et autorisé à
gérer IAM et à appeler Access Analyzer :

```sh
python3 scripts/bootstrap.py --account-id ACCOUNT_ID \
  --admin-profile ADMIN_PROFILE --user-name DEPLOY_USER --apply
```

Pour un rôle, utiliser `--role-name DEPLOY_ROLE` à la place de `--user-name`.
Le script vérifie le compte et le destinataire, valide toutes les politiques,
puis les crée sous `/vitalora/` et les attache au seul destinataire indiqué.
Une politique existante différente bloque l’application ; une politique
identique est réutilisée. Une application interrompue peut être reprise.

Utiliser ensuite le profil IAM du destinataire pour déployer, sans permission
administrateur supplémentaire. Root est refusé par `deploy.py`. Les politiques
de déploiement donnent des droits importants sur les rôles et ressources du
projet ; elles sont réservées aux membres de confiance.

`iam:PassRole` reste limité aux rôles `vitalora-*` et aux services EC2/Lambda.
`lambda:GetEventSourceMapping` reste limité aux ARN du compte et de la région.
Les permissions applicatives EC2/Lambda restent distinctes du déploiement.
Les identifiants réels sous `docs/evidence/` sont des preuves historiques,
jamais des paramètres de déploiement.

Références : [CloudTrail](https://servicereference.us-east-1.amazonaws.com/v1/cloudtrail/cloudtrail.json)
et [Budgets](https://servicereference.us-east-1.amazonaws.com/v1/budgets/budgets.json).
