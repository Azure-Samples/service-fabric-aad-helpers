<#
.VERSION
1.0.4

.SYNOPSIS
Setup applications in a Service Fabric cluster Azure Active Directory tenant.

.PREREQUISITE
1. An Azure Active Directory tenant.
2. A Global Admin user within tenant.

.PARAMETER TenantId
ID of tenant hosting Service Fabric cluster.

.PARAMETER WebApplicationName
Name of web application representing Service Fabric cluster.

.PARAMETER WebApplicationUri
App ID URI of web application.

.PARAMETER WebApplicationReplyUrl
Reply URL of web application. Format: https://<Domain name of cluster>:<Service Fabric Http gateway port>

.PARAMETER NativeClientApplicationName
Name of native client application representing client.

.PARAMETER ClusterName
A friendly Service Fabric cluster name. Application settings generated from cluster name: WebApplicationName = ClusterName + "_Cluster", NativeClientApplicationName = ClusterName + "_Client"

.PARAMETER Location
Used to set metadata for specific region (for example: china, germany). Ignore it in global environment.

.PARAMETER AddResourceAccess
Used to add the cluster application's resource access to "Windows Azure Active Directory" application explicitly when AAD is not able to add automatically. This may happen when the user account does not have adequate permission under this subscription.

.EXAMPLE
. Scripts\SetupApplications.ps1 -TenantId '4f812c74-978b-4b0e-acf5-06ffca635c0e' -ClusterName 'MyCluster' -WebApplicationReplyUrl 'https://mycluster.westus.cloudapp.azure.com:19080'

Setup tenant with default settings generated from a friendly cluster name.

.EXAMPLE
. Scripts\SetupApplications.ps1 -TenantId '4f812c74-978b-4b0e-acf5-06ffca635c0e' -WebApplicationName 'SFWeb' -WebApplicationUri 'https://SFweb' -WebApplicationReplyUrl 'https://mycluster.westus.cloudapp.azure.com:19080' -NativeClientApplicationName 'SFnative'

Setup tenant with explicit application settings.

.EXAMPLE
. $configObj = Scripts\SetupApplications.ps1 -TenantId '4f812c74-978b-4b0e-acf5-06ffca635c0e' -ClusterName 'MyCluster' -WebApplicationReplyUrl 'https://mycluster.westus.cloudapp.azure.com:19080'

Setup and save the setup result into a temporary variable to pass into SetupUser.ps1
#>

