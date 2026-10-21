import { Router } from 'express';

const MAX_TITLE_LENGTH = 255;
// ids come from a SERIAL column, i.e. a signed 32-bit integer.
const MAX_ID = 2147483647;
const INVALID_ID = 'id must be a positive integer';
const NOT_FOUND = 'Movie not found';
const NUL_ERROR = 'title and description must not contain NUL characters';

// PostgreSQL text and varchar values cannot contain U+0000. Such an input is a
// client error, so it must be rejected here rather than surface as a 500.
const containsNul = (value) => typeof value === 'string' && value.includes('\u0000');

/** Returns the id as a number, or null when the path parameter is not a valid movie id. */
export function parseMovieId(raw) {
  if (typeof raw !== 'string' || !/^\d+$/.test(raw)) {
    return null;
  }
  const id = Number(raw);
  return id >= 1 && id <= MAX_ID ? id : null;
}

/** Validates a POST/PUT body and returns either `{ value }` (normalized) or `{ error }`. */
export function validateMoviePayload(body) {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    return { error: 'Request body must be a JSON object' };
  }
  const { title, description } = body;
  if (typeof title !== 'string' || title.trim() === '') {
    return { error: 'title is required and must be a non-empty string' };
  }
  if (title.trim().length > MAX_TITLE_LENGTH) {
    return { error: `title must be at most ${MAX_TITLE_LENGTH} characters` };
  }
  if (description !== undefined && description !== null && typeof description !== 'string') {
    return { error: 'description must be a string' };
  }
  if (containsNul(title) || containsNul(description)) {
    return { error: NUL_ERROR };
  }
  return { value: { title: title.trim(), description: description ?? '' } };
}

/** REST routes for /api/movies. Express 5 forwards rejected promises to the error handler. */
export function createMoviesRouter(db) {
  const router = Router();

  router.get('/', async (req, res) => {
    const { title } = req.query;
    if (title !== undefined && typeof title !== 'string') {
      return res.status(400).json({ error: 'title filter must be a single string' });
    }
    if (containsNul(title)) {
      return res.status(400).json({ error: 'title filter must not contain NUL characters' });
    }
    res.json(await db.listMovies(title));
  });

  router.post('/', async (req, res) => {
    const { value, error } = validateMoviePayload(req.body);
    if (error) {
      return res.status(400).json({ error });
    }
    // 201 Created, as the orchestrator audit of the Zone01 platform expects.
    res.status(201).json(await db.createMovie(value));
  });

  router.delete('/', async (req, res) => {
    const deleted = await db.deleteAllMovies();
    res.json({ message: 'All movies deleted', deleted });
  });

  router.get('/:id', async (req, res) => {
    const id = parseMovieId(req.params.id);
    if (id === null) {
      return res.status(400).json({ error: INVALID_ID });
    }
    const movie = await db.getMovie(id);
    if (movie === null) {
      return res.status(404).json({ error: NOT_FOUND });
    }
    res.json(movie);
  });

  router.put('/:id', async (req, res) => {
    const id = parseMovieId(req.params.id);
    if (id === null) {
      return res.status(400).json({ error: INVALID_ID });
    }
    const { value, error } = validateMoviePayload(req.body);
    if (error) {
      return res.status(400).json({ error });
    }
    const movie = await db.updateMovie(id, value);
    if (movie === null) {
      return res.status(404).json({ error: NOT_FOUND });
    }
    res.json(movie);
  });

  router.delete('/:id', async (req, res) => {
    const id = parseMovieId(req.params.id);
    if (id === null) {
      return res.status(400).json({ error: INVALID_ID });
    }
    if (!(await db.deleteMovie(id))) {
      return res.status(404).json({ error: NOT_FOUND });
    }
    res.json({ message: 'Movie deleted', id });
  });

  return router;
}
