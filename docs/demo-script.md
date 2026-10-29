# Scénario de démonstration VITALORA

Durée cible : 8 à 10 minutes. Utiliser des données fictives et la région
`eu-west-3`. Préparer un profil IAM connecté avant la séance.

## Préparation

```sh
python3 scripts/deploy.py --profile TEAM_PROFILE --yes --verify
python3 scripts/terraform.py --profile TEAM_PROFILE output
```

L’option de validation crée des commandes fictives et injecte une erreur de
supervision contrôlée. Conserver les résultats JSON dans `test-results/`.
Ouvrir l’URL ALB, le tableau `vitalora-hybrid` et les groupes de journaux EC2 et
Lambda. Attendre le rétablissement de l’alarme avant de la déclencher en direct.

## Déroulement

| Temps | Action | Explication et preuve |
| --- | --- | --- |
| 0:00–1:00 | Présenter le schéma | Une application réunit EC2 synchrone et Lambda asynchrone ; montrer les frontières publiques/privées |
| 1:00–2:00 | Parcourir les quatre catégories et ajouter deux produits | Express sur EC2 derrière ALB ; 40 images S3 privées avec URL présignées |
| 2:00–3:00 | Commander avec `demo@example.com` | Numéro immédiat et total calculé côté serveur ; aucun paiement réel |
| 3:00–4:00 | Observer le statut « Expédiée » | Transaction validée, publication persistante vers SNS, file SQS et traitement Lambda |
| 4:00–5:00 | Montrer la commande, l’historique et la preuve RDS | Commande, lignes, stock et événement enregistrés ensemble ; quatre statuts persistants |
| 5:00–6:00 | Filtrer les journaux par identifiant de commande | Publication, confirmation, préparation et expédition ; gestion des doublons |
| 6:00–7:00 | Montrer chiffrement, audit et tableau de bord | RDS/S3 privés, rôles distincts, audit de gestion et métriques |
| 7:00–8:00 | Injecter l’erreur contrôlée | Vraie alarme de traitement ; différence avec une erreur d’invocation Lambda |
| 8:00–9:00 | Expliquer reproduction et suppression | Même compte validé, autres comptes non vérifiés ; socle conservé et facturation différée |

Pour une vérification automatisée avec lecture directe de RDS :

```sh
python3 scripts/verify.py --profile TEAM_PROFILE
```

Ce script crée sa propre commande fictive. Utiliser son identifiant enregistré
dans `test-results/phase-1-4.json` pour présenter ses preuves RDS et journaux.
Ne pas les confondre avec une autre commande passée dans le navigateur.
`GET /orders/ORDER_ID` donne les données et l’historique de la commande affichée.

Le filtre CloudWatch `{ $.orderId = 1 }` doit contenir le vrai identifiant.
Le traitement utilise `/aws/lambda/vitalora-order-processor`, l’application
`/vitalora/application`. Le tableau de bord affiche aussi une chronologie commune.

Pour démontrer une vraie alarme :

```sh
python3 scripts/verify-monitoring.py --profile TEAM_PROFILE
```

L’enregistrement invalide déclenche une réponse partielle en échec et une
métrique réelle. Ce contrôle ne représente pas trois périodes complètes de
reprise SQS. CloudTrail prouve des changements de gestion de l’infrastructure ;
RDS et CloudWatch documentent les commandes.

## Fin de séance

Conserver les preuves puis supprimer l’environnement :

```sh
python3 scripts/terraform.py --profile TEAM_PROFILE destroy
python3 scripts/terraform.py --profile TEAM_PROFILE state list
```

Attendre `Destroy complete` et un état applicatif vide. L’interface réseau
privée de Lambda peut subsister après la fonction. Le script récupère
automatiquement le défaut 403 du déclencheur déjà supprimé après deux contrôles
AWS ciblés ; les autres erreurs interrompent la récupération. Voir le
[guide de reproduction](reproducibility.md#récupération-du-déclencheur-lambda).
Conserver aussi `test-results/cleanup.json` avec les preuves de la séance.

Présenter le budget et les coûts/crédits lorsque les données sont stabilisées.
Expliquer la durée de vie d’EC2, ALB, RDS et des journaux, sans annoncer une
facture nulle non vérifiée. Les preuves AWS historiques conservent leur langue
et leur date d’origine. Un aperçu local français ne prouve pas un nouveau
déploiement sur AWS.
