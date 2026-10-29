# VITALORA — Rapport d’architecture et de réalisation

## Objectif et périmètre

VITALORA illustre un catalogue de compléments alimentaires, la commande de
plusieurs produits, la confirmation immédiate, l’enregistrement durable et la
simulation de préparation/expédition. Quarante produits fictifs couvrent le
bien-être quotidien, la nutrition sportive, les plantes et la nutrition beauté.
Les montants sont exprimés en centimes. Aucun paiement ni envoi physique réel
n’est effectué.

Le périmètre pédagogique actualisé associe EC2 et Serverless dans une seule
architecture. Express sur EC2 héberge l’interface et l’API synchrone ; Lambda
traite les commandes de façon asynchrone. La seconde boutique Serverless,
CloudFront, API Gateway et DynamoDB ne font pas partie de cette réalisation.

Les [schémas de topologie et de séquence](architecture.md) décrivent la démo.
Terraform organise le réseau, la base et les images, EC2/ALB, la messagerie et la
supervision en modules. L’application et la fonction utilisent Node.js 22 et
AWS SDK pour JavaScript v3. Les textes du projet sont désormais en français ;
les contrats API, champs de base et identifiants AWS restent stables.

## Choix des services et compromis

| Choix | Intérêt | Compromis |
| --- | --- | --- |
| ALB et EC2 Auto Scaling | Routage géré, contrôle de santé, remplacement et exploitation des machines virtuelles | Coût de base et démarrage ; une instance ne fournit pas de redondance simultanée |
| RDS MySQL privé | Relations commandes/lignes, transactions, verrous de stock et reporting | Une seule AZ dans la démo, sans basculement de base |
| S3 privé et URL présignées | Stockage durable sans lecture anonyme du compartiment | Expiration des URL et permissions S3/KMS à contrôler |
| SNS puis SQS | Diffusion et mise en file indépendantes du parcours de commande | Livraison possiblement répétée, nécessitant l’idempotence |
| Lambda avec accès VPC | Traitement à la demande et connexion privée à RDS | Suppression des interfaces réseau parfois plus lente que celle de la fonction |
| Boîte d’envoi persistante en base | Évite de perdre l’événement entre validation SQL et publication | Léger délai de scrutation et possibilité de republication après incident |
| CloudWatch et CloudTrail | Preuves métier séparées de l’audit de gestion de l’infrastructure | Les événements de gestion ne tracent pas à eux seuls les requêtes SQL ou toutes les données de messagerie |

MSK/Kafka n’est pas nécessaire à cette démonstration de petite taille. SNS/SQS
apporte diffusion, tampon, reprises et DLQ avec moins d’exploitation. Des
conteneurs gérés ou une API Serverless séparée sont des alternatives possibles,
mais ajouteraient une autre réalisation sans bénéfice nécessaire au périmètre.

## Données et fiabilité

`products`, `orders` et `order_items` représentent le catalogue et les commandes.
`outbox` conserve les événements non publiés ; `order_status_history` enregistre
les étapes persistantes. Les graines de produits et les objets image sont
créés automatiquement. Une nouvelle initialisation conserve stocks et commandes.

Le serveur valide la requête et calcule le total. Une transaction verrouille
les produits dans un ordre stable, vérifie le stock, crée la commande et ses
lignes, décrémente les quantités, inscrit `received` et ajoute l’événement en
attente. Une clé d’idempotence facultative évite qu’une reprise HTTP crée une
seconde commande.

Le processus EC2 verrouille l’événement en attente, le publie vers SNS puis le
marque publié uniquement après succès. Un échec le laisse disponible pour une
nouvelle tentative. Un incident après publication peut provoquer un doublon :
le traitement Lambda utilise des transitions verrouillées et un historique
unique. Il reprend depuis la dernière étape validée et ignore les doublons
pour une commande déjà terminée.

Les statuts techniques sont `received`, `confirmed`, `processing`, `shipped`.
L’interface affiche « Reçue », « Confirmée », « En préparation », « Expédiée ».
Les journaux structurés contiennent les identifiants de commande et d’événement.
SQS utilise des lots de cinq messages et une visibilité de 180 secondes. Le
déclencheur limite la concurrence à deux. Les réponses partielles isolent les
messages en échec ; après trois réceptions infructueuses, la politique de
redirection les déplace vers la DLQ, conservée pendant 14 jours.

## Sécurité et observabilité

Pour la démo, ALB reçoit le trafic HTTP public sur le port 80. Le port applicatif
EC2 n’accepte que le groupe de sécurité ALB. RDS n’est pas public et n’accepte
le port 3306 que depuis les groupes applicatif et Lambda. SSH est désactivé par
défaut ; les contrôles utilisent Systems Manager. Les connexions de base
vérifient TLS avec le bundle officiel d’autorités de certification RDS fourni.

