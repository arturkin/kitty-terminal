#!/usr/bin/env bash
# PreToolUse guard: cloud and IaC mutations need explicit approval.
#
# Reads are silent. Anything that changes state -- or any verb this script does
# not recognise -- returns "ask". Fail closed: an unknown subcommand prompts
# rather than running, because the cost of a missed verb is a prod mutation.
#
# Exception: a command that *explicitly* names a local cluster context runs
# unsupervised. Deliberately not based on `kubectl config current-context` --
# a command with no --context inherits whatever the context happens to be, and
# a forgotten context switch is exactly how a prod mutation gets waved through.
set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command? // empty' 2>/dev/null) || exit 0
[ -z "${cmd//[[:space:]]/}" ] && exit 0

ask() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

# Local cluster contexts that may be mutated without approval.
LOCAL_CTX='(kind-[A-Za-z0-9_.-]+|k3d-[A-Za-z0-9_.-]+|minikube|docker-desktop|docker-for-desktop|rancher-desktop|colima|orbstack)'

# `--context foo`, `--context=foo`, and helm's `--kube-context` spelling.
# A context whose name mentions prod never qualifies, however it is spelled --
# otherwise `kubectl config rename-context gke-prod kind-prod` would buy
# blanket approval for the real cluster.
names_local_context() {
  printf '%s' "$1" | grep -qiE -- '--(kube-)?context[[:space:]=]+["'"'"']?[A-Za-z0-9_.-]*(prod|live)' && return 1
  printf '%s' "$1" | grep -qE -- "--(kube-)?context[[:space:]=]+[\"']?${LOCAL_CTX}([\"'[:space:]]|$)"
}

# Split on shell operators so `ls && helm uninstall api` is inspected in full.
segments=$(printf '%s' "$cmd" | sed -E 's/\|\||&&|[;|&]/\n/g')

while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}"
  [ -z "$seg" ] && continue

  # Peel env assignments and wrappers until the real binary is in front.
  # Uses =~ rather than a case glob: in a glob, [A-Za-z0-9_]*= matches any
  # string containing '=', so `kubectl scale --replicas=0` looked like an env
  # assignment and got its binary stripped.
  while :; do
    if   [[ $seg =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+ ]]; then seg="${seg#* }"
    elif [[ $seg =~ ^(sudo|command|nohup|time|stdbuf|env)[[:space:]]+ ]];  then seg="${seg#* }"
    elif [[ $seg =~ ^doppler[[:space:]]+run[[:space:]].*--[[:space:]]+ ]]; then seg="${seg#*-- }"
    else break
    fi
    seg="${seg#"${seg%%[![:space:]]*}"}"
  done

  read -r bin rest <<<"$seg"
  bin="${bin##*/}"
  bin="${bin//\"/}"; bin="${bin//\'/}"

  # Tokens that are not flags -- the verb is among these. Split with read -a
  # (not tr) so whitespace is actually what gets split on.
  set -f
  read -r -a toks <<<"$rest"
  set +f
  verbs=$(printf '%s\n' "${toks[@]+"${toks[@]}"}" | tr -d "\"'" | grep -vE '^-|^$' || true)
  has() { printf '%s\n' "$verbs" | grep -qxE "$1"; }

  case "$bin" in
    kubectl|oc)
      names_local_context "$seg" && continue
      has 'rollout' && { has 'status|history' && continue; ask "kubectl rollout changes cluster state"; }
      has 'config'  && { has 'view|current-context|get-contexts|get-clusters' && continue; ask "kubectl config modifies kubeconfig"; }
      has 'get|describe|logs|top|explain|api-resources|api-versions|version|cluster-info|events|diff|auth|wait' && continue
      ask "kubectl mutates cluster state and no local --context was given"
      ;;
    helm)
      names_local_context "$seg" && continue
      has 'repo|plugin|dependency' && { has 'list|ls|update' && continue; ask "helm repo/plugin change is a mutation"; }
      has 'list|ls|get|status|history|show|search|template|lint|version|env|inspect' && continue
      ask "helm mutates a release and no local --kube-context was given"
      ;;
    gcloud)
      has 'create|delete|update|patch|set|deploy|import|restore|enable|disable|ssh|scp|reset|start|stop|resize|add|remove|attach|detach|clone|promote|rollback|migrate|submit|apply|replace|undelete|revoke|grant|move|rename|cancel|abandon|drain|upgrade|install|uninstall|activate|deactivate|bind|unbind|set-iam-policy|add-iam-policy-binding|remove-iam-policy-binding|sign|untag|expire' \
        && ask "gcloud mutation (you are a GCP admin -- confirm the project and resource)"
      has 'list|describe|get|get-iam-policy|get-value|read|show|check|validate|lookup|search|test-iam-permissions|tail|info|version|help|topic|print-access-token|access' && continue
      ask "unrecognised gcloud verb -- approving explicitly (fail closed)"
      ;;
    gsutil)
      has 'ls|cat|stat|du|hash|version|help' && continue
      ask "gsutil mutation on Cloud Storage"
      ;;
    bq)
      has 'query' && ask "bq query can run DML (DELETE/UPDATE/INSERT)"
      has 'ls|show|head|version|help' && continue
      ask "unrecognised bq verb -- approving explicitly (fail closed)"
      ;;
    pulumi)
      has 'stack' && { has 'ls|output|history|graph' && continue; ask "pulumi stack change"; }
      has 'config' && { has 'get' && continue; ask "pulumi config set is a mutation"; }
      has 'plugin' && { has 'ls' && continue; ask "pulumi plugin change"; }
      has 'preview|about|version|whoami|logs' && continue
      ask "pulumi mutates infrastructure state"
      ;;
    terraform|tofu)
      has 'state' && { has 'list|show' && continue; ask "terraform state mutation"; }
      has 'workspace' && { has 'list|show' && continue; ask "terraform workspace change"; }
      has 'plan|show|validate|output|providers|version|graph|console' && continue
      ask "terraform mutates infrastructure"
      ;;
  esac
done <<<"$segments"

exit 0
