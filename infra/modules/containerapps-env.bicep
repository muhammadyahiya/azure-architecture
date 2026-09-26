// =============================================================================
// containerapps-env.bicep — the environment + both Container Apps.
// processing-worker scales on Service Bus subscription depth via KEDA, using
// the identity-based auth mode (no connection string secret). rag-api scales
// on concurrent HTTP requests and keeps 1 warm replica to avoid cold-start
// latency on the retrieval path.
//
// Both apps start on a placeholder image (mcr.microsoft.com/k8se/quickstart)
// so infra can deploy before the first CI build exists — app-cd.yml updates
// the image on every push to main.
// =============================================================================
param suffix string
param location string
param logAnalyticsWorkspaceId string
param vnetSubnetId string = ''
param workerIdentityId string
param workerIdentityClientId string
param ragApiIdentityId string
param serviceBusNamespaceFqdn string
param serviceBusProcessingQueueName string
param cosmosEndpoint string
param searchEndpoint string
param foundryEndpoint string
param appInsightsConnectionString string
param containerRegistryLoginServer string

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: last(split(logAnalyticsWorkspaceId, '/'))
}

resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${suffix}'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: empty(vnetSubnetId) ? null : {
      infrastructureSubnetId: vnetSubnetId
      internal: false // flip to true once you've set up private ingress — see docs/decision-log.md
    }
    workloadProfiles: [
      { name: 'Consumption', workloadProfileType: 'Consumption' }
    ]
  }
}

resource processingWorker 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-processing-worker-${suffix}'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${workerIdentityId}': {} }
  }
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      registries: [
        { server: containerRegistryLoginServer, identity: workerIdentityId }
      ]
      activeRevisionsMode: 'Single'
    }
    template: {
      containers: [
        {
          name: 'processing-worker'
          image: 'mcr.microsoft.com/k8se/quickstart:latest' // replaced by app-cd.yml
          resources: { cpu: json('1.0'), memory: '2Gi' }
          env: [
            { name: 'SERVICEBUS_NAMESPACE_FQDN', value: serviceBusNamespaceFqdn }
            { name: 'SERVICEBUS_SUBSCRIPTION', value: serviceBusProcessingQueueName }
            { name: 'COSMOS_ENDPOINT', value: cosmosEndpoint }
            { name: 'SEARCH_ENDPOINT', value: searchEndpoint }
            { name: 'FOUNDRY_ENDPOINT', value: foundryEndpoint }
            { name: 'AZURE_CLIENT_ID', value: workerIdentityClientId } // tells DefaultAzureCredential which UAMI to use
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 10
        rules: [
          {
            name: 'servicebus-queue-scaler'
            custom: {
              type: 'azure-servicebus'
              identity: workerIdentityId // KEDA authenticates via this UAMI, no shared access key
              metadata: {
                namespace: replace(serviceBusNamespaceFqdn, '.servicebus.windows.net', '')
                topicName: 'document-ingested'
                subscriptionName: serviceBusProcessingQueueName
                messageCount: '5' // ~5 in-flight messages per replica before KEDA adds another
              }
            }
          }
        ]
      }
    }
  }
}

resource ragApi 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-rag-api-${suffix}'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${ragApiIdentityId}': {} }
  }
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      registries: [
        { server: containerRegistryLoginServer, identity: ragApiIdentityId }
      ]
      ingress: {
        external: true
        targetPort: 8000
        traffic: [
          { latestRevision: true, weight: 100 } // switch to a split for canary rollouts of a new prompt/model version
        ]
      }
      activeRevisionsMode: 'Multiple' // required for traffic-split canary deploys
    }
    template: {
      containers: [
        {
          name: 'rag-api'
          image: 'mcr.microsoft.com/k8se/quickstart:latest' // replaced by app-cd.yml
          resources: { cpu: json('1.0'), memory: '2Gi' }
          env: [
            { name: 'COSMOS_ENDPOINT', value: cosmosEndpoint }
            { name: 'SEARCH_ENDPOINT', value: searchEndpoint }
            { name: 'FOUNDRY_ENDPOINT', value: foundryEndpoint }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
          ]
        }
      ]
      scale: {
        minReplicas: 1 // keep one warm — this is a synchronous, latency-sensitive path
        maxReplicas: 20
        rules: [
          { name: 'http-concurrency', http: { metadata: { concurrentRequests: '30' } } }
        ]
      }
    }
  }
}

output ragApiFqdn string = ragApi.properties.configuration.ingress.fqdn
