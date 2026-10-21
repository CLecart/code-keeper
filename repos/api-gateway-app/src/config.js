const DEFAULTS = {
  PORT: '3000',
  INVENTORY_APP_URL: 'http://inventory-app:8080',
  RABBITMQ_HOST: 'rabbitmq',
  RABBITMQ_PORT: '5672',
  RABBITMQ_QUEUE: 'billing_queue',
  LOG_DIR: '/var/logs/api-gateway',
};

const REQUIRED = ['RABBITMQ_USER', 'RABBITMQ_PASSWORD'];

export class ConfigError extends Error {}

function parsePort(name, value) {
  const port = Number(value);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new ConfigError(`${name} must be a TCP port number (got "${value}")`);
  }
  return port;
}

function parseHttpUrl(name, value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new ConfigError(`${name} must be an absolute URL (got "${value}")`);
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') {
    throw new ConfigError(`${name} must use http or https (got "${value}")`);
  }
  // A loop rather than /\/+$/, which backtracks quadratically on a long run of slashes.
  let end = value.length;
  while (value[end - 1] === '/') end -= 1;
  return value.slice(0, end);
}

/** Reads and validates the environment; throws ConfigError on any problem. */
export function loadConfig(env = process.env) {
  const missing = REQUIRED.filter((name) => !env[name]);
  if (missing.length > 0) {
    throw new ConfigError(`Missing required environment variable(s): ${missing.join(', ')}`);
  }
  const get = (name) => env[name] || DEFAULTS[name];

  return {
    port: parsePort('PORT', get('PORT')),
    inventoryUrl: parseHttpUrl('INVENTORY_APP_URL', get('INVENTORY_APP_URL')),
    logDir: get('LOG_DIR'),
    rabbitmq: {
      host: get('RABBITMQ_HOST'),
      port: parsePort('RABBITMQ_PORT', get('RABBITMQ_PORT')),
      user: env.RABBITMQ_USER,
      password: env.RABBITMQ_PASSWORD,
      queue: get('RABBITMQ_QUEUE'),
    },
  };
}
