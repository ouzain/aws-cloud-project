# État de VITALORA

## Fonctionnalités livrées

- Boutique et catalogue français : quatre catégories, quarante produits et images privées.
- Commandes transactionnelles, contrôle du stock et idempotence HTTP.
- Publication persistante des événements et traitement SNS/SQS/Lambda.
- Historique des statuts et journaux EC2/Lambda corrélés.
- RDS privé chiffré, rôles distincts et permissions applicatives limitées.
- Audit de gestion, budget, tableau de bord et alarmes CloudWatch.
- Modules Terraform, déploiement et vérification en une commande.
- Nettoyage avec récupération ciblée du défaut de suppression Lambda.

## Déploiement pour les utilisateurs

Le [guide de nouveau compte et nouvelle machine](docs/new-account.md) décrit
les prérequis, l’initialisation IAM, la configuration, la validation et la
suppression. Les cinq [modèles de permissions](ops/iam/README.md) utilisent
le compte cible. Leur génération est locale ; leur application exige une
action explicite du propriétaire. Aucun identifiant n’est créé ni partagé.

L’absence d’état au premier déploiement est acceptée. L’initialisation d’un
bucket interrompue peut être reprise. Le contrôle CloudTrail attend la
livraison d’un événement du déploiement et bloque en cas de refus IAM.

## Validation et limites

Les résultats sont conservés sous `docs/evidence/`, avec leur date et leur
périmètre. La [validation fonctionnelle AWS](docs/evidence/2026-10-29-fr-aws/README.md)
couvre catalogue, commandes, base, traitement asynchrone, supervision et
suppression. Les [contrôles de portabilité](docs/evidence/2026-10-29-portability/README.md)
couvrent les permissions paramétrées et une copie source neuve sans identifiants.

Le 2 novembre 2026, l’équipe a [confirmé un déploiement réussi](docs/evidence/2026-11-02-reproduction/README.md)
depuis une autre machine dans un nouveau compte AWS indépendant. La reproduction
sur une autre machine et dans un autre compte est donc confirmée par l’équipe.
Les journaux de cette exécution ne sont pas annexés à ce compte rendu.

Ces contrôles ne certifient pas tous les comptes ou toutes les machines. Un
déploiement réel doit vérifier les permissions, quotas et restrictions du compte,
les fonctionnalités et le nettoyage. Un plan valide seul ne suffit pas.
La démonstration utilise une instance EC2 et une base RDS dans une seule AZ ;
l’ALB couvre deux AZ et l’ASG peut monter à deux instances.

## Livrables et points de clôture

Le [rapport](docs/project-report.md), les [schémas](docs/architecture.md) et le
[scénario de démonstration](docs/demo-script.md) décrivent l’architecture et les
preuves à présenter. Chaque utilisateur doit conserver sa révision, ses résultats
de validation et ses propres justificatifs de suppression et de coûts.
La reproduction dans un compte indépendant est confirmée par l’équipe ; la tenue
de la soutenance reste à confirmer. Aucun coût final nul n’est garanti.
