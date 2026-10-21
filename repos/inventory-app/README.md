# inventory-app

Microservice d'inventaire du projet code-keeper : une API REST de films, stockée dans PostgreSQL.

| | |
|---|---|
| Langage | Node.js 24, Express 5 |
| Port | `8080` |
| Santé | `GET /health` |
| Tests | `npm ci && npm test` (test runner intégré de Node) |
| Image | `code-keeper/inventory-app` dans Amazon ECR |

## Configuration (variables d'environnement)

| Variable | Défaut | Rôle |
|---|---|---|
| `PORT` | `8080` | Port HTTP |
| `DB_HOST` | `inventory-database` | Hôte PostgreSQL |
| `DB_PORT` | `5432` | Port PostgreSQL |
| `DB_NAME` | `movies` | Base de données |
| `DB_USER` | `inventory_user` | Utilisateur |
| `DB_PASSWORD` | aucun, **obligatoire** | Mot de passe, fourni par un secret Kubernetes |

Ce dépôt est publié depuis le dossier `repos/inventory-app/` du dépôt code-keeper.
