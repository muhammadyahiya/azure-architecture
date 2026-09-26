// =============================================================================
// cosmosdb.bicep — document metadata, processing status, and audit trail.
// AI Search holds vectors + chunks for retrieval; Cosmos holds the operational
// record (who uploaded what, when it was indexed, what chunk count, errors).
// Keeping these separate means you can rebuild the Search index from Cosmos +
// blob at any time without re-deriving provenance.
// =============================================================================
param suffix string
param location string
param workerPrincipalId string
param ragApiPrincipalId string

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: 'cosmos-${suffix}'
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: { defaultConsistencyLevel: 'Session' }
    locations: [
      { locationName: location, failoverPriority: 0 }
    ]
    disableLocalAuth: true // RBAC / managed identity only, no primary keys
    capabilities: [] // add { name: 'EnableServerless' } here for dev/test cost savings
  }
}

resource db 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmos
  name: 'ragplatform'
  properties: { resource: { id: 'ragplatform' } }
}

resource documentsContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: db
  name: 'documents'
  properties: {
    resource: {
      id: 'documents'
      partitionKey: { paths: ['/documentId'], kind: 'Hash' }
      indexingPolicy: {
        indexingMode: 'consistent'
        includedPaths: [{ path: '/*' }]
        excludedPaths: [{ path: '/chunkText/?' }] // don't index the large text blob field
      }
    }
  }
}

var dataContributorRoleDefId = resourceId('Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions', cosmos.name, '00000000-0000-0000-0000-000000000002')

resource workerDataRbac 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmos
  name: guid(cosmos.id, workerPrincipalId, 'contributor')
  properties: {
    roleDefinitionId: dataContributorRoleDefId
    principalId: workerPrincipalId
    scope: cosmos.id
  }
}

resource ragApiDataRbac 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmos
  name: guid(cosmos.id, ragApiPrincipalId, 'contributor')
  properties: {
    roleDefinitionId: dataContributorRoleDefId
    principalId: ragApiPrincipalId
    scope: cosmos.id
  }
}

output endpoint string = cosmos.properties.documentEndpoint
output databaseName string = db.name
output containerName string = documentsContainer.name
