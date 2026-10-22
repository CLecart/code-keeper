# api-gateway-app

Passerelle d'API du projet code-keeper : elle transmet `/api/movies` à inventory-app et publie les commandes de `/api/billing` dans la file RabbitMQ.

| | |
|---|---|
| Langage | Node.js 24, Express 5, http-proxy-middleware, amqplib |
| Port | `3000` |
| Santé | `GET /health` |
| Tests | `npm ci && npm test` (test runner intégré de Node) |
| Image | `code-keeper/api-gateway-app` dans Amazon ECR |

En CI, le job `lint` (étape `scan`) applique les règles recommandées d'ESLint (`npm run lint`), et le job `integration-test` (étape `test`) démarre la passerelle réelle face à un vrai RabbitMQ (service GitLab) et à une inventory-app simulée (`npm run test:integration`, fichiers `integration/*.int.js`). En local, ces tests visent un RabbitMQ de test grâce à `INTEGRATION_RABBITMQ_HOST`, `INTEGRATION_RABBITMQ_PORT`, `RABBITMQ_DEFAULT_USER` et `RABBITMQ_DEFAULT_PASS`.

## Configuration (variables d'environnement)

| Variable | Défaut | Rôle |
|---|---|---|
| `PORT` | `3000` | Port HTTP |
| `INVENTORY_APP_URL` | `http://inventory-app:8080` | Adresse d'inventory-app |
| `RABBITMQ_HOST` | `rabbitmq` | Hôte RabbitMQ |
| `RABBITMQ_PORT` | `5672` | Port RabbitMQ |
| `RABBITMQ_USER` | aucun, **obligatoire** | Utilisateur RabbitMQ |
| `RABBITMQ_PASSWORD` | aucun, **obligatoire** | Mot de passe RabbitMQ |
| `RABBITMQ_QUEUE` | `billing_queue` | File où sont publiées les commandes |
| `LOG_DIR` | `/var/logs/api-gateway` | Dossier des journaux d'accès |

Les identifiants RabbitMQ sont fournis par un secret Kubernetes. Ce dépôt est publié depuis le dossier `repos/api-gateway-app/` du dépôt code-keeper.
