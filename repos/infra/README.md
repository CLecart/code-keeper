# infra

Infrastructure des deux environnements du projet code-keeper, **staging** et **prod**, décrite avec Terraform. Elle reprend l'architecture de cloud-design.

| Couche | Contenu | Où |
|---|---|---|
| AWS | VPC sur 2 zones avec 1 NAT, cluster EKS 1.36 (2 à 3 nœuds c7i-flex.large), ALB interne, API Gateway HTTPS + Cognito, journaux et tableau de bord CloudWatch | `terraform/modules/environment/` |
| Environnements | Le même module appelé deux fois : seuls le nom et la plage réseau changent | `terraform/envs/staging/`, `terraform/envs/prod/` |
| Plateforme Kubernetes | Espace `code-keeper`, stockage chiffré, 2 bases PostgreSQL, RabbitMQ, règles réseau, droits des pipelines d'applications, Cluster Autoscaler, Prometheus + Grafana, Fluent Bit | `platform/`, `scripts/deploy-platform.sh` |
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

- Aucune clé AWS : le pipeline prend le rôle `code-keeper-ci-infra` avec le jeton d'identité de son job (OIDC). Seule la branche protégée `main` de ce dépôt y a droit. Ce rôle crée les clusters et en est administrateur.
- Les pipelines des applications n'ont, dans Kubernetes, que les droits de leur propre déploiement. Leur rôle `code-keeper-ci-<application>` n'a aucune politique d'accès EKS : EKS le place dans le groupe Kubernetes `code-keeper-deploy-<application>` (`terraform/modules/environment/eks.tf`), auquel `platform/rbac.yaml` donne un Role limité à ses propres objets :

  | Commande du job de déploiement | Droits |
  |---|---|
  | `kubectl apply -k` | Lire et modifier **son** Service, **son** Deployment ou StatefulSet, **son** autoscaler et **son** PodDisruptionBudget ; en créer (première installation) |
  | `kubectl rollout status` | Lire et suivre **son** Deployment ou StatefulSet |
  | `kubectl get pods -l` | Lire les pods |

  Rien d'autre : ni les secrets, ni les bases, ni RabbitMQ, ni les autres applications, ni le quota, ni les règles réseau, ni les droits eux-mêmes, et aucune suppression. RBAC ne peut pas limiter une **création** à un nom (l'objet n'existe pas encore) : un pipeline d'application peut créer d'autres objets de ces types, sans pouvoir modifier ni supprimer ceux des autres. `Scripts/rbac-test.sh staging|prod` (dépôt code-keeper) le vérifie dans le cluster.
- Le nom du stockage d'état et les IP autorisées sur l'API EKS viennent de variables CI protégées, pas du code.
- Les mots de passe des bases et de RabbitMQ sont tirés au hasard dans le cluster par `scripts/deploy-platform.sh`, au premier déploiement. Ils ne sont jamais affichés ni écrits dans Git.

## Étape validate : syntaxe et bonnes pratiques

Trois jobs, sans aucun accès AWS, dans chaque pipeline (demande de fusion, `main`, suppression) :

| Job | Ce qu'il vérifie | Réglages |
|---|---|---|
| `validate` | Syntaxe et format : `terraform validate` des deux environnements, `terraform fmt -check` | — |
| `tflint` | Bonnes pratiques Terraform (TFLint) : déclarations inutilisées, versions des modules et des fournisseurs figées, variables typées, syntaxe obsolète | `.tflint.hcl` : jeu de règles `terraform` intégré à TFLint, préréglage `recommended` ; aucun greffon téléchargé |
| `iac-scan` | Bonnes pratiques de sécurité (Trivy) : échoue sur un défaut de gravité haute ou critique, dans notre code et dans les modules du registre (`vpc`, `eks`) | `.trivyignore.yaml` : les exceptions assumées ci-dessous |

Exceptions assumées, chacune limitée au fichier où Trivy la signale : le même défaut ailleurs fait échouer le job.

| Règle | Où | Pourquoi |
|---|---|---|
| AWS-0104 : trafic sortant sans restriction | Groupe de sécurité des nœuds (module `eks`) | Les nœuds tirent les images et appellent les API AWS par la passerelle NAT, sans point de terminaison VPC : ces services n'ont pas de plage d'adresses fixe |
| AWS-0054 : écouteur HTTP | ALB (`alb.tf`) | ALB interne, joignable seulement par le lien VPC d'API Gateway ; les clients arrivent en HTTPS sur API Gateway |
| AWS-0040 : API EKS publique | Cluster (module `eks`) | Ouverte seulement aux IP de la machine d'administration et du runner (`eks_api_allowed_cidrs`, jamais `0.0.0.0/0`) |
| AWS-0039 : secrets sans clé KMS dédiée | Cluster (module `eks`) | Coût : 1 USD/mois par clé et 7 jours d'attente avant sa suppression ; EKS chiffre déjà par défaut toutes les données de l'API Kubernetes depuis la version 1.28 |

Trivy applique les règles intégrées à sa version figée (`--skip-check-update`) : un commit donne le même résultat dans tous les pipelines, suppression comprise. La ligne `ERROR ... Falling back to embedded checks` de son journal est donc normale.

En local, depuis ce dossier, avec les mêmes commandes que le pipeline :

```bash
docker run --rm -v "$PWD:/src:ro" -w /src ghcr.io/terraform-linters/tflint:v0.64.0 \
  --chdir=terraform --recursive --config=/src/.tflint.hcl
docker run --rm -v "$PWD:/src:ro" -w /src public.ecr.aws/aquasecurity/trivy:0.76.1 config \
  --skip-check-update --skip-dirs "**/.terraform" --exit-code 1 --severity HIGH,CRITICAL \
  --ignorefile .trivyignore.yaml terraform/
```

## Scripts

| Script | Rôle |
|---|---|
| `scripts/deploy-platform.sh staging\|prod` | Installe la couche plateforme après `terraform apply` |
| `scripts/remove-platform.sh staging\|prod` | Supprime l'espace `code-keeper` et attend la suppression de ses disques EBS, **avant** `terraform destroy` ; relancé après une suppression interrompue, il passe ce qui est déjà fait |
| `scripts/image-tag.sh <image>` | Étiquette d'une image de plateforme : le dernier commit qui a modifié `images/<image>` |
| `scripts/grafana.sh staging\|prod` | Ouvre Grafana sur http://localhost:3001 (port-forward) |

Ce dépôt est publié depuis le dossier `repos/infra/` du dépôt code-keeper.
