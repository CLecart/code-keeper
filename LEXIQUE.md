# Lexique — code-keeper

Les mots du projet, expliqués simplement. Pour chaque mot : **ce que c'est**, **à quoi ça
sert**, et **un exemple dans le projet**. Pour trouver un mot : `Ctrl+F`.

Les explications détaillées sont dans le [README](README.md). Les mots de l'architecture AWS
reprise de cloud-design (zone de disponibilité, sous-réseau, NAT, disque EBS, Prometheus,
Grafana…) sont expliqués dans le
[lexique de cloud-design](https://github.com/CLecart/cloud-design/blob/main/LEXIQUE.md).

## Sommaire

1. [DevOps et la livraison continue](#1-devops-et-la-livraison-continue)
2. [Git et GitLab](#2-git-et-gitlab)
3. [Les pipelines GitLab](#3-les-pipelines-gitlab)
4. [Les runners](#4-les-runners)
5. [Ansible](#5-ansible)
6. [Terraform et l'infrastructure en code](#6-terraform-et-linfrastructure-en-code)
7. [AWS](#7-aws)
8. [Les identités, les secrets et les droits](#8-les-identités-les-secrets-et-les-droits)
9. [Les scans et la qualité du code](#9-les-scans-et-la-qualité-du-code)
10. [Kubernetes et le déploiement](#10-kubernetes-et-le-déploiement)
11. [Les tests](#11-les-tests)
12. [Les mises à jour](#12-les-mises-à-jour)
13. [L'application](#13-lapplication)
14. [Les coûts](#14-les-coûts)

---

## 1. DevOps et la livraison continue

**DevOps**
- C'est quoi : une façon de travailler qui rapproche ceux qui écrivent le code (Dev) et ceux
  qui le font tourner (Ops), avec les mêmes outils et le même but.
- Ça sert à : livrer souvent, vite, et sans casser la production.
- Exemple : une modification du code arrive en production en quelques minutes, testée,
  scannée et approuvée.

**Agile**
- C'est quoi : une méthode de gestion de projet qui avance par petites livraisons
  fréquentes plutôt que par une grosse livraison à la fin.
- Exemple : le sujet part d'une entreprise qui passe en mode Agile et a besoin de livrer
  souvent.

**Intégration continue (CI)**
- C'est quoi : vérifier automatiquement chaque changement dès qu'il est poussé : il se
  construit, ses tests passent, il n'apporte pas de faille.
- Ça sert à : trouver les erreurs tout de suite, quand elles sont faciles à corriger.
- Exemple : à chaque push, les étapes build, test et scan des 3 applications.

**Livraison continue et déploiement continu (CD)**
- C'est quoi : emmener automatiquement un changement validé jusqu'aux serveurs.
  **Déploiement continu** : tout part en production tout seul. **Livraison continue** : tout
  est prêt, mais un humain décide du passage en production.
- Exemple : ici, staging est automatique et la production attend une approbation : c'est de
  la livraison continue.

**DevSecOps**
- C'est quoi : DevOps avec la sécurité intégrée à chaque étape, au lieu d'un contrôle à la fin.
- Exemple : le SAST et Trivy dans chaque pipeline, qui bloquent sur une faille haute ou
  critique ; hadolint et ESLint en plus pour la qualité.

**Environnement**
- C'est quoi : une copie complète de l'application et de son infrastructure, pour un usage
  donné.
- Exemple : 2 environnements identiques, `staging` (réseau `10.0.0.0/16`) et `prod`
  (`10.1.0.0/16`).

**Staging (préproduction)**
- C'est quoi : l'environnement de répétition, aussi proche que possible de la production.
- Ça sert à : essayer une nouvelle version pour de vrai avant les utilisateurs.
- Exemple : chaque nouvelle image y est déployée automatiquement.

**Production (prod)**
- C'est quoi : l'environnement que les vrais utilisateurs utilisent.

**Approbation (porte manuelle)**
- C'est quoi : une étape du pipeline qui attend qu'une personne autorisée clique pour
  continuer.
- Ça sert à : garder une décision humaine avant la production.
- Exemple : le job `approve-production`, que seuls les Maintainers peuvent lancer.

**Promotion d'image**
- C'est quoi : construire l'image une seule fois, puis déployer **la même** de staging vers
  la production.
- Ça sert à : être sûr que ce qui part en prod est exactement ce qui a été testé.
- Exemple : l'image `api-gateway-app:8c26f43b` (pipeline n° 43) en staging, puis en prod.

**Zéro coupure (zero downtime)**
- C'est quoi : mettre à jour une application sans qu'aucune requête n'échoue.
- Exemple : 740 requêtes sur 740 réussies en prod pendant un vrai déploiement (pipeline
  n° 47).

---

## 2. Git et GitLab

**Git**
- C'est quoi : l'outil qui garde l'historique de toutes les versions du code.

**Dépôt (repository)**
- C'est quoi : un dossier de code suivi par Git, avec tout son historique.
- Exemple : 5 dépôts dans GitLab (`inventory-app`, `billing-app`, `api-gateway-app`,
  `infra`, `renovate`), dont le contenu vit aussi dans `repos/` de ce dépôt.

**Commit**
- C'est quoi : un enregistrement de modifications dans l'historique, avec un message et un
  identifiant unique.
- Exemple : l'étiquette d'une image est l'identifiant court du commit, comme `8c26f43b`.

**Branche**
- C'est quoi : une ligne de travail séparée, pour modifier le code sans toucher à la
  version principale.
- Exemple : `developer` pousse une branche de travail ; son pipeline construit, teste et
  scanne, sans rien déployer.

**`main`**
- C'est quoi : la branche principale, celle qui part en production.

**Branche protégée**
- C'est quoi : une branche que seuls certains rôles peuvent modifier.
- Ça sert à : empêcher qu'un changement non relu arrive en production.
- Exemple : `main` est protégée dans les 5 projets : seuls les Maintainers poussent ou
  fusionnent, et personne ne peut forcer (`force push`).

**Demande de fusion (merge request, MR)**
- C'est quoi : la demande d'intégrer une branche dans `main`, avec relecture et pipeline.
- Ça sert à : discuter et vérifier un changement avant de l'accepter.
- Exemple : la fusion n'est possible que si le pipeline est vert et les discussions
  résolues ; `api-gateway-app!3` (mise à jour de sécurité de `morgan`).

**GitLab**
- C'est quoi : une plateforme qui réunit les dépôts Git, les demandes de fusion, les droits
  et les pipelines.
- Exemple : GitLab CE 19.5.1, sur une machine EC2 `m7i-flex.large`.

**GitLab CE (Community Edition)**
- C'est quoi : l'édition gratuite et libre de GitLab.
- Exemple : les environnements protégés (liste nominative d'approbateurs) n'y sont pas :
  ils demandent GitLab Premium.

**Auto-hébergé (self-managed)**
- C'est quoi : installé sur ses propres machines, au lieu d'utiliser GitLab.com.
- Exemple : GitLab reste privé, fermé à Internet.

**Groupe et projet**
- C'est quoi : un projet GitLab contient un dépôt et ses pipelines ; un groupe rassemble des
  projets et leurs membres.
- Exemple : le groupe `code-keeper` et ses 5 projets, créés par Ansible.

**Rôles GitLab**
- C'est quoi : le niveau de droits d'un membre : Developer (30), Maintainer (40), Owner (50).
- Exemple : `clecart` est Owner, `stakeholder` Maintainer (il approuve la prod),
  `developer` et `renovate-bot` Developer (ils proposent, sans déployer).

**API GitLab**
- C'est quoi : la porte d'entrée de GitLab pour les programmes, au lieu de l'interface web.
- Exemple : Ansible crée les comptes, les projets, les variables et les runners par l'API,
  sans un clic.

**Jeton d'accès personnel**
- C'est quoi : un mot de passe spécial, limité à certains droits, pour qu'un programme agisse
  au nom d'un compte.
- Exemple : le jeton de `renovate-bot`, rangé dans une variable masquée et protégée.

**Jeton d'emprunt d'identité (impersonation token)**
- C'est quoi : un jeton créé par un administrateur pour agir au nom d'un autre compte.
- Exemple : `Scripts/protection-test.sh` agit comme `developer`, puis révoque son jeton.

---

## 3. Les pipelines GitLab

**Pipeline**
- C'est quoi : la suite de jobs qui se lance automatiquement à chaque changement.
- Exemple : build → test → scan → containerization → deploy-staging → approval →
  deploy-production.

**Job**
- C'est quoi : une tâche du pipeline, lancée dans un conteneur propre et jetable.
- Exemple : `test`, `dependency-scan`, `apply-staging`.

**Étape (stage)**
- C'est quoi : un groupe de jobs ; les étapes s'enchaînent dans l'ordre.
- Exemple : les 7 étapes du pipeline `infra` : images, init, validate, plan, apply-staging,
  approval, apply-production.

**`.gitlab-ci.yml`**
- C'est quoi : le fichier qui décrit le pipeline d'un dépôt.
- Exemple : celui des 3 applications est identique, sauf 2 variables (`APP_NAME`,
  `K8S_WORKLOAD`).

**`rules`**
- C'est quoi : les conditions qui décident si un job tourne ou non.
- Exemple : `.on-main` : les jobs qui touchent AWS ne tournent que sur `main` protégée.

**`needs`**
- C'est quoi : la liste des jobs qu'un job attend ; il démarre dès qu'**eux** ont réussi.
- Attention : un job absent de la liste ne le bloque pas.
- Exemple : `containerization` attend les 6 contrôles ; il en manquait 2 au début.

**Job manuel (`when: manual`)**
- C'est quoi : un job qui ne démarre que si une personne le lance.
- Exemple : `approve-production` ; avec `allow_failure: false`, la suite du pipeline attend.

**Artefact**
- C'est quoi : un fichier produit par un job et gardé pour les jobs suivants.
- Exemple : le plan Terraform `plan.tfplan`, gardé un jour ; le rapport `junit.xml` des tests.

**Variable CI/CD**
- C'est quoi : une valeur donnée aux jobs sans l'écrire dans le code.
- **Protégée** : donnée aux seules branches protégées. **Masquée** : cachée dans les journaux.
- Exemple : `AWS_ROLE_ARN`, `TF_STATE_BUCKET` (protégées), `RENOVATE_TOKEN` (masquée et
  protégée).

**`resource_group`**
- C'est quoi : un verrou qui ne laisse passer qu'un job à la fois.
- Exemple : un seul déploiement à la fois dans staging, un seul en production.

**Programmation de pipeline (schedule)**
- C'est quoi : un pipeline lancé à heure fixe, comme un réveil.
- Exemple : le projet `renovate`, chaque jour ouvré à 7 h (`0 7 * * 1-5`).

**Environnement GitLab**
- C'est quoi : la page de GitLab qui garde l'historique des déploiements (quoi, où, par qui).
- Exemple : `staging` et `production` dans **Operate → Environments**.

---

## 4. Les runners

**GitLab Runner**
- C'est quoi : le programme qui exécute les jobs des pipelines pour GitLab.
- Exemple : GitLab Runner 19.5.0, sur sa propre machine `c7i-flex.large`, séparée de GitLab.

**Runner**
- C'est quoi : un exécutant enregistré dans GitLab, qui prend des jobs.
- Exemple : 2 runners sur la même machine : `code-keeper-runner` (général) et
  `code-keeper-builder`.

**Exécuteur Docker**
- C'est quoi : le mode où chaque job tourne dans un conteneur neuf, supprimé à la fin.
- Ça sert à : des jobs propres, qui ne se gênent pas entre eux.

**Image de job**
- C'est quoi : l'image Docker dans laquelle tourne un job.
- Exemple : `node:24-alpine` pour les applications, `terraform:1.16.6` pour l'infrastructure.

**Étiquette de runner (tag)**
- C'est quoi : un mot qui envoie un job vers un runner précis.
- Exemple : `docker-build` envoie la construction des images vers le runner « builder ».

**Runner protégé**
- C'est quoi : un runner qui ne prend que les jobs des branches protégées.
- Exemple : `code-keeper-builder`, le seul qui a accès à Docker, ne construit que le code
  relu de `main`.

**Socket Docker (socket binding)**
- C'est quoi : partager avec le job la prise de commande de Docker de la machine.
- Ça sert à : construire des images sans mode privilégié.
- Attention : le job pilote alors le Docker de la machine ; c'est pourquoi seul le runner
  protégé l'a.

**Services (GitLab CI)**
- C'est quoi : des conteneurs lancés à côté d'un job, le temps du job.
- Exemple : un vrai PostgreSQL 17 et un vrai RabbitMQ 4.2 pour `integration-test`.

---

## 5. Ansible

**Ansible**
- C'est quoi : un outil qui installe et configure des machines à partir de fichiers texte ;
  il se connecte par SSH, sans agent à installer sur elles.
- Ça sert à : décrire l'état voulu une fois, et l'appliquer autant de fois qu'on veut.
- Exemple : ansible-core 2.21.5 installe GitLab et ses runners en 8 minutes environ.

**Playbook**
- C'est quoi : le fichier principal d'Ansible, qui dit quoi faire sur quelles machines.
- Exemple : `ansible/site.yml`.

**Play**
- C'est quoi : une partie du playbook : un groupe de machines et ce qu'on y fait.
- Exemple : 6 plays : `pki`, `common`, `gitlab`, `gitlab_oidc`, `gitlab_projects`,
  `gitlab_runner`.

**Rôle**
- C'est quoi : un paquet de tâches rangé dans un dossier, réutilisable.
- Exemple : `ansible/roles/gitlab/` installe et configure GitLab.

**Tâche**
- C'est quoi : une seule action (installer un paquet, écrire un fichier, appeler l'API…).
- Exemple : 62 tâches au total, listées par `ansible-playbook site.yml --list-tasks`.

**Module**
- C'est quoi : l'outil qu'utilise une tâche.
- Exemple : `ansible.builtin.cron` crée la tâche de nettoyage hebdomadaire du runner.

**Collection**
- C'est quoi : un paquet de modules en plus, téléchargé avec `ansible-galaxy`.
- Exemple : `community.crypto` crée l'autorité de certification et le certificat de GitLab.

**Inventaire**
- C'est quoi : la liste des machines qu'Ansible gère.
- Exemple : `ansible/inventory/hosts.yml`, écrit par `Scripts/make-hosts.sh` à partir des
  sorties de Terraform (jamais dans git).

**Idempotence**
- C'est quoi : relancer la même chose ne change rien si tout est déjà en place.
- Ça sert à : pouvoir relancer sans risque.
- Exemple : un 2ᵉ passage du playbook donne `changed=0` sur les 3 hôtes.

**`--list-tasks`**
- C'est quoi : l'option qui affiche les tâches du playbook sans rien exécuter.
- Exemple : ce que l'auditeur demande de voir.

**Ansible Vault (coffre)**
- C'est quoi : le chiffrement des secrets d'Ansible.
- Exemple : les mots de passe GitLab et les jetons sont dans `vault.yml`, chiffré et ignoré
  par git ; le mot de passe du coffre est hors du dépôt, dans `~/.config/code-keeper`.

**Paquet Omnibus**
- C'est quoi : le paquet officiel de GitLab, qui contient tout ce qu'il lui faut (base de
  données, serveur web…).
- Exemple : le paquet `gitlab-ce` installé sur Ubuntu 24.04.

**`gitlab-ctl`**
- C'est quoi : la commande qui gère les services du paquet Omnibus.
- Exemple : `sudo gitlab-ctl status`.

**systemd et `systemctl`**
- C'est quoi : le gestionnaire de services de Linux, et sa commande.
- Exemple : `systemctl status gitlab-runsvdir` (GitLab), `systemctl status gitlab-runner
  docker` (runner).

**SSH**
- C'est quoi : la connexion chiffrée à une machine distante, par une clé.
- Exemple : la clé `~/.ssh/code-keeper`, pour GitLab et le runner.

---

## 6. Terraform et l'infrastructure en code

**Infrastructure as Code (IaC, l'infrastructure en code)**
- C'est quoi : décrire son infrastructure dans des fichiers texte au lieu de cliquer dans une
  console.
- Ça sert à : la recréer à l'identique, garder l'historique dans git, relire avant de changer.

**Terraform**
- C'est quoi : l'outil d'infrastructure en code de HashiCorp : on décrit ce qu'on veut dans des
  fichiers `.tf`, Terraform crée, modifie ou supprime ce qu'il faut.
- Exemple : Terraform 1.16.6, pour le socle et pour les 2 environnements.

**Socle (`bootstrap/`)**
- C'est quoi : ce qui doit exister avant tout pipeline, créé une fois depuis le poste admin.
- Exemple : 54 ressources : les machines GitLab et runner, ECR, le stockage des états, OIDC,
  les rôles IAM.

**Module**
- C'est quoi : un ensemble de ressources réutilisable, comme une fonction qu'on appelle.
- Exemple : `modules/environment`, appelé 2 fois, par `envs/staging` et `envs/prod` ; il
  utilise les modules officiels `vpc` 6.7.3 et `eks` 21.29.0.

**Fournisseur (provider)**
- C'est quoi : le « pilote » qui permet à Terraform de parler à un service.
- Exemple : `hashicorp/aws` 6.69.1.

**Fichier de verrouillage (`.terraform.lock.hcl`)**
- C'est quoi : le fichier qui fige la version exacte des fournisseurs.
- Ça sert à : obtenir le même résultat partout, sur le PC comme dans le pipeline.

**État (state)**
- C'est quoi : le fichier où Terraform note ce qu'il a créé.
- Exemple : celui du socle reste sur le PC ; ceux des environnements sont dans S3.

**Backend S3 et verrou**
- C'est quoi : ranger l'état dans un stockage S3 partagé, avec un verrou (`use_lockfile`).
- Ça sert à : que deux pipelines ne modifient jamais le même état en même temps.
- Exemple : `envs/staging/terraform.tfstate` et `envs/prod/terraform.tfstate`.

**`terraform plan` (plan enregistré)**
- C'est quoi : l'aperçu de ce que Terraform va faire ; on peut l'enregistrer dans un fichier.
- Exemple : `plan.tfplan`, gardé un jour, puis appliqué tel quel par `apply`.

**`terraform apply`**
- C'est quoi : la commande qui crée ou modifie réellement l'infrastructure.
- Exemple : 91 ressources par environnement.

**`terraform destroy`**
- C'est quoi : la commande qui supprime ce que Terraform a créé.
- Exemple : le pipeline `infra` lancé avec `DESTROY=true` en fin de séance.

**`terraform fmt` et `terraform validate`**
- C'est quoi : `fmt` vérifie la mise en forme du code, `validate` qu'il est correct.
- Exemple : le job `validate` du pipeline `infra`.

**TFLint**
- C'est quoi : un outil qui repère les mauvaises pratiques dans le code Terraform
  (déclarations inutilisées, versions non figées…).
- Exemple : TFLint 0.64.0, job `tflint` ; il n'a rien trouvé à corriger.

**tfsec**
- C'est quoi : un outil d'analyse de sécurité du code Terraform, cité en bonus par le sujet.
- Exemple : remplacé ici par Trivy (`iac-scan`), déjà utilisé pour les dépendances et les
  images : un outil de moins.

**Étiquettes AWS (tags)**
- C'est quoi : des étiquettes `clé = valeur` posées sur les ressources AWS.
- Exemple : `Stack=bootstrap` sur tout le socle ; une règle IAM interdit aux pipelines de
  toucher ce qui la porte.

---

## 7. AWS

**AWS (Amazon Web Services)**
- C'est quoi : le cloud d'Amazon : des machines, du réseau, du stockage et des services, loués
  à l'heure.
- Exemple : tout le projet est à Paris (`eu-west-3`).

**EC2**
- C'est quoi : le service de machines virtuelles d'AWS.
- Exemple : GitLab sur `m7i-flex.large` (8 Gio de mémoire), le runner sur `c7i-flex.large`
  (4 Gio).

**IP fixe (Elastic IP)**
- C'est quoi : une adresse publique qui ne change pas quand on éteint et rallume la machine.
- Exemple : GitLab et le runner gardent la même adresse d'une séance à l'autre.

**VPC**
- C'est quoi : un réseau privé, isolé, dans le cloud.
- Exemple : 3 VPC : l'outillage `10.100.0.0/24`, staging `10.0.0.0/16`, prod `10.1.0.0/16`.

**Groupe de sécurité (Security Group)**
- C'est quoi : un pare-feu autour d'une ressource.
- Exemple : GitLab ne s'ouvre qu'à mon IP, à celles de l'équipe (web seulement) et au runner.

**Service de métadonnées (IMDSv2)**
- C'est quoi : une adresse interne qui donne à une machine EC2 des informations sur elle-même,
  et parfois des droits AWS.
- Exemple : limité à un saut (`http_put_response_hop_limit = 1`) : les conteneurs des jobs
  ne peuvent pas le joindre.

**S3**
- C'est quoi : le stockage de fichiers d'AWS.
- Exemple : un stockage privé pour les états Terraform (versionné, chiffré, HTTPS
  obligatoire) et un stockage public pour les 2 documents OIDC de GitLab.

**ECR (Elastic Container Registry)**
- C'est quoi : le registre d'images Docker privé d'AWS.
- Exemple : 6 dépôts d'images partagés par staging et prod, étiquettes **immuables**, scan à
  chaque envoi, 30 images gardées.

**EKS (Elastic Kubernetes Service)**
- C'est quoi : Kubernetes géré par AWS.
- Exemple : un cluster EKS 1.36 par environnement, 2 à 3 nœuds `c7i-flex.large`.

**API Gateway et Cognito**
- C'est quoi : API Gateway est la porte d'entrée HTTPS gérée par AWS ; Cognito gère les
  utilisateurs et leur donne un jeton.
- Exemple : sans jeton Cognito valide, `/api/*` répond `401` ; limite de 20 requêtes par
  seconde.

**ALB interne**
- C'est quoi : un répartiteur de charge sans adresse publique.
- Exemple : il reçoit le trafic d'API Gateway et l'envoie aux nœuds du cluster.

**CloudWatch**
- C'est quoi : la surveillance d'AWS (métriques, journaux, tableaux de bord).
- Exemple : les journaux des environnements, gardés un jour.

**AWS CLI**
- C'est quoi : l'outil en ligne de commande d'AWS (`aws …`).
- Exemple : les scripts de `Scripts/` et les jobs qui poussent les images.

---

## 8. Les identités, les secrets et les droits

**IAM (Identity and Access Management)**
- C'est quoi : le service d'AWS qui décide **qui** peut faire **quoi**.

**Utilisateur IAM et clé d'accès**
- C'est quoi : une identité permanente, avec une clé (identifiant + secret) pour la ligne de
  commande.
- Exemple : `clecart-admin`, sur mon poste seulement, pour le socle et les scripts ; les
  pipelines ne l'utilisent jamais.

**Rôle IAM**
- C'est quoi : un ensemble de droits qu'on « emprunte » pour un temps, sans mot de passe
  permanent.
- Exemple : `code-keeper-ci-infra`, `code-keeper-ci-inventory-app`… un par projet.

**Politique IAM (policy)**
- C'est quoi : la liste écrite des actions autorisées ou interdites.
- Exemple : une application ne peut pousser que **sa** propre image.

**Politique de confiance (trust policy)**
- C'est quoi : la règle qui dit **qui** a le droit de prendre un rôle.
- Exemple : seul le jeton du projet, sur la branche `main`, peut prendre son rôle.

**OIDC (OpenID Connect)**
- C'est quoi : une méthode standard pour prouver son identité avec un jeton signé.
- Ça sert à : donner des droits AWS aux pipelines **sans aucune clé stockée**.
- Exemple : chaque job de `main` échange son jeton GitLab contre le rôle de son projet.

**Jeton d'identité (ID token) et JWT**
- C'est quoi : un « badge » numérique signé par GitLab, qui dit quel projet, quelle branche et
  quel job le demande. JWT est son format.
- Exemple : `id_tokens: AWS_ID_TOKEN` dans les pipelines, valable pour `sts.amazonaws.com`.

**`sub` et `aud`**
- C'est quoi : deux champs du jeton. `sub` dit **qui** (projet et branche), `aud` dit **pour
  qui** il est fait.
- Exemple : `project_path:code-keeper/infra:ref_type:branch:ref:main`.

**Fournisseur OIDC (IAM)**
- C'est quoi : la déclaration, dans AWS, de GitLab comme émetteur de jetons de confiance.
- Exemple : AWS lit les clés publiques de GitLab dans un stockage S3 public, car GitLab est
  fermé à Internet (méthode de la documentation GitLab).

**STS et identifiants temporaires**
- C'est quoi : STS est le service d'AWS qui donne des identifiants valables peu de temps.
- Exemple : une heure au plus pour un job ; rien à voler après.

**Principe du moindre privilège**
- C'est quoi : donner à chacun uniquement les droits dont il a besoin, rien de plus.
- Ça sert à : limiter les dégâts si quelque chose est piraté.
- Exemple : un rôle par projet ; un Role Kubernetes par application.

**Escalade de privilèges**
- C'est quoi : réussir à se donner plus de droits que ceux qu'on a reçus.
- Exemple : sans limite, le rôle `infra` aurait pu créer un rôle plus puissant que lui.

**Limite de permissions (permissions boundary)**
- C'est quoi : un plafond de droits posé sur un rôle : quoi qu'on lui donne, il ne le dépasse
  jamais.
- Exemple : `code-keeper-environment-boundary`, obligatoire sur tout rôle créé par le
  pipeline `infra`.

**Refus explicite (Deny)**
- C'est quoi : une interdiction qui l'emporte sur toute autorisation.
- Exemple : aucun rôle des pipelines ne peut toucher aux machines étiquetées `Stack=bootstrap`.

**Simulateur de politiques IAM**
- C'est quoi : l'outil d'AWS qui dit si une action serait autorisée, sans la faire.
- Exemple : 15 essais sur 15 avec le résultat attendu
  (`preuves/2026-10-22-iam-fixes/simulateur.log`).

**Secret**
- C'est quoi : une donnée à ne jamais montrer (mot de passe, jeton, clé).
- Exemple : aucun dans le code ; les mots de passe des bases sont tirés au hasard **dans le
  cluster**.

**Autorité de certification (CA)**
- C'est quoi : celui qui signe les certificats et garantit qu'ils sont authentiques.
- Exemple : une CA propre au projet, créée par Ansible, qui signe le certificat HTTPS de
  GitLab ; sa clé privée reste sur mon poste.

**Certificat, HTTPS et TLS**
- C'est quoi : HTTPS est le web chiffré, TLS la technique de chiffrement ; le certificat prouve
  l'identité du serveur.
- Exemple : le navigateur avertit sur GitLab tant que le certificat de la CA du projet n'est
  pas importé.

**Let's Encrypt**
- C'est quoi : une autorité qui délivre des certificats gratuits reconnus par les navigateurs.
- Exemple : écarté : il aurait fallu ouvrir GitLab à tout Internet.

---

## 9. Les scans et la qualité du code

**Scan de sécurité**
- C'est quoi : une analyse automatique qui cherche des failles connues ou des erreurs
  dangereuses.
- Exemple : un job qui échoue arrête le pipeline : pas d'image, pas de déploiement.

**CVE**
- C'est quoi : le numéro officiel d'une faille de sécurité connue.
- Exemple : CVE-2026-90711, faille critique de `proxy-addr`, trouvée par Trivy et corrigée
  avant le premier pipeline.

**Gravité**
- C'est quoi : le niveau d'une faille : faible, moyenne, haute (HIGH), critique (CRITICAL).
- Exemple : les pipelines bloquent sur HIGH et CRITICAL.

**SAST (Static Application Security Testing)**
- C'est quoi : l'analyse de sécurité du code source, sans le lancer.
- Exemple : le SAST de GitLab (gratuit), avec l'analyseur Semgrep.

**Semgrep**
- C'est quoi : l'analyseur qui lit le code et cherche des motifs dangereux.
- Exemple : le job `semgrep-sast` ; `sast-gate` échoue s'il trouve une faille haute ou
  critique.

**Trivy**
- C'est quoi : un scanner gratuit, sans compte : dépendances, secrets, images Docker et code
  Terraform.
- Exemple : Trivy 0.76.1 dans 3 jobs : `dependency-scan`, `containerization` (image) et
  `iac-scan` (Terraform).

**`--ignore-unfixed`**
- C'est quoi : l'option de Trivy qui ne bloque que les failles qui ont déjà une correction.
- Ça sert à : ne pas bloquer le pipeline sur une faille que personne ne peut encore corriger.

**Analyse de l'IaC (`iac-scan`)**
- C'est quoi : chercher les défauts de sécurité dans le code Terraform.
- Exemple : 4 défauts acceptés et justifiés dans `.trivyignore.yaml` du dépôt `infra`.

**Lint et linter**
- C'est quoi : un linter lit le code et signale les erreurs probables et les mauvaises
  pratiques.
- Exemple : ESLint 10.12.0 (job `lint`) pour le JavaScript, hadolint pour le Dockerfile.

**hadolint**
- C'est quoi : le linter des Dockerfile.
- Exemple : hadolint v2.15.1, job `dockerfile-lint`.

**Vérification de syntaxe**
- C'est quoi : vérifier qu'un fichier est du code valide, sans le lancer.
- Exemple : `node --check` sur chaque fichier, dans le job `build`.

**Scan ECR**
- C'est quoi : le scan des failles fait par ECR à chaque image envoyée.

**OSV**
- C'est quoi : une base publique de failles connues dans les bibliothèques.
- Exemple : Renovate l'utilise pour ouvrir des demandes de fusion de sécurité.

**Témoin (contrôle)**
- C'est quoi : un essai fait exprès pour vérifier qu'un contrôle sait bien échouer.
- Exemple : un fichier cassé exprès a prouvé que la vérification de syntaxe le refuse.

---

## 10. Kubernetes et le déploiement

**Kubernetes (K8s)**
- C'est quoi : l'outil qui lance les conteneurs sur les machines d'un cluster, les relance
  s'ils plantent, et en ajoute si la charge monte.

**Pod**
- C'est quoi : la plus petite unité de Kubernetes : un ou quelques conteneurs qui tournent
  ensemble.

**Deployment et StatefulSet**
- C'est quoi : un Deployment fait tourner des copies interchangeables ; un StatefulSet, des
  copies qui gardent leur nom et leur disque.
- Exemple : api-gateway et inventory-app sont des Deployments ; billing-app, les bases et
  RabbitMQ des StatefulSets.

**Namespace**
- C'est quoi : un « dossier » qui regroupe et isole des objets Kubernetes.
- Exemple : tout est dans `code-keeper`.

**Manifest**
- C'est quoi : un fichier YAML qui décrit un objet Kubernetes.
- Exemple : `repos/api-gateway-app/k8s/api-gateway-app.yaml`.

**kubectl**
- C'est quoi : l'outil en ligne de commande de Kubernetes.
- Exemple : `kubectl -n code-keeper rollout status deployment/inventory-app`.

**kustomize**
- C'est quoi : un outil intégré à kubectl qui assemble des manifests et les adapte sans les
  recopier.
- Exemple : le pipeline y écrit l'étiquette de la nouvelle image, puis `kubectl apply -k`.

**Helm et chart**
- C'est quoi : Helm est le « gestionnaire de paquets » de Kubernetes ; un chart est un paquet.
- Exemple : la surveillance (kube-prometheus-stack 92.11.0), Fluent Bit 0.58.3, le Cluster
  Autoscaler 9.59.0.

**Couche plateforme**
- C'est quoi : ce qui tourne dans le cluster sans faire partie d'une application.
- Exemple : les 2 bases, RabbitMQ, la surveillance, les droits ; déployés par le pipeline
  `infra`, jamais redémarrés par un déploiement d'application.

**Mise à jour progressive (rolling update)**
- C'est quoi : remplacer les pods un par un au lieu de tous d'un coup.
- Exemple : `maxSurge: 1` (un pod de plus pendant la mise à jour), `maxUnavailable: 0` (aucun
  pod en moins).

**Sonde de disponibilité (readiness probe)**
- C'est quoi : le test qui dit si un pod peut recevoir des requêtes.
- Exemple : un nouveau pod ne reçoit du trafic que quand sa sonde répond.

**`preStop`**
- C'est quoi : une action lancée juste avant l'arrêt d'un conteneur.
- Exemple : une pause de 10 s, le temps que plus aucune requête ne lui soit envoyée.

**HPA (HorizontalPodAutoscaler)**
- C'est quoi : la règle qui ajoute ou retire des copies d'un service selon la charge.
- Exemple : api-gateway et inventory-app, de 2 à 5 copies.

**PodDisruptionBudget (budget de perturbation)**
- C'est quoi : la règle qui limite le nombre de copies arrêtées en même temps pendant une
  maintenance.
- Exemple : `maxUnavailable: 1` : les copies partent une par une.

**Vidange d'un nœud (drain)**
- C'est quoi : vider une machine de ses pods avant une maintenance.
- Exemple : 136 requêtes sur 136 et 109 sur 109 réussies pendant une vidange.

**RBAC, Role et RoleBinding**
- C'est quoi : les droits dans Kubernetes. Un **Role** liste des actions permises, un
  **RoleBinding** les donne à un groupe.
- Exemple : le groupe `code-keeper-deploy-inventory-app` ne peut modifier que les objets
  d'inventory-app ; 118 contrôles sur 118 (`Scripts/rbac-test.sh`).

**Entrée d'accès EKS (access entry)**
- C'est quoi : le lien, dans EKS, entre un rôle IAM et un groupe Kubernetes.
- Exemple : le rôle `code-keeper-ci-billing-app` devient le groupe
  `code-keeper-deploy-billing-app` dans le cluster.

**Pod Security (`restricted`)**
- C'est quoi : le niveau de sécurité imposé aux pods d'un namespace.
- Exemple : un pod privilégié est refusé dans `code-keeper` (*« violates PodSecurity
  "restricted:v1.36" »*).

**ResourceQuota (quota)**
- C'est quoi : une limite sur ce qu'on peut créer dans un namespace.
- Exemple : `no-load-balancers` : aucun load balancer payant créé hors de Terraform.

**NetworkPolicy**
- C'est quoi : une règle qui dit quels pods peuvent parler à quels pods.
- Exemple : tout le trafic entrant est refusé par défaut, puis seuls les échanges utiles sont
  ouverts.

**Secret Kubernetes**
- C'est quoi : un objet qui contient une donnée sensible.
- Exemple : les mots de passe des bases et de RabbitMQ, que les pipelines des applications ne
  peuvent pas lire.

---

## 11. Les tests

**Test unitaire**
- C'est quoi : un test d'un petit morceau de code, seul.
- Exemple : 101 tests (40 + 39 + 22), `npm test`.

**Test d'intégration**
- C'est quoi : un test de l'application réelle avec ses vrais partenaires (base, file de
  messages).
- Exemple : 16 tests (9 + 4 + 3) contre de vrais PostgreSQL 17 et RabbitMQ 4.2, avec des
  identifiants jetables propres au job.

**Test de bout en bout**
- C'est quoi : un test du système entier, comme un vrai utilisateur.
- Exemple : `Scripts/test-api.sh` passe par l'URL publique et le jeton Cognito : 16 contrôles.

**Rapport JUnit**
- C'est quoi : un format standard de résultats de tests, que GitLab affiche.
- Exemple : le nombre de tests réussis apparaît dans la demande de fusion.

**Scripts de contrôle**
- C'est quoi : des scripts qui vérifient une règle sur le vrai système.
- Exemple : `protection-test.sh` (9 contrôles), `rbac-test.sh` (118),
  `zero-downtime-test.sh` (requêtes en continu pendant un déploiement).

**`npm ci` et `package-lock.json`**
- C'est quoi : `package-lock.json` note la version exacte de chaque dépendance ; `npm ci`
  installe exactement celles-là.
- Ça sert à : tester et construire avec les mêmes versions partout.

---

## 12. Les mises à jour

**Dépendance**
- C'est quoi : une bibliothèque ou un outil dont le projet a besoin.
- Exemple : `express`, `pg`, `amqplib` côté code ; Terraform, Trivy, les charts Helm côté
  outils.

**Version figée (épinglée)**
- C'est quoi : une version écrite exactement, qui ne change que par une décision.
- Exemple : GitLab `19.5.1-ce.0`, Trivy `0.76.1`, l'image `terraform:1.16.6`.

**Renovate**
- C'est quoi : un robot qui cherche les nouvelles versions des dépendances et ouvre une
  demande de fusion pour chacune.
- Exemple : Renovate 44.176.2, chaque jour ouvré à 7 h ; le 22 octobre, 9 demandes, toutes
  avec un pipeline vert.

**Tableau de bord des dépendances (Dependency Dashboard)**
- C'est quoi : un ticket tenu à jour par Renovate, qui liste les mises à jour de chaque dépôt.

**Mise à jour de sécurité**
- C'est quoi : une mise à jour qui corrige une faille connue.
- Exemple : `morgan` 1.12.1 (2 failles moyennes), fusionnée (`api-gateway-app!3`) et déployée
  en prod le jour même.

**Correctif critique (patch release)**
- C'est quoi : une petite version publiée en urgence pour corriger une faille.
- Exemple : GitLab 19.5.0 → 19.5.1, en changeant une ligne d'Ansible.

**Correctifs automatiques d'Ubuntu**
- C'est quoi : l'installation automatique, chaque jour, des mises à jour de sécurité du
  système.
- Exemple : activés par le rôle Ansible `common` sur GitLab et le runner.

**Dependabot**
- C'est quoi : l'équivalent de Renovate chez GitHub.
- Exemple : écarté : c'est un service de GitHub, et le projet vit dans GitLab.

---

## 13. L'application

**Microservices**
- C'est quoi : une application découpée en petits services indépendants.
- Exemple : `inventory-app`, `billing-app`, `api-gateway-app`, chacun dans son dépôt et avec
  son pipeline.

**inventory-app**
- C'est quoi : l'API des films (ajouter, lire, modifier, supprimer), avec sa base PostgreSQL.

**billing-app**
- C'est quoi : le service qui lit les commandes dans RabbitMQ et les enregistre dans sa base.

**api-gateway-app**
- C'est quoi : le point d'entrée **de l'application** : il relaie les films vers inventory-app
  et dépose les commandes dans RabbitMQ.
- Attention : à ne pas confondre avec **API Gateway**, le service d'AWS placé devant lui.

**PostgreSQL**
- C'est quoi : une base de données relationnelle.
- Exemple : PostgreSQL 17, une base pour l'inventaire, une pour les commandes.

**RabbitMQ**
- C'est quoi : une file de messages, un « bureau de poste » entre services.
- Exemple : si billing-app est arrêté, les commandes attendent dans la file, aucune n'est
  perdue.

**Conteneur, image et Dockerfile**
- C'est quoi : un conteneur est une application emballée avec tout ce qu'il lui faut ; l'image
  est son modèle figé ; le Dockerfile, la recette de l'image.
- Exemple : chaque dépôt d'application a son `Dockerfile` ; l'image part dans ECR.

**Node.js**
- C'est quoi : le moteur qui fait tourner du JavaScript côté serveur.
- Exemple : les 3 applications, en Node.js 24.

**crud-master**
- C'est quoi : le projet d'école d'où vient l'application (API de films et de commandes).
- Exemple : bonus : c'est mon propre code, déjà utilisé dans cloud-design, au lieu de celui
  fourni.

---

## 14. Les coûts

**Paiement à l'usage**
- C'est quoi : on paie à l'heure ce qu'on utilise vraiment.
- Exemple : ≈ 0,38 $/h par environnement, ≈ 0,23 $/h pour GitLab et le runner, ≈ 1 $/h tout
  allumé.

**Plan gratuit et crédits**
- C'est quoi : la formule d'AWS pour les nouveaux comptes : des crédits offerts, sans jamais
  débiter la carte ; le compte ferme quand ils sont épuisés.
- Exemple : le compte du projet, sur le plan gratuit du début à la fin.

**Éteindre ou détruire**
- C'est quoi : éteindre une machine garde ses disques et son adresse (encore payants) ;
  détruire supprime tout.
- Exemple : GitLab et le runner sont éteints entre deux séances (≈ 0,46 $/jour) ; les
  environnements sont détruits.

**Fin de séance**
- C'est quoi : tout arrêter dans le bon ordre à la fin du travail.
- Exemple : pipeline `infra` avec `DESTROY=true`, puis `Scripts/tooling.sh stop`, puis
  `Scripts/inventory.sh`.

**Inventaire**
- C'est quoi : la vérification qu'il ne reste rien de payant.
- Exemple : `Scripts/inventory.sh` regarde les 17 régions et sort en erreur s'il reste
  quelque chose en dehors du socle éteint.

**AWS Budgets**
- C'est quoi : le service qui envoie une alerte quand les dépenses dépassent un seuil.
- Exemple : budget de 10 $ par mois, alertes à 50 % et 100 %.
