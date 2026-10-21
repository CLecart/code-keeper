// Reads and validates the environment. Non-secret values have sane defaults;
// secrets must be provided explicitly so a misconfiguration fails fast.

export class ConfigError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ConfigError';
  }
}

const REQUIRED = ['DB_PASSWORD', 'RABBITMQ_PASSWORD'];

const isSet = (value) => typeof value === 'string' && value.trim() !== '';

function optional(env, name, fallback) {
  return isSet(env[name]) ? env[name] : fallback;
}

function port(env, name, fallback) {
  const raw = optional(env, name, String(fallback));
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 1 || value > 65535) {
    throw new ConfigError(`Invalid ${name}: expected a TCP port, got "${raw}"`);
  }
  return value;
}

export function loadConfig(env = process.env) {
  const missing = REQUIRED.filter((name) => !isSet(env[name]));
  if (missing.length > 0) {
    throw new ConfigError(`Missing required environment variable(s): ${missing.join(', ')}`);
  }

  return Object.freeze({
    port: port(env, 'PORT', 8080),
    db: Object.freeze({
      host: optional(env, 'DB_HOST', 'billing-database'),
      port: port(env, 'DB_PORT', 5432),
      database: optional(env, 'DB_NAME', 'orders'),
      user: optional(env, 'DB_USER', 'billing_user'),
      password: env.DB_PASSWORD,
    }),
    rabbitmq: Object.freeze({
      hostname: optional(env, 'RABBITMQ_HOST', 'rabbitmq'),
      port: port(env, 'RABBITMQ_PORT', 5672),
      username: optional(env, 'RABBITMQ_USER', 'rabbit_user'),
      password: env.RABBITMQ_PASSWORD,
      queue: optional(env, 'RABBITMQ_QUEUE', 'billing_queue'),
    }),
  });
}
