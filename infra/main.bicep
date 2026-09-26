// =============================================================================
// main.bicep — subscription-scope orchestrator
// Creates the resource group, then composes every module below.
// Deploy with:
//   az deployment sub create --location <region> --template-file main.bicep \
//     --parameters main.parameters.json
// =============================================================================
targetScope = 'subscription'

@description('Short project name, lowercase, no spaces — used as a naming prefix')
@minLength(3)
@maxLength(12)
param projectName string

@description('Environment name: dev | test | prod')
@allowed(['dev', 'test', 'prod'])
param environmentName string = 'dev'

@description('Azure region for all resources')
param location string = 'eastus2'

@description('Optional subnet resource ID if you are injecting Container Apps + private endpoints into a VNet. Leave empty to skip networking (see docs/decision-log.md).')
param vnetSubnetId string = ''

@description('Object ID of the GitHub Actions federated Entra ID app registration, granted least-privilege RBAC on the resources it needs to deploy/push to')
param cicdPrincipalId string

var suffix = '${projectName}-${environmentName}'
var rgName = 'rg-${suffix}'

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
}

module identity 'modules/identity.bicep' = {
  name: 'identity'
  scope: rg
  params: {
    suffix: suffix
    location: location
    cicdPrincipalId: cicdPrincipalId
  }
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    suffix: suffix
    location: location
  }
}

module keyvault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  scope: rg
  params: {
    suffix: suffix
    location: location
    workerPrincipalId: identity.outputs.workerIdentityPrincipalId
    ragApiPrincipalId: identity.outputs.ragApiIdentityPrincipalId
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    suffix: suffix
    location: location
    functionIdentityPrincipalId: identity.outputs.functionIdentityPrincipalId
    functionIdentityId: identity.outputs.functionIdentityId
    functionIdentityClientId: identity.outputs.functionIdentityClientId
    workerPrincipalId: identity.outputs.workerIdentityPrincipalId
  }
}

module servicebus 'modules/servicebus.bicep' = {
  name: 'servicebus'
  scope: rg
  params: {
    suffix: suffix
    location: location
    workerPrincipalId: identity.outputs.workerIdentityPrincipalId
    functionIdentityPrincipalId: identity.outputs.functionIdentityPrincipalId
  }
}

module eventgrid 'modules/eventgrid.bicep' = {
  name: 'eventgrid'
  scope: rg
  params: {
    suffix: suffix
    location: location
    storageAccountId: storage.outputs.storageAccountId
    serviceBusTopicId: servicebus.outputs.ingestTopicId
  }
}

module cosmosdb 'modules/cosmosdb.bicep' = {
  name: 'cosmosdb'
  scope: rg
  params: {
    suffix: suffix
    location: location
    workerPrincipalId: identity.outputs.workerIdentityPrincipalId
    ragApiPrincipalId: identity.outputs.ragApiIdentityPrincipalId
  }
}

module aisearch 'modules/ai-search.bicep' = {
  name: 'aisearch'
  scope: rg
  params: {
    suffix: suffix
    location: location
    workerPrincipalId: identity.outputs.workerIdentityPrincipalId
    ragApiPrincipalId: identity.outputs.ragApiIdentityPrincipalId
  }
}

module aifoundry 'modules/ai-foundry.bicep' = {
  name: 'aifoundry'
  scope: rg
  params: {
    suffix: suffix
    location: location
    workerPrincipalId: identity.outputs.workerIdentityPrincipalId
    ragApiPrincipalId: identity.outputs.ragApiIdentityPrincipalId
  }
}

module containerAppsEnv 'modules/containerapps-env.bicep' = {
  name: 'containerAppsEnv'
  scope: rg
  params: {
    suffix: suffix
    location: location
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    vnetSubnetId: vnetSubnetId
    workerIdentityId: identity.outputs.workerIdentityId
    workerIdentityClientId: identity.outputs.workerIdentityClientId
    ragApiIdentityId: identity.outputs.ragApiIdentityId
    serviceBusNamespaceFqdn: servicebus.outputs.namespaceFqdn
    serviceBusProcessingQueueName: servicebus.outputs.processingQueueName
    cosmosEndpoint: cosmosdb.outputs.endpoint
    searchEndpoint: aisearch.outputs.endpoint
    foundryEndpoint: aifoundry.outputs.endpoint
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    containerRegistryLoginServer: identity.outputs.acrLoginServer
  }
}

output resourceGroupName string = rg.name
output containerRegistryLoginServer string = identity.outputs.acrLoginServer
output ragApiFqdn string = containerAppsEnv.outputs.ragApiFqdn
