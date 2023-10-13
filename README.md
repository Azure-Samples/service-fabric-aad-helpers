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

PowerShell scripts for setting up Azure Active Directory (Azure AD) to authenticate clients for a Service Fabric cluster (which must be done *before* creating the cluster). Scripts can be re-executed as needed with same configuration if errors or timeouts occurred or additional users need to be configured.

## Features

This repo provides the following scripts for Azure AD:

* Create Azure AD applications (web, native) to control access to your Service Fabric cluster
* Delete existing Azure AD applications (web, native) for controlling your cluster
* Create a new Azure AD user
* Delete an existing Azure AD user

## Getting Started

### Prerequisites

- [Azure Active Directory (Azure AD) tenant](https://docs.microsoft.com/en-us/azure/active-directory/develop/quickstart-create-new-tenant).

## Usage

### Create Azure AD applications

Run **SetupApplications.ps1** to create two Azure AD applications (web and native applications) to control access to the cluster, storing the output into a variable to reuse when [creating Azure AD users](#create-azure-ad-users).

```PowerShell
$ConfigObj = .\SetupApplications.ps1 -TenantId '<tenant_id>' -ClusterName '<cluster_name>' -WebApplicationReplyUrl 'https://<cluster_domain>:19080/Explorer' -WebApplicationUri 'api://<tenant_id>/<cluster_name>' -AddResourceAccess
```

- **TenantId**: You can find this by executing the PowerShell command `Get-AzureSubscription`.

- **ClusterName**: This is used to prefix the Azure AD applications created by the script. It does not need to match the actual cluster name. It is provided to help you map Azure AD artifacts to their Service Fabric cluster.

- **WebApplicationReplyUrl**: The endpoint Azure AD returned to your users after signing in. Set this to the Service Fabric Explorer for your cluster, which by default is at *https://<cluster_domain>:19080/Explorer*

- **WebApplicationUri**: Application ID URI of web application. If using https:// format, the domain has to be a verified domain. 
Format: https://<Domain name of cluster>
Example: 'https://mycluster.contoso.com'
Alternatively api:// format can be used which does not require a verified domain. 
Format: api://<tenant id>/<cluster name>
Example: 'https://4f812c74-978b-4b0e-acf5-06ffca635c0e/mycluster'

- Refer to the *SetupApplications.ps1* script source for additional options and examples.

Running the script will prompt you to sign in to an account with admin privileges for the Azure AD tenant. Once signed in, the script will create the web and native applications to represent your Service Fabric cluster. The script will also print the JSON required by the Azure Resource Manager template when you go on to [create your Service Fabric cluster](https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-creation-create-template#add-azure-ad-configuration-to-use-azure-ad-for-client-access), so be sure to save it somewhere.

### Create Azure AD users

Run **SetupUser.ps1** to create *read-only* and *admin* user roles for your cluster, using the `$ConfigObj` returned when [creating your Azure AD applications](#create-azure-ad-applications). For example:

```PowerShell
.\SetupUser.ps1 -ConfigObj $ConfigObj -UserName 'TestUser' -Password 'P@ssword!123'
.\SetupUser.ps1 -ConfigObj $ConfigObj -UserName 'TestAdmin' -Password 'P@ssword!123' -IsAdmin
```

Refer to the *SetupUser.ps1* script source for additional options and examples.

### Delete Azure AD applications and users

Run same scripts with '-remove' switch if the Azure AD applications or user configurations need to be removed.

```PowerShell
$ConfigObj = .\SetupApplications.ps1 -TenantId '<tenant_id>' -ClusterName '<cluster_name>' -WebApplicationReplyUrl 'https://<cluster_domain>:19080/Explorer' -WebApplicationUri 'api://<tenant_id>/<cluster_name>' -AddResourceAccess -remove

# remove configuration from user
.\SetupUser.ps1 -ConfigObj $ConfigObj -UserName 'TestUser' -Password 'P@ssword!123' -remove

# remove user
.\SetupUser.ps1 -ConfigObj $ConfigObj -UserName 'TestUser' -Password 'P@ssword!123' -remove -force
```

Refer to *CleanupApplications.ps1* and *CleanupUser.ps1* scripts for additional options and examples.

## Resources

- [Service Fabric: Set up Azure Active Directory for client authentication](https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-creation-setup-aad)
- [Active Directory: Set up a dev environment](https://docs.microsoft.com/en-us/azure/active-directory/develop/quickstart-create-new-tenant)
