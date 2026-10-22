# Révision de l'audit — code-keeper

Fiche de préparation du jeu de rôle (« vous êtes l'ingénieur DevOps qui présente sa solution ») et de la
démonstration. Les détails sont dans le [README](README.md).

## Les chiffres à connaître

| Sujet | Valeur |
|---|---|
| Dépôts GitLab | 5 : `inventory-app`, `billing-app`, `api-gateway-app`, `infra`, `renovate` |
| Comptes | `clecart` (Owner), `stakeholder` (Maintainer, approuve la prod), `developer` (Developer), `renovate-bot` (Developer) |
| GitLab | CE 19.5.1 sur `m7i-flex.large` ; 2 runners 19.5.0 sur `c7i-flex.large` |
| Terraform | 54 ressources pour le socle ; 91 par environnement (staging, prod) |
| Pipeline infra | Création : staging ≈ 16 min, prod ≈ 13 min après approbation ; suppression : staging ≈ 14 min, prod ≈ 12 min après approbation (91 ressources de chaque côté) |
| Pipeline d'une application | ≈ 2 min 30 jusqu'à staging ; 14 s pour la prod après approbation (mesuré avant l'ajout de `integration-test` et `lint`) |
| Jobs par pipeline | Application : 8 sur une branche ou une demande de fusion, 12 sur `main` ; infra : 3 sur une branche (étape `validate`), 4 sur une demande de fusion, 12 sur `main` (pipeline n° 44), 11 pour une suppression |
| Tests | 101 tests unitaires (40, 39, 22) ; tests d'intégration : 9, 4 et 3 ; scénario de bout en bout 16/16 en staging et en prod |
| Sans coupure | 74/74 et 90/90 requêtes en HTTP 200 pendant une mise à jour ; 136/136 et 109/109 pendant la vidange d'un nœud ; **740/740 en prod pendant un vrai déploiement** (pipeline n° 47) |
| Contrôles scriptés | `protection-test.sh` : 9/9 ; `rbac-test.sh` : 118/118 en staging et en prod |
| Coûts | ≈ 0,77 $/h les deux environnements, ≈ 0,23 $/h GitLab + runner ; éteints : 0,46 $/jour |
| Failles trouvées puis corrigées | `proxy-addr` (critique), `follow-redirects` (2 hautes) ; GitLab 19.5.0 → 19.5.1 ; `morgan` 1.12.1 (2 moyennes) : demande Renovate fusionnée et déployée (pipeline n° 43) |

## Déroulé de la démonstration

Avant l'audit : tout rallumer ([README §4.7](README.md#47-le-début-de-séance-et-avant-laudit)), compter environ 45 min.
Répété le 22 octobre : pipelines n° 38 (infra) et 40 à 42 (applications), puis `Scripts/test-api.sh` 16/16 en staging
et 9/9 en prod (`--skip-stop`).

| Question de la grille | Ce que je montre |
|---|---|
| Fichiers du dépôt | `tree -L 2` ; README ; `ansible/` ; `repos/*/.gitlab-ci.yml` |
| GitLab par Ansible | `ansible-playbook site.yml --list-tasks` ; deux passages de suite : le second donne `changed=0` (le premier peut installer des correctifs Ubuntu ; mesuré le 22 octobre sur les 3 hôtes) |
| Services | Par `ssh -i ~/.ssh/code-keeper` : `systemctl status gitlab-runsvdir` et `sudo gitlab-ctl status` (GitLab) ; `systemctl status gitlab-runner docker` (runner) |
| Runners | GitLab → Admin → CI/CD → Runners : 2 en ligne ; jobs exécutés dans chaque pipeline |
| Infra 2 environnements | `diff` des deux `main.tf` ; pipeline `infra` et ses 7 étapes (`validate` : `validate`, `tflint`, `iac-scan`) |
| CI/CD | Une modification de code → demande de fusion → fusion → staging → approbation (`stakeholder`) → prod |
| Fonctionnement | `Scripts/test-api.sh prod` (16/16) ; `Scripts/zero-downtime-test.sh staging api-gateway` (puis `… drain`) |
| Sécurité | `Scripts/protection-test.sh` (9/9, dont créer un projet et approuver la prod) ; rôles IAM ; `Scripts/rbac-test.sh staging` (droits Kubernetes des pipelines d'applications) ; Pod Security ; Renovate (demande de sécurité `morgan`, fusionnée et déployée : `api-gateway-app!3`) |

## Les 16 questions du jeu de rôle

### 1. Qu'est-ce que DevOps, et quels bénéfices pour le cycle de vie du logiciel ?
DevOps, c'est une culture et un ensemble de pratiques qui rapprochent ceux qui écrivent le code (Dev) et ceux qui le
font tourner (Ops), avec un objectif commun : livrer souvent, vite et sans casser la production. Les bénéfices :
des livraisons plus fréquentes et plus petites (donc moins risquées), des erreurs trouvées plus tôt (tests et scans
automatiques), un retour en arrière simple, moins de tâches manuelles, et une même façon de travailler pour tous.
Ici : une modification du code arrive en production en quelques minutes, testée, scannée et approuvée.

### 2. Comment DevOps améliore-t-il la collaboration entre développement et exploitation ?
Tout le monde partage les mêmes outils et la même source de vérité : le code dans GitLab, l'infrastructure décrite
dans Git (Terraform, Ansible), les pipelines visibles par tous. Le développeur propose par une demande de fusion, la
CI donne un verdict objectif, l'exploitant (ou le responsable, `stakeholder`) approuve la mise en production. Les
problèmes se règlent sur une demande de fusion ou un ticket, plus par messages perdus. Renovate et le tableau de
bord des dépendances rendent la maintenance visible pour tous.

### 3. Quelles pratiques DevOps courantes, et comment les avez-vous intégrées ?
| Pratique | Dans le projet |
|---|---|
| Gestion de versions et branches protégées | GitLab, `main` protégée, demandes de fusion |
| Intégration continue | Build, tests unitaires et d'intégration, scans et lint à chaque push et demande de fusion |
| Livraison et déploiement continus | Staging automatique, prod après approbation, sans coupure |
| Infrastructure as Code | Terraform (socle, 2 environnements), Ansible (GitLab, runners) ; Terraform vérifié à chaque pipeline (`validate`, TFLint, Trivy) |
| Sécurité intégrée (DevSecOps) | SAST, Trivy (dépendances, images, Terraform), hadolint, scan ECR, OIDC, moindre privilège (AWS et Kubernetes) |
| Surveillance | Prometheus, Grafana, CloudWatch (repris de cloud-design) |
| Maintenance continue | Renovate, correctifs automatiques, versions figées |

### 4. Pourquoi l'automatisation est-elle centrale, et quels outils avez-vous utilisés ?
L'automatisation rend les opérations répétables, rapides et sans oubli : la même commande donne le même résultat,
et elle sert de documentation vivante. Outils : **Terraform** (socle et environnements), **Ansible** (installation
et configuration de GitLab, des comptes, des projets, des runners), **GitLab CI** (tous les pipelines), **Docker**
(images), **kubectl/Helm/kustomize** (déploiements), **Trivy, Semgrep, hadolint, TFLint, ESLint** (scans), **Renovate** (mises à
jour), et des scripts de vérification (tests de bout en bout, de coupure, de protection, inventaire des coûts).

### 5. Quel est le rôle de la CI/CD, et comment améliore-t-elle qualité et vitesse ?
La CI vérifie chaque changement dès qu'il est poussé : il se construit, ses tests passent, il n'apporte pas de faille.
La CD emmène automatiquement ce changement validé jusqu'aux environnements, toujours de la même façon. Qualité :
rien n'arrive en production sans tests verts, scans propres et passage par staging. Vitesse : environ 2 min 30
jusqu'à staging, un clic d'approbation, 14 s pour la prod. Exemple réel : Trivy a trouvé une faille critique dans
une dépendance, corrigée avant le premier pipeline des applications.

### 6. Pourquoi l'Infrastructure as Code, et comment garantit-elle cohérence et reproductibilité ?
L'infrastructure est décrite dans des fichiers versionnés, relus et appliqués par un outil : pas de clic oublié, et
on peut la recréer à l'identique. Ici, staging et prod sont **le même module Terraform** appelé deux fois : le `diff`
des deux fichiers ne montre que le nom, la plage réseau et la clé de l'état. Le pipeline les crée et les supprime à
la demande, à l'identique (le 22 octobre : création n° 5, suppression n° 36, recréation n° 38). GitLab lui-même est
reproductible : un second passage du playbook ne change rien (`changed=0`).

### 7. Comment DevOps améliore-t-il la sécurité, et qu'avez-vous intégré ?
La sécurité devient automatique et continue au lieu d'être un contrôle final. Dans ce projet : SAST et scans de
dépendances, d'images et de la configuration Terraform à chaque pipeline (bloquants), branches protégées, comptes
sans droit de créer un projet personnel ni un groupe (un Developer n'a ainsi aucun projet à lui pour atteindre le
runner « builder »), aucun secret dans le code (Ansible Vault, variables masquées, mots de passe générés dans le
cluster), aucun accès AWS stocké (OIDC), un rôle par projet avec le moindre privilège, un Role Kubernetes par
application (il ne peut modifier que ses objets), Pod Security et quotas dans Kubernetes, GitLab fermé à Internet,
mises à jour automatiques (Renovate : la correction de sécurité de `morgan`, proposée et déployée le même jour) et
correctif GitLab appliqué le jour même.

### 8. Quelles difficultés, et comment les avez-vous surmontées ?
- **GitLab fermé et OIDC** : AWS doit lire les clés de GitLab ; solution documentée par GitLab, une copie des clés
  publiques dans S3 (et une empreinte pour créer le fournisseur IAM avant ce dépôt).
- **Moindre privilège réel** : une relecture avec le simulateur IAM a montré que le rôle Terraform pouvait s'auto-élever
  ; ajout d'une limite de permissions et d'une interdiction sur le socle, prouvées au simulateur. De même, le rôle de
  déploiement de chaque application pouvait modifier tout l'espace `code-keeper` (bases, RabbitMQ, secrets) : il ne
  peut plus modifier que ses propres objets (un Role Kubernetes par application).
- **Pièges de GitLab CI** : SAST absent des pipelines de demande de fusion, vérification de syntaxe qui ne pouvait
  pas échouer : trouvés en relecture, corrigés et prouvés par des témoins. Plus tard, `integration-test` et `lint`
  manquaient aux `needs` de `containerization` : leur échec n'aurait pas bloqué le déploiement (corrigé).
- **Synchroniser les dépôts** : avec `git subtree`, une fusion faite dans GitLab ne pouvait plus être ramenée
  (« unrelated histories ») ; `Scripts/repos.sh` synchronise maintenant le contenu et refuse de publier par-dessus une
  version jamais ramenée.
- **Coûts** : discipline de fin de séance, inventaire automatique, quota contre les load balancers non prévus.

### 9. Comment DevOps aide-t-il à optimiser les ressources et les coûts dans le cloud ?
Ce qui est décrit en code se crée et se détruit à la demande : les environnements ne coûtent que pendant les heures
de travail (0,77 $/h), GitLab et le runner sont éteints la nuit (0,46 $/jour). Choix économiques : une passerelle NAT
au lieu de deux, pas de clé KMS dédiée, journaux gardés un jour, machines du plan gratuit, images de 30 versions au
plus, autoscaling de 2 à 3 nœuds. L'inventaire de fin de séance vérifie qu'il ne reste rien de payant en dehors du socle éteint (disques et IP de
GitLab et du runner, ≈ 13,80 $/mois).

### 10. Pourquoi GitLab et GitLab Runner, et qu'apportent-ils ?
GitLab réunit au même endroit le code, les demandes de fusion, les droits, les pipelines, les variables secrètes,
les environnements et l'historique des déploiements (qui a approuvé quoi, quand). Les runners exécutent les jobs
dans des conteneurs propres et jetables. J'en ai deux : un général (sans accès à Docker) et un « builder » réservé aux
branches protégées, qui seul construit les images. Auto-hébergé, GitLab reste privé et gratuit (édition CE).

### 11. Quels avantages d'Ansible pour déployer GitLab et ses runners ?
Ansible décrit l'état voulu (paquets, configuration, comptes, projets, runners) et ne change que ce qui diffère :
relancé, il ne fait rien. Il ne demande rien sur les machines (SSH seulement), il garde les secrets chiffrés (Ansible
Vault) et il sert de documentation. Il m'a permis de monter GitLab en 8 minutes, puis de le mettre à jour en 19.5.1
en changeant une ligne, et de créer comptes, projets, variables et programmations par l'API, sans clic.

### 12. Qu'est-ce que l'IaC, et comment l'avez-vous mise en œuvre avec Terraform ?
Deux niveaux. **`bootstrap/`** (lancé depuis le poste admin) : réseau, machines GitLab et runner, ECR, stockage des
états, OIDC et rôles IAM (54 ressources). **`infra`** (lancé par son pipeline) : un module `environment` (VPC, EKS,
ALB, API Gateway, Cognito, CloudWatch, rôles des pods) appelé par `envs/staging` et `envs/prod` ; états séparés dans
S3 avec verrou ; versions des fournisseurs figées par les fichiers de verrouillage ; code vérifié à chaque pipeline
(`terraform validate`, TFLint, analyse de sécurité Trivy) ; plan enregistré puis appliqué tel quel.

### 13. À quoi servent les pipelines CI/CD, et qu'ont-ils automatisé ?
Ils transforment chaque changement en un parcours toujours identique et vérifié. Ici, sans intervention : installer
les dépendances exactes, vérifier la syntaxe, lancer les tests unitaires et d'intégration (vrais PostgreSQL et
RabbitMQ), analyser le code (SAST, ESLint) et les dépendances, puis, seulement si tout est vert, construire l'image,
la scanner, la pousser dans ECR, la déployer en staging et attendre la fin du déploiement. Côté infrastructure :
vérifier le Terraform (format, validité, TFLint, Trivy), calculer les plans, les appliquer et déployer la
plateforme. Seule l'approbation de la production reste humaine, volontairement.

### 14. Comment avez-vous assuré la sécurité tout au long des étapes du pipeline ?
| Étape | Sécurité |
|---|---|
| Déclenchement | `main` protégée ; jobs AWS et variables réservés à `main` ; runner « builder » protégé |
| Build/Test | Dépendances exactes (`npm ci`), conteneurs jetables ; tests d'intégration avec des services et des identifiants jetables, propres au job |
| Scan | SAST (bloquant sur haute et critique), Trivy dépendances et secrets, hadolint, ESLint |
| Validate (`infra`) | Trivy sur la configuration Terraform (bloquant sur haute et critique, 4 exceptions justifiées), TFLint ; sans accès AWS |
| Containerization | Seulement si tous les contrôles ont réussi (`needs`) ; Trivy sur l'image avant l'envoi ; étiquettes ECR immuables ; scan ECR à l'envoi |
| Déploiement | OIDC (pas de clé), rôle limité à **ses** objets de l'espace `code-keeper` (Role Kubernetes), Pod Security `restricted`, quota |
| Production | Approbation par un Maintainer, tracée par GitLab |

### 15. Expliquez le pipeline CI de chaque dépôt
Applications : `build` (npm ci + syntaxe), `test` (tests unitaires : 40/39/22, rapport JUnit) et `integration-test`
(l'application réelle contre de vrais PostgreSQL 17 et RabbitMQ 4.2, services GitLab : 9/4/3 tests), `scan`
(`semgrep-sast` + `sast-gate`, `dependency-scan` Trivy, `dockerfile-lint` hadolint, `lint` ESLint),
`containerization` (sur `main`, seulement si tous ces jobs ont réussi : image construite, scannée, poussée dans ECR
avec le commit comme étiquette). Le même fichier sert aux trois, seules deux variables changent. Infra : `images`,
`init`, l'étape `validate` (`validate` : fmt + validate ; `tflint` : bonnes pratiques ; `iac-scan` : sécurité, avec
Trivy), `plan` des deux environnements. Sur une demande de fusion, seuls `init` (sans état) et l'étape `validate`
tournent, et l'étape `validate` seule sur un push de branche, sans accès AWS. Renovate : `validate-config` à chaque
push et demande de fusion.

### 16. Expliquez le pipeline CD de chaque dépôt
Applications : `deploy-staging` (mise à jour progressive : un nouveau pod prêt avant qu'un ancien s'arrête, pause de
10 s à l'arrêt, attente de la fin du déploiement), `approve-production` (manuel, Maintainers), `deploy-production`
(la même image) ; pour api-gateway et inventory-app, 2 copies au minimum et un budget de perturbation : une
maintenance de nœud ne les coupe pas non plus. Le déploiement ne part qu'après `containerization`, donc après tous
les contrôles, et son rôle ne peut modifier dans Kubernetes que les objets de son application. Exemple réel : la
mise à jour de sécurité `morgan`, fusionnée dans `api-gateway-app`, a été déployée par le pipeline n° 43 (image
`8c26f43b`) en staging, puis en prod après approbation.
Infra : les plans attendent toute l'étape `validate` ; `apply-staging` puis la plateforme (bases, RabbitMQ,
surveillance, droits des pipelines d'applications), `approve-production`, `apply-production`. Avec `DESTROY=true`, le
même chemin supprime les environnements, la prod seulement après approbation.

## Alternatives et limites

Résumé du [README §9](README.md#9-choix-techniques-et-alternatives) et du [§11](README.md#11-limites-connues), à
savoir dire en quelques phrases.

- **Alternatives écartées** : GitLab sur une VM locale (pas assez de mémoire pour 8 Go, et arrêté avec le poste) ;
  un seul cluster à deux espaces (moins cher, mais pas deux environnements) ; des clés AWS dans des variables
  masquées (valables jusqu'à leur rotation, alors qu'OIDC n'en a aucune) ; Let's Encrypt (il faudrait ouvrir GitLab
  au monde) ; Snyk ou SonarQube Cloud (compte, 100 analyses de code par mois pour Snyk) ; le registre GitLab
  (certificat à faire accepter par chaque nœud) ; Docker-in-Docker (mode privilégié) ou Kaniko (abandonné) ; les
  bases avec leur application (coupure à chaque déploiement) ; Dependabot (GitHub) ; tfsec à part (Trivy fait déjà
  l'analyse de sécurité du Terraform).
- **Disponibilité** : une seule instance GitLab et une seule machine runner (2 jobs à la fois). Les bases, RabbitMQ
  et `billing-app` n'ont qu'une copie : une maintenance de nœud les redémarre ailleurs, et ce qui en dépend est
  indisponible pendant ce temps. Une mise à jour de `billing-app` coupe la consommation quelques secondes (les
  commandes attendent dans RabbitMQ, aucune n'est perdue).
- **Coupure courte** : pendant le redémarrage d'api-gateway, `/api/billing` peut répondre 503 environ une seconde.
- **Droits** : RBAC ne peut pas limiter une création à un nom (un pipeline d'application peut créer d'autres objets
  de ses types, sans modifier ceux des autres) ; l'approbation de la prod repose sur le droit de fusionner dans
  `main` (les environnements protégés sont réservés à GitLab Premium).
- **Sécurité assumée** : 4 défauts signalés par Trivy, acceptés et justifiés dans `.trivyignore.yaml` (trafic sortant
  des nœuds, HTTP vers l'ALB interne, API EKS publique limitée aux IP de l'admin et du runner, pas de clé KMS dédiée).
- **Confort** : le navigateur avertit sur le certificat de GitLab tant que `ca.crt` n'est pas importé ; Renovate,
  sans jeton GitHub, ne montre pas les notes de version.
