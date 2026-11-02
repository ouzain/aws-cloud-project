# Architecture VITALORA

Une seule application associe EC2 et Serverless dans `eu-west-3`. La démo utilise
une instance EC2 et une base RDS dans une seule AZ. ALB couvre deux zones de
disponibilité ; l’ASG peut atteindre deux instances. Le schéma décrit cette
configuration économique, sans prétendre déployer une base RDS Multi-AZ.

```mermaid
flowchart TB
  browser[Navigateur]
  subgraph regional["Services AWS régionaux"]
    assets["Images et paquet applicatif S3 privés<br/>SSE-KMS avec clé gérée par AWS"]
    topic["SNS : order-confirmation"]
    queue["SQS : order-processing"]
    dlq["SQS : file de lettres mortes"]
    logs["CloudWatch : journaux, tableau de bord et quatre alarmes"]
    trail["CloudTrail : événements de gestion"]
    audit["Compartiment S3 d’audit privé"]
    budget["Budget mensuel : alertes à 20 / 50 / 80 %"]
  end
  subgraph vpc["VPC 10.0.0.0/16 — deux zones de disponibilité"]
    subgraph public["Sous-réseaux publics : 10.0.1.0/24 et 10.0.2.0/24"]
      alb["ALB public — HTTP 80<br/>Contrôle de santé : /ready"]
      ec2["EC2 / Express / ASG<br/>Capacité souhaitée 1, maximum 2<br/>Port 3000 accessible uniquement depuis ALB"]
    end
    subgraph private["Sous-réseaux privés : 10.0.11.0/24 et 10.0.12.0/24"]
      worker["Traitement de commande Lambda<br/>Connexion VPC privée<br/>Concurrence SQS maximale : 2"]
      rds[("RDS MySQL 8.4 chiffré<br/>Une AZ, TLS, port 3306<br/>Accès depuis les groupes EC2 et Lambda uniquement")]
    end
  end
  browser -->|Interface et API| alb
  alb --> ec2
  ec2 -->|Commande et événement dans une transaction| rds
  ec2 -->|Reprise de la boîte d’envoi| topic
  topic -->|Abonnement sans enveloppe SNS| queue
  queue -->|Déclencheur géré par Lambda| worker
  queue -->|Après trois réceptions en échec| dlq
  worker -->|Persistance des statuts| rds
  ec2 -->|Lecture et génération des URL présignées| assets
  assets -->|Images HTTPS présignées| browser
  ec2 --> logs
  worker --> logs
  trail --> audit
```

S3, SNS, SQS et la supervision sont des services régionaux, hors du VPC. La
connexion VPC de Lambda sert à joindre RDS. Le service Lambda gère la lecture
SQS et l’envoi habituel des journaux. Les sous-réseaux privés n’ont ni route
Internet par défaut, ni NAT Gateway, ni endpoint d’interface payant. EC2 dispose
d’un accès sortant public pour l’installation, les API AWS et Systems Manager.
SSH est désactivé par défaut.

```mermaid
sequenceDiagram
  participant UI as Navigateur
  participant API as Express sur EC2
  participant DB as RDS
  participant Pub as Publication sur EC2
  participant SNS
  participant SQS
  participant Worker as Lambda
  UI->>API: POST /orders + Idempotency-Key
  API->>DB: Ouvrir la transaction, verrouiller et vérifier le stock
  API->>DB: Enregistrer commande, lignes, historique et événement
  API->>DB: Valider la transaction
  API-->>UI: Numéro, total et statut actuel
  Pub->>DB: Verrouiller l’événement non publié
  Pub->>SNS: Publier order.created
  SNS-->>SQS: Livrer l’événement de l’abonnement
  Pub->>DB: Marquer la publication uniquement après succès SNS
  SQS->>Worker: Livrer un lot
  Worker->>DB: Persister confirmed, processing puis shipped
  Worker-->>SQS: Signaler uniquement les messages en échec
  UI->>API: GET /orders/:id
  API->>DB: Lire la commande et son historique
  API-->>UI: Afficher « Expédiée »
```

La commande et l’événement en attente sont validés ensemble. La livraison SNS
est au moins une fois. Transactions, verrous et unicité de l’historique
permettent de gérer les doublons ; le transport n’est pas garanti exactement
une fois. Les statuts techniques de l’API restent en anglais et l’interface les
traduit en français.

Une extension de haute disponibilité utiliserait deux instances EC2 et RDS
Multi-AZ. Son coût supplémentaire doit être distingué de la configuration de
démonstration. La [reproduction dans un nouveau compte depuis une autre machine](evidence/2026-11-02-reproduction/README.md)
a été confirmée par l’équipe le 2 novembre 2026.
