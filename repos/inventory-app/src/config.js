/** Thrown when the environment is missing or invalid; index.js turns it into exit code 1. */
export class ConfigError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ConfigError';
  }
}

/**
 * Parses and validates the environment. Non-secret variables default to the values used
 * in docker-compose.yml; the database password is mandatory.
 */
export function loadConfig(env = process.env) {
  return {
    port: readPort(env, 'PORT', '8080'),
    db: {
      host: readString(env, 'DB_HOST', 'inventory-database'),
      port: readPort(env, 'DB_PORT', '5432'),
      database: readString(env, 'DB_NAME', 'movies'),
      user: readString(env, 'DB_USER', 'inventory_user'),
      password: readString(env, 'DB_PASSWORD'),
    },
  };
}

function readString(env, name, fallback) {
  const value = env[name];
  if (value !== undefined && value !== '') {
    return value;
  }
  if (fallback !== undefined) {
    return fallback;
  }
  throw new ConfigError(`Missing required environment variable ${name}`);
}

function readPort(env, name, fallback) {
  const raw = readString(env, name, fallback);
  const port = Number(raw);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new ConfigError(`${name} must be an integer between 1 and 65535, got "${raw}"`);
  }
  return port;
}
