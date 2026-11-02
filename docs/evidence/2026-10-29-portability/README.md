# Préparation du déploiement dans un compte neuf — contrôles du 29 octobre 2026

Les [résultats](verification.json) distinguent les contrôles locaux de la
validation AWS qui reste à faire dans un deuxième compte. Les
[empreintes des sources](source-hashes.json) identifient les fichiers vérifiés.

- Le diagnostic d’état absent a été reproduit avec Terraform 1.13.5 dans un
  dossier local sans état. Le script retourne une liste vide ; les refus IAM,
  problèmes de verrouillage et diagnostics mixtes restent bloquants.
- Le parcours d’initialisation d’un nouveau backend et la reprise d’une création
  de bucket interrompue sont testés sans modifier AWS.
- Les modèles sont rendus pour plusieurs comptes, sans compte personnel fixe.
  Les cinq politiques résolues ont passé AWS Access Analyzer sans erreur ni
  alerte de sécurité ; aucune politique n’a été créée ou attachée pendant ce contrôle.
- Les garde-fous IAM couvrent le mauvais compte, la validation refusée, les
  politiques existantes différentes et la réutilisation des politiques identiques.
- La livraison CloudTrail différée, le passage de minuit UTC, les événements
  anciens ou d’un autre compte, le délai maximal et les refus d’accès sont testés.
- Un dossier source neuf a été préparé sans `.tools/`, `.terraform/`, paramètres
  privés, identifiants ou dépendances. Après installation npm verrouillée :
  construction, neuf tests Node, trente-quatre tests Python, génération locale
  IAM, initialisation Terraform sans backend distant et validation réussies.

Le dossier neuf a été testé sur la même machine physique macOS. Windows natif
est refusé ; utiliser Linux dans WSL2. Aucun compte AWS indépendant n’a été
déployé par ces tests. Les quotas, restrictions du compte, connexion IAM et
l’adresse budgétaire du propriétaire doivent encore être validés sur le compte cible.

Consulter [le parcours complet](../../new-account.md) avant le déploiement réel.

## Confirmation ultérieure

Les constats ci-dessus décrivent les seuls contrôles du 29 octobre 2026.
Le 2 novembre 2026, l’équipe a confirmé un déploiement réussi depuis une autre
machine dans un nouveau compte AWS indépendant. Le
[compte rendu séparé](../2026-11-02-reproduction/README.md) conserve cette
confirmation sans modifier les résultats JSON historiques.
