# Cloud guardrails

`~/.claude/hooks/approve-cloud-mutations.sh` makes cloud and IaC mutations
prompt for approval. Reads stay silent. It exists because this account has
admin on GCP, where the gap between `list` and `delete` is one word.

Tests: `./tests/approve-cloud-mutations.sh` — 59 cases. Run it after any edit;
the hook fails closed, so a bug is silent until something does not prompt.

## The rule

| | |
|---|---|
| Read verbs | run unsupervised |
| Write verbs | prompt |
| **Unrecognised verbs** | **prompt** — fail closed |

Fail-closed is the important half. A new `gcloud` subcommand nobody has taught
the hook about prompts rather than runs. The cost is an occasional needless
confirmation; the alternative is a mutation that slips through because the verb
list was stale.

Covered: `gcloud`, `gsutil`, `bq`, `kubectl`/`oc`, `helm`, `pulumi`,
`terraform`/`tofu`. Not covered: `docker` — local in practice.

## What it actually inspects

The command is split on `&&`, `||`, `;` and `|` before anything else, so the
binary cannot be hidden behind a harmless first command. Env assignments
(`CLOUDSDK_CORE_PROJECT=p gcloud …`), wrappers (`sudo`, `env`, `nohup`,
`doppler run --`) and absolute paths (`/opt/homebrew/bin/kubectl`) are all
peeled off before the binary is identified. Each of those is a test case.

`bq query` always prompts — it accepts DML, so "query" is not a read.

## The local-cluster exception

A mutation runs unsupervised **only when the command explicitly names a local
context**:

```
--context kind-*   --context k3d-*   --context minikube
--context docker-desktop | rancher-desktop | colima | orbstack
--kube-context <same>        # helm's spelling
```

It is deliberately **not** based on `kubectl config current-context`. A command
with no `--context` inherits whatever the context happens to be, and a
forgotten context switch is precisely how a prod mutation gets waved through.
No explicit context means it prompts, every time.

A context whose name contains `prod` or `live` never qualifies, however it is
spelled — otherwise `kubectl config rename-context gke-prod kind-prod` would
buy blanket approval for the real cluster.

## Where it sits

```
1. git push confirmation
2. deny-sensitive-files.sh      (credential files -- deny)
3. approve-cloud-mutations.sh   (cloud/IaC writes -- ask)
4. rtk hook claude              (output compression -- rewrite)
```

Ahead of rtk on purpose: rtk rewrites the command, and an approval prompt has
to be decided on what was actually typed. rtk never auto-allows any of these
binaries — verified, not assumed — so its rewrite cannot undercut an `ask`.

## Known gaps

- **Secret-returning reads are unsupervised by choice.**
  `gcloud secrets versions access`, `kubectl get secret -o yaml` and
  `gcloud auth print-access-token` are read verbs that print credentials, and
  they run without prompting. Credential *files* are still blocked by
  `deny-sensitive-files.sh` (`~/.config/gcloud/`, `.kube/`, `.config/doppler/`),
  so this gap is API responses only. Move those verbs out of the gcloud read
  list to close it.
- Verb lists are hand-maintained. Fail-closed limits the damage, but a verb
  wrongly classified as a *read* is a real hole — that direction does not fail
  closed. Add a test with the fix.
