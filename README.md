# EKS LLM Lab

Self-hosted LLM platform on Kubernetes (EKS).

## Overview
- An EKS cluster serving an open model through vLLM on a single spot GPU (NVIDIA T4 on g4dn, or L4 on g6).
- A small RAG API behind Amazon API Gateway.
- Dashboards showing latency, cost per million tokens, and node pool scaling.

All infrastructure is defined as Terraform, split into four small stacks applied in order.

## Architecture
![Architecture: requests flow left to right; vLLM metrics size the GPU pool](docs/architecture.png)

Requests enter through API Gateway (API key, throttling, 29 s timeout), cross a VPC Link to an internal NLB, and
reach `rag-api`, which embeds with TEI, retrieves from Qdrant and sends prompt plus context to vLLM on the GPU
pool. Prometheus scrapes vLLM's and rag-api's `/metrics`; KEDA scales vLLM replicas on queue depth, and Karpenter
adds a GPU node (`g4dn`, or `g6` as fallback) when a GPU pod is pending.

The diagram shows the target design. The TEI model is set by `tei_model` in `02-apps/terraform.tfvars`
(currently `BAAI/bge-base-en-v1.5`), and OpenCost is not installed: GPU cost comes from Karpenter's price
estimates instead (see [Dashboard](#dashboard)).

## Repository Layout
```
llm-lab/
├── modules/
│   └── k8s-manifests/  # applies a folder of YAML (*.yaml, *.yaml.tftpl) via kubernetes_manifest
├── 00-infra/      # VPC, EKS, node group, IAM, Karpenter IAM, ECR (aws provider only)
├── 01-platform/   # Helm charts: Karpenter, LB controller, device plugin, Prometheus, KEDA, Qdrant
├── 02-apps/       # manifests/{karpenter,llm,rag}: NodePools, vLLM, TEI, KEDA, alerts, rag-api
├── 03-gateway/    # API Gateway REST API, VPC Link, usage plan
├── docs/          # architecture diagram, troubleshooting guide
└── rag-api/       # FastAPI source + Dockerfile
```

Each stack is split by concern (`versions.tf`, `providers.tf`, `variables.tf`, `outputs.tf`, one file per
component) and reads the stacks before it through `terraform_remote_state`. State is local
(`<stack>/terraform.tfstate`), so run every stack from the same checkout.

## Prerequisites
- Service Quotas of ≥8 vCPUs for G and VT instances, for the capacity type in `gpu_node_pool.capacity_types`
  (currently spot: "All G and VT Spot Instance Requests").
- For spot node pools, the EC2 Spot service-linked role. Karpenter cannot create it, so in an account that has
  never run spot instances create it once: `aws iam create-service-linked-role --aws-service-name spot.amazonaws.com`
  (an "has been taken" error means it already exists).
- Terraform 1.9+, AWS CLI v2, kubectl, helm, Docker with buildx, Python 3.12, jq.
- Optional: Hugging Face token (model used is ungated).

## Configuration
Every tunable value lives in the stack's `terraform.tfvars` (loaded automatically); `variables.tf` only declares
types, descriptions and validation, with no defaults.

| Stack | Main settings in `terraform.tfvars` |
|---|---|
| `00-infra` | `name`, `region`, `tags`, VPC CIDRs (the number of `private_subnets` sets the AZ count), `kubernetes_version`, `system_node_group`, `endpoint_public_access` |
| `01-platform` | `chart_versions` for all Helm charts |
| `02-apps` | `images`, `vllm` (model and server args), `vllm_autoscaling`, `tei_model`, `gpu_node_pool` / `cpu_node_pool`, `node_class`, `nlb_name` |
| `03-gateway` | `api_name`, `stage_name`, `integration_timeout_ms`, `usage_plan` (throttle and daily quota) |

Keep `gpu_node_pool.cpu_limit` within your G/VT vCPU quota, and `vllm_autoscaling.max_replicas` within what that
limit fits (one GPU node per replica; two 4-vCPU `xlarge` nodes with the default 8 vCPUs). Spot and On-Demand have separate
quotas ("All G and VT Spot Instance Requests" vs "Running On-Demand G and VT instances"), and new accounts often
start with a Spot quota of 0; check it in Service Quotas before applying a spot-only `capacity_types`.

The system node group runs one node, and Karpenter runs one replica on it (its chart requires one replica per
non-Karpenter node). Change the group's size with `min_size`/`max_size`: the EKS module ignores later
`desired_size` changes.

Manifests in `02-apps/manifests/` are rendered with `templatefile()`: `.yaml.tftpl` files take values from the
module calls in `02-apps/*.tf`. A literal `${` or `%{` in any manifest must be written `$${` / `%%{`. See
[modules/k8s-manifests/README.md](modules/k8s-manifests/README.md) for how manifests are rendered and applied.

## Deploy
Apply the stacks in order; each one needs the previous stacks' state.

```bash
# 1. VPC, EKS, IAM, ECR
terraform -chdir=00-infra init && terraform -chdir=00-infra apply

# 2. Build and push rag-api (02-apps deploys <ecr_repository_url>:<rag_api_image_tag>)
ECR=$(terraform -chdir=00-infra output -raw ecr_repository_url)
REGION=$(terraform -chdir=00-infra output -raw region)
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${ECR%%/*}"
docker buildx build --platform linux/amd64 -t "$ECR:latest" --push rag-api

# 3. Helm charts (Karpenter, LB controller, NVIDIA plugin, Prometheus, KEDA, Qdrant)
terraform -chdir=01-platform init && terraform -chdir=01-platform apply

# 4. Karpenter NodePools, vLLM, TEI, rag-api and its internal NLB
terraform -chdir=02-apps init && terraform -chdir=02-apps apply

# 5. API Gateway in front of the NLB
terraform -chdir=03-gateway init && terraform -chdir=03-gateway apply
```

kubectl access:
```bash
aws eks update-kubeconfig --name "$(terraform -chdir=00-infra output -raw cluster_name)" --region "$REGION"
```

vLLM's first start downloads the model weights and can take up to ~15 minutes (`kubectl -n llm get pods -w`).

Re-pushing the same `rag_api_image_tag` does not change the Deployment, so Terraform will not roll it; run
`kubectl -n rag rollout restart deploy/rag-api`, or push a new tag and set `rag_api_image_tag`.

## Use the API
Every request needs the API key from the usage plan.

```bash
URL=$(terraform -chdir=03-gateway output -raw invoke_url)
KEY=$(terraform -chdir=03-gateway output -raw api_key)
curl -H "x-api-key: $KEY" "$URL/health"

# Ingest: each document is split into 800-char chunks; re-ingesting a source replaces its chunks
curl -sL https://raw.githubusercontent.com/vllm-project/vllm/main/README.md -o vllm.md
jq -n --rawfile t vllm.md '[{source: "vllm-readme", text: $t}]' |
  curl -s "$URL/ingest" -H "x-api-key: $KEY" -H 'Content-Type: application/json' -d @-

# Ask: answers only from the top_k (default 4, max 20) closest chunks; sources[n-1] is citation [n]
curl -s "$URL/ask" -H "x-api-key: $KEY" -H 'Content-Type: application/json' \
  -d '{"question": "Which hardware does vLLM support?"}' | jq
```

`/ask` returns 404 until something is ingested, 503 while vLLM is paused or starting, 504 if vLLM takes over 25 s,
and 502 if TEI is down.

To test inside the cluster without the gateway: `kubectl -n rag port-forward svc/rag-api 8080:80`, then use
`localhost:8080` without the API key.

## Dashboard
Grafana (from kube-prometheus-stack) is only reachable inside the cluster; open it with a port-forward:

```bash
kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

Log in at http://localhost:3000 as `admin` with that password, then open **Dashboards → LLM / RAG**. It has rows
for vLLM serving and latency, the RAG API, TEI embeddings, pod CPU/memory and GPU cost. It is defined in
`02-apps/dashboards/llm-rag.json` and loaded by `02-apps/observability.tf`; it is provisioned, so Grafana does not
keep edits made in its UI. The JSON is generated: change `02-apps/dashboards/gen_dashboard.py`, run
`python3 02-apps/dashboards/gen_dashboard.py` to rewrite `llm-rag.json`, then re-apply `02-apps`. The KEDA threshold
line is filled in from `vllm_autoscaling.queue_threshold` at apply time.

GPU cost (`llm:gpu_node_hourly_cost:usd` in `02-apps/manifests/llm/llm-rules.yaml`) is Karpenter's price estimate
for each running GPU node's instance type, capacity type and zone; for spot that follows the spot price history,
not the exact bill. The vLLM and cost panels stay empty while no GPU node is running.

## Pause the GPU overnight
vLLM never scales below `vllm_autoscaling.min_replicas` (1) on its own. To stop paying for the GPU node, pause
KEDA at zero replicas; Karpenter then removes the empty node:

```bash
kubectl -n llm annotate scaledobject vllm autoscaling.keda.sh/paused-replicas="0" --overwrite   # pause
kubectl -n llm annotate scaledobject vllm autoscaling.keda.sh/paused-replicas-                  # resume
```

## Cost Estimate
- The GPU node is the largest cost; pause it when idle (see above).
- GPU in eu-central-1: spot g4dn.xlarge ~$0.32/h, spot g6.xlarge ~$0.47/h (on-demand $0.66 / $1.01); spot may be
  interrupted.
- Fixed, whatever the GPU does: EKS control plane, NAT gateway, internal NLB, on-demand `m6i.large` system node
  and EBS, about $230/month; the spot CPU node adds about $50.
- Rough totals with g4dn.xlarge spot: ~$510/month running 24/7, ~$400/month paused 12 h every night.
  Spot prices move; check with `aws ec2 describe-spot-price-history`.
- g4dn's T4 has no BF16 (vLLM runs the model in FP16), about half the L4's prompt throughput and a smaller KV cache;
  fine for a lab, use `g6` first for heavier concurrent load.

## Tear Down
Destroy in reverse order:

```bash
terraform -chdir=03-gateway destroy    # VPC Link first: it targets the NLB owned by 02-apps
terraform -chdir=02-apps destroy       # deletes NodePools; Karpenter then terminates its nodes
kubectl get nodeclaims                 # wait until empty, or Karpenter's EC2 instances are orphaned
terraform -chdir=01-platform destroy
terraform -chdir=00-infra destroy
```

## Troubleshooting
See [docs/troubleshooting.md](docs/troubleshooting.md): connecting with kubectl/helm, Helm releases failing on the
LB controller webhook, failed releases left behind, namespaces stuck in `Terminating`, a GPU pod stuck `Pending`,
and finding orphaned AWS resources.

## Known Gaps
- The gateway proxies every path, so any API key holder can also call `/ingest` and read `/metrics`.
