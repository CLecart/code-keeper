// Coding issues of every JavaScript file (src, unit and integration tests):
// the recommended rules of ESLint, for ES modules running on Node.js.
// node_modules is ignored by default.
import js from '@eslint/js';
import { defineConfig } from 'eslint/config';
import globals from 'globals';

export default defineConfig([
  js.configs.recommended,
  {
    languageOptions: {
      globals: globals.node,
    },
  },
]);
