"""
Submits (doesn't run inline) a training job to the Azure ML workspace behind
your Foundry hub/project. This is the "you own model weights" MLOps track —
see docs/decision-log.md for why this is a separate pipeline from app-cd.yml.

Usage: python train.py --config-name <job-name> and let model-cd.yml wire the
rest (evaluate -> register -> deploy) via job status polling.
"""
import argparse
import os

from azure.ai.ml import MLClient, command, Input
from azure.ai.ml.entities import Environment
from azure.identity import DefaultAzureCredential


def get_ml_client() -> MLClient:
    return MLClient(
        credential=DefaultAzureCredential(),
        subscription_id=os.environ["AZURE_SUBSCRIPTION_ID"],
        resource_group_name=os.environ["AZURE_RESOURCE_GROUP"],
        # For a Foundry-hosted workspace, this is the Foundry hub/project name,
        # not a separate "AML workspace" — they're the same resource. See
        # docs/decision-log.md for why this template keeps that ambiguity explicit.
        workspace_name=os.environ["AML_WORKSPACE_NAME"],
    )


def submit_training_job(experiment_name: str, training_script: str, data_path: str) -> str:
    ml_client = get_ml_client()

    env = Environment(
        name="training-env",
        conda_file="environment.yml",
        image="mcr.microsoft.com/azureml/curated/sklearn-1.5:latest",
    )

    job = command(
        code="./src",  # your actual training code lives alongside this, not shown — this wraps it
        command=f"python {training_script} --data ${{inputs.data}} --output-model-dir ${{outputs.model_dir}}",
        environment=env,
        inputs={"data": Input(type="uri_folder", path=data_path)},
        outputs={"model_dir": {"type": "uri_folder"}},
        compute="cpu-cluster",  # provision separately, or switch to serverless compute
        experiment_name=experiment_name,
        display_name=f"{experiment_name}-training-run",
    )

    submitted = ml_client.jobs.create_or_update(job)
    print(f"Submitted job: {submitted.name} (status: {submitted.status})")
    return submitted.name


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--experiment-name", required=True)
    parser.add_argument("--training-script", default="train_model.py")
    parser.add_argument("--data-path", required=True)
    args = parser.parse_args()
    job_name = submit_training_job(args.experiment_name, args.training_script, args.data_path)
    # Write job name where model-cd.yml can pick it up as a step output
    with open(os.environ.get("GITHUB_OUTPUT", "/dev/null"), "a") as f:
        f.write(f"job_name={job_name}\n")
