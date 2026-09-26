// =============================================================================
// ai-search.bicep — vector + hybrid + semantic-ranked retrieval index.
// The index schema itself is created at deploy time by processing_worker
// (see src/processing_worker/search_indexer.py) — Bicep only provisions the
// service, not the index, so index/field changes don't require an infra deploy.
// =============================================================================
param suffix string
param location string
param workerPrincipalId string
param ragApiPrincipalId string

resource search 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: 'srch-${suffix}'
  location: location
  sku: { name: 'standard' } // 'basic' works for dev; semantic ranker needs standard+ for production SLAs
  properties: {
    replicaCount: 1
    partitionCount: 1
    semanticSearch: 'standard'
    disableLocalAuth: true // RBAC / managed identity only, no admin/query API keys
    authOptions: null
  }
}

var searchIndexDataContributorRoleId = '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
var searchIndexDataReaderRoleId = '1407120a-92aa-4202-b7e9-c0e197c71c8f'
var searchServiceContributorRoleId = '7ca78c08-252a-4471-8644-bb5ff32d4ba0'

resource workerServiceContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, workerPrincipalId, searchServiceContributorRoleId)
  scope: search
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchServiceContributorRoleId)
    principalId: workerPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource workerIndexContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, workerPrincipalId, searchIndexDataContributorRoleId)
  scope: search
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchIndexDataContributorRoleId)
    principalId: workerPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource ragApiIndexReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, ragApiPrincipalId, searchIndexDataReaderRoleId)
  scope: search
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchIndexDataReaderRoleId)
    principalId: ragApiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output endpoint string = 'https://${search.name}.search.windows.net'
output serviceName string = search.name
