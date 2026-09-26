"""Registers the trained model artifact as a new version in the Azure ML model registry — only reached if evaluate.py passed."""
import argparse

from azure.ai.ml import MLClient
from azure.ai.ml.entities import Model
from azure.ai.ml.constants import AssetTypes
from azure.identity import DefaultAzureCredential


def register(job_name: str, model_name: str, subscription_id: str, resource_group: str, workspace_name: str) -> str:
    ml_client = MLClient(
        credential=DefaultAzureCredential(),
        subscription_id=subscription_id,
        resource_group_name=resource_group,
        workspace_name=workspace_name,
    )

    model = Model(
        path=f"azureml://jobs/{job_name}/outputs/model_dir",
        name=model_name,
        type=AssetTypes.CUSTOM_MODEL,
        description=f"Registered from training job {job_name} via model-cd.yml",
    )
    registered = ml_client.models.create_or_update(model)
    print(f"Registered {registered.name}:{registered.version}")
    return registered.version


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--job-name", required=True)
    parser.add_argument("--model-name", required=True)
    parser.add_argument("--subscription-id", required=True)
    parser.add_argument("--resource-group", required=True)
    parser.add_argument("--workspace-name", required=True)
    args = parser.parse_args()
    register(args.job_name, args.model_name, args.subscription_id, args.resource_group, args.workspace_name)
