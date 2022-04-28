targetScope = 'subscription'

param location string
param namingStructure string
param deploymentNameStructure string
param vnetAddressPrefixes array
param dnsServers array = []
param subnets array
param containerNames object
param tags object = {}

// shared resources resrouce group
resource sharedWorkspaceRG 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: replace(replace(namingStructure, '{subwloadname}', 'sharedsvc'), '{rtype}', 'rg')
  location: location
}

// add log analytics if not present
module workspaceLaw '../child_modules/logAnalytics.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'law')
  scope: sharedWorkspaceRG
  params: {
    namingStructure: namingStructure
    location: location
    tags: tags
  }
}

// pull existing resrouce group to deploy new resrouces within
resource networkingWorkspaceRG 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: replace(replace(namingStructure, '{subwloadname}', 'network'), '{rtype}', 'rg')
  location: location
  tags: tags
}

// Add VNET
module workspaceVnet '../child_modules/network.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'net')
  scope: networkingWorkspaceRG
  params: {
    location: location
    namingStructure: namingStructure
    addressPrefixes: vnetAddressPrefixes
    dnsServers: dnsServers
    subnets: subnets
    tags: tags
  }
}

// Add Private Storage
resource dataWorkspaceRG 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: replace(replace(namingStructure, '{subwloadname}', 'storage'), '{rtype}', 'rg')
  location: location
  tags: tags
}

module privateStorageAccount '../child_modules/storage_account.bicep' = {
  name: replace(deploymentNameStructure, '{rtype}', 'stg-pri')
  scope: dataWorkspaceRG
  params: {
    location: location
    namingStructure: namingStructure
    subwloadname: 'pri'
    containerNames: [
      containerNames['exportApprovedContainerName']
      containerNames['exportPendingContainerName']
    ]
    // The private storage account must be integrated with a VNet
    vnetId: workspaceVnet.outputs.vnetId
    subnetId: workspaceVnet.outputs.pepSubnetId
    privatize: true
    tags: tags
  }
}

output privateStorageAccountId string = privateStorageAccount.outputs.storageAccountId
output privateStorageAccountName string = privateStorageAccount.outputs.storageAccountName
output privateStorageAccountRG string = dataWorkspaceRG.name
output workloadSubnetId string = workspaceVnet.outputs.workloadSubnetId