Param
(
    [Parameter(ParameterSetName = 'Customize', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Prefix', Mandatory = $true)]
    [String]
    $TenantId,

    [Parameter(ParameterSetName = 'Customize')]	
    [String]
    $WebApplicationName,

    [Parameter(ParameterSetName = 'Customize')]
    [Parameter(ParameterSetName = 'Prefix')]
    [String]
    $WebApplicationUri,

    [Parameter(ParameterSetName = 'Customize')]
    [Parameter(ParameterSetName = 'Prefix')]
    [String]
    [ValidateSet('AzureADMyOrg', 'AzureADMultipleOrgs', 'AzureADandPersonalMicrosoftAccount')]
    $signInAudience = 'AzureADMyOrg',

    [Parameter(ParameterSetName = 'Customize', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Prefix', Mandatory = $true)]
    [String]
    $WebApplicationReplyUrl,
	
    [Parameter(ParameterSetName = 'Customize')]
    [String]
    $NativeClientApplicationName,

    [Parameter(ParameterSetName = 'Prefix', Mandatory = $true)]
    [String]
    $ClusterName,

    [Parameter(ParameterSetName = 'Prefix')]
    [Parameter(ParameterSetName = 'Customize')]
    [ValidateSet('us', 'china')]
    [String]
    $Location,

    [Parameter(ParameterSetName = 'Customize')]
    [Parameter(ParameterSetName = 'Prefix')]
    [Switch]
    $AddResourceAccess,
    
    [Parameter(ParameterSetName = 'Customize')]
    [Parameter(ParameterSetName = 'Prefix')]
    [Switch]$force,

    [Parameter(ParameterSetName = 'Customize')]
    [Parameter(ParameterSetName = 'Prefix')]
    [Switch]$remove

)

. "$PSScriptRoot\Common.ps1"
$graphAPIFormat = $resourceUrl + "/v1.0/" + $TenantId + "/{0}"
$global:ConfigObj = @{}

function main () {
    Write-Host 'TenantId = ' $TenantId
    $configObj.ClusterName = $clusterName
    $configObj.TenantId = $TenantId
    $webApp = $null

    if ($remove) {
        write-host "removing service principals"
        $result = remove-servicePrincipals -headers $headers

        write-warning "removing app registrations"
        $result = $result -and (remove-appRegistration -WebApplicationUri $WebApplicationUri -headers $headers)

        
        return $result
    }

    if (!$WebApplicationName) {
        $WebApplicationName = "ServiceFabricCluster"
    }
    
    if (!$WebApplicationUri) {
        $WebApplicationUri = "https://ServiceFabricCluster"
    }
    
    if (!$NativeClientApplicationName) {
        $NativeClientApplicationName = "ServiceFabricClusterNativeClient"
    }

    $requiredResourceAccess = @(@{
            resourceAppId  = "00000002-0000-0000-c000-000000000000"
            resourceAccess = @(@{
                    id   = "311a71cc-e848-46a1-bdf8-97ff7156d8e6"
                    type = "Scope"
                })
        })

    # check / add app registration
    $webApp = get-appRegistration -WebApplicationUri $WebApplicationUri -headers $headers
    if (!$webApp) {
        $webApp = add-appRegistration -WebApplicationUri $WebApplicationUri `
            -WebApplicationReplyUrl $WebApplicationReplyUrl `
            -requiredResourceAccess $requiredResourceAccess
    }

    assert-notNull $webApp 'Web Application Creation Failed'
    $configObj.WebAppId = $webApp.appId
    Write-Host "Web Application Created: $($webApp.appId)"

    # check / add oauth user_impersonation permissions
    $oauthPermissionsId = get-OauthPermissions -webApp $webApp
    if (!$oauthPermissionsId) {
        $oauthPermissionsId = add-OauthPermissions -webApp $webApp -WebApplicationName $WebApplicationName
    }
    assert-notNull $oauthPermissionsId 'Web Application Oauth permissions Failed'
    Write-Host "Web Application Oauth permissions created: $($oauthPermissionsId|convertto-json)"  -ForegroundColor Green

    # check / add servicePrincipal
    $servicePrincipal = get-servicePrincipal -webApp $webApp -headers $headers
    if (!$servicePrincipal) {
        $servicePrincipal = add-servicePrincipal -webApp $webApp
    }
    assert-notNull $servicePrincipal 'service principal configuration failed'
    Write-Host "Service Principal Created: $($servicePrincipal.appId)" -ForegroundColor Green
    $configObj.ServicePrincipalId = $servicePrincipal.Id

    # check / add native app
    $nativeApp = get-nativeClient -webApp $webApp -WebApplicationUri $WebApplicationUri -headers $headers
    if (!$nativeApp) {
        $nativeApp = add-nativeClient -webApp $webApp -requiredResourceAccess $requiredResourceAccess -oauthPermissionsId $oauthPermissionsId
    }
    assert-notNull $nativeApp 'Native Client Application Creation Failed'
    Write-Host "Native Client Application Created: $($nativeApp.appId)"  -ForegroundColor Green
    $configObj.NativeClientAppId = $nativeApp.appId

    # check / add native app service principal
    $servicePrincipalNa = get-servicePrincipal -webApp $nativeApp -headers $headers
    if (!$servicePrincipalNa) {
        $servicePrincipalNa = add-servicePrincipal -webApp $nativeApp
    }
    assert-notNull $servicePrincipalNa 'native app service principal configuration failed'
    Write-Host "Native app service principal created: $($servicePrincipalNa.appId)" -ForegroundColor Green

    # check / add native app service principal AAD
    $servicePrincipalAAD = add-servicePrincipalGrants -servicePrincipalNa $servicePrincipalNa `
        -servicePrincipal $servicePrincipal `
        -headers $headers

    assert-notNull $servicePrincipalAAD 'aad app service principal configuration failed'
    Write-Host "AAD Application Configured: $($servicePrincipalAAD)"  -ForegroundColor Green
    write-host "configobj: $($configObj|convertto-json)"

    #ARM template AAD resource
    write-host "-----ARM template-----"
    write-host "`"azureActiveDirectory`": $(@{
        tenantId           = $configObj.tenantId
        clusterApplication = $configObj.WebAppId
        clientApplication  = $configObj.NativeClientAppId
    } | ConvertTo-Json)," -ForegroundColor Cyan

    return $configObj
}

function add-appRegistration($WebApplicationUri, $WebApplicationReplyUrl, $requiredResourceAccess) {
    #Create Web Application
    write-host "creating app registration with $WebApplicationUri." -foregroundcolor yellow
    $webApp = @{}
    $appRole = @(@{
            allowedMemberTypes = @('User')
            description        = 'ReadOnly roles have limited query access'
            displayName        = 'ReadOnly'
            id                 = [guid]::NewGuid()
            isEnabled          = $true
            value              = 'User'
        }, @{
            allowedMemberTypes = @('User')
            description        = 'Admins can manage roles and perform all task actions'
            displayName        = 'Admin'
            id                 = [guid]::NewGuid()
            isEnabled          = $true
            value              = 'Admin'
        })

    $uri = [string]::Format($graphAPIFormat, 'applications')
    $webAppResource = @{
        homePageUrl           = $WebApplicationReplyUrl
        redirectUris          = @($WebApplicationReplyUrl)
        implicitGrantSettings = @{
            enableAccessTokenIssuance = $false
            enableIdTokenIssuance     = $true
        }
    }
    if ($AddResourceAccess) {
        $webApp = @{
            displayName            = $WebApplicationName
            signInAudience         = $signInAudience
            identifierUris         = @($WebApplicationUri)
            defaultRedirectUri     = $WebApplicationReplyUrl
            appRoles               = $appRole
            requiredResourceAccess = $requiredResourceAccess
            web                    = $webAppResource
        }
    }
    else {
        $webApp = @{
            displayName        = $WebApplicationName
            signInAudience     = $signInAudience
            identifierUris     = @($WebApplicationUri)
            defaultRedirectUri = $WebApplicationReplyUrl
            appRoles           = $appRole
            web                = $webAppResource
        }
    }

    $webApp = call-graphApi -uri $uri -headers $headers -body $webApp
    return $webApp
}

function add-nativeClient($webApp, $requiredResourceAccess, $oauthPermissionsId) {
    #Create Native Client Application
    $uri = [string]::Format($graphAPIFormat, "applications")
    $nativeAppResourceAccess = @($requiredResourceAccess.Clone())
    
    # todo not working in ms sub tenant
    # could be because of resource not existing?
    $nativeAppResourceAccess += @{
        resourceAppId  = $webApp.appId
        resourceAccess = @(@{
                id   = $oauthPermissionsId
                type = 'Scope'
            })
    }

    $nativeAppResource = @{
        publicClient           = @{ redirectUris = @("urn:ietf:wg:oauth:2.0:oob") }
        displayName            = $NativeClientApplicationName
        requiredResourceAccess = $nativeAppResourceAccess
    }

    $nativeApp = call-graphApi -uri $uri -headers $headers -body $nativeAppResource
    return $nativeApp
}

function add-OauthPermissions($webApp, $WebApplicationName) {
    write-host "adding user_impersonation scope"
    $patchApplicationUri = $graphAPIFormat -f ("applications/{0}" -f $webApp.Id)
    $webApp.api.oauth2PermissionScopes = @($webApp.api.oauth2PermissionScopes)
    $userImpersonationScopeId = [guid]::NewGuid()
    $webApp.api.oauth2PermissionScopes += @{
        id                      = $userImpersonationScopeId
        isEnabled               = $false
        type                    = "User"
        adminConsentDescription = "Allow the application to access $WebApplicationName on behalf of the signed-in user."
        adminConsentDisplayName = "Access $WebApplicationName"
        userConsentDescription  = "Allow the application to access $WebApplicationName on your behalf."
        userConsentDisplayName  = "Access $WebApplicationName"
        value                   = "user_impersonation"
    }

    $result = call-graphApi -uri $patchApplicationUri -method "Patch" -headers $headers -body @{
        'api' = @{
            "oauth2PermissionScopes" = $webApp.api.oauth2PermissionScopes
        }
    }

    if ($result) {
        return $userImpersonationScopeId
    }

    return $null
}

function add-servicePrincipalGrants($servicePrincipalNa, $servicePrincipal) {
    #OAuth2PermissionGrant
    #AAD service principal
    $AADServicePrincipalId = (get-servicePrincipalAAD).value.Id
    assert-notNull $AADServicePrincipalId 'aad app service principal enumeration failed'
    $global:currentGrants = get-oauthPermissionGrants($servicePrincipalNa.Id)
    $result = $currentGrants
    
    $scope = "User.Read"
    if (!$currentGrants -or !($currentGrants.scope.Contains($scope))) {
        $result = add-servicePrincipalGrantScope -clientId $servicePrincipalNa.Id -resourceId $AADServicePrincipalId -scope $scope
    }

    $scope = "user_impersonation"
    if (!$currentGrants -or !($currentGrants.scope.Contains($scope))) {
        $result = $result -and (add-servicePrincipalGrantScope -clientId $servicePrincipalNa.Id -resourceId $servicePrincipal.Id -scope $scope)
    }

    return $result
}

function add-servicePrincipalGrantScope($clientId, $resourceId, $scope) {
    $uri = [string]::Format($graphAPIFormat, "oauth2PermissionGrants")
    $oauth2PermissionGrants = @{
        clientId    = $clientId
        consentType = "AllPrincipals"
        resourceId  = $resourceId #$configObj.ServicePrincipalId
        scope       = $scope
        startTime   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffff")
        expiryTime  = (Get-Date).AddYears(1800).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffff")
    }

    $result = call-graphApi -uri $uri -headers $headers -body $oauth2PermissionGrants
    assert-notNull $result "aad app service principal oauth permissions $scope configuration failed"
    return $result
}

function add-servicePrincipal($webApp) {
    #Service Principal
    $uri = [string]::Format($graphAPIFormat, "servicePrincipals")
    $servicePrincipal = @{
        accountEnabled            = $false
        appId                     = $webApp.appId
        displayName               = $webApp.displayName
        appRoleAssignmentRequired = $true
    }

    $servicePrincipal = call-graphApi -uri $uri -headers $headers -body $servicePrincipal
    return $servicePrincipal
}

function get-appRegistration($WebApplicationUri, $headers) {
    # check for existing app by identifieruri
    $uri = [string]::Format($graphAPIFormat, "applications?`$search=`"identifierUris:$WebApplicationUri`"")
   
    $webApp = (call-graphApi $uri -headers $headers -body "" -method 'get').value
    write-host "currentAppRegistration:$webApp"

    if ($webApp) {
        write-host "app registration $($webApp.appId) with $WebApplicationUri already exists." -foregroundcolor yellow
        write-host "currentAppRegistration:$($webApp|convertto-json -depth 99)"
        return $webApp
    }

    return $null
}

function get-nativeClient($webApp, $headers) {
    # check for existing native clinet
    $uri = [string]::Format($graphAPIFormat, "applications?`$search=`"displayName:$NativeClientApplicationName`"")
   
    $nativeClient = (call-graphApi $uri -headers $headers -body "" -method 'get').value
    write-host "nativeClient:$nativeClient"

    if ($nativeClient) {
        write-host "native client $($nativeClient.appId) with $WebApplicationUri already exists." -foregroundcolor yellow
        write-host "current service principal:$($nativeClient|convertto-json -depth 99)"
        return $nativeClient
    }

    return $null
}

function get-OauthPermissions($webApp) {
    # Check for an existing delegated permission with value "user_impersonation". Normally this is created by default,
    # but if it isn't, we need to update the Application object with a new one.
    $user_impersonation_scope = $webApp.api.oauth2PermissionScopes | Where-Object { $_.value -eq "user_impersonation" }
    if ($user_impersonation_scope) {
        write-host "user_impersonation scope already exists. $($user_impersonation_scope.id)" -ForegroundColor yellow
        return $user_impersonation_scope.id
    }

    return $null
}

function get-oauthPermissionGrants($clientId) {
    # get 'Windows Azure Active Directory' app registration by well-known appId
    $uri = [string]::Format($graphAPIFormat, "oauth2PermissionGrants") + "?`$filter=clientId eq '$clientId'"
    $grants = call-graphApi -uri $uri -Headers $headers -method 'get'
    write-verbose "grants:$($grants | convertto-json -depth 2)"
    return $grants.value
}

function get-servicePrincipal($webApp, $headers) {
    # check for existing app by identifieruri
    $uri = [string]::Format($graphAPIFormat, "servicePrincipals?`$search=`"appId:$($webApp.appId)`"")
   
    $servicePrincipal = (call-graphApi $uri -headers $headers -body "" -method 'get').value
    write-host "servicePrincipal:$servicePrincipal"

    if ($servicePrincipal) {
        write-host "service principal $($servicePrincipal.appId) already exists." -foregroundcolor yellow
        write-host "current service principal:$($servicePrincipal|convertto-json -depth 99)"
        return $servicePrincipal
    }

    return $null
}

function get-servicePrincipalAAD() {
    # get 'Windows Azure Active Directory' app registration by well-known appId
    $uri = [string]::Format($graphAPIFormat, "servicePrincipals") + '?$filter=appId eq ''00000002-0000-0000-c000-000000000000'''
    $global:AADServicePrincipal = call-graphApi -uri $uri -Headers $headers -method 'get'
    write-verbose "aad service princiapal:$($AADServicePrincipal | convertto-json -depth 2)"
    return $AADServicePrincipal
}

function remove-appRegistration($WebApplicationUri, $headers) {
    # remove app registration
    $webApp = get-appRegistration -WebApplicationUri $WebApplicationUri -headers $headers
    if (!$webApp) {
        return $true
    } 

    $uri = [string]::Format($graphAPIFormat, "applications/$($webApp.id)")
    $webApp = (call-graphApi $uri -headers $headers -body "" -method 'delete')

    if (!$webApp) {
        return $true
    }
    return $false
}

function remove-servicePrincipals($headers) {
    $result = $true
    $webApp = get-appRegistration -WebApplicationUri $WebApplicationUri -headers $headers
    if ($webApp) {
        $servicePrincipal = get-servicePrincipal -webApp $webApp -headers $headers
        if ($servicePrincipal) {
            $uri = [string]::Format($graphAPIFormat, "servicePrincipals/$($servicePrincipal.id)")
            $result = $result -and (call-graphApi $uri -headers $headers -body "" -method 'delete')
        }
    }
    
    $nativeApp = get-nativeClient -webApp $webApp -WebApplicationUri $WebApplicationUri -headers $headers
    if ($nativeApp) {
        $servicePrincipalNa = get-servicePrincipal -webApp $nativeApp -headers $headers
        if ($servicePrincipalNa) {
            $uri = [string]::Format($graphAPIFormat, "servicePrincipals/$($servicePrincipalNa.id)")
            $result = $result -and (call-graphApi $uri -headers $headers -body "" -method 'delete')
        }    
    }

    return $result
}

main