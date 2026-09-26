// =============================================================================
// monitoring.bicep — Log Analytics + Application Insights
// Every Container App and Function ships traces here; the rag_api additionally
// emits OpenTelemetry spans that Foundry's Control Plane can correlate with
// model/tool calls when you wire the Foundry tracing exporter (see rag_api/main.py).
// =============================================================================
param suffix string
param location string

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${suffix}'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${suffix}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

output logAnalyticsWorkspaceId string = logAnalytics.id
output appInsightsConnectionString string = appInsights.properties.ConnectionString
