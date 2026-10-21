#!/usr/bin/env bash
# Creates, once, the Ansible Vault password (outside the repository) and the
# encrypted secrets file ansible/group_vars/all/vault.yml (ignored by Git).
# No secret is printed or written in clear on disk.
#   Read the secrets:  cd ansible && ansible-vault view group_vars/all/vault.yml
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS_FILE="$HOME/.config/code-keeper/vault-pass"
VAULT_FILE="$ROOT/ansible/group_vars/all/vault.yml"

umask 077

if [[ ! -s "$PASS_FILE" ]]; then
  mkdir -p "$(dirname "$PASS_FILE")"
  python3 -c 'import secrets; print(secrets.token_urlsafe(48))' >"$PASS_FILE"
  echo "Created the vault password: $PASS_FILE"
fi

if [[ -e "$VAULT_FILE" ]]; then
  echo "$VAULT_FILE already exists: nothing to do."
  exit 0
fi

# Letters and digits only, so no value needs quoting in YAML or Ruby.
python3 - <<'PY' | ansible-vault encrypt --vault-password-file "$PASS_FILE" --output "$VAULT_FILE" -
import secrets, string

def secret(length):
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))

print(f'vault_gitlab_root_password: "{secret(24)}"')
print(f'vault_gitlab_api_token: "{secret(20)}"')
print("vault_gitlab_user_passwords:")
for user in ("clecart", "developer", "stakeholder"):
    print(f'  {user}: "{secret(24)}"')
PY

echo "Created the encrypted secrets: $VAULT_FILE"
