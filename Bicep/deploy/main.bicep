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
    addressPrefix: '172.17.1.0/25'
    privateEndpointNetworkPolicies: 'Enabled'
    serviceEndpoints: []
  }
  {
    name: 'compute' // this is hard coded in a resource lookup
    addressPrefix: '172.17.1.128/25'
    privateEndpointNetworkPolicies: 'Disabled'
    serviceEndpoints: []
  }
]

//########################################################################//
//                                                                        //
//                                Modules                                 //
//                                                                        //
//########################################################################//

// run modules if we need foundational resources
// move all this stuff out to main.bicep and remove foundation module
module foundations '../root_modules/foundation.bicep' = {
  name: 'foundation-${deploymentTime}'
  params: {
    location: location
    namingStructure: namingStructure
    deploymentNameStructure: deploymentNameStructure
    containerNames: containerNames
    vnetAddressPrefixes: vnetAddressPrefixes
    subnets: subnets
    tags: tags
  }
}

// run modules if we need data automation resources
module dataAutomation '../root_modules/dataAutomation.bicep' = {
  name: 'data-automation-${deploymentTime}'
  params: {
    location: location
    workspaceName: workspaceName
    namingStructure: namingStructure
    deploymentNameStructure: deploymentNameStructure
    containerNames: containerNames
    privateStorageAccountName: foundations.outputs.privateStorageAccountName
    privateStorageAccountRG: foundations.outputs.privateStorageAccountRG
    approverEmail: approverEmail
    tags: tags
  }
}

// run modules if we need avd access to TRE
// take incoming bool to establish this layer
module access '../root_modules/access.bicep' = {
  name: 'access-${deploymentTime}'
  params: {
    location: location
    namingStructure: namingStructure
    subwloadname: 'access'
    deploymentNameStructure: deploymentNameStructure
    avdSubnetId: foundations.outputs.workloadSubnetId
    rdshPrefix: 'rdsh'
    tags: tags
  }
}
