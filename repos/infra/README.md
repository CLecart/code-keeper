# infra

Infrastructure des deux environnements du projet code-keeper, **staging** et **prod**, décrite avec Terraform. Elle reprend l'architecture de cloud-design.

| Couche | Contenu | Où |
|---|---|---|
| AWS | VPC sur 2 zones avec 1 NAT, cluster EKS 1.36 (2 à 3 nœuds c7i-flex.large), ALB interne, API Gateway HTTPS + Cognito, journaux et tableau de bord CloudWatch | `terraform/modules/environment/` |
| Environnements | Le même module appelé deux fois : seuls le nom et la plage réseau changent | `terraform/envs/staging/`, `terraform/envs/prod/` |
| Plateforme Kubernetes | Espace `code-keeper`, stockage chiffré, 2 bases PostgreSQL, RabbitMQ, règles réseau, Cluster Autoscaler, Prometheus + Grafana, Fluent Bit | `platform/`, `scripts/deploy-platform.sh` |
| Images de plateforme | `inventory-database`, `billing-database`, `rabbitmq-server` (Alpine) | `images/` |

Les applications (`inventory-app`, `billing-app`, `api-gateway-app`) sont déployées par leurs propres pipelines dans l'espace `code-keeper`.

## Ce qui différencie staging et prod

| | staging | prod |
|---|---|---|
| Nom (cluster, préfixe de toutes les ressources) | `code-keeper-staging` | `code-keeper-prod` |
| Plage du VPC | `10.0.0.0/16` | `10.1.0.0/16` |
| État Terraform (S3) | `envs/staging/terraform.tfstate` | `envs/prod/terraform.tfstate` |

Tout le reste (types et nombre de machines, services, réglages) est identique.

## Secrets et droits

- Aucune clé AWS : le pipeline prend le rôle `code-keeper-ci-infra` avec le jeton d'identité de son job (OIDC). Seule la branche protégée `main` de ce dépôt y a droit.
- Le nom du stockage d'état et les IP autorisées sur l'API EKS viennent de variables CI protégées, pas du code.
- Les mots de passe des bases et de RabbitMQ sont tirés au hasard dans le cluster par `scripts/deploy-platform.sh`, au premier déploiement. Ils ne sont jamais affichés ni écrits dans Git.

## Scripts

| Script | Rôle |
|---|---|
| `scripts/deploy-platform.sh staging\|prod` | Installe la couche plateforme après `terraform apply` |
| `scripts/remove-platform.sh staging\|prod` | Supprime l'espace `code-keeper` et attend la suppression de ses disques EBS, **avant** `terraform destroy` ; relancé après une suppression interrompue, il passe ce qui est déjà fait |
| `scripts/image-tag.sh <image>` | Étiquette d'une image de plateforme : le dernier commit qui a modifié `images/<image>` |
| `scripts/grafana.sh staging\|prod` | Ouvre Grafana sur http://localhost:3001 (port-forward) |

Ce dépôt est publié depuis le dossier `repos/infra/` du dépôt code-keeper.
