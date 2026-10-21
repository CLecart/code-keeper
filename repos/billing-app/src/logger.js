// Minimal structured logger: one JSON object per line, no dependency.

function serializeError(err) {
  const out = { name: err.name, message: err.message };
  if (err.code !== undefined) {
    out.code = err.code;
  }
  return out;
}

export function createLogger(stream = process.stdout) {
  const log = (level) => (msg, fields = {}) => {
    const entry = { time: new Date().toISOString(), level, msg, ...fields };
    if (fields.err instanceof Error) {
      entry.err = serializeError(fields.err);
    }
    stream.write(`${JSON.stringify(entry)}\n`);
  };

  return { info: log('info'), warn: log('warn'), error: log('error') };
}
