---
page_type: sample
languages:
- powershell
products:
- azure
- azure-service-fabric
description: "PowerShell scripts for setting up Azure Active Directory (Azure AD) to authenticate clients for a Service Fabric cluster (which must be done before creating the cluster)."
urlFragment: service-fabric-aad-helpers
---

# Service Fabric Azure AD helper scripts

PowerShell scripts for setting up Azure Active Directory (Azure AD) to authenticate clients for a Service Fabric cluster (which must be done *before* creating the cluster).

## Features

This repo provides the following scripts for Azure AD:

* Create Azure AD applications (web, native) to control access to your Service Fabric cluster
* Delete existing Azure AD applications (web, native) for controlling your cluster
* Create a new Azure AD user
* Delete an existing Azure AD user

## Getting Started

### Prerequisites

- Windows OS
- [Nuget CLI](https://docs.microsoft.com/en-us/nuget/tools/nuget-exe-cli-reference) (`nuget.exe`)
- [Azure Active Directory (Azure AD) tenant](https://docs.microsoft.com/en-us/azure/active-directory/develop/quickstart-create-new-tenant)

### Installation

- `nuget install Microsoft.IdentityModel.Clients.ActiveDirectory`

## Usage

### Create Azure AD applications

Run **SetupApplications.ps1** to create two Azure AD applications (web and native applications) to control access to the cluster, storing the output into a variable to reuse when [creating Azure AD users](#create-azure-ad-users).

```PowerShell
$Configobj = .\SetupApplications.ps1 -TenantId '<tenant_id>' -ClusterName '<cluster_name>' -WebApplicationReplyUrl 'https://<cluster_domain>:19080/Explorer' -AddResourceAccess
```

- **TenantId**: You can find this by executing the PowerShell command `Get-AzureSubscription`.

- **ClusterName**: This is used to prefix the Azure AD applications created by the script. It need not match the actual cluster name — it's provided to help you map Azure AD artifacts to their Service Fabric cluster.

- **WebApplicationReplyUrl**: The endpoint Azure AD returned to your users after signing in. Set this to the Service Fabric Explorer for your cluster, which by default is at *https://<cluster_domain>:19080/Explorer*

- Refer to the *SetupApplications.ps1* script source for additional options and examples.

Running the script will prompt you to sign in to an account with admin privileges for the Azure AD tenant. Once signed in, the script will create the web and native applications to represent your Service Fabric cluster. The script will also print the JSON required by the Azure Resource Manager template when you go on to [create your Service Fabric cluster](https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-creation-create-template#add-azure-ad-configuration-to-use-azure-ad-for-client-access), so be sure to save it somewhere.

### Create Azure AD users

Run **SetupUser.ps1** to create *read-only* and *admin* user roles for your cluster, using the `$Configobj` returned when [creating your Azure AD applications](#create-azure-ad-applications). For example:

```PowerShell
.\SetupUser.ps1 -ConfigObj $Configobj -UserName 'TestUser' -Password 'P@ssword!123'
.\SetupUser.ps1 -ConfigObj $Configobj -UserName 'TestAdmin' -Password 'P@ssword!123' -IsAdmin
```

Refer to the *SetupUser.ps1* script source for additional options and examples.

### Delete Azure AD applications and users

Run **CleanupApplications.ps1** if you need to delete the Azure AD applications you created from the *SetupApplications.ps1* script. Include the optional `-CleanupUsers` flag to also delete any users created for the given cluster.

```PowerShell
.\CleanupApplications.ps1 -TenantId '<tenant_id>' -ClusterName '<cluster_name>' -CleanupUsers
```

Refer to *CleanupApplications.ps1* and *CleanupUser.ps1* scripts for additional options and examples.

## Resources

- [Service Fabric: Set up Azure Active Directory for client authentication](https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-creation-setup-aad)
- [Active Directory: Set up a dev environment](https://docs.microsoft.com/en-us/azure/active-directory/develop/quickstart-create-new-tenant)
