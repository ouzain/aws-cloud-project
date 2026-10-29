# Reconstruction dans le même compte — 29 octobre 2026

Compte : `573199225243`. Région : `eu-west-3`.

Le premier environnement avait été entièrement supprimé et son état confirmé
vide. La commande suivante a compilé, recréé puis contrôlé les phases 1 à 5 :

```sh
python3 scripts/deploy.py --profile vitalora --expect-account 573199225243 --require-empty --yes --verify
```

L’exécution de 14:21 à 14:33 UTC a créé 96 ressources, sans modification ni
suppression dans le plan initial. Aucune ressource applicative n’a été créée
manuellement dans la console. IAM, l’état distant et le socle audit/budget
préexistant sont restés des prérequis.

- [Déploiement](deployment.json) : identité, dates, état initial vide et réussite.
- [Phases 1 à 4](phase-1-4.json) : 40 produits/images, nouvelle commande 1
  expédiée, lecture directe RDS et journaux.
- [Phase 5](phase-5.json) : chiffrement, événement `CreateVpc`, budget et vraie
  alarme `ALARM`.
- [Compilation](verification.json) : tests, plan, empreintes et limites.
- [Suppression](cleanup.json) : état final vide, ressources applicatives absentes
  et journal d’audit préexistant toujours actif.

La suppression a rencontré l’erreur documentée de lecture d’un déclencheur
Lambda déjà supprimé. L’absence de son UUID a été confirmée avant le retrait
de cette seule entrée d’état. Terraform a ensuite terminé la suppression sans
autorisation IAM supplémentaire. Aucun état, plan sensible ou identifiant n’est
inclus dans cette archive.

La seconde visite du navigateur a été bloquée par une limite d’usage de
l’approbation automatique. La capture disponible provient du premier
environnement. Les vérifications API, base, journaux et supervision ont réussi
indépendamment dans le second. La répétabilité concerne un seul compte.

Les preuves datent d’avant la traduction française et sont conservées sans
modification. Elles ne représentent pas une nouvelle exécution de la version
française.
