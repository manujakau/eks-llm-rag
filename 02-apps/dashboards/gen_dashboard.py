"""Generates llm-rag.json next to this script: python3 02-apps/dashboards/gen_dashboard.py

The KEDA threshold is written as the string "__KEDA_THRESHOLD__"; 02-apps/observability.tf replaces it (quotes
included) with vllm_autoscaling.queue_threshold, so the JSON stays valid and Grafana gets a number.
"""
import json
from pathlib import Path

OUT = Path(__file__).with_name("llm-rag.json")
KEDA_THRESHOLD = "__KEDA_THRESHOLD__"
DS = {"type": "prometheus", "uid": "${datasource}"}
M = 'model_name=~"$model_name"'
RAG = 'job="rag-api", handler!~"/health|/metrics"'
TEI = 'job="tei"'
PODS = 'namespace=~"llm|rag", container=~"vllm|tei|rag-api|qdrant"'
RI = "$__rate_interval"

panels = []
_id = 0
y = 0


def row(title):
    global y, _id
    _id += 1
    panels.append({"id": _id, "type": "row", "title": title, "collapsed": False, "panels": [],
                   "gridPos": {"h": 1, "w": 24, "x": 0, "y": y}})
    y += 1


def line(widths_and_panels, h=8):
    """Lays panels out left to right on one line of the grid."""
    global y
    x = 0
    for w, p in widths_and_panels:
        p["gridPos"] = {"h": h, "w": w, "x": x, "y": y}
        panels.append(p)
        x += w
    y += h


def ts(title, targets, unit="short", description="", threshold=None, min_=None, max_=None):
    global _id
    _id += 1
    custom = {"drawStyle": "line", "lineWidth": 1, "fillOpacity": 10, "showPoints": "never",
              "spanNulls": False}
    steps = [{"color": "green", "value": None}]
    if threshold is not None:
        steps.append({"color": "red", "value": threshold})
        custom["thresholdsStyle"] = {"mode": "dashed"}
    defaults = {"unit": unit, "custom": custom,
                "thresholds": {"mode": "absolute", "steps": steps}}
    if min_ is not None:
        defaults["min"] = min_
    if max_ is not None:
        defaults["max"] = max_
    return {
        "id": _id, "type": "timeseries", "title": title, "description": description, "datasource": DS,
        "fieldConfig": {"defaults": defaults, "overrides": []},
        "options": {"legend": {"displayMode": "list", "placement": "bottom", "showLegend": True},
                    "tooltip": {"mode": "multi", "sort": "desc"}},
        "targets": [{"refId": chr(65 + i), "datasource": DS, "expr": e, "legendFormat": l}
                    for i, (e, l) in enumerate(targets)],
    }


def quantiles(metric, sel, by=""):
    """p50 and p95 of a histogram, optionally split by a label."""
    grp = f"{by}, le" if by else "le"
    prefix = f"{{{{{by}}}}} " if by else ""
    return [(f"histogram_quantile({q}, sum by ({grp}) (rate({metric}_bucket{{{sel}}}[{RI}])))",
             f"{prefix}p{int(q * 100)}") for q in (0.5, 0.95)]


row("vLLM serving")
line([
    (8, ts("Requests running / waiting", [
        (f"sum(vllm:num_requests_running{{{M}}})", "running"),
        (f"sum(vllm:num_requests_waiting{{{M}}})", "waiting"),
    ], description="Dashed line: KEDA queue_threshold (02-apps vllm_autoscaling). KEDA targets this many "
                   "waiting requests per replica.", threshold=KEDA_THRESHOLD, min_=0)),
    (4, ts("vLLM replicas", [
        ('kube_deployment_spec_replicas{namespace="llm", deployment="vllm"}', "desired"),
        ('kube_deployment_status_replicas{namespace="llm", deployment="vllm"}', "current"),
    ], min_=0)),
    (6, ts("Tokens / s", [
        (f"sum(rate(vllm:generation_tokens_total{{{M}}}[{RI}]))", "generation"),
        (f"sum(rate(vllm:prompt_tokens_total{{{M}}}[{RI}]))", "prompt"),
    ], min_=0)),
    (6, ts("KV-cache usage", [
        (f"vllm:kv_cache_usage_perc{{{M}}}", "{{pod}}"),
    ], unit="percentunit", description="Dashed line: VllmKvCacheFull alert level (0.95).",
        threshold=0.95, min_=0, max_=1)),
])
line([
    (12, ts("Prefix-cache hit rate", [
        (f"sum(rate(vllm:prefix_cache_hits_total{{{M}}}[{RI}])) / sum(rate(vllm:prefix_cache_queries_total{{{M}}}[{RI}]))",
         "hit rate"),
    ], unit="percentunit", min_=0, max_=1)),
    (12, ts("Preemptions / s", [
        (f"sum(rate(vllm:num_preemptions_total{{{M}}}[{RI}]))", "preemptions"),
    ], description="Requests evicted from the KV cache and recomputed; non-zero means the cache is too small "
                   "for the load.", min_=0)),
])

