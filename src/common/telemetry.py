"""
Wires OpenTelemetry to Application Insights so processing_worker and rag_api
traces land in the same place, and (per docs/decision-log.md) can be
correlated with Foundry Control Plane traces once you enable the Foundry
tracing exporter alongside this one.
"""
import logging
import os

from azure.monitor.opentelemetry import configure_azure_monitor


def init_telemetry(service_name: str) -> None:
    conn_str = os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING")
    if not conn_str:
        logging.warning("APPLICATIONINSIGHTS_CONNECTION_STRING not set — telemetry disabled (fine for local dev)")
        return
    configure_azure_monitor(connection_string=conn_str, logger_name=service_name)
