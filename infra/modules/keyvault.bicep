// =============================================================================
// keyvault.bicep — for the one class of thing that IS a secret: third-party
// API keys you don't control. Azure-native calls use managed identity, not this.
// =============================================================================
param suffix string
param location string
param workerPrincipalId string
param ragApiPrincipalId string

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-${take(suffix, 17)}' // Key Vault names are capped at 24 chars
  location: location
  properties: {
    sku: { family: 'A', name: 'standard' }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
  }
}

var kvSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User

resource secretsUserForWorker 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, workerPrincipalId, kvSecretsUserRoleId)
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvSecretsUserRoleId)
    principalId: workerPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource secretsUserForRagApi 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, ragApiPrincipalId, kvSecretsUserRoleId)
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvSecretsUserRoleId)
    principalId: ragApiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output vaultUri string = kv.properties.vaultUri
output vaultName string = kv.name
