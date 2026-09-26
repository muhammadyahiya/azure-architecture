// =============================================================================
// servicebus.bicep — the reliability layer in front of processing_worker.
// A topic (not a plain queue) so you can add more subscribers later (e.g. an
// audit-log consumer) without touching the publisher.
// =============================================================================
param suffix string
param location string
param workerPrincipalId string
param functionIdentityPrincipalId string

resource sb 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: 'sb-${suffix}'
  location: location
  sku: { name: 'Standard', tier: 'Standard' }
}

resource ingestTopic 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = {
  parent: sb
  name: 'document-ingested'
  properties: {
    defaultMessageTimeToLive: 'P1D'
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    requiresDuplicateDetection: true
  }
}

resource processingSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: ingestTopic
  name: 'processing-worker'
  properties: {
    maxDeliveryCount: 5
    deadLetteringOnMessageExpiration: true
    lockDuration: 'PT5M' // generous — chunking + embedding a large doc can take a while
    requiresSession: true // one session per documentId keeps a multi-page doc's chunks in order
  }
}

var serviceBusDataSenderRoleId = '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'
var serviceBusDataReceiverRoleId = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'

resource functionSenderRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sb.id, functionIdentityPrincipalId, serviceBusDataSenderRoleId)
  scope: sb
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataSenderRoleId)
    principalId: functionIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource workerReceiverRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sb.id, workerPrincipalId, serviceBusDataReceiverRoleId)
  scope: sb
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataReceiverRoleId)
    principalId: workerPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output namespaceFqdn string = '${sb.name}.servicebus.windows.net'
output ingestTopicId string = ingestTopic.id
output ingestTopicName string = ingestTopic.name
output processingQueueName string = processingSubscription.name
