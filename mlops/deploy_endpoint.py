"""
Deploys the newly-registered model version to a managed online endpoint with
a traffic-split canary: the new version gets a small slice of live traffic
(default 10%) alongside whatever's already serving, rather than a hard cutover.
Promote to 100% manually (or in a follow-up pipeline step gated on production
metrics) once you trust it.
"""
import argparse

from azure.ai.ml import MLClient
from azure.ai.ml.entities import ManagedOnlineEndpoint, ManagedOnlineDeployment
from azure.identity import DefaultAzureCredential


def deploy(
    endpoint_name: str,
    model_name: str,
    model_version: str,
    deployment_name: str,
    canary_traffic_percent: int,
    subscription_id: str,
    resource_group: str,
    workspace_name: str,
) -> None:
    ml_client = MLClient(
        credential=DefaultAzureCredential(),
        subscription_id=subscription_id,
        resource_group_name=resource_group,
        workspace_name=workspace_name,
    )

    try:
        ml_client.online_endpoints.get(endpoint_name)
    except Exception:
        ml_client.online_endpoints.begin_create_or_update(
            ManagedOnlineEndpoint(name=endpoint_name, auth_mode="aad_token")  # Entra ID token auth, not a static key
        ).result()

    deployment = ManagedOnlineDeployment(
        name=deployment_name,
        endpoint_name=endpoint_name,
        model=f"{model_name}:{model_version}",
        instance_type="Standard_DS3_v2",
        instance_count=1,
    )
    ml_client.online_deployments.begin_create_or_update(deployment).result()

    endpoint = ml_client.online_endpoints.get(endpoint_name)
    current_traffic = endpoint.traffic or {}
    remaining = 100 - canary_traffic_percent
    other_deployments = {k: v for k, v in current_traffic.items() if k != deployment_name}
    scale_factor = (remaining / sum(other_deployments.values())) if other_deployments and sum(other_deployments.values()) > 0 else 0
    new_traffic = {k: round(v * scale_factor) for k, v in other_deployments.items()}
    new_traffic[deployment_name] = canary_traffic_percent
    endpoint.traffic = new_traffic
    ml_client.online_endpoints.begin_create_or_update(endpoint).result()

    print(f"Deployed {deployment_name} ({model_name}:{model_version}) to {endpoint_name} at {canary_traffic_percent}% traffic")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--endpoint-name", required=True)
    parser.add_argument("--model-name", required=True)
    parser.add_argument("--model-version", required=True)
    parser.add_argument("--deployment-name", required=True)
    parser.add_argument("--canary-traffic-percent", type=int, default=10)
    parser.add_argument("--subscription-id", required=True)
    parser.add_argument("--resource-group", required=True)
    parser.add_argument("--workspace-name", required=True)
    args = parser.parse_args()
    deploy(
        args.endpoint_name, args.model_name, args.model_version, args.deployment_name,
        args.canary_traffic_percent, args.subscription_id, args.resource_group, args.workspace_name,
    )
