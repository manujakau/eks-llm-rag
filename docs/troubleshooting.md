# Troubleshooting

Fixes for problems hit while applying and destroying the stacks. Commands assume the repo root and a working
kubeconfig ([Connect to the cluster](#connect-to-the-cluster)).

```bash
CLUSTER=$(terraform -chdir=00-infra output -raw cluster_name)
REGION=$(terraform -chdir=00-infra output -raw region)
```

## Contents
- [Connect to the cluster](#connect-to-the-cluster)
- [Helm release fails: `no endpoints available for service "aws-load-balancer-webhook-service"`](#helm-release-fails-no-endpoints-available-for-service-aws-load-balancer-webhook-service)
- [Helm release left in `failed` status / `cannot re-use a name that is still in use`](#helm-release-left-in-failed-status--cannot-re-use-a-name-that-is-still-in-use)
- [Namespace stuck in `Terminating` / `context deadline exceeded` on destroy](#namespace-stuck-in-terminating--context-deadline-exceeded-on-destroy)
- [`/ingest` or `/ask` returns `embedding service error (ConnectError)`](#ingest-or-ask-returns-embedding-service-error-connecterror)
- [GPU or CPU pod stays `Pending`](#gpu-or-cpu-pod-stays-pending)
- [vLLM restarts: `VLLM_PORT 'tcp://...' appears to be a URI`](#vllm-restarts-vllm_port-tcp-appears-to-be-a-uri)
- [VPC Link `FAILED`: `NLB is not in active state`](#vpc-link-failed-nlb-is-not-in-active-state)
- [`Provider produced inconsistent result after apply` on a manifest](#provider-produced-inconsistent-result-after-apply-on-a-manifest)
- [Check for orphaned AWS resources](#check-for-orphaned-aws-resources)

## Connect to the cluster

### Install the tools
kubectl must be within one minor version of the cluster (`kubernetes_version` in `00-infra/terraform.tfvars`).

```bash
# kubectl (Linux x86_64); replace v1.37.0 with your cluster's minor version
curl -LO "https://dl.k8s.io/release/v1.37.0/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

# helm: install script, or `sudo snap install helm --classic`
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Write the kubeconfig
```bash
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"
kubectl get nodes
```

Tokens come from `aws eks get-token` on every call; there is no password. The IAM identity that ran
`00-infra` is cluster admin (`enable_cluster_creator_admin_permissions = true`), and the API endpoint is public
(`endpoint_public_access = true`).

| Error | Cause and fix |
|---|---|
| `You must be logged in to the server (Unauthorized)` | Different IAM identity from the one that created the cluster. Check `aws sts get-caller-identity`; switch profile or add an EKS access entry for it |
| `couldn't get current server API group list` / timeout | Wrong `--region`, or the endpoint is unreachable from your network |
| `exec plugin: invalid apiVersion` | AWS CLI v1 or too old; install v2 |
| `Command 'helm' not found` / `kubectl: command not found` | Not installed; see above, or use the toolbox container below |

### No local tools: toolbox container
`alpine/k8s` bundles kubectl, helm and the AWS CLI; pick the tag matching the cluster version.

```bash
docker run --rm -it --network host -v "$HOME/.aws:/root/.aws:ro" alpine/k8s:1.37.0 sh -c "
  aws eks update-kubeconfig --name $CLUSTER --region $REGION && sh"
```

## Helm release fails: `no endpoints available for service "aws-load-balancer-webhook-service"`

```
Internal error occurred: failed calling webhook "mservice.elbv2.k8s.aws": failed to call webhook: Post
"https://aws-load-balancer-webhook-service.kube-system.svc:443/mutate-v1-service?timeout=10s":
no endpoints available for service "aws-load-balancer-webhook-service"
```

**Cause.** The AWS Load Balancer Controller registers a mutating webhook that every new Service passes
through. If another chart creates a Service after the webhook is registered but before the controller's pods are
ready, the API server rejects it. `01-platform` makes Karpenter, KEDA, kube-prometheus-stack and Qdrant
`depends_on = [helm_release.lbc]` to prevent this; a chart added to `01-platform` that creates Services needs the
same.

**If it still happens**, the controller itself is not running:

```bash
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl -n kube-system get endpoints aws-load-balancer-webhook-service   # must list pod IPs
kubectl -n kube-system logs deploy/aws-load-balancer-controller
```

Common causes in the logs: wrong `vpcId` or region (re-apply `00-infra` after changing `region`), or the Pod
Identity association not matching its service account. Then clean up the failed release (next section) and
re-apply.

## Helm release left in `failed` status / `cannot re-use a name that is still in use`

A release that fails during create can stay installed in the cluster but not in Terraform state, so neither
`apply` nor `destroy` touches it again. Its half-created objects can break other things; a failed KEDA install,
for example, leaves an APIService with no Service behind it, which blocks namespace deletion (next section).

```bash
helm list -A                                  # STATUS failed
terraform -chdir=01-platform state list       # release missing from state
helm uninstall <release> -n <namespace>       # e.g. helm uninstall keda -n keda
kubectl delete namespace <namespace>          # if the chart created it (create_namespace = true)
```

Then `terraform -chdir=01-platform apply` installs it cleanly.

## Namespace stuck in `Terminating` / `context deadline exceeded` on destroy

`terraform destroy` waits about five minutes for `kubernetes_namespace_v1` and then fails with
`context deadline exceeded`. First find out what the namespace is waiting for:

```bash
kubectl get ns <ns> -o jsonpath='{range .status.conditions[*]}{.type}={.status}: {.message}{"\n"}{end}'
```

### `NamespaceDeletionDiscoveryFailure=True ... stale GroupVersion discovery`
An aggregated API is registered but its Service is gone, so the namespace controller cannot list every resource
type and will not finish. Find it and remove its owner:

```bash
kubectl get apiservices | grep -v Local       # AVAILABLE False (ServiceNotFound)
```

| APIService | Owner | Fix |
|---|---|---|
| `v1beta1.external.metrics.k8s.io` | KEDA | `helm uninstall keda -n keda`, or `kubectl delete apiservice v1beta1.external.metrics.k8s.io` if the release is already gone |

The namespaces finish within seconds; run the `destroy` again so Terraform records it.

### `NamespaceContentRemaining` / `NamespaceFinalizersRemaining=True`
Objects inside still carry finalizers, usually because their controller was removed first (`01-platform`
destroyed before `02-apps`). List them:

```bash
kubectl api-resources --verbs=list --namespaced -o name |
  xargs -n1 kubectl get -n <ns> --ignore-not-found --show-kind -o name
```

| Leftover | Finalizer owner | Before removing the finalizer |
|---|---|---|
| `ScaledObject` in `llm` | KEDA | Nothing; it only scales the Deployment |
| `Service rag-api`, `TargetGroupBinding` in `rag` | LB controller | Delete the NLB `rag-api-nlb` and its target groups in AWS, after the API Gateway VPC Link that targets it (`03-gateway`) |
| `PersistentVolumeClaim` in `rag` | EBS CSI driver (`00-infra` add-on) | Usually clears on its own; otherwise delete the EBS volume in AWS |

```bash
kubectl -n <ns> patch <kind>/<name> --type=merge -p '{"metadata":{"finalizers":null}}'
```

Removing a finalizer only stops Kubernetes waiting; the AWS resource it was cleaning up stays and keeps costing
money until you delete it. Prevent all of this by destroying in the order given in
[README: Tear Down](../README.md#tear-down).

## `/ingest` or `/ask` returns `embedding service error (ConnectError)`

rag-api cannot reach TEI (`http://tei.llm:8080`). TEI is usually not running yet:

```bash
kubectl -n llm get pods -l app=tei                      # Pending, or Running but not Ready
kubectl -n llm logs deploy/tei --tail=20                # model download progress once it runs
```

| TEI state | Cause and fix |
|---|---|
| `Pending`, events show Karpenter nominating `cpu-*` NodeClaims that never become nodes | Karpenter cannot launch a CPU node; see [GPU or CPU pod stays `Pending`](#gpu-or-cpu-pod-stays-pending) |
| `Running`, `0/1` Ready | Still downloading the model; wait for Ready (the readiness probe keeps it out of the Service until then) |

## GPU or CPU pod stays `Pending`

```bash
kubectl -n llm describe pod -l app=vllm | tail -20
kubectl get nodeclaims
kubectl get events -A --field-selector involvedObject.kind=NodeClaim --sort-by=.lastTimestamp | tail
kubectl -n kube-system logs deploy/karpenter | grep -iE 'error|insufficient|quota' | tail -20
```

Karpenter creates a NodeClaim, the launch fails, it deletes it and retries about every 3 minutes; the
NodeClaim events carry the EC2 error.

| Symptom | Fix |
|---|---|
| `AuthFailure.ServiceLinkedRoleCreationNotPermitted ... service-linked role for EC2 Spot Instances` (GPU NodeClaims may show only `UnfulfillableCapacity`) | The account has never run spot and Karpenter may not create the role. Create it once: `aws iam create-service-linked-role --aws-service-name spot.amazonaws.com`. Karpenter picks it up on its next retry; no apply needed |
| `VcpuLimitExceeded` / `MaxSpotInstanceCountExceeded` in Karpenter logs | Raise the G/VT quota for the capacity type in `gpu_node_pool.capacity_types`; Spot ("All G and VT Spot Instance Requests") and On-Demand are separate and new accounts often start at 0 |
| `InsufficientInstanceCapacity`, or `UnfulfillableCapacity: Unable to fulfill capacity due to your request configuration` with the Spot role present | No spot capacity for the allowed types. Check `aws ec2 get-spot-placement-scores --instance-types g4dn.xlarge g6.xlarge g5.xlarge --target-capacity 1 --region-names "$REGION"` per type (1 = almost none, 10 = very likely); allow a family that scores well in `gpu_node_pool.instance_families`, or add `"on-demand"` to `capacity_types` |
| Karpenter: `exceeds limits` | `gpu_node_pool.cpu_limit` is used up: two `xlarge` nodes at 8 vCPU. Normal at `max_replicas`; a replacement waits until load drops |
| vLLM `0/0` and the ScaledObject has `autoscaling.keda.sh/paused-replicas` | Paused on purpose; see [README: Pause the GPU overnight](../README.md#pause-the-gpu-overnight) |

## vLLM restarts: `VLLM_PORT 'tcp://...' appears to be a URI`

The pod is `Running 0/1` with a growing restart count, the startup probe gets `connection refused`, and the API
server only logs `RuntimeError: Engine core initialization failed. See root cause above`. Find the cause in the
engine process:

```bash
kubectl -n llm logs deploy/vllm --previous | grep -v 'Attempted to load weight' | grep -E 'EngineCore.*(Error|error)' | tail
```

| Root cause | Fix |
|---|---|
| `ValueError: VLLM_PORT 'tcp://172.20.x.x:8000' appears to be a URI` | Kubernetes injects `<SERVICE>_PORT=tcp://...` for every Service in the namespace, and the Service named `vllm` produces `VLLM_PORT`, a real vLLM setting. The Deployment sets `enableServiceLinks: false`; re-apply `02-apps` if an older version is running |
| `CUDA out of memory` during KV cache or CUDA graph setup | Lower `vllm.gpu_memory_utilization` or `vllm.max_model_len` in `02-apps/terraform.tfvars` |

Expected warnings on a T4 (g4dn) that are not errors: BF16 cast to FP16, `Cannot use FA version 2`,
`FlashInfer ... unsupported compute capability 7.5`, `Not enough SMs to use max_autotune_gemm`.

## VPC Link `FAILED`: `NLB is not in active state`

```
Error: waiting for API Gateway VPC Link (...) create: unexpected state 'FAILED', wanted target 'AVAILABLE'.
last error: NLB is not in active state.
```

**Cause.** The LB controller creates `rag-api-nlb` in the background after `02-apps` finishes, and it stays
`provisioning` for a few minutes. `03-gateway` now waits for it (`terraform_data.wait_for_nlb` runs
`aws elbv2 wait load-balancer-available`, up to 10 minutes), so this only appears with an older checkout or when
the NLB takes longer than that.

```bash
aws elbv2 describe-load-balancers --region "$REGION" --names rag-api-nlb --query 'LoadBalancers[0].State'
```

Once it shows `active`, run `terraform -chdir=03-gateway apply` again; Terraform replaces the `FAILED` link. If the
NLB never appears, check the `rag-api` Service: `kubectl -n rag describe svc rag-api` (events) and the LB
controller logs.

## `Provider produced inconsistent result after apply` on a manifest

```
Error: Provider produced inconsistent result after apply
... .object.spec.template.spec.containers[0].readinessProbe.timeoutSeconds: was null, but now cty.NumberIntVal(1).
```

**Cause.** A `kubernetes_manifest` bug: when a new block (a probe, `securityContext`, ...) is added to an object
that already exists, fields left out are planned as null, the API server fills in its defaults, and the provider
rejects the difference. The change itself has usually been applied; check with `kubectl get ... -o yaml`.

**Fix.** Write the defaults the error lists into the manifest, then apply again. For a probe they are
`timeoutSeconds: 1`, `successThreshold: 1`, `failureThreshold: 3`, `periodSeconds: 10` and `httpGet.scheme: HTTP`.
Objects created with the block from the start are not affected.

## Check for orphaned AWS resources
After a failed destroy, or after removing finalizers by hand, check for resources that still cost money:

```bash
O="--region $REGION --output table"
aws ec2 describe-instances $O --filters Name=tag-key,Values=karpenter.sh/nodepool \
  Name=instance-state-name,Values=pending,running \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,Tags[?Key==`karpenter.sh/nodepool`]|[0].Value]'
aws elbv2 describe-load-balancers $O --query 'LoadBalancers[].[LoadBalancerName,State.Code]'
aws apigateway get-vpc-links $O --query 'items[].[name,status]'
aws ec2 describe-volumes $O --filters Name=tag-key,Values=kubernetes.io/created-for/pvc/name \
  --query 'Volumes[].[VolumeId,Size,State]'
```

Karpenter instances left after `01-platform` is destroyed are no longer managed by anything; terminate them
with `aws ec2 terminate-instances --instance-ids ...` before destroying `00-infra`, or the VPC deletion fails.
