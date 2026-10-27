# VITALORA — Architecture VM (Ousmane)

Couvre les Phases 1 et 2 du roadmap (socle réseau/calcul + données/stockage),
plus le module réseau partagé et une base de Phase 3 (catalogue/commandes)
pour pouvoir valider de bout en bout.

## 0. Prérequis (une fois par personne)

```bash
aws configure --profile ton-profil-aws
# Access Key, Secret, région eu-west-3

# Bucket S3 pour TON state, dans TON compte (remplace le nom, il doit être unique globalement)
aws s3 mb s3://tfstate-vitalora-ouzain --profile ton-profil-aws --region eu-west-3
aws s3api put-bucket-versioning \
  --bucket tfstate-vitalora-ouzain \
  --versioning-configuration Status=Enabled \
  --profile ton-profil-aws
```

Copie les fichiers d'exemple :

```bash
cd envs/vm-based
cp terraform.tfvars.example terraform.tfvars        # édite-le (profil, owner_tag, admin_cidr)
cp backend-example.hcl backend-ouzain.hcl             # édite-le (nom de ton bucket)
```

## 1. Déployer (Phases 1 + 2)

```bash
terraform init -backend-config=backend-ouzain.hcl
terraform plan
terraform apply
```

Compte ~5-10 min (le temps que l'ASG lance l'EC2, que l'ALB passe l'instance
en `healthy`, et que RDS finisse de provisionner).

## 2. Charger le schéma et les données de départ

```bash
DB_ENDPOINT=$(terraform output -raw db_endpoint)
mysql -h "$DB_ENDPOINT" -P 3306 -u vitalora_admin -p vitalora < ../../sql/schema.sql
# Le mot de passe est dans SSM : 
aws ssm get-parameter --name /vitalora/db/password --with-decryption \
  --query 'Parameter.Value' --output text --profile ton-profil-aws
```

Il faut lancer cette commande depuis un poste qui peut atteindre RDS sur le
port 3306 — RDS est en subnet privé, donc pas accessible depuis ta machine
directement. Deux options simples :
- un tunnel SSH via l'EC2 (`key_name` doit être renseigné dans `terraform.tfvars`) :
  `ssh -i ta-cle.pem -L 3306:$DB_ENDPOINT:3306 ec2-user@$(terraform output -raw alb_dns_name)` n'est pas possible via l'ALB (il ne fait que du HTTP) — passe par l'IP publique de l'instance EC2 (console AWS) à la place de l'ALB.
- ou exécute la commande `mysql` directement **sur l'EC2** (elle est dans le même VPC) : `ssh ec2-user@<ip-publique-ec2>` puis lance le client `mysql` depuis là (installe-le avec `sudo dnf install -y mariadb105`).

## 3. Valider (critères du roadmap)

```bash
ALB_DNS=$(terraform output -raw alb_dns_name)

curl http://$ALB_DNS/health              # {"status":"ok"}          -> Phase 1
curl http://$ALB_DNS/products            # liste des produits        -> Phase 2 + 3
curl -X POST http://$ALB_DNS/orders \
  -H "Content-Type: application/json" \
  -d '{"customer_email":"test@vitalora.fr","items":[{"product_id":1,"qty":2}]}'
```

## 4. Nettoyer (toujours, en fin de session — voir Gouvernance budgétaire)

```bash
terraform destroy
```

## Ce qui reste à brancher par le reste de l'équipe

- **Personne C (Phase 4)** : créer le topic SNS nommé `vitalora-order-confirmation`
  (le rôle IAM de l'EC2 autorise déjà `sns:Publish` sur `vitalora-*`) puis
  décommenter/compléter le TODO dans `app/server.js` (route `POST /orders`).
- **Personne C (Phase 5)** : CloudTrail, dashboard CloudWatch, alarmes — rien
  à modifier côté réseau/compute, juste à lire les ressources déjà taguées
  `Owner = var.owner_tag`.
- **Personne B (Serverless)** : peut réutiliser `sql/schema.sql` (même modèle
  de données, adapté en single-table DynamoDB) et le même bucket d'assets si
  besoin, mais n'a pas besoin du module `network` (pas de VPC côté Lambda).
