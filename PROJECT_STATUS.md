# État du projet VITALORA

Mise à jour : 29 octobre 2026.

## Architecture et langue

L’architecture retenue associe EC2/Express derrière ALB, RDS privé, images S3
privées et traitement asynchrone SNS, SQS et Lambda. La seconde boutique
Serverless indépendante est hors périmètre.

À la demande de l’équipe, le projet passe de l’anglais au français : interface,
catalogue, descriptions, documentation, commentaires et supports de soutenance.
Les routes API, champs SQL, noms de ressources AWS, codes d’erreur et événements
structurés restent stables. Les preuves historiques ne sont pas retraduites.

| Phase | Périmètre | État |
| --- | --- | --- |
| 1 | Réseau sur deux AZ, ALB, EC2 et ASG | Validée sur AWS |
| 2 | RDS privé chiffré, 40 produits et images privées | Validée sur AWS |
| 3 | Catalogue, panier, commandes et contrôles de stock | Validée sur AWS |
| 4 | Publication persistante, SNS/SQS/Lambda et historique | Validée sur AWS |
| 5 | IAM, chiffrement, audit, tableau de bord, alarmes et budget | Validée sur AWS |
| 6 | Modules Terraform, déploiement en une commande et reconstruction | Reconstruction dans le même compte validée ; autres comptes non vérifiés |
| 7 | Rapport, schémas, scénario et présentation en français | Supports préparés ; soutenance à répéter et à présenter |

## Résultats AWS archivés

La première vérification fonctionnelle du 29 octobre à 13:27 UTC utilisait AWS
SDK 3.1159.0. Les quatre catégories comportaient dix produits ; les 40 images
privées ont été téléchargées par URL présignée. La commande 8 a atteint `shipped`.
Une lecture directe de RDS a confirmé deux lignes, le total et la publication
de l’événement. Les journaux EC2 et Lambda contenaient le même identifiant de
commande. Une commande passée dans le navigateur a aussi atteint `shipped`.

À 13:29 UTC, les vérifications de la phase 5 ont confirmé le chiffrement, six
widgets, quatre alarmes, les abonnements aux seuils budgétaires 20/50/80 % et
l’audit de gestion. Un enregistrement invalide a produit une vraie alarme.
Les neuf tests applicatifs et les quatre tests de propriété Terraform ont réussi.
La validation Terraform et les plans sans modification après recompilation et
réinitialisation ont réussi. L’audit des dépendances ne signalait aucune
vulnérabilité connue. Voir [les preuves initiales](docs/evidence/2026-10-29/README.md).

Les corrections couvrent la persistance des statuts, la boîte d’envoi
transactionnelle, les doublons, les erreurs de connexion, les graines et images,
le renouvellement des instances et le paquet partagé EC2/Lambda.

## Reconstruction et limite de validation

Seul le compte `573199225243` dans `eu-west-3` a été testé. Le script
`python3 scripts/deploy.py --profile vitalora --yes --verify` regroupe compilation,
tests, initialisation, plan, déploiement et vérifications. `--require-empty`
exige un état applicatif vide. Le profil IAM doit déjà être connecté et autorisé.

La seconde exécution a duré de 14:21 à 14:33 UTC. Elle a créé 96 ressources,
sans modification ni suppression dans le plan initial. La nouvelle commande 1
a atteint `shipped`, avec lecture RDS et vraie alarme vérifiées. Voir
[les preuves de reconstruction](docs/evidence/2026-10-29-rebuild/README.md).
Cela établit la reproductibilité dans le même compte, sans certifier les comptes
indépendants des autres membres. Consulter [le guide](docs/reproducibility.md).

Une seconde visite du navigateur a été bloquée par une limite d’usage de
l’approbation automatique. La capture historique provient du premier
environnement ; elle ne représente pas une deuxième répétition ni l’interface
française. La traduction française doit être distinguée de ces anciens tests AWS.

La démo utilise une seule instance EC2 et RDS dans une seule AZ. ALB couvre deux
AZ et l’ASG peut monter à deux instances ; cela ne constitue pas une base Multi-AZ.

## Cycle de vie et éléments restants

Les deux environnements ont été entièrement supprimés. À 15:33 UTC, l’état
applicatif était vide et les inventaires EC2, ALB, RDS, Lambda, SQS et VPC ne
contenaient plus de ressources applicatives. L’audit préexistant continuait.
Le budget, le compartiment d’état chiffré/versionné, l’audit et les politiques IAM
autorisées sont conservés. Aucun coût final nul n’est affirmé.

La suppression a nécessité le retrait d’une entrée d’état de déclencheur déjà
supprimé, après confirmation de son absence. L’élargissement de la permission de
lecture a été refusé par l’approbation automatique ; le périmètre IAM initial a
été rétabli et la suppression a abouti sans cette permission supplémentaire.
La récupération est désormais automatisée et a passé un banc AWS isolé à
16:43 UTC : défaut 403 reproduit, deux contrôles d’absence, retrait de la seule
entrée résiduelle avec verrouillage, puis suppression complète des six ressources
temporaires. Une deuxième suppression vide et les inventaires AWS ont réussi.
Le profil IAM n’a pas été élargi. L’état de boutique reste vide, contrôlé en
lecture seule. Voir [les preuves de nettoyage](docs/evidence/2026-10-29-cleanup/README.md).

La version validée est regroupée dans la branche `feat/hybrid-validation-fr` pour revue avant intégration à `main`.
Restent la décision sur les comptes indépendants, la répétition finale de la
soutenance, la vérification de la facturation et le partage de la version commune.

## Supports

Le [rapport](docs/project-report.md), les [schémas](docs/architecture.md) et le
[scénario](docs/demo-script.md) sont en français. La présentation modifiable de
dix diapositives est jointe à la conversation Codex. Les intervenants doivent
encore répéter et présenter la soutenance.

## Validation de la traduction française

Les neuf tests applicatifs, les quatre tests de gouvernance et la validation
Terraform ont réussi après traduction. Les 40 titres SVG correspondent au
catalogue français. Le paquet applicatif a été recompilé. Le navigateur local
a vérifié le panier, le format `49,80 €`, le message de stock et « Expédiée ».
Les dix diapositives françaises ont été contrôlées visuellement.
Voir [les preuves locales](docs/evidence/2026-10-29-fr/README.md).
Cette étape n’a créé aucune ressource AWS et ne remplace pas les validations
historiques ou les vérifications restant à effectuer dans d’autres comptes.

## Validation AWS de la version française

La reconstruction du 29 octobre à 17:04 UTC a passé les contrôles des phases
1 à 5. Les 40 produits français et les fichiers HTML/JavaScript déployés
correspondent aux sources locales. Dans le navigateur, une commande réelle
numéro 3, avec deux articles de catégories différentes et un total de 49,80 €,
a atteint « Expédiée ». La catégorie sportive reste sélectionnée.
L’injection contrôlée a déclenché une vraie alarme CloudWatch. Les preuves
fonctionnelles, de supervision et la capture sont archivées dans
[la validation française AWS](docs/evidence/2026-10-29-fr-aws/README.md).

À 17:26 UTC, les 96 ressources de cette reconstruction française ont été
supprimées. La récupération Lambda a fonctionné sur l’environnement complet.
L’état et les inventaires applicatifs sont vides ; le socle préexistant reste.
La validation française AWS est terminée. La branche `feat/hybrid-validation-fr`
regroupe le code et les preuves pour revue. Le périmètre multi-compte,
la répétition et le bilan de coûts restent à traiter.
