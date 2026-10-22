# renovate

Robot de mise à jour des dépendances du groupe code-keeper : [Renovate](https://docs.renovatebot.com/), auto-hébergé dans GitLab.

| | |
|---|---|
| Quand | Chaque jour ouvré à 7 h (programmation du pipeline), ou à la main (**Build → Pipeline schedules → Run**) |
| Où | Les dépôts du groupe qui contiennent un `renovate.json` : `inventory-app`, `billing-app`, `api-gateway-app`, `infra` et celui-ci |
| Quoi | Paquets npm, images Docker (Dockerfile et `.gitlab-ci.yml`), fournisseurs et modules Terraform, charts Helm, image Trivy |
| Résultat | Une demande de fusion par mise à jour, une étiquetée `security` quand la base OSV signale une faille, et un ticket « Dependency Dashboard » par dépôt |
| Qui fusionne | Un Maintainer, après le pipeline vert de la demande de fusion (le robot est Developer : il ne pousse jamais sur `main`) |

## Fichiers

| Fichier | Rôle |
|---|---|
| `.gitlab-ci.yml` | Le job `renovate` (image officielle `ghcr.io/renovatebot/renovate`), lancé seulement par la programmation ou à la main sur `main` ; le job `validate-config` (`renovate-config-validator --strict`), à chaque push et demande de fusion |
| `default.json` | Réglages communs, repris par chaque dépôt avec `"extends": ["local>code-keeper/renovate"]` |
| `renovate.json` | Ce dépôt se met lui-même à jour (version de l'image Renovate) |

## Secret

`RENOVATE_TOKEN` : jeton personnel du compte `renovate-bot` (droits `api`, `read_user`, `write_repository`), variable CI **masquée et protégée**, créée par Ansible depuis le coffre chiffré. Il n'est jamais écrit dans le code.

Ce dépôt est publié depuis le dossier `repos/renovate/` du dépôt code-keeper.
