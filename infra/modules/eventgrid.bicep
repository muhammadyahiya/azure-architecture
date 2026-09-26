// =============================================================================
// eventgrid.bicep — routes native Blob "created" events to the Service Bus
// ingest topic. Storage account already emits these via its system topic;
// we just subscribe to it and filter to the /documents container + supported
// extensions.
// =============================================================================
param suffix string
param location string
param storageAccountId string
param serviceBusTopicId string

resource systemTopic 'Microsoft.EventGrid/systemTopics@2023-12-15-preview' = {
  name: 'egst-${suffix}'
  location: location
  properties: {
    source: storageAccountId
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
}

resource subscriptionToServiceBus 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2023-12-15-preview' = {
  parent: systemTopic
  name: 'route-to-servicebus'
  properties: {
    destination: {
      endpointType: 'ServiceBusTopic'
      properties: {
        resourceId: serviceBusTopicId
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
      ]
      subjectBeginsWith: '/blobServices/default/containers/documents/'
      subjectEndsWith: '' // narrow per project, e.g. '.pdf'
    }
    retryPolicy: {
      maxDeliveryAttempts: 30
      eventTimeToLiveInMinutes: 1440
    }
    deadLetterWithResourceIdentity: {
      identity: {
        type: 'SystemAssigned'
      }
      deadLetterDestination: {
        endpointType: 'StorageBlob'
        properties: {
          resourceId: storageAccountId
          blobContainerName: 'eventgrid-deadletter'
        }
      }
    }
  }
}

output systemTopicName string = systemTopic.name
