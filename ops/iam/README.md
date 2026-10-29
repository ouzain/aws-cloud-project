# Autorisations de déploiement

Les trois politiques de ce dossier complètent les autorisations existantes
d’audit, de budget et de connexion locale de `vitalora-deployer` dans le compte
`573199225243`. Elles ne remplacent pas les rôles applicatifs EC2 et Lambda.

Le socle provient d’un plan de création Terraform en lecture seule analysé par
AWS IAM Policy Autopilot, puis revu pour les mises à jour, contrôles et
suppressions. AWS IAM Access Analyzer n’a signalé aucune erreur ni alerte de
sécurité.

```sh
uvx iam-policy-autopilot@latest generate-policies /absolute/path/plan.json \
  --region eu-west-3 --account 573199225243 --resource-cutoff 100 --pretty
```

- Les opérations régionales sont limitées à `eu-west-3`.
- Les ressources nommées utilisent `vitalora-*` lorsque le service le permet.
- L’accès S3 vise `vitalora-*` et `tfstate-vitalora-*`.
- Les rôles et profils d’instance IAM gérés utilisent `vitalora-*`.
- La transmission de rôles vise uniquement EC2/Lambda et les rôles du projet.
- Les rôles liés aux services concernent Auto Scaling, ELB et RDS.
- Systems Manager vise les instances marquées pour le projet et le document
  standard `AWS-RunShellScript`.
- Les appels de chiffrement KMS sont limités aux intégrations de services du
  projet ; les délégations doivent servir des ressources AWS.

Les identifiants EC2 et réseau étant attribués à la création, certaines
permissions de cycle de vie sont régionales. Ces droits de déploiement restent
séparés des droits des rôles applicatifs.

Ces politiques contiennent l’identifiant du compte actuel. Les régénérer et
les revoir pour un autre compte. Les plans peuvent contenir des secrets :
conserver des permissions de fichier restrictives et ne pas les versionner.

`lambda:GetEventSourceMapping` reste limité aux ARN de déclencheur du compte et
de la région. Lors d’une suppression, AWS a renvoyé `AccessDenied` après la
disparition du déclencheur. Une recherche du propriétaire renvoyait
`ResourceNotFound` et la liste du profil de déploiement était vide. L’entrée
résiduelle a été retirée de l’état après ces contrôles, puis la suppression a
abouti. Aucune permission de lecture sur tout le compte n’a été ajoutée.

Cette récupération est maintenant automatisée par `scripts/terraform.py`,
après deux listes AWS concordantes filtrées sur la fonction et la file exactes,
et une nouvelle vérification de l’état. Le script ne retire que l’adresse du
déclencheur supprimé et reprend une seule fois. Une erreur ou une présence
confirmée bloque cette récupération. Le banc temporaire utilise le même profil
IAM ; aucune politique de déploiement n’est élargie pour ce contrôle.

Politiques gérées sous le chemin IAM `/vitalora/` :
`vitalora-hybrid-deployment-1`, `vitalora-hybrid-deployment-2` et
`vitalora-hybrid-deployment-3`.

`vitalora-monitoring.json` est un complément approuvé séparément, attaché sous
`vitalora-hybrid-monitoring`. Il autorise les alarmes, tableaux de bord et filtres
de métrique CloudWatch du projet ainsi que leur lecture. Il ne permet pas de
modifier CloudTrail, les budgets ou les permissions KMS. Les identifiants des
politiques restent inchangés lors du passage en français.
