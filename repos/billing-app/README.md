# billing-app

Microservice de facturation du projet code-keeper : il lit les commandes dans la file RabbitMQ et les enregistre dans PostgreSQL.

| | |
|---|---|
| Langage | Node.js 24, Express 5, amqplib |
| Port | `8080` |
| Santé | `GET /health` |
| Tests | `npm ci && npm test` (test runner intégré de Node) |
| Image | `code-keeper/billing-app` dans Amazon ECR |

## Configuration (variables d'environnement)

| Variable | Défaut | Rôle |
|---|---|---|
| `PORT` | `8080` | Port HTTP |
| `DB_HOST` | `billing-database` | Hôte PostgreSQL |
| `DB_PORT` | `5432` | Port PostgreSQL |
| `DB_NAME` | `orders` | Base de données |
| `DB_USER` | `billing_user` | Utilisateur |
| `DB_PASSWORD` | aucun, **obligatoire** | Mot de passe PostgreSQL |
| `RABBITMQ_HOST` | `rabbitmq` | Hôte RabbitMQ |
| `RABBITMQ_PORT` | `5672` | Port RabbitMQ |
| `RABBITMQ_USER` | `rabbit_user` | Utilisateur RabbitMQ |
| `RABBITMQ_PASSWORD` | aucun, **obligatoire** | Mot de passe RabbitMQ |
| `RABBITMQ_QUEUE` | `billing_queue` | File lue |

Les mots de passe sont fournis par des secrets Kubernetes. Ce dépôt est publié depuis le dossier `repos/billing-app/` du dépôt code-keeper.
