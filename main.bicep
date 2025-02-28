@description('location of all resources')
param location string = resourceGroup().location

@maxLength(5)
@minLength(2)
@description('Name of AI platform. This is used to generate names for all resources.')
param aiPlatformPrefix string = 'aiplt'

@description('NSG name to be created.')
param nsgName string = 'nsg-prod'

@description('Generated. The password to use for virtual machine.')
param vmUserName string = 'vmadmin'

@description('Generated. The password to use for virtual machine.')
@secure()
param vmPassword string = newGuid()

// Generate globally unique suffix which is a function of the aiPlatformName and resource group id
var namingSuffix = uniqueString(aiPlatformPrefix, resourceGroup().id)
// Use the unique suffix to generate unique names for resources where needed.
var aiPlatformName = '${aiPlatformPrefix}${namingSuffix}'
var userIdentityName = 'mi-aihub-dev'
var keyVaultName = 'kv-ai-${aiPlatformName}'
var vmName = 'vm-ai-dev-001' 
var vmSize = 'Standard_D2as_v5'

// User Assigned Managed Identity
module managedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = {
  name: 'mi'
  params: {
    name: userIdentityName
    location: location
  }
}

module nsg 'br/public:avm/res/network/network-security-group:0.5.0' = {
  name: 'nsg'
  params: {
    name: nsgName
    location: location
  }
}

module aiplatform 'br/public:avm/ptn/ai-platform/baseline:0.6.4' = {
  name: aiPlatformName
  params: {
    name: aiPlatformName
    location: location

    storageAccountConfiguration: {
      // name is optional. We will let module set the unique names
      //name: 'st${namingSuffix}'
      sku: 'Standard_LRS'
    }
    managedIdentityName: managedIdentity.outputs.name
    containerRegistryConfiguration: {
      // name and trustPolicyStatus are not mandatory parameters.
    }

    virtualNetworkConfiguration: {
      addressPrefix: '10.1.0.0/16'
      enabled: true
      //name is optional. We will let module set the unique names
      subnet: {
        addressPrefix: '10.1.0.0/24'
        name: 'subnet-01'
        networkSecurityGroupResourceId: nsg.outputs.resourceId
      }
    }
    virtualMachineConfiguration: {
      enabled: true
      name: vmName
      zone: 0
      size: vmSize
      adminUsername: vmUserName
      adminPassword: vmPassword
      encryptionAtHost: false
      imageReference: {
        offer: 'dsvm-win-2022'
        publisher: 'microsoft-dsvm'
        sku: 'winserver-2022'
        version: 'latest'
      }
      ////name is optional. We will let module set the unique names
      nicConfigurationConfiguration: {
        ipConfigName: 'ipcfg-01'
        name: 'nic-01'
        networkSecurityGroupResourceId: nsg.outputs.resourceId
        privateIPAllocationMethod: 'Dynamic'
      }
      osDisk: {
        caching: 'ReadOnly'
        createOption: 'FromImage'
        deleteOption: 'Delete'
        diskSizeGB: 256
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
        name: 'disk-01'
      }
      patchMode: 'AutomaticByPlatform'
    }

    bastionConfiguration: {
      enabled: false
    }
    keyVaultConfiguration: {
      enablePurgeProtection: false
      name: keyVaultName
    }
  }
}
module metricAlert 'br/public:avm/res/insights/metric-alert:0.3.1' = {
  name: 'metricAlertDeployment'
  params: {
    // Required parameters
    criteria: {
      allof: [
        {
          criterionType: 'StaticThresholdCriterion'
          dimensions: []
          metricName: 'Failed Runs'
          name: '1st criterion'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Average'
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    name: 'mlworkspace-failed-runs'
    // Non-required parameters
    location: 'Global'
    scopes: [
      aiplatform.outputs.workspaceHubResourceId
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    severity: 1
  }
}