row("vLLM latency")
line([
    (6, ts("Time to first token", quantiles("vllm:time_to_first_token_seconds", M), unit="s", min_=0)),
    (6, ts("Inter-token latency", quantiles("vllm:inter_token_latency_seconds", M), unit="s", min_=0)),
    (6, ts("End-to-end latency", quantiles("vllm:e2e_request_latency_seconds", M), unit="s", min_=0)),
    (6, ts("Queue time", quantiles("vllm:request_queue_time_seconds", M), unit="s", min_=0)),
])

row("RAG API")
line([
    (8, ts("Requests / s by handler and status", [
        (f"sum by (handler, status) (rate(http_requests_total{{{RAG}}}[{RI}]))", "{{handler}} {{status}}"),
    ], unit="reqps", min_=0)),
    (8, ts("5xx error rate", [
        (f'sum by (handler) (rate(http_requests_total{{{RAG}, status="5xx"}}[{RI}])) '
         f"/ sum by (handler) (rate(http_requests_total{{{RAG}}}[{RI}]))", "{{handler}}"),
    ], unit="percentunit", description="Share of requests answered with 5xx. /ask returns 503 while vLLM is "
                                       "down and 504 when it takes over 25 s.", min_=0, max_=1)),
    (8, ts("Latency by handler", quantiles("http_request_duration_seconds", RAG, by="handler"),
           unit="s", min_=0)),
])

row("Embeddings (TEI)")
line([
    (8, ts("Embed requests / s", [
        (f"sum(rate(te_embed_count{{{TEI}}}[{RI}]))", "total"),
        (f"sum(rate(te_embed_success{{{TEI}}}[{RI}]))", "success"),
    ], min_=0)),
    (16, ts("Embed latency p95", [
        (f"histogram_quantile(0.95, sum by (le) (rate(te_embed_duration_bucket{{{TEI}}}[{RI}])))", "total"),
        (f"histogram_quantile(0.95, sum by (le) (rate(te_embed_queue_duration_bucket{{{TEI}}}[{RI}])))", "queue"),
        (f"histogram_quantile(0.95, sum by (le) (rate(te_embed_inference_duration_bucket{{{TEI}}}[{RI}])))",
         "inference"),
    ], unit="s", min_=0)),
])

row("Resources")
line([
    (12, ts("CPU (cores)", [
        (f"sum by (pod) (rate(container_cpu_usage_seconds_total{{{PODS}}}[{RI}]))", "{{pod}}"),
    ], min_=0)),
    (12, ts("Memory (working set)", [
        (f"sum by (pod) (container_memory_working_set_bytes{{{PODS}}})", "{{pod}}"),
    ], unit="bytes", min_=0)),
])

row("Cost")
line([
    (12, ts("GPU nodes $/h", [
        ("llm:gpu_node_hourly_cost:usd", "GPU nodes"),
    ], unit="currencyUSD", description="Karpenter's price estimate for each running GPU node "
                                       "(instance type, capacity type, zone), summed.", min_=0)),
    (12, ts("$ per million output tokens", [
        ("llm:usd_per_million_output_tokens", "$ / 1M tokens"),
    ], unit="currencyUSD", description="GPU $/h divided by output tokens per hour (15 min rate). Empty or "
                                       "infinite while no tokens are generated.", min_=0)),
])

dashboard = {
    "uid": "llm-rag",
    "title": "LLM / RAG",
    "tags": ["llm", "rag", "vllm"],
    "timezone": "browser",
    "editable": True,
    "graphTooltip": 1,
    "refresh": "30s",
    "time": {"from": "now-1h", "to": "now"},
    "schemaVersion": 39,
    "version": 1,
    "templating": {"list": [
        {"name": "datasource", "label": "Data source", "type": "datasource", "query": "prometheus",
         "current": {"selected": False, "text": "Prometheus", "value": "prometheus"}, "hide": 0},
        {"name": "model_name", "label": "Model", "type": "query", "datasource": DS,
         "definition": "label_values(vllm:num_requests_running, model_name)",
         "query": {"query": "label_values(vllm:num_requests_running, model_name)", "refId": "model_name"},
         "refresh": 2, "includeAll": True, "allValue": ".*", "multi": False, "sort": 1,
         "current": {"selected": True, "text": "All", "value": "$__all"}, "hide": 0},
    ]},
    "annotations": {"list": []},
    "panels": panels,
}

OUT.write_text(json.dumps(dashboard, indent=2) + "\n")
