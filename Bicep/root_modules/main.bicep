targetScope = 'subscription'

param deploymentTime string = utcNow()
param location string = deployment().location
@allowed([
  'dev'
  'test'
  'prod'
  'sandbox'
  'staging'
  'shared'
  'uat'
])
param environment string
param workspaceName string
param approverEmail string
param sequence int = 1
param tags object = {}

// existing resource objects
param avdAccess bool = false
param virtualNetwork object = {}
param computeSubnetId string = ''
param privateEndpointSubnetId string = ''
param privateStorage object = {}
param logAnalytics object = {}
param userAssignedManagedIdentity object = {}

//########################################################################//
//                                                                        //
//                             Varliables                                 //
//                                                                        //
//########################################################################//

var namingConvention = '{wloadname}-{subwloadname}-{rtype}-{env}-{loc}-{seq}'
var sequenceFormatted = format('{0:00}', sequence)
var deploymentNameStructure = toLower('${workspaceName}-{rtype}-${deploymentTime}')
var namingStructure = toLower(replace(replace(replace(replace(namingConvention, '{env}', environment), '{loc}', location), '{seq}', sequenceFormatted), '{wloadname}', workspaceName))

var containerNames = {
  'exportApprovedContainerName': 'export-approved'
  'ingestContainerName': 'ingest'
  'exportPendingContainerName': 'export-pending'
}

var vnetAddressPrefixes = [
  '172.17.0.0/24'
]

var subnets = [
  {
    name: 'privateEndpoints' // this is hard coded in a resource lookup
    addressPrefix: '172.17.0.0/25'
    privateEndpointNetworkPolicies: 'Enabled'
    serviceEndpoints: []
  }
  {
    name: 'compute' // this is hard coded in a resource lookup
    addressPrefix: '172.17.0.128/25'
    privateEndpointNetworkPolicies: 'Disabled'
    serviceEndpoints: []
  }
]

//########################################################################//
//                                                                        //
//                             Foundations                                //
//                                                                        //
//########################################################################//

// get the existing log analytics workspace resource group if the logAnalytics object was supplied at deployment
resource existingLogAnalyticsRG 'Microsoft.Resources/resourceGroups@2021-04-01' existing = if (!empty(logAnalytics)) {
  name: split(privateStorage.id, '/')[3]
}

// get the existing log analytics workspace if the logAnalytics object was supplied at deployment
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2020-03-01-preview' existing = if (!empty(logAnalytics)) {
  name: logAnalytics.name
  scope: existingLogAnalyticsRG
}

// create the log analytics resource group if the logAnalytics object wasn't supplied at deployment
resource sharedWorkspaceRG 'Microsoft.Resources/resourceGroups@2021-04-01' = if (empty(logAnalytics)) {
  name: replace(replace(namingStructure, '{subwloadname}', 'sharedsvc'), '{rtype}', 'rg')
  location: location
}

// create the log analytics workspace resource if the logAnalytics object wasn't supplied at deployment
module workspaceLaw '../child_modules/logAnalytics.bicep' = if (empty(logAnalytics)) {
  name: replace(deploymentNameStructure, '{rtype}', 'law')
  scope: sharedWorkspaceRG
  params: {
    namingStructure: namingStructure
    location: location
    tags: tags
  }
}

//##################################################################################################################################################################################

// create the virtual network resource group if the virtualNetwork object wasn't supplied at deployment
resource newNetworkWorkspaceRG 'Microsoft.Resources/resourceGroups@2021-04-01' = if (empty(virtualNetwork)) {
  name: replace(replace(namingStructure, '{subwloadname}', 'network'), '{rtype}', 'rg')
  location: location
  tags: tags
}

// create the virtual network if the virtualNetwork object wasn't supplied at deployment
module workspaceVnet '../child_modules/network.bicep' = if (empty(virtualNetwork)) {
  name: replace(deploymentNameStructure, '{rtype}', 'net')
  scope: newNetworkWorkspaceRG
  params: {
    location: location
    namingStructure: namingStructure
    addressPrefixes: vnetAddressPrefixes
    subnets: subnets
    tags: tags
  }
}

//##################################################################################################################################################################################

// get the existing privatized storage account resource group if the storageAccount object was supplied at deployment
resource existingPrivateStorageRG 'Microsoft.Resources/resourceGroups@2021-04-01' existing = if (!empty(privateStorage)) {
  name: split(privateStorage.id, '/')[3]
}

// get the existing privatized storage account if the storageAccount object was supplied at deployment
resource existingPrivateStorageAccount 'Microsoft.Storage/storageAccounts@2021-02-01' existing = if (!empty(privateStorage)) {
  name: privateStorage.name
  scope: existingPrivateStorageRG
}

// create the storage resource group if the storageAccount object wasn't supplied at deployment
resource newDataWorkspaceRG 'Microsoft.Resources/resourceGroups@2021-04-01' = if (empty(privateStorage)) {
  name: replace(replace(namingStructure, '{subwloadname}', 'storage'), '{rtype}', 'rg')
  location: location
  tags: tags
}

// create the private storage account if the storageAccount object wasn't supplied at deployment
module newPrivateStorageAccount '../child_modules/storage_account.bicep' = if (empty(privateStorage)) {
  name: replace(deploymentNameStructure, '{rtype}', 'stg-pri')
  scope: newDataWorkspaceRG
  params: {
    location: location
    namingStructure: namingStructure
    subwloadname: 'pri'
    containerNames: [
      containerNames['exportApprovedContainerName']
      containerNames['exportPendingContainerName']
    ]
    // The private storage account must be integrated with a VNet
    vnetId: empty(virtualNetwork) ? workspaceVnet.outputs.vnetId : virtualNetwork.id
    subnetId: empty(virtualNetwork) ? workspaceVnet.outputs.pepSubnetId : privateEndpointSubnetId
    privatize: true
    tags: tags
  }
}

//########################################################################//
//                                                                        //
//                                Modules                                 //
//                                                                        //
//########################################################################//

// run data automation module
module dataAutomation './dataAutomation.bicep' = {
  name: 'data-automation-${deploymentTime}'
  params: {
    location: location
    workspaceName: workspaceName
    namingStructure: namingStructure
    deploymentNameStructure: deploymentNameStructure
    containerNames: containerNames
    privateStorageAccountName: empty(privateStorage) ? newPrivateStorageAccount.outputs.storageAccountName : existingPrivateStorageAccount.name
    privateStorageAccountRG: empty(privateStorage) ? newDataWorkspaceRG.name : existingPrivateStorageRG.name
    approverEmail: approverEmail
    userAssignedManagedIdentity: userAssignedManagedIdentity
    tags: tags
  }
}

// run avd access module if requested by user
module access './access.bicep' = if (avdAccess) {
  name: 'access-${deploymentTime}'
  params: {
    location: location
    namingStructure: namingStructure
    subwloadname: 'access'
    deploymentNameStructure: deploymentNameStructure
    avdSubnetId: empty(virtualNetwork) ? workspaceVnet.outputs.workloadSubnetId : computeSubnetId
    rdshPrefix: 'rdsh'
    tags: tags
  }
}
