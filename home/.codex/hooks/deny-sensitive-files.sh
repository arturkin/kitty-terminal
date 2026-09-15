#!/usr/bin/env bash
# PreToolUse guard: refuse any tool call that would read or print credential files.
# Matches on the resolved path text, so cat/head/sed/less/strings/cp are all covered.
set -uo pipefail

input=$(cat)

targets=$(printf '%s' "$input" | jq -r '
  [ (.tool_input.command? // empty),
    (.tool_input.file_path? // empty),
    (.tool_input.path? // empty),
    (.tool_input.pattern? // empty),
    (.tool_input.paths? // [] | .[]? // empty),
    (.tool_input.glob? // empty)
  ] | map(tostring) | join(" ")' 2>/dev/null) || exit 0

[ -z "${targets//[[:space:]]/}" ] && exit 0

# Normalise ~ and $HOME so both spellings of a path hit the same patterns.
targets=${targets//\~\//$HOME/}
targets=${targets//\$HOME/$HOME}
targets=${targets//\$\{HOME\}/$HOME}

# Path-context prefix: start of string, whitespace, slash, quote or =.
P='(^|[[:space:]/"'"'"'=,;:(])'
# Filename terminator: anything that is not a name character.
S='([^A-Za-z0-9_.-]|$)'

read -r -d '' PATTERNS <<PAT
${P}\.(gitconfig|git-credentials|netrc|npmrc|pypirc|pgpass|my\.cnf)${S}
${P}\.(ssh|gnupg|aws|kube|doppler|password-store|op)(/|${S})
\.config/(gh|gcloud|doppler|op|hub|git|containers)/
\.docker/config\.json
\.claude/\.credentials\.json
\.claude\.json${S}
${P}\.(zsh_history|bash_history|sh_history|zsh_sessions|python_history|node_repl_history|psql_history|mysql_history|lesshst)
\.zsh_historydocker
${P}(id_rsa|id_dsa|id_ecdsa|id_ed25519|authorized_keys|known_hosts)${S}
\.(pem|p12|pfx|p8|jks|keystore|asc|gpg|kdbx)${S}
${P}(credentials|client_secret|service.account|serviceaccount)[A-Za-z0-9_.-]*\.json${S}
${P}\.env([.][A-Za-z0-9_-]+)*${S}
${P}(secrets?|credentials)\.(ya?ml|json|toml|ini|txt)${S}
git[[:space:]]+config([[:space:]]+--(global|local|system|worktree|file[[:space:]=][^[:space:]]*))*[[:space:]]+(--(list|get|get-all|get-regexp|get-urlmatch|l\b)|[A-Za-z0-9_-]+\.[A-Za-z0-9_.-]+[[:space:]]*($|[|;&>]))
PAT

if printf '%s' "$targets" | grep -qiE "$PATTERNS"; then
  cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked by the sensitive-files guard (~/.claude/hooks/deny-sensitive-files.sh): this call references a credential, key, history or dotfile that must never be read or printed. Do not attempt to work around this — ask the user to inspect the file themselves."}}
JSON
  exit 0
fi

exit 0
