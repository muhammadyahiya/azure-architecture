"""
The CI/CD gate. Computes a metric against a held-out set and exits non-zero if
it's below threshold — model-cd.yml treats this step's exit code as a hard
gate before register_model.py / deploy_endpoint.py ever run.

For a fine-tuned/custom model: accuracy, F1, RMSE, whatever your task uses.
For an LLM/agent app (no weights to retrain — see docs/decision-log.md),
replace this with an offline eval suite over groundedness/relevance/safety
against a fixed prompt set, and gate app-cd.yml instead of this file.
"""
import argparse
import json
import sys

from azure.ai.ml import MLClient
from azure.identity import DefaultAzureCredential


def evaluate_job(job_name: str, metric_name: str, threshold: float, subscription_id: str, resource_group: str, workspace_name: str) -> bool:
    ml_client = MLClient(
        credential=DefaultAzureCredential(),
        subscription_id=subscription_id,
        resource_group_name=resource_group,
        workspace_name=workspace_name,
    )

    job = ml_client.jobs.get(job_name)
    metrics = ml_client.jobs.get_metrics(job_name)  # illustrative — actual metric retrieval depends on how train_model.py logs to MLflow
    score = metrics.get(metric_name)

    if score is None:
        print(f"Metric '{metric_name}' not found on job {job_name}", file=sys.stderr)
        return False

    passed = score >= threshold
    print(json.dumps({"job": job_name, "metric": metric_name, "score": score, "threshold": threshold, "passed": passed}))
    return passed


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--job-name", required=True)
    parser.add_argument("--metric-name", default="accuracy")
    parser.add_argument("--threshold", type=float, default=0.85)
    parser.add_argument("--subscription-id", required=True)
    parser.add_argument("--resource-group", required=True)
    parser.add_argument("--workspace-name", required=True)
    args = parser.parse_args()

    ok = evaluate_job(args.job_name, args.metric_name, args.threshold, args.subscription_id, args.resource_group, args.workspace_name)
    sys.exit(0 if ok else 1)
