import fs from 'node:fs';

/** Fields describing an error in a log line (message and code only, never the stack). */
export function errorFields(err) {
  return err instanceof Error ? { error: err.message, code: err.code } : { error: String(err) };
}

/**
 * Minimal structured logger: one JSON object per line, written to every sink
 * (stdout by default, plus the gateway.log file once it has been opened).
 */
export function createLogger({ sinks = [process.stdout], service = 'api-gateway' } = {}) {
  const write = (level, msg, fields) => {
    const line = JSON.stringify({ time: new Date().toISOString(), level, service, msg, ...fields });
    for (const sink of sinks) {
      sink.write(`${line}\n`);
    }
  };
  return {
    info: (msg, fields) => write('info', msg, fields),
    warn: (msg, fields) => write('warn', msg, fields),
    error: (msg, fields) => write('error', msg, fields),
    addSink: (sink) => sinks.push(sink),
  };
}

/**
 * Opens an append-only log file and returns a sink for it, or null (after a
 * warning) when the file cannot be opened: logging degrades to stdout instead
 * of crashing the gateway.
 */
export function openLogFile(filePath, logger) {
  let fd;
  try {
    fd = fs.openSync(filePath, 'a');
  } catch (err) {
    logger.warn('log file unavailable, logging to stdout only', { file: filePath, ...errorFields(err) });
    return null;
  }
  const stream = fs.createWriteStream(filePath, { fd });
  let writable = true;
  stream.on('error', (err) => {
    writable = false;
    logger.warn('log file disabled after a write error', { file: filePath, ...errorFields(err) });
  });
  return {
    write(chunk) {
      if (writable) {
        stream.write(chunk);
      }
    },
    end() {
      writable = false;
      return new Promise((resolve) => stream.end(resolve));
    },
  };
}

/** Fan-out sink so the access log reaches both stdout and access.log. */
export function teeSink(sinks) {
  return { write: (chunk) => sinks.forEach((sink) => sink.write(chunk)) };
}
