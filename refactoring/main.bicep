@description('The location into which your Azure resources should be deployed.')
param location string = resourceGroup().location

@description('The administrator login username for the SQL server.')
param sqlAdministratorLogin string

@secure()
@description('The administrator login password for the SQL server.')
param sqlAdministratorLoginPassword string

@allowed([
  'F1'
  'D1'
  'B1'
  'B2'
  'B3'
  'S1'
  'S2'
  'S3'
  'P1'
  'P2'
  'P3'
  'P4'
])
param hostingPlanSkuName string = 'F1'

@minValue(1)
param skuCapacity int = 1



param managedIdentityName string = 'manager'
param webSiteName string = 'webSite${uniqueString(resourceGroup().id)}'
param container1Name string = 'productspecs'
param productManualsName string = 'productmanuals'

var roleDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
var hostingPlanName = 'hostingplan${uniqueString(resourceGroup().id)}'
var sqlServerName = 'toywebsite${uniqueString(resourceGroup().id)}'
var databaseName = 'ToyCompanyWebsite'
var storageAccountName = 'toywebsite${uniqueString(resourceGroup().id)}'

resource storageAccount 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
  }

  resource blobServices 'blobServices' existing = {
    name: 'default'
  }
}

resource container1 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  parent: storageAccount::blobServices
  name: container1Name
}

resource sqlserver 'Microsoft.Sql/servers@2019-06-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: sqlAdministratorLogin
    administratorLoginPassword: sqlAdministratorLoginPassword
    version: '12.0'
  }
}

resource sqlServerNameDatabaseName 'Microsoft.Sql/servers/databases@2020-08-01-preview' = {
  parent: sqlserver
  name: databaseName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 1073741824
  }
}

resource sqlserverNameAllowAllAzureIPs 'Microsoft.Sql/servers/firewallRules@2014-04-01' = {
  parent: sqlserver
  name: 'AllowAllAzureIPs'
  properties: {
    endIpAddress: '0.0.0.0'
    startIpAddress: '0.0.0.0'
  }
}

resource productManuals 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  parent: storageAccount::blobServices
  name: 'default${productManualsName}'
}

resource appServicesPlan 'Microsoft.Web/serverfarms@2020-06-01' = {
  name: hostingPlanName
  location: location
  sku: {
    name: hostingPlanSkuName
    capacity: skuCapacity
  }
}

resource appServicesApps 'Microsoft.Web/sites@2020-06-01' = {
  name: webSiteName
  location: location
  properties: {
    serverFarmId: appServicesPlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: AppInsightsWebSiteName.properties.InstrumentationKey
        }
        {
          name: 'StorageAccountConnectionString'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
      ]
    }
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentities.id}': {}
    }
  }
}

// We don't need this anymore. We use a managed identity to access the database instead.
//resource webSiteConnectionStrings 'Microsoft.Web/sites/config@2020-06-01' = {
//  name: '${webSite.name}/connectionstrings'
//  properties: {
//    DefaultConnection: {
//      value: 'Data Source=tcp:${sqlserver.properties.fullyQualifiedDomainName},1433;Initial Catalog=${databaseName};User Id=${sqlAdministratorLogin}@${sqlserver.properties.fullyQualifiedDomainName};Password=${sqlAdministratorLoginPassword};'
//      type: 'SQLAzure'
//    }
//  }
//}

resource managedIdentities 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: managedIdentityName
  location: location
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(roleDefinitionId, resourceGroup().id)

  properties: {
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: managedIdentities.properties.principalId
  }
}

resource AppInsightsWebSiteName 'Microsoft.Insights/components@2018-05-01-preview' = {
  name: 'AppInsights'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}
