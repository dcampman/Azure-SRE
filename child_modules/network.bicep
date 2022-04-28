param location string
param namingStructure string
param subwloadname string = ''
param addressPrefixes array
param dnsServers array
param subnets array
param nsgSecurityRules array = []
param defaultRouteNextHop string = ''
param tags object = {}

var customDNS = !empty(dnsServers)
var baseName = !empty(subwloadname) ? replace(namingStructure, '{subwloadname}', subwloadname) : replace(namingStructure, '-{subwloadname}', '')

// create vnet
resource virtual_network 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: replace(baseName, '{rtype}', 'vnet')
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: addressPrefixes
    }
    dhcpOptions: customDNS ? {
      dnsServers: dnsServers
    } : json('null')
    subnets: [for (s, index) in subnets: {
      name: s.name
      properties: {
        addressPrefix: s.addressPrefix
        privateEndpointNetworkPolicies: !empty(s.privateEndpointNetworkPolicies) ? 'Disabled' : s.privateEndpointNetworkPolicies
        networkSecurityGroup: {
          id: networkSecurityGroups[index].id
        }
        routeTable: {
          id: routeTables[index].id
        }
      }
    }]
  }
  tags: tags
}

// create nsgs
resource networkSecurityGroups 'Microsoft.Network/networkSecurityGroups@2021-05-01' = [for s in subnets: {
  name: 'nsg-${s.name}'
  location: location
  properties: {
    securityRules: !empty(nsgSecurityRules) ? nsgSecurityRules : json('null')
  }
  tags: tags
}]

// create route tables
resource routeTables 'Microsoft.Network/routeTables@2021-05-01' = [for s in subnets: {
  name: 'rt-${s.name}'
  location: location
  properties: {
    disableBgpRoutePropagation: true
    routes: !empty(defaultRouteNextHop) ? [
      {
        name: 'default'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopIpAddress: defaultRouteNextHop
          nextHopType: 'VirtualAppliance'
        }
      }
    ] : json('null')
  }
  tags: tags
}]

resource pepSubnet 'Microsoft.Network/virtualNetworks/subnets@2021-05-01' existing = {
  name: '${virtual_network.name}/privateEndpoints'
}

resource workloadSubnet 'Microsoft.Network/virtualNetworks/subnets@2021-05-01' existing = {
  name: '${virtual_network.name}/compute'
}

output vnetId string = virtual_network.id
output pepSubnetId string = pepSubnet.id
output workloadSubnetId string = workloadSubnet.id
