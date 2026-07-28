#!/bin/sh
set -eu

vault_name="${1:?vault name is required}"
session_file="$HOME/.agent-vault/session.json"

address="$(jq -er '.address' "$session_file")"
token="$(jq -er '.token' "$session_file")"

# Infisical exports an array of secret objects. Reduce it to the one payload
# Agent Vault accepts, without ever writing the values to disk.
jq -ce --arg vault "$vault_name" '
  if type != "array" then
    error("expected an array from infisical export")
  else
    {
      vault: $vault,
      credentials: (
        map(
          if ((.key | type) == "string" and (.value | type) == "string") then
            {key: .key, value: .value}
          else
            error("every exported secret must have string key and value fields")
          end
        )
        | from_entries
      )
    }
    | if (.credentials | length) == 0 then
        error("infisical export returned no secrets")
      else
        .
      end
  end
' \
  | curl \
      --fail-with-body \
      --silent \
      --show-error \
      --header "Authorization: Bearer $token" \
      --header "Content-Type: application/json" \
      --data-binary @- \
      "$address/v1/credentials"
