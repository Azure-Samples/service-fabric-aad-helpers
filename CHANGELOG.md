## service-fabric-aad-helpers Changelog

### 23-11-12 231112

- add support for Visual Studio client ids
  .PARAMETER AddVisualStudioAccess
  Used to add the Visual Studio MSAL client id's to the cluster application
      https://learn.microsoft.com/en-us/azure/service-fabric/service-fabric-manage-application-in-visual-studio
      Visual Studio 2022 and future versions: 04f0c124-f2bc-4f59-8241-bf6df9866bbd
      Visual Studio 2019 and earlier: 872cd9fa-d31f-45e0-9eab-6e460a02d1f1

### 22-08-23 v2.0

- add support for https://shell.azure.com
- remove nuget requirement
- migrate from ADAL to MSAL
- migrate from Azure Active Directory (AAD) graph to MSGraph v1.0
- add support for re-execution of script for resiliency
- add additional output
- add script to update cluster with AAD settings 'SetupClusterResource.ps1'