EC2 et Lambda disposent de rôles distincts. EC2 lit sa configuration SSM et les
images du projet, publie dans le sujet SNS et écrit ses journaux. Lambda consomme
sa file, écrit ses journaux et possède les permissions d’interface réseau EC2
requises pour sa connexion VPC. Les images S3 utilisent une clé KMS gérée par
AWS et des clés de compartiment ; l’accès public est bloqué et les requêtes
sans signature échouent. Le stockage RDS et les volumes EC2 sont chiffrés ;
EC2 impose IMDSv2. La démo partage un identifiant de base : des utilisateurs SQL
séparés avec des droits restreints constitueraient une évolution de production.

Le script utilise des identifiants temporaires actualisables et refuse root
pour les changements applicatifs. Root a servi uniquement à l’initialisation
et à la maintenance autorisées des permissions. Les plans et l’état peuvent
contenir des secrets : les plans temporaires sont protégés puis supprimés,
l’état indépendant reste chiffré, versionné, privé et verrouillé dans S3.

CloudWatch conserve sept jours de journaux et fournit six widgets et quatre
alarmes : CPU, erreurs d’invocation Lambda, échecs de traitement et DLQ. Une
métrique métier est nécessaire car une réponse partielle en échec peut ne pas
augmenter `Errors`. Le test contrôlé invoque le traitement avec un enregistrement
fictif invalide et observe une vraie alarme. Il ne valide pas tout le cycle
temporisé de redirection SQS. Aucun e-mail d’alarme n’est configuré. L’e-mail de
confirmation SNS est facultatif et nécessite une adresse confirmée.

CloudTrail enregistre les événements de gestion avec validation des fichiers.
Un audit et un budget préexistants peuvent être réutilisés. Un compte préparé
sans ce socle peut les créer avec le module de supervision, les permissions
correspondantes et une adresse de notification budgétaire.

## Budget et disponibilité

La capacité par défaut est une instance EC2 `t3.micro`, une base MySQL
`db.t4g.micro` dans une seule AZ avec 20 Go de stockage et un ALB sur deux AZ.
L’ASG remplace une instance défaillante et peut atteindre deux instances. Cette
configuration limite le budget au prix de la redondance simultanée. Deux
instances EC2 et RDS Multi-AZ constituent l’extension de haute disponibilité.

Il n’y a ni NAT Gateway, ni endpoint d’interface payant, ni clé KMS dédiée,
ni zone DNS hébergée, ni seconde architecture. L’accès utilise le DNS ALB.
ALB, IPv4 publiques, calcul, base, stockage, journaux et requêtes peuvent
consommer des crédits ou entraîner des frais. Les conditions promotionnelles
et le délai de facturation ne permettent pas de certifier une facture finale
nulle.

Les alertes 20/50/80 % portent sur le budget mensuel, pas sur le crédit restant.
Créer l’environnement pendant les séances de travail, conserver les preuves,
puis le détruire. Vérifier les coûts stabilisés après la séance. Le stockage
d’état et la gouvernance préexistante sont conservés et comptabilisés séparément.

## Réalisation et résultats

La revue initiale a conduit à corriger la persistance des statuts, la livraison
transactionnelle, les doublons, les erreurs de base, les graines et images,
le paquet partagé et le renouvellement des instances. EC2 et Lambda utilisent
le même paquet verrouillé. Les dépendances AWS SDK sont fixées à 3.1159.0 et
l’audit archivé ne signalait alors aucune vulnérabilité connue.

Les neuf tests applicatifs et les quatre tests de propriété de gouvernance
Terraform ont réussi. La première vérification AWS a contrôlé les 40 images,
le stock transactionnel, l’idempotence HTTP, l’annulation d’un produit invalide,
l’historique complet, la lecture directe de RDS et les journaux corrélés. Les
contrôles de sécurité ont vérifié chiffrement, confidentialité, livraison d’audit,
abonnements budgétaires et vraie alarme. Les plans après recompilation et
réinitialisation ne signalaient aucun changement.

Les résultats et les limites propres à chaque exécution sont conservés
dans [les preuves de validation](evidence/2026-10-29-fr-aws/README.md).
Les [contrôles de portabilité](evidence/2026-10-29-portability/README.md)
couvrent les modèles IAM, les erreurs de premier déploiement et une copie
source neuve. Ils ne certifient pas le déploiement dans tous les comptes.

## Reproduction et soutenance

Le [guide de reproduction](reproducibility.md) décrit les prérequis et commandes.
`scripts/deploy.py` regroupe compilation, contrôles, plan, déploiement et validation
facultative. `scripts/terraform.py` permet les opérations individuelles et la
suppression.

Le [scénario de démonstration](demo-script.md) relie une commande à sa persistance,
son traitement, ses journaux, l’audit et les alarmes, puis à la suppression.
La présentation française insiste sur les rôles des services, la boîte d’envoi,
l’idempotence, l’accès privé à RDS, le budget et les limites réelles de validation.
Les schémas et la présentation distinguent la démo d’une extension Multi-AZ.
