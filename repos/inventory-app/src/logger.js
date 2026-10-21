/**
 * Minimal structured logger: one JSON object per line on stdout.
 * Dependency-free on purpose (architecture contract); never log secrets.
 */
export function createLogger({ service, stream = process.stdout } = {}) {
  const write = (level) => (msg, fields = {}) => {
    const entry = { time: new Date().toISOString(), level, service, msg, ...fields };
    if (fields.err instanceof Error) {
      entry.err = serializeError(fields.err);
    }
    stream.write(`${JSON.stringify(entry)}\n`);
  };

  return { info: write('info'), warn: write('warn'), error: write('error') };
}

// Error objects are not JSON-serializable; keep the useful, non-sensitive parts only.
function serializeError(err) {
  const { name, message, code } = err;
  return code === undefined ? { name, message } : { name, message, code };
}
