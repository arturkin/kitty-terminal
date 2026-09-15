#!/usr/bin/env bash
# Regression tests for home/.claude/hooks/approve-cloud-mutations.sh.
#
# The hook fails closed, so a bug here is silent: a mutation stops prompting
# and you find out afterwards. Run this after touching the hook.
#
#   ./tests/approve-cloud-mutations.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/home/.claude/hooks/approve-cloud-mutations.sh"
pass=0; fail=0

t() { # t <expected: allow|ASK> <command>
  local exp="$1" cmd="$2" got
  got=$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd" \
        | bash "$HOOK" \
        | python3 -c 'import sys;print("ASK" if sys.stdin.read().strip() else "allow")')
  if [ "$got" = "$exp" ]; then
    pass=$((pass+1)); printf '  ok   %-5s %s\n' "$got" "$cmd"
  else
    fail=$((fail+1)); printf 'FAIL   exp=%-5s got=%-5s %s\n' "$exp" "$got" "$cmd"
  fi
}

echo "── reads pass through ──"
for c in \
  "kubectl get pods -n prod" \
  "kubectl get pods -o jsonpath={.items[*]}" \
  "kubectl describe deploy api" \
  "kubectl logs pod-1 --tail=50" \
  "kubectl rollout status deploy/api" \
  "kubectl config current-context" \
  "helm list -A" "helm status api" "helm template ./chart" "helm get values api" \
  "gcloud compute instances list --filter=name=x" \
  "gcloud projects get-iam-policy my-proj" \
  "gcloud logging read 'resource.type=\"k8s_container\"' --limit 10" \
  "gsutil ls gs://bucket" "bq ls mydataset" \
  "pulumi preview" "terraform plan -var=env=prod" \
  "yarn test && git status"
do t allow "$c"; done

echo "── mutations prompt ──"
for c in \
  "kubectl delete deploy api -n prod" "kubectl apply -f manifest.yaml" \
  "kubectl scale deploy api --replicas=0" "kubectl exec -it pod-1 -- sh" \
  "kubectl rollout restart deploy/api" "kubectl drain node-1" \
  "kubectl patch deploy api -p '{}'" "kubectl cordon node-1" \
  "helm upgrade --install api ./chart -f prod-values.yaml" \
  "helm uninstall api" "helm rollback api 3" "helm repo add x https://y" \
  "gcloud compute instances delete vm1" \
  "gcloud projects add-iam-policy-binding p --member=user:x --role=roles/owner" \
  "gcloud container clusters resize c1 --num-nodes=0" \
  "gcloud sql instances patch db --tier=x" \
  "gcloud iam service-accounts keys create k.json --iam-account=a" \
  "gsutil rm -r gs://bucket/prefix" \
  "bq query 'DELETE FROM t WHERE 1=1'" \
  "pulumi up --yes" "pulumi destroy" \
  "terraform apply -auto-approve" "terraform state rm aws_x.y"
do t ASK "$c"; done

echo "── the binary cannot be hidden ──"
for c in \
  "ls && helm uninstall api" \
  "echo hi; kubectl delete ns prod" \
  "sudo kubectl delete pod x" \
  "CLOUDSDK_CORE_PROJECT=p gcloud compute instances delete vm1" \
  "/opt/homebrew/bin/kubectl delete deploy api" \
  "doppler run -- gcloud compute instances delete vm1" \
  "cat x.yaml | kubectl apply -f -" \
  "kubectl frobnicate widgets" \
  "gcloud some-new-service do-a-thing"
do t ASK "$c"; done

echo "── explicit local context is exempt ──"
for c in \
  "kubectl delete pod x --context kind-dev" \
  "kubectl apply -f m.yaml --context=minikube" \
  "kubectl delete pod x --context k3d-test" \
  "helm uninstall api --kube-context docker-desktop"
do t allow "$c"; done

echo "── but a prod-ish name never is, and no context means no exemption ──"
for c in \
  "kubectl delete pod x --context kind-prod" \
  "kubectl delete pod x --context kind-dev-prod-real" \
  "kubectl delete pod x --context=minikube-production" \
  "kubectl delete pod x --context prod-gke" \
  "helm uninstall api"
do t ASK "$c"; done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
