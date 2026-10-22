// ESLint flat config, run by the lint job of the scan stage: the recommended
// rules report coding issues (unused variables, undefined names, unreachable
// code...) that the security scanners do not look for.
import js from '@eslint/js';
import globals from 'globals';

export default [
  js.configs.recommended,
  {
    languageOptions: {
      // Node.js globals (process, Buffer, fetch...); the tests import
      // node:test explicitly, so they need no test-framework globals.
      globals: globals.node,
    },
  },
];
