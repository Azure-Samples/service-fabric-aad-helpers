---
page_type: sample
languages:
- powershell
products:
- azure
- azure-service-fabric
description: "PowerShell scripts for setting up Azure Active Directory (Entra) to authenticate clients for a Service Fabric cluster (which must be done before creating the cluster)."
urlFragment: service-fabric-aad-helpers
---

# Service Fabric Entra helper scripts

PowerShell scripts for setting up Azure Active Directory (AAD/Entra) to authenticate clients for a Service Fabric cluster (which must be done *before* creating the cluster). Scripts can be re-executed as needed with same configuration if errors or timeouts occurred or additional users need to be configured.

## Features

This repo provides the following scripts for Entra:

* Create Entra applications (web, native) to control access to your Service Fabric cluster
* Delete existing Entra applications (web, native) for controlling your cluster
* Create a new Entra user
* Delete an existing Entra user

## Getting Started

### Prerequisites

* [Azure Active Directory (Entra) tenant](https://docs.microsoft.com/en-us/azure/active-directory/develop/quickstart-create-new-tenant).

## Usage

### Create Entra applications

Run **SetupApplications.ps1** to create two Entra applications (web and native applications) to control access to the cluster, storing the output into a variable to reuse when [creating Entra users](#create-entra-users).

```powershell
$ConfigObj = .\SetupApplications.ps1 -TenantId '<tenant_id>' `
  -ClusterName '<cluster_name>' `
  -SpaApplicationReplyUrl 'https://<cluster_domain>:19080/Explorer' `
  -WebApplicationUri 'api://<tenant_id>/<cluster_name>' `
  -AddResourceAccess
```

### SetupApplications Parameters

<details><summary>Click to expand</summary>

```powershell
>help .\SetupApplications.ps1 -full
PARAMETERS
    -TenantId <String>
        ID of tenant hosting Service Fabric cluster.

    -WebApplicationName <String>
        Name of web application representing Service Fabric cluster.

    -WebApplicationUri <String>
        App ID URI of web application. If using https:// format, the domain has to be a verified domain. Format: https://<Domain name
        of cluster>
        Example: 'https://mycluster.contoso.com'
        Alternatively api:// format can be used which does not require a verified domain. Format: api://<tenant id>/<cluster name>
        Example: 'api://4f812c74-978b-4b0e-acf5-06ffca635c0e/mycluster'

    -SpaApplicationReplyUrl <String>
        Reply URL of spa application. Format: https://<Domain name of cluster>:<Service Fabric Http gateway port>
        Example: 'https://mycluster.westus.cloudapp.azure.com:19080/Explorer/index.html'

    -NativeClientApplicationName <String>
        Name of native client application representing client.

    -ClusterName <String>
        A friendly Service Fabric cluster name. Application settings generated from cluster name: WebApplicationName = ClusterName +
        "_Cluster", NativeClientApplicationName = ClusterName + "_Client"

    -Location <String>
        'Used to set metadata for specific region (for example: china, germany). Ignore it in global environment.'

    -AddResourceAccess [<SwitchParameter>]
        Used to add the cluster applications resource access to Entra application explicitly when AAD is not able to add
        automatically. This may happen when the user account does not have adequate permission under this subscription.

    -AddVisualStudioAccess [<SwitchParameter>]
        Used to add the Visual Studio MSAL client ids to the cluster application
            'https://learn.microsoft.com/en-us/azure/service-fabric/service-fabric-manage-application-in-visual-studio'
            Visual Studio 2022 and future versions: '04f0c124-f2bc-4f59-8241-bf6df9866bbd'
            Visual Studio 2019 and earlier: '872cd9fa-d31f-45e0-9eab-6e460a02d1f1'

    -SignInAudience <String>
        Sign in audience option for selection of Applicaiton AAD tenant configuration type. Default selection is 'AzureADMyOrg'
        'AzureADMyOrg', 'AzureADMultipleOrgs', 'AzureADandPersonalMicrosoftAccount'

    -TimeoutMin <Int32>
        Script execution retry wait timeout in minutes. Default is 5 minutes. If script times out, it can be re-executed and will
        continue configuration as script is idempotent.

    -LogFile <String>
        Log file path to save script transcript logs.

    -Force [<SwitchParameter>]
        Use Force switch to force new authorization to acquire new token.

    -Remove [<SwitchParameter>]
        Use Remove to remove AAD configuration for provided cluster.

    -MGClientId <Guid>
        Optional AAD client id for management group. If not provided, it will use default client id.

    -MGClientSecret <String>
        Optional AAD client secret for management group.

    -MGGrantType <String>
        Optional AAD grant type for management group. Default is 'device_code'.

-------------------------- EXAMPLE 1 --------------------------
    PS > .\SetupApplications.ps1 -TenantId '4f812c74-978b-4b0e-acf5-06ffca635c0e' `
            -ClusterName 'MyCluster' `
            -WebApplicationUri 'api://4f812c74-978b-4b0e-acf5-06ffca635c0e/mycluster' `
            -SpaApplicationReplyUrl 'https://mycluster.westus.cloudapp.azure.com:19080/explorer/index.html'

    Setup tenant with default settings generated from a friendly cluster name.

    -------------------------- EXAMPLE 2 --------------------------
    PS > .\SetupApplications.ps1 -TenantId '4f812c74-978b-4b0e-acf5-06ffca635c0e' `
            -WebApplicationName 'SFWeb' `
            -WebApplicationUri 'https://mycluster.contoso.com' `
            -SpaApplicationReplyUrl 'https://mycluster.contoso:19080/explorer/index.html' `
            -NativeClientApplicationName 'SFnative'

    Setup tenant with explicit application settings.

    -------------------------- EXAMPLE 3 --------------------------
    PS > $ConfigObj = .\SetupApplications.ps1 -TenantId '4f812c74-978b-4b0e-acf5-06ffca635c0e' `
            -ClusterName 'MyCluster' `
            -WebApplicationUri 'api://4f812c74-978b-4b0e-acf5-06ffca635c0e/mycluster' `
            -SpaApplicationReplyUrl 'https://mycluster.westus.cloudapp.azure.com:19080/explorer/index.html'

    Setup and save the setup result into a temporary variable to pass into SetupUser.ps1

    -------------------------- EXAMPLE 4 --------------------------
    PS > .\SetupApplications.ps1 -TenantId '4f812c74-978b-4b0e-acf5-06ffca635c0e' `
            -WebApplicationUri 'api://4f812c74-978b-4b0e-acf5-06ffca635c0e/mycluster' `
            -SpaApplicationReplyUrl 'https://mycluster.westus.cloudapp.azure.com:19080/explorer/index.html' `
            -AddResourceAccess `
            -AddVisualStudioAccess

    Setup tenant with explicit application settings and add explicit resource access to Entra application.
```

</details>

Running the script will prompt you to sign in to an account with admin privileges for the Entra tenant. Once signed in, the script will create the web and native applications to represent your Service Fabric cluster. The script will also print the JSON required by the Azure Resource Manager template when you go on to [create your Service Fabric cluster](https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-creation-create-template#add-entra-configuration-to-use-entra-for-client-access), so be sure to save it somewhere.

### Create Entra users

Run **SetupUser.ps1** to create *read-only* and *admin* user roles for your cluster, using the `$ConfigObj` returned when [creating your Entra applications](#create-entra-applications). For example:

```PowerShell
.\SetupUser.ps1 -ConfigObj $ConfigObj -UserName 'TestUser' -Password 'P@ssword!123'
.\SetupUser.ps1 -ConfigObj $ConfigObj -UserName 'TestAdmin' -Password 'P@ssword!123' -IsAdmin
```

Refer to the *SetupUser.ps1* script source for additional options and examples.

### Delete Entra applications and users

Run same scripts with '-remove' switch if the Entra applications or user configurations need to be removed.

```PowerShell
$ConfigObj = .\SetupApplications.ps1 -TenantId '<tenant_id>' -ClusterName '<cluster_name>' -SpaApplicationReplyUrl 'https://<cluster_domain>:19080/Explorer' -WebApplicationUri 'api://<tenant_id>/<cluster_name>' -AddResourceAccess -remove

# remove configuration from user
.\SetupUser.ps1 -ConfigObj $ConfigObj -UserName 'TestUser' -Password 'P@ssword!123' -remove

# remove user
.\SetupUser.ps1 -ConfigObj $ConfigObj -UserName 'TestUser' -Password 'P@ssword!123' -remove -force
```

### SetupUser Parameters

<details><summary>Click to expand</summary>

```powershell
>help .\SetupUser.ps1 -full
PARAMETERS
    -TenantId <String>
        ID of tenant hosting Service Fabric cluster.

    -WebApplicationId <String>
        ObjectId of web application representing Service Fabric cluster.

    -UserName <String>

    -Password <String>
        Password of new user.

    -IsAdmin [<SwitchParameter>]
        User is assigned admin app role if indicated; otherwise, readonly app role.

    -ConfigObj <Hashtable>
        Temporary variable of tenant setup result returned by SetupApplications.ps1.

    -Location <String>
        Used to set metadata for specific region (for example: china). Ignore it in global environment.

    -Domain <String>
        Domain is the verified domain being used for user account configuration.

    -TimeoutMin <Int32>
        Script execution retry wait timeout in minutes. Default is 5 minutes. If script times out, it can be re-executed and will
        continue configuration as script is idempotent.

    -LogFile <String>

    -Remove [<SwitchParameter>]
        Use Remove to remove AAD configuration and optionally user.

    -Force [<SwitchParameter>]
        Use Force switch to force removal of AAD user account if specifying -remove.

    -------------------------- EXAMPLE 1 --------------------------

    PS > . Scripts\SetupUser.ps1 -ConfigObj $ConfigObj -UserName 'SFuser' -Password 'Test4321'

    Setup up a read-only user with return SetupApplications.ps1

    -------------------------- EXAMPLE 2 --------------------------

    PS > . Scripts\SetupUser.ps1 -TenantId '7b25ab7e-cd25-4f0c-be06-939424dc9cc9' `
            -WebApplicationId '9bf7c6f3-53ce-4c63-8ab3-928c7bf4200b' `
            -UserName 'SFAdmin' `
            -Password 'Test4321' `
            -IsAdmin

    Setup up an admin user providing values for parameters
```

</details>

### Update an existing Entra Application

Update an existing Entra Application to migrate the web redirect URIs to SPA redirect URIs.
This will update the Application registration by moving any web redirect URIs that contain the port(by default 19080) to SPA redirect URIs and ensuring they end with /Explorer/index.html
The webApplicationId can be found in azure portal by checking the Application (client) ID section of the app registration essentials or the ClusterApplication section of your cluster's  azureActiveryDirectory section of your arm template.

```PowerShell

# The WhatIf flag will show what web redirect URIs would be removed and SPA redirect URIs would be created without making the change.
# This can be helpful to see what changes would be made prior to running it.
.\UpdateApplication.ps1 -WebApplicationId '<web_app_id>' -TenantId '<tenant_id>' -WhatIf

.\UpdateApplication.ps1 -WebApplicationId '<web_app_id>' -TenantId '<tenant_id>'

# Update for clusters not using standard 19080 http port
.\UpdateApplication.ps1 -WebApplicationId '<web_app_id>' -TenantId '<tenant_id>' -HttpPort 19007

```

### UpdateApplication Parameters

<details><summary>Click to expand</summary>

```powershell
>help .\UpdateApplication.ps1 -full

PARAMETERS
    -WebApplicationId <String>
        The WebApplicationId of the application to update

    -TimeoutMin <Int32>
        The timeout in minutes for the script to run

    -HttpPort <Int32>
        The port to search for in the redirect URIs

    -LogFile <String>
        The path to the log file

    -TenantId <String>
        The tenant id of the application to update

    -WhatIf [<SwitchParameter>]
        The switch to run the script in whatif mode

    -------------------------- EXAMPLE 1 --------------------------

    PS > .\UpdateApplication.ps1 -WebApplicationId 'https://mysftestcluster.contoso.com' `
        -TenantId '00000000-0000-0000-0000-000000000000' `
        -TimeoutMin 5 `
        -HttpPort 19080 `
        -LogFile 'C:\temp\update-app.log' `
        -WhatIf
```

</details>

## Update an existing Cluster

Run **SetupClusterResource.ps1** to update an existing cluster that was created without Entra, using the `$ConfigObj` returned when [creating your Entra applications](#create-entra-applications). For example:

```powershell
$ConfigObj = .\SetupClusterResource.ps1 -TenantId '<tenant_id>' `
  -ClusterName '<cluster_name>' `
  -SpaApplicationReplyUrl 'https://<cluster_domain>:19080/Explorer' `
  -WebApplicationUri 'api://<tenant_id>/<cluster_name>' `
  -AddResourceAccess
```

### SetupClusterResource Parameters

<details><summary>Click to expand</summary>

```powershell
>help .\SetupClusterResource.ps1 -full

PARAMETERS
    -ConfigObj <Hashtable>
        hashtable containing configuration values

    -TenantId <String>
        tenant id of the application to update

    -ClusterApplication <String>
        the application id of the cluster application

    -ClientApplication <String>
        the application id of the client application

    -ResourceGroupName <String>
        the resource group name of the cluster

    -ClusterName <String>
        the name of the cluster

    -DeploymentName <String>
        the name of the deployment

    -TemplateFile <String>
        the path to the template file

    -WhatIf [<SwitchParameter>]
        the switch to run the script in whatif mode

    -Force [<SwitchParameter>]

    -------------------------- EXAMPLE 1 --------------------------

    PS > .\setupClusterResource.ps1 -tenantId 'cb4dc457-01c8-40c7-855a-5468ebd5bc74' `
            -clusterApplication 'e6bba8d5-3fb6-47ac-9927-2a50cf763d36' `
            -clientApplication '2324af84-f14b-4ee8-a695-6b464f8dbb92' `
            -resourceGroupName 'mysftestcluster' `
            -clusterName 'mysftestcluster'

    -------------------------- EXAMPLE 2 --------------------------

    PS > .\setupClusterResource.ps1
            -ConfigObj $ConfigObj `
            -resourceGroupName 'mysftestcluster' `
            -clusterName 'mysftestcluster'
```

</details>

## Resources

* [Service Fabric: Set up Microsoft Entra ID for client authentication](https://learn.microsoft.com/azure/service-fabric/service-fabric-cluster-creation-setup-aad)

* [Service Fabric: Set up Microsoft Entra ID for client authentication in the Azure portal](https://learn.microsoft.com/azure/service-fabric/service-fabric-cluster-creation-setup-azure-ad-via-portal)

* [Active Directory: Set up a dev environment](https://learn.microsoft.com/azure/active-directory/develop/quickstart-create-new-tenant)
