# VITALORA — Architecture VM (Ousmane)

Couvre les Phases 1 et 2 du roadmap (socle réseau/calcul + données/stockage),
plus le module réseau partagé et une base de Phase 3 (catalogue/commandes)
pour pouvoir valider de bout en bout.

## 0. Prérequis (une fois par personne)

```bash
aws configure --profile default
# Access Key, Secret, région eu-west-3

# Bucket S3 pour mon state, dans mon compte (remplace le nom, il doit être unique globalement)
aws s3 mb s3://tfstate-vitalora-ouzain --profile default --region eu-west-3
aws s3api put-bucket-versioning \
  --bucket tfstate-vitalora-ouzain \
  --versioning-configuration Status=Enabled \
  --profile default
```

Copie les fichiers d'exemple :

```bash
cd envs/vm-based
cp terraform.tfvars.example terraform.tfvars        # édite-le (profil, owner_tag, admin_cidr)
cp backend-example.hcl backend-ouzain.hcl             # édite-le (nom de mon bucket)
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

RDS est en subnet privé (`publicly_accessible = false`) et son security group
n'accepte le port 3306 que depuis l'EC2. Un `mysql -h <endpoint>` lancé depuis
ta machine expire donc (`ERROR 2003 ... (60)`). Il faut passer par l'EC2, avec
un tunnel SSH.

### 2.1 Prérequis

1. **Client MySQL** sur ta machine : `brew install mysql-client` (macOS).
2. **Droits IAM** : l'utilisateur AWS CLI doit pouvoir lire le mot de passe
   (`ssm:GetParameter` sur `/vitalora/db/*`, par ex. la policy
   `AmazonSSMReadOnlyAccess`). Sans cela : `AccessDeniedException`.
3. **Région** : tout est en `eu-west-3`. Si ton profil AWS est dans une autre
   région, ajoute toujours `--region eu-west-3`, sinon `ParameterNotFound`.
4. **Key pair EC2** : sans `key_name`, l'EC2 n'a aucune clé SSH.
   - Crée la clé dans eu-west-3 (le `.pem` n'est téléchargeable qu'une fois) :
     ```bash
     aws ec2 create-key-pair --key-name vitalora-key --region eu-west-3 --profile default \
       --query KeyMaterial --output text > ~/.ssh/vitalora-key.pem
     chmod 400 ~/.ssh/vitalora-key.pem
     ```
   - Renseigne-la dans `terraform.tfvars` (**avec des guillemets**, sinon
     `Variables not allowed`) : `key_name = "vitalora-key"`
   - Applique : `terraform apply`
5. **Recréer l'instance** : `key_name` ne s'applique qu'à la création d'une
   instance. L'ASG ne remplace pas l'instance existante, il faut la terminer
   pour qu'il en lance une nouvelle avec la clé :
   ```bash
   aws ec2 describe-instances --region eu-west-3 --profile default \
     --filters "Name=instance-state-name,Values=running" \
     --query 'Reservations[].Instances[].[InstanceId,KeyName,PublicIpAddress]' --output table
   # Si KeyName vaut None :
   aws ec2 terminate-instances --instance-ids <i-xxxx> --region eu-west-3 --profile default
   ```
   Attends 1-2 min, relance la commande `describe-instances` : `KeyName` doit
   valoir `vitalora-key`. Note la nouvelle `PublicIpAddress` (elle change à
   chaque recréation).
6. **Port 22** : le CIDR autorisé (`admin_cidr`) doit correspondre à ton IP
   publique actuelle (`curl ifconfig.me`).

### 2.2 Ouvrir le tunnel SSH (terminal 1, à laisser ouvert)

```bash
cd envs/vm-based
DB_ENDPOINT=$(terraform output -raw db_endpoint)
ssh -i ~/.ssh/vitalora-key.pem -N -L 3307:"$DB_ENDPOINT":3306 ec2-user@<IP_PUBLIQUE_EC2>
```

- On utilise le port local `3307` pour ne pas entrer en conflit avec un MySQL local.
- L'IP à utiliser est celle de l'EC2, pas l'ALB (il ne fait que du HTTP).
- La première connexion demande de confirmer l'empreinte : réponds `yes`.
- `Permission denied (publickey...)` : l'instance n'a pas la clé (voir étape 5)
  ou le `.pem` ne correspond pas à la key pair.

### 2.3 Importer le schéma (terminal 2)

```bash
cd envs/vm-based
DB_PASS=$(aws ssm get-parameter --name /vitalora/db/password --with-decryption \
  --query 'Parameter.Value' --output text --region eu-west-3 --profile default)
MYSQL_PWD="$DB_PASS" mysql -h 127.0.0.1 -P 3307 -u vitalora_admin vitalora < ../../sql/schema.sql
unset DB_PASS
```

Vérification :

```bash
MYSQL_PWD="$(aws ssm get-parameter --name /vitalora/db/password --with-decryption \
  --query Parameter.Value --output text --region eu-west-3 --profile default)" \
  mysql -h 127.0.0.1 -P 3307 -u vitalora_admin vitalora -e "SHOW TABLES;"
```

Quand c'est terminé, ferme le tunnel (`Ctrl+C` dans le terminal 1).

### Alternative : exécuter depuis l'EC2

```bash
scp -i ~/.ssh/vitalora-key.pem ../../sql/schema.sql ec2-user@<IP_PUBLIQUE_EC2>:~
ssh -i ~/.ssh/vitalora-key.pem ec2-user@<IP_PUBLIQUE_EC2>
# Sur l'EC2 :
sudo dnf install -y mariadb105
PASS=$(aws ssm get-parameter --name /vitalora/db/password --with-decryption \
  --query Parameter.Value --output text --region eu-west-3)
MYSQL_PWD="$PASS" mysql -h <db_endpoint> -u vitalora_admin vitalora < ~/schema.sql
```

### Dépannage

| Erreur | Cause | Solution |
|---|---|---|
| `AccessDeniedException ... ssm:GetParameter` | Pas de droit IAM | Attacher une policy SSM en lecture |
| `ParameterNotFound` | Mauvaise région ou `apply` non fait | `--region eu-west-3`, vérifier `terraform state list \| grep ssm` |
| `Variables not allowed` | Valeur sans guillemets dans le `.tfvars` | `key_name = "vitalora-key"` |
| `ERROR 2003 ... (60)` | RDS privé, accès direct impossible | Passer par le tunnel SSH |
| `Permission denied (publickey)` | EC2 sans la clé | Terminer l'instance pour que l'ASG la recrée |

## 3. Valider (critères du roadmap)

### 3.1 Tester depuis le navigateur

Depuis `envs/vm-based`, récupère le nom DNS de l'ALB :

```bash
terraform output -raw alb_dns_name
```

Ouvre ensuite `http://<alb_dns_name>/` dans ton navigateur. Après avoir
chargé le schéma et les données de départ, vérifie le parcours suivant :

1. Le catalogue des produits s'affiche.
2. Les onglets de catégories filtrent les produits (par exemple « Compléments
   à base de plantes »).
3. Tu peux ajouter un produit au panier et voir le total.
4. Tu peux saisir une adresse e-mail et valider la commande.
5. Une confirmation affiche le numéro de commande.

La commande doit être enregistrée dans RDS ; le parcours nécessite donc que
RDS soit joignable par l'application et que `sql/schema.sql` ait été importé.

> **Note :** le `user_data` déploie aussi le front : `app/public/` (`index.html`,
> `app.js`, `style.css`) est compressé par Terraform (`base64gzip`), décodé sur
> l'EC2 dans `/opt/vitalora/public/` et servi par `express.static`. Si la page
> ne s'affiche pas, consulte `/var/log/vitalora-userdata.log` sur l'EC2.

### 3.1 bis Vérifier qu'une commande passée via le web est enregistrée dans RDS

1. **Noter l'état avant commande** (tunnel SSH ouvert, voir 2.2). Exemple avec
   le produit 1 :
   ```bash
   export MYSQL_PWD="$(aws ssm get-parameter --name /vitalora/db/password --with-decryption \
     --query Parameter.Value --output text --region eu-west-3 --profile default)"
   alias vdb='mysql -h 127.0.0.1 -P 3307 -u vitalora_admin vitalora'

   vdb -e "SELECT COUNT(*) AS nb_commandes FROM orders; SELECT product_id, stock_qty FROM products WHERE product_id=1;"
   ```
2. **Passer une commande dans le navigateur** avec un e-mail reconnaissable
   (ex. `test-web@vitalora.fr`), 2 unités du produit 1, puis noter le numéro
   affiché dans la confirmation (ex. `#12`).
3. **Vérifier la commande en base** :
   ```bash
   vdb -e "SELECT * FROM orders WHERE customer_email='test-web@vitalora.fr' ORDER BY order_id DESC LIMIT 1;"
   vdb -e "SELECT * FROM order_items WHERE order_id=<NUMERO>;"
   ```
   Attendu : une ligne `orders` avec `status = 'received'`, et une ligne
   `order_items` par produit du panier (`qty` et `unit_price_cents` corrects).
4. **Vérifier le total et le stock** :
   ```bash
   vdb -e "SELECT o.order_id, o.customer_email, SUM(oi.qty*oi.unit_price_cents)/100 AS total_eur
           FROM orders o JOIN order_items oi USING(order_id)
           WHERE o.order_id=<NUMERO> GROUP BY o.order_id;"
   vdb -e "SELECT product_id, stock_qty FROM products WHERE product_id=1;"
   ```
   Attendu : le total correspond à celui du panier et le stock a diminué de la
   quantité commandée.
5. **Cohérence avec l'API** : `curl "http://$ALB_DNS/orders/<NUMERO>"` doit
   renvoyer les mêmes données que la base.
6. **Cas d'échec (rollback)** : une commande refusée (stock insuffisant, produit
   inexistant) ne doit rien laisser en base. Compare `COUNT(*)` de `orders`
   avant et après une requête `insufficient_stock` (voir 3.2) : il doit être
   identique, et le stock inchangé.
7. Ferme le tunnel et `unset MYSQL_PWD` en fin de test.

### 3.2 Tester les routes en ligne de commande

```bash
ALB_DNS=$(terraform output -raw alb_dns_name)

curl "http://$ALB_DNS/health"                       # {"status":"ok"} -> Phase 1
curl "http://$ALB_DNS/products"                     # catalogue -> Phases 2 + 3
curl "http://$ALB_DNS/products?category=plantes"    # filtre par catégorie

ORDER_ID=$(curl -s -X POST "http://$ALB_DNS/orders" \
  -H "Content-Type: application/json" \
  -d '{"customer_email":"test@vitalora.fr","items":[{"product_id":1,"qty":2}]}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['order_id'])")

curl "http://$ALB_DNS/orders/$ORDER_ID"             # commande, lignes et total
```

La création d'une commande décrémente le stock. Pour vérifier ce comportement,
consulte le catalogue avant et après la commande ou relis la commande avec
`GET /orders/$ORDER_ID`.

Tu peux aussi vérifier les réponses d'erreur de l'API ; `-i` affiche le code
HTTP et le corps de la réponse :

```bash
# E-mail absent ou invalide : HTTP 400, invalid_email
curl -i -X POST "http://$ALB_DNS/orders" \
  -H "Content-Type: application/json" \
  -d '{"items":[{"product_id":1,"qty":1}]}'

# Panier vide : HTTP 400, empty_cart
curl -i -X POST "http://$ALB_DNS/orders" \
  -H "Content-Type: application/json" \
  -d '{"customer_email":"test@vitalora.fr","items":[]}'

# Produit inexistant : HTTP 400, product_not_found
curl -i -X POST "http://$ALB_DNS/orders" \
  -H "Content-Type: application/json" \
  -d '{"customer_email":"test@vitalora.fr","items":[{"product_id":999999,"qty":1}]}'

# Quantité supérieure au stock : HTTP 409, insufficient_stock
# Le produit 20 a un stock initial de 40 ; 50 reste dans la limite de validation.
curl -i -X POST "http://$ALB_DNS/orders" \
  -H "Content-Type: application/json" \
  -d '{"customer_email":"test@vitalora.fr","items":[{"product_id":20,"qty":50}]}'
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
