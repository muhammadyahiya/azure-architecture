// =============================================================================
// storage.bicep — ADLS Gen2-enabled storage account for document ingestion.
// Blob-created events are emitted natively by the storage account's system
// topic; see eventgrid.bicep for the subscription that routes them.
// =============================================================================
param suffix string
param location string
param functionIdentityPrincipalId string
param functionIdentityId string
param functionIdentityClientId string
param workerPrincipalId string

resource sa 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: replace('st${suffix}', '-', '')
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    isHnsEnabled: true // ADLS Gen2 hierarchical namespace
    minimumTlsVersion: 'TLS1_2'
    allowSharedKeyAccess: false // managed identity / RBAC only, no account keys
  }
}

resource docsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${sa.name}/default/documents'
}

var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var storageBlobDataReaderRoleId = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'

resource functionBlobRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sa.id, functionIdentityPrincipalId, storageBlobDataContributorRoleId)
  scope: sa
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: functionIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource workerBlobRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sa.id, workerPrincipalId, storageBlobDataReaderRoleId)
  scope: sa
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataReaderRoleId)
    principalId: workerPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// -----------------------------------------------------------------------------
// Ingestion Function — a cheap, independent validation gate. It listens to the
// SAME blob-created signal as the Event Grid → Service Bus path below, via a
// native blob trigger (source: EventGrid, so it's push- not poll-based), but
// on its own plan/identity. It writes the initial "received" record to Cosmos
// and rejects obviously-bad uploads (wrong extension, zero bytes) before they
// ever reach the expensive chunk/embed worker. A bug here never blocks that
// worker, because the two are decoupled listeners, not a pipeline.
// -----------------------------------------------------------------------------
resource funcPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'plan-ingestion-fn-${suffix}'
  location: location
  sku: { name: 'FC1', tier: 'FlexConsumption' }
  kind: 'functionapp,linux'
  properties: { reserved: true }
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: 'func-ingestion-${suffix}'
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${functionIdentityId}': {} }
  }
  properties: {
    serverFarmId: funcPlan.id
    httpsOnly: true
    siteConfig: {
      appSettings: [
        { name: 'AzureWebJobsStorage__accountName', value: sa.name }
        { name: 'AzureWebJobsStorage__credential', value: 'managedidentity' }
        { name: 'AzureWebJobsStorage__clientId', value: functionIdentityClientId }
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'python' }
        { name: 'COSMOS_ENDPOINT', value: '' } // set via app-cd.yml / az cli after cosmosdb module output is known
      ]
    }
  }
}

output storageAccountId string = sa.id
output storageAccountName string = sa.name
output documentsContainerName string = 'documents'
output functionAppName string = functionApp.name
output functionAppId string = functionApp.id
