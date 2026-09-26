// =============================================================================
// ai-foundry.bicep — Microsoft Foundry account + project + a model deployment.
// NOTE: Foundry's resource schema has moved fast across 2025-2026 (hub/project
// workspace kind -> unified "AIServices" account + project sub-resource ->
// ongoing Agent Service / Foundry IQ additions). Verify this against
// `az foundry` / the current bicep-registry-modules AVM module before you rely
// on it for anything beyond a starting point — see docs/decision-log.md.
// =============================================================================
param suffix string
param location string
param workerPrincipalId string
param ragApiPrincipalId string

@description('Model to deploy from the Foundry catalog for generation, e.g. gpt-4o, gpt-5.4, claude-... — check current catalog availability/region for your subscription')
param generationModel string = 'gpt-4o'

@description('Embedding model for the RAG pipeline')
param embeddingModel string = 'text-embedding-3-large'

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: 'aif-${suffix}'
  location: location
  kind: 'AIServices'
  sku: { name: 'S0' }
  identity: { type: 'SystemAssigned' }
  properties: {
    customSubDomainName: 'aif-${suffix}'
    disableLocalAuth: true // managed identity / Entra ID token auth only
    allowProjectManagement: true
  }
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2024-10-01' = {
  parent: foundryAccount
  name: 'project-${suffix}'
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {}
}

resource generationDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: foundryAccount
  name: generationModel
  sku: { name: 'Standard', capacity: 10 }
  properties: {
    model: { format: 'OpenAI', name: generationModel }
  }
}

resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: foundryAccount
  name: embeddingModel
  sku: { name: 'Standard', capacity: 10 }
  properties: {
    model: { format: 'OpenAI', name: embeddingModel }
  }
  dependsOn: [generationDeployment] // deployments provision sequentially against one account
}

var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908'

resource workerFoundryRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundryAccount.id, workerPrincipalId, cognitiveServicesUserRoleId)
  scope: foundryAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: workerPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource ragApiFoundryRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundryAccount.id, ragApiPrincipalId, cognitiveServicesUserRoleId)
  scope: foundryAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: ragApiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output endpoint string = foundryAccount.properties.endpoint
output accountName string = foundryAccount.name
output projectName string = foundryProject.name
output generationDeploymentName string = generationDeployment.name
output embeddingDeploymentName string = embeddingDeployment.name
