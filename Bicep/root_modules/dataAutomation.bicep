targetScope = 'subscription'

param location string
param namingStructure string
param workspaceName string
param deploymentNameStructure string
param privateStorageAccountName string
param privateStorageAccountRG string
param containerNames object
param approverEmail string
param tags object = {}

var uamiRoles = {
  'Storage Account Contributor': subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab')
  'Data Factory Contributor': subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '673868aa-7521-48a0-acc6-0f60742d39f5')
}

// get the workspace resource group
resource dataAutomationRG 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: privateStorageAccountRG
}

resource storageaccount 'Microsoft.Storage/storageAccounts@2021-02-01' existing = {
  name: privateStorageAccountName
  scope: dataAutomationRG
}

// user assigned managed identity for Post Deployment Tasks
module uami '../child_modules/uami.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'uami')
  scope: dataAutomationRG
  params: {
    location: location
    namingStructure: namingStructure
    subwloadname: workspaceName
    roles: uamiRoles
    tags: tags
  }
}

// adf
module adf '../child_modules/adf.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'adf')
  scope: dataAutomationRG
  params: {
    namingStructure: namingStructure
    location: location
    deploymentNameStructure: deploymentNameStructure
    privateStorageAcctName: privateStorageAccountName
    userAssignedIdentityId: uami.outputs.managedIdentityId
    tags: tags
  }
}

//logic app
module logicApp '../child_modules/logicApp.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'logicApp')
  scope: dataAutomationRG
  params: {
    namingStructure: namingStructure
    location: location
    storageAcctName: privateStorageAccountName
    adfName: adf.outputs.name
    approverEmail: approverEmail
    tags: tags
  }
}

// Add Public Storage
module publicStorageAccount '../child_modules/storage_account.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'stg-pub')
  scope: dataAutomationRG
  params: {
    location: location
    namingStructure: namingStructure
    subwloadname: 'pub'
    containerNames: [
      containerNames['ingestContainerName']
    ]
    principalIds: [
      adf.outputs.principalId
    ]
    privatize: false
    tags: tags
  }
}

// Setup System Event Grid Topic for public storage account. We only do this here to control the name of the event grid topic
module eventGridForPublic '../child_modules/eventGrid.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'evgt-public')
  scope: dataAutomationRG
  params: {
    location: location
    namingStructure: namingStructure
    subwloadname: publicStorageAccount.outputs.storageAccountName
    resourceId: publicStorageAccount.outputs.storageAccountId
    topicName: 'Microsoft.Storage.StorageAccounts'
    tags: tags
  }
}

// Setup System Event Grid Topic for private storage account. We only do this here to control the name of the event grid topic
module eventGridForPrivate '../child_modules/eventGrid.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'evgt-private')
  scope: dataAutomationRG
  params: {
    location: location
    namingStructure: namingStructure
    subwloadname: privateStorageAccountName
    resourceId: storageaccount.id
    topicName: 'Microsoft.Storage.StorageAccounts'
    tags: tags
  }
}

//
module ingestTrigger '../child_modules/adfTrigger.bicep' = {
  scope: dataAutomationRG
  name: replace(deploymentNameStructure, '{rtype}', 'adf-trigger-public')
  params: {
    adfName: adf.outputs.name
    workspaceName: workspaceName
    storageAccountId: publicStorageAccount.outputs.storageAccountId
    storageAccountType: 'Public'
    ingestPipelineName: 'pipe-data_move'
    sourceStorageAccountName: publicStorageAccount.outputs.storageAccountName
    sinkStorageAccountName: privateStorageAccountName
    containerName: containerNames['ingestContainerName']
  }
}

module exportTrigger '../child_modules/adfTrigger.bicep' = {
  scope: dataAutomationRG
  name: replace(deploymentNameStructure, '{rtype}', 'adf-trigger-private')
  params: {
    adfName: adf.outputs.name
    workspaceName: workspaceName
    storageAccountId: storageaccount.id
    storageAccountType: 'Private'
    ingestPipelineName: 'pipe-data_move'
    sourceStorageAccountName: privateStorageAccountName
    sinkStorageAccountName: publicStorageAccount.outputs.storageAccountName
    containerName: containerNames['exportApprovedContainerName']
  }
}

module adfManagedPrivateEndpoint '../child_modules/adfManagedPrivateEndpoint.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'adf-pep')
  scope: dataAutomationRG
  params: {
    adfName: adf.outputs.name
    privateStorageAccountId: storageaccount.id
    privateStorageAccountName: privateStorageAccountName
  }
}

// deployment script for post deployment tasks
module deploymentScript '../child_modules/deploymentScript.bicep' = {
  name: 'StartTrigger-${replace(deploymentNameStructure, '{rtype}', 'dplscr')}'
  scope: dataAutomationRG
  params: {
    location: location
    subwloadname: 'StartTriggers'
    namingStructure: namingStructure
    arguments: ' -ResourceGroupName ${dataAutomationRG.name} -azureDataFactoryName ${adf.outputs.name} -privateLinkResourceId ${adfManagedPrivateEndpoint.outputs.privateEndpointId}'
    scriptContent: '\r\n          param(\r\n            [string] [Parameter(Mandatory=$true)] $ResourceGroupName,\r\n            [string] [Parameter(Mandatory=$true)] $azureDataFactoryName,\r\n            [string] [Parameter(Mandatory=$true)] $privateLinkResourceId\r\n          )\r\n\r\n          Connect-AzAccount -Identity\r\n\r\n          # Start Triggers\r\n          Get-AzDataFactoryV2Trigger -DataFactoryName $azureDataFactoryName -ResourceGroupName $ResourceGroupName | Start-AzDataFactoryV2Trigger -Force | Out-Null\r\n\r\n          # Approve DFS private endpoint\r\n          foreach ($privateLinkConnection in (Get-AzPrivateEndpointConnection -PrivateLinkResourceId $privateLinkResourceId)) { if ($privateLinkConnection.PrivateLinkServiceConnectionState.Status -eq "Pending") { Approve-AzPrivateEndpointConnection -ResourceId $privateLinkConnection.id } }\r\n        '
    userAssignedIdentityId: uami.outputs.managedIdentityId
    tags: tags
  }
}