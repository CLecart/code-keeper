// ESLint flat configuration (npm run lint): the recommended rules catch coding
// issues such as unused variables, unreachable code or a lost error cause.
// Every .js file is an ES module ("type": "module") run by Node.js, hence the
// Node.js globals (process, Buffer, fetch...). node_modules is ignored by default.
import js from '@eslint/js';
import globals from 'globals';

export default [
  js.configs.recommended,
  {
    languageOptions: {
      globals: globals.node,
    },
  },
];
