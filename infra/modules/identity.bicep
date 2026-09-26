// =============================================================================
// identity.bicep — user-assigned managed identities + container registry
// One identity per compute component so RBAC stays least-privilege and you can
// see in the Portal exactly which app touched which resource.
// =============================================================================
param suffix string
param location string

@description('Entra ID App Registration object ID used by GitHub Actions OIDC federation')
param cicdPrincipalId string

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: replace('acr${suffix}', '-', '')
  location: location
  sku: { name: 'Standard' }
  properties: {
    adminUserEnabled: false // pushes/pulls happen via managed identity / OIDC, never admin creds
  }
}

resource functionIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-ingestion-fn-${suffix}'
  location: location
}

resource workerIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-processing-worker-${suffix}'
  location: location
}

resource ragApiIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-rag-api-${suffix}'
  location: location
}

var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d' // AcrPull

resource acrPullForWorker 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, workerIdentity.id, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: workerIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource acrPullForRagApi 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, ragApiIdentity.id, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: ragApiIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// GitHub Actions (federated, no secret) gets AcrPush so app-ci.yml can build/push images
var acrPushRoleId = '8311e382-0749-4cb8-b61a-304f252e45ec' // AcrPush

resource acrPushForCicd 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, cicdPrincipalId, acrPushRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPushRoleId)
    principalId: cicdPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output acrLoginServer string = acr.properties.loginServer
output functionIdentityId string = functionIdentity.id
output functionIdentityPrincipalId string = functionIdentity.properties.principalId
output functionIdentityClientId string = functionIdentity.properties.clientId
output workerIdentityId string = workerIdentity.id
output workerIdentityPrincipalId string = workerIdentity.properties.principalId
output workerIdentityClientId string = workerIdentity.properties.clientId
output ragApiIdentityId string = ragApiIdentity.id
output ragApiIdentityPrincipalId string = ragApiIdentity.properties.principalId
