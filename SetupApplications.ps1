<#
.SYNOPSIS
Setup applications in a Service Fabric cluster Entra tenant.

.DESCRIPTION
version: 231112

Prerequisites:
1. An Entra tenant.
2. A Global Admin user within tenant.

.PARAMETER TenantId
ID of tenant hosting Service Fabric cluster.

.PARAMETER WebApplicationName
Name of web application representing Service Fabric cluster.

.PARAMETER WebApplicationUri
App ID URI of web application. If using https:// format, the domain has to be a verified domain. Format: https://<Domain name of cluster>
Example: 'https://mycluster.contoso.com'
Alternatively api:// format can be used which does not require a verified domain. Format: api://<tenant id>/<cluster name>
Example: 'api://4f812c74-978b-4b0e-acf5-06ffca635c0e/mycluster'

.PARAMETER SpaApplicationReplyUrl
Reply URL of spa application. Format: https://<Domain name of cluster>:<Service Fabric Http gateway port>
Example: 'https://mycluster.westus.cloudapp.azure.com:19080/Explorer/index.html'

.PARAMETER NativeClientApplicationName
Name of native client application representing client.

.PARAMETER ClusterName
A friendly Service Fabric cluster name. Application settings generated from cluster name: WebApplicationName = ClusterName + "_Cluster", NativeClientApplicationName = ClusterName + "_Client"

.PARAMETER Location
Used to set metadata for specific region (for example: china, germany). Ignore it in global environment.

.PARAMETER AddResourceAccess
Used to add the cluster applications resource access to Entra application explicitly when AAD is not able to add automatically. This may happen when the user account does not have adequate permission under this subscription.

.PARAMETER AddVisualStudioAccess
Used to add the Visual Studio MSAL client ids to the cluster application
    'https://learn.microsoft.com/en-us/azure/service-fabric/service-fabric-manage-application-in-visual-studio'
    Visual Studio 2022 and future versions: '04f0c124-f2bc-4f59-8241-bf6df9866bbd'
    Visual Studio 2019 and earlier: '872cd9fa-d31f-45e0-9eab-6e460a02d1f1'

.PARAMETER SignInAudience
Sign in audience option for selection of Applicaiton AAD tenant configuration type. Default selection is 'AzureADMyOrg'
'AzureADMyOrg', 'AzureADMultipleOrgs', 'AzureADandPersonalMicrosoftAccount'

.PARAMETER TimeoutMin
Script execution retry wait timeout in minutes. Default is 5 minutes. If script times out, it can be re-executed and will continue configuration as script is idempotent.

.PARAMETER LogFile
Log file path to save script transcript logs.

.PARAMETER Force
Use Force switch to force new authorization to acquire new token.

.PARAMETER Remove
Use Remove to remove AAD configuration for provided cluster.

.EXAMPLE
.\SetupApplications.ps1 -TenantId '4f812c74-978b-4b0e-acf5-06ffca635c0e' `
        -ClusterName 'MyCluster' `
        -WebApplicationUri 'api://4f812c74-978b-4b0e-acf5-06ffca635c0e/mycluster' `
        -SpaApplicationReplyUrl 'https://mycluster.westus.cloudapp.azure.com:19080/explorer/index.html'

Setup tenant with default settings generated from a friendly cluster name.

.EXAMPLE
.\SetupApplications.ps1 -TenantId '4f812c74-978b-4b0e-acf5-06ffca635c0e' `
        -WebApplicationName 'SFWeb' `
        -WebApplicationUri 'https://mycluster.contoso.com' `
        -SpaApplicationReplyUrl 'https://mycluster.contoso:19080/explorer/index.html' `
        -NativeClientApplicationName 'SFnative'

Setup tenant with explicit application settings.

.EXAMPLE
$ConfigObj = .\SetupApplications.ps1 -TenantId '4f812c74-978b-4b0e-acf5-06ffca635c0e' `
        -ClusterName 'MyCluster' `
        -WebApplicationUri 'api://4f812c74-978b-4b0e-acf5-06ffca635c0e/mycluster' `
        -SpaApplicationReplyUrl 'https://mycluster.westus.cloudapp.azure.com:19080/explorer/index.html'

Setup and save the setup result into a temporary variable to pass into SetupUser.ps1

.EXAMPLE
.\SetupApplications.ps1 -TenantId '4f812c74-978b-4b0e-acf5-06ffca635c0e' `
        -WebApplicationUri 'api://4f812c74-978b-4b0e-acf5-06ffca635c0e/mycluster' `
        -SpaApplicationReplyUrl 'https://mycluster.westus.cloudapp.azure.com:19080/explorer/index.html' `
        -AddResourceAccess `
        -AddVisualStudioAccess

Setup tenant with explicit application settings and add explicit resource access to Entra application.
#>
[cmdletbinding()]
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

    [Parameter(ParameterSetName = 'Customize', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Prefix', Mandatory = $true)]
    [String]
    $SpaApplicationReplyUrl,

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
    [Switch]
    $AddVisualStudioAccess,

    [Parameter(ParameterSetName = 'Customize')]
    [Parameter(ParameterSetName = 'Prefix')]
    [String]
    [ValidateSet('AzureADMyOrg', 'AzureADMultipleOrgs', 'AzureADandPersonalMicrosoftAccount')]
    $SignInAudience = 'AzureADMyOrg',

    [Parameter(ParameterSetName = 'Customize')]
    [Parameter(ParameterSetName = 'Prefix')]
    [int]
    $TimeoutMin = 5,

    [Parameter(ParameterSetName = 'Customize')]
    [Parameter(ParameterSetName = 'Prefix')]
    [string]
    $LogFile,

    [Parameter(ParameterSetName = 'Customize')]
    [Parameter(ParameterSetName = 'Prefix')]
    [Switch]$Force,

    [Parameter(ParameterSetName = 'Customize')]
    [Parameter(ParameterSetName = 'Prefix')]
    [Switch]
    $Remove
)

# load common functions
. "$PSScriptRoot\Common.ps1"

$graphAPIFormat = $global:ConfigObj.GraphAPIFormat
$sleepSeconds = 5
$msGraphUserReadAppId = '00000003-0000-0000-c000-000000000000'
$msGraphUserReadId = 'e1fe6dd8-ba31-4d61-89e7-88639da4683d'
$visualStudioClientIds = @(
    '04f0c124-f2bc-4f59-8241-bf6df9866bbd', # Visual Studio 2022 and future versions
    '872cd9fa-d31f-45e0-9eab-6e460a02d1f1'  # Visual Studio 2019 and earlier
)

function main () {
    try {
        if ($LogFile) {
            Start-Transcript -path $LogFile -Force | Out-Null
        }

        setup-Applications
    }
    catch [Exception] {
        write-errorMessage $psitem
    }
    finally {
        if ($LogFile) {
            Stop-Transcript | Out-Null
        }
    }
}

function add-appRegistration($WebApplicationUri, $SpaApplicationReplyUrl, $requiredResourceAccess) {
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
        implicitGrantSettings = @{
            enableAccessTokenIssuance = $false
            enableIdTokenIssuance     = $true
        }
    }

    $spaAppResource = @{
        redirectUris = @($SpaApplicationReplyUrl)
    }

    $webApp = @{
        displayName            = $webApplicationName
        signInAudience         = $SignInAudience
        identifierUris         = @($WebApplicationUri)
        defaultRedirectUri     = $SpaApplicationReplyUrl
        appRoles               = $appRole
        requiredResourceAccess = $null
        spa                    = $spaAppResource
        web                    = $webAppResource
        api                    = @{
            preAuthorizedApplications = @()
            oauth2PermissionScopes    = @()
        }
    }

    if ($AddResourceAccess) {
        $webApp.requiredResourceAccess = $requiredResourceAccess
    }

    # add
    $webApp = invoke-graphApi -retry -uri $uri -body $webApp -method 'post'

    if ($webApp) {
        $stopTime = set-stopTime $TimeoutMin

        while (!($webApp.api.oauth2PermissionScopes.gethashcode())) {
            $webApp = wait-forResult -functionPointer (get-item function:\get-appRegistration) `
                -message "waiting for app registration completion" `
                -stopTime $stopTime `
                -WebApplicationUri $WebApplicationUri
            start-sleep -Seconds $sleepSeconds
        }
    }

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
        publicClient           = @{
            redirectUris = @("urn:ietf:wg:oauth:2.0:oob")
        }
        displayName            = $NativeClientApplicationName
        signInAudience         = $SignInAudience
        isFallbackPublicClient = $true
        requiredResourceAccess = $nativeAppResourceAccess
    }

    $nativeApp = invoke-graphApi -retry -uri $uri -body $nativeAppResource -method 'post'

    if ($nativeApp) {
        $null = wait-forResult -functionPointer (get-item function:\get-nativeClient) `
            -message "waiting for native app registration completion" `
            -WebApplicationUri $WebApplicationUri `
            -NativeClientApplicationName $NativeClientApplicationName
    }

    return $nativeApp
}

function add-oauthPermissions($webApp, $webApplicationName) {
    write-host "adding user_impersonation scope"
    $uri = [string]::format($graphAPIFormat, "applications/$($webApp.Id)")
    $webApp.api.oauth2PermissionScopes = @($webApp.api.oauth2PermissionScopes)
    $userImpersonationScopeId = [guid]::NewGuid()
    $webApp.api.oauth2PermissionScopes += @{
        id                      = $userImpersonationScopeId
        isEnabled               = $true
        type                    = "User"
        adminConsentDescription = "Allow the application to access $webApplicationName on behalf of the signed-in user."
        adminConsentDisplayName = "Access $webApplicationName"
        userConsentDescription  = "Allow the application to access $webApplicationName on your behalf."
        userConsentDisplayName  = "Access $webApplicationName"
        value                   = "user_impersonation"
    }

    $null = wait-forResult -functionPointer (get-item function:\invoke-graphApi) `
        -message "waiting for patch application uri to be available" `
        -uri $uri `
        -method get

    # timing issue even when call above successful
    $result = invoke-graphApi -retry -uri $uri -method 'patch' -body @{
        'api' = @{
            "oauth2PermissionScopes" = $webApp.api.oauth2PermissionScopes
        }
    }

    if ($result) {
        $null = wait-forResult -functionPointer (get-item function:\get-OauthPermissions) `
            -message "waiting for oauth permission completion" `
            -webApp $webApp
    }

    return $userImpersonationScopeId
}

function add-preauthorizedApplications($webApp, [guid[]]$applicationIds, [guid[]]$delegatedPermissionIds) {
    #Create PreAuthorized Applications
    $uri = [string]::format($graphAPIFormat, "applications/$($webApp.Id)")
    $preAuthorizedApplications = [collections.arraylist]::new()

    foreach ($applicationId in $applicationIds) {
        # check for existing preauthorized applications and merge permissions
        $mergedPermissions = [collections.arraylist]::new()
        [void]$mergedPermissions.AddRange($delegatedPermissionIds)

        $existingApplication = get-preauthorizedApplications -applicationId $webApp.id -applicationIds $applicationId
        if ($existingApplication) {
            foreach ($existingPermission in $existingApplication.delegatedPermissionIds) {
                if (!$mergedPermissions -contains $existingPermission) {
                    [void]$mergedPermissions.Add($existingPermission)
                }
            }
        }
    
        $preAuthorizedApplications.Add(@{
                appId                  = $applicationId
                delegatedPermissionIds = $mergedPermissions
            })
    }

    $webApp.api.preAuthorizedApplications = $preAuthorizedApplications
    $result = invoke-graphApi -retry -uri $uri -method 'patch' -body @{
        'api' = @{
            "preAuthorizedApplications" = $webApp.api.preAuthorizedApplications
        }
    }

    if ($result) {
        $null = wait-forResult -functionPointer (get-item function:\get-preauthorizedApplications) `
            -message "waiting for preauthorized applications completion" `
            -applicationId $webApp.id `
            -applicationIds $applicationIds `
            -delegatedPermissionIds $delegatedPermissionIds
    }

    return $preAuthorizedApplications
}

function add-servicePrincipal($webApp, $assignmentRequired) {
    #Service Principal
    write-host "adding service principal: $($webapp.appid)"
    $uri = [string]::Format($graphAPIFormat, "servicePrincipals")
    $servicePrincipal = @{
        accountEnabled            = $true
        appId                     = $webApp.appId
        displayName               = $webApp.displayName
        appRoleAssignmentRequired = $assignmentRequired
    }

    $servicePrincipal = invoke-graphApi -retry -uri $uri -body $servicePrincipal -method 'post'

    if ($servicePrincipal) {
        $null = wait-forResult -functionPointer (get-item function:\get-servicePrincipal) `
            -message "waiting for service principal creation completion" `
            -webApp $webApp
    }

    return $servicePrincipal
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
        resourceId  = $resourceId
        scope       = $scope
        startTime   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffff")
        expiryTime  = (Get-Date).AddYears(1800).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffff")
    }

    $result = invoke-graphApi -uri $uri -body $oauth2PermissionGrants -method 'post'
    assert-notNull $result "aad app service principal oauth permissions $scope configuration failed"

    if ($result) {
        $stopTime = set-stopTime $TimeoutMin
        $checkGrants = $null

        while (!$checkGrants -or !($checkGrants.scope.Contains($scope))) {
            $checkGrants = wait-forResult -functionPointer (get-item function:\get-oauthPermissionGrants) `
                -message "waiting for service principal grants creation completion" `
                -stopTime $stopTime `
                -clientId $clientId
            start-sleep -Seconds $sleepSeconds
        }
    }

    return $result
}

function confirm-visualStudioAccess($webApp, [guid]$oauthPermissionsId) {
    $preAuthorizedApplications = get-preauthorizedApplications -applicationId $webApp.id -applicationIds $visualStudioClientIds -delegatedPermissionIds @($oauthPermissionsId)
    if ($preAuthorizedApplications) {
        write-host "visual studio preauthorized applications already exists."
        # todo: should we remove if $AddVisualStudioAccess is false?
        if (!$AddVisualStudioAccess) {
            $remove = $true

            if (!$Force) {
                $remove = (read-host "Do you want to remove visual studio preauthorized applications? (y/n)") -ieq 'y'
            }

            if ($remove) {
                write-host "removing visual studio preauthorized applications" -ForegroundColor Yellow
                remove-preauthorizedApplications -webApp $webApp -applicationIds $visualStudioClientIds -delegatedPermissionIds @($oauthPermissionsId)
                return
            }
        }
    }
    else {
        write-host "visual studio preauthorized applications do not exist."
    }

    if (!$preAuthorizedApplications -and $AddVisualStudioAccess) {
        write-host "adding visual studio preauthorized applications" -ForegroundColor Green
        # check / add preauthorized applications
        $preAuthorizedApplications = add-preauthorizedApplications -webApp $webApp -applicationIds $visualStudioClientIds -delegatedPermissionIds @($oauthPermissionsId)
        assert-notNull $preAuthorizedApplications 'Web Application preauthorized applications Failed'
        Write-Host "Web Application preauthorized applications created: $($preAuthorizedApplications|convertto-json)"  -ForegroundColor Green
    }
    else {
        write-host "visual studio preauthorized applications not do not need to be modified." -ForegroundColor Yellow
    }
}

function get-appRegistration($WebApplicationUri) {
    # check for existing app by identifieruri
    $uri = [string]::Format($graphAPIFormat, "applications?`$search=`"identifierUris:$WebApplicationUri`"")

    $webApp = (invoke-graphApi -uri $uri -method 'get').value
    write-host "currentAppRegistration:$webApp"

    if ($webApp) {
        write-host "app registration $($webApp.appId) with $WebApplicationUri already exists." -foregroundcolor yellow
        write-host "currentAppRegistration:$($webApp|convertto-json -depth 99)"
        return $webApp
    }

    return $null
}

function get-appRegistrationById([guid]$applicationId) {
    # get existing application by 'id'
    $uri = [string]::format($graphAPIFormat, "applications/$($applicationId)")
    $webApp = (invoke-graphApi -uri $uri -method 'get')
    
    if ($webApp) {
        write-verbose "currentAppRegistration:$($webApp|convertto-json -depth 99)"
        return $webApp
    }
    else {
        write-error "$uri does not exist."
    }

    return $null
}

function get-nativeClient($NativeClientApplicationName) {
    # check for existing native clinet
    $uri = [string]::Format($graphAPIFormat, "applications?`$search=`"displayName:$NativeClientApplicationName`"")

    $nativeClient = (invoke-graphApi -uri $uri -method 'get').value
    write-host "nativeClient:$nativeClient"

    if ($nativeClient) {
        write-host "native client $($nativeClient.appId) with $WebApplicationUri already exists." -foregroundcolor yellow
        write-host "current service principal:$($nativeClient|convertto-json -depth 99)"
        return $nativeClient
    }

    return $null
}

function get-oauthPermissions($webApp) {
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
    # get 'Entra' app registration by well-known appId
    $uri = [string]::Format($graphAPIFormat, "oauth2PermissionGrants") + "?`$filter=clientId eq '$clientId'"
    $grants = invoke-graphApi -uri $uri -method 'get'
    write-verbose "grants:$($grants | convertto-json -depth 2)"
    return $grants.value
}

function get-preauthorizedApplications([guid]$applicationId, [guid[]]$applicationIds, [guid[]]$delegatedPermissionIds = $null) {
    # check for existing preauthorized applications
    $webApp = get-appRegistrationById -applicationId $applicationId
    $preAuthorizedApplications = $webApp.api.preAuthorizedApplications | Where-Object {
        $psitem.appId -in $applicationIds
    }

    if ($preAuthorizedApplications -and $delegatedPermissionIds) {
        $preAuthorizedApplications = $preAuthorizedApplications | Where-Object {
            $psitem.delegatedPermissionIds -like $delegatedPermissionIds
        }
    }

    write-host "preAuthorizedApplications:$preAuthorizedApplications"

    if ($preAuthorizedApplications.count -eq $applicationIds.count) {
        write-host "preAuthorizedApplications already exists. $($filter)" -foregroundcolor yellow
        write-host "current preAuthorizedApplications:$($preAuthorizedApplications|convertto-json -depth 99)"
        return $preAuthorizedApplications
    }

    return $null
}

function get-servicePrincipal($webApp) {
    # check for existing app by identifieruri
    $uri = [string]::Format($graphAPIFormat, "servicePrincipals?`$search=`"appId:$($webApp.appId)`"")
    $servicePrincipal = (invoke-graphApi -uri $uri -method 'get').value
    write-host "servicePrincipal:$servicePrincipal"

    if ($servicePrincipal) {
        write-host "service principal $($servicePrincipal.appId) already exists." -foregroundcolor yellow
        write-host "current service principal:$($servicePrincipal|convertto-json -depth 99)"
        return $servicePrincipal
    }

    return $null
}

function get-servicePrincipalAAD() {
    # get 'Entra' app registration by well-known appId
    $uri = [string]::Format($graphAPIFormat, "servicePrincipals") + "?`$filter=appId eq '$msGraphUserReadAppId'"
    $global:AADServicePrincipal = invoke-graphApi -uri $uri -method 'get'
    write-verbose "aad service princiapal:$($AADServicePrincipal | convertto-json -depth 2)"
    return $AADServicePrincipal
}

function remove-appRegistration($WebApplicationUri) {
    # remove web app registration
    $webApp = get-appRegistration -WebApplicationUri $WebApplicationUri
    if (!$webApp) {
        return $true
    }

    $ConfigObj.WebAppId = $webApp.appId
    $uri = [string]::Format($graphAPIFormat, "applications/$($webApp.id)")
    $webApp = (invoke-graphApi -uri $uri -method 'delete')

    if ($webApp) {
        $null = wait-forResult -functionPointer (get-item function:\invoke-graphApi) `
            -message "waiting for web client delete to complete..." `
            -waitForNullResult `
            -uri $uri `
            -method 'get'
    }

    return $true
}

function remove-nativeClient($NativeClientApplicationName) {
    # remove native app registration
    $nativeApp = get-nativeClient -nativeClientApplicationName $NativeClientApplicationName
    if (!$nativeApp) {
        return $true
    }

    $uri = [string]::Format($graphAPIFormat, "applications/$($nativeApp.id)")
    $nativeApp = (invoke-graphApi -uri $uri -method 'delete')

    if ($nativeApp) {
        $ConfigObj.NativeClientAppId = $nativeApp.appId

        $null = wait-forResult -functionPointer (get-item function:\invoke-graphApi) `
            -message "waiting for native client delete to complete..." `
            -waitForNullResult `
            -uri $uri `
            -method 'get'
    }

    return $true
}

function remove-preauthorizedApplications($webApp, [guid[]]$applicationIds, [guid[]]$delegatedPermissionIds) {
    # remove preauthorized applications
    if (!(get-preauthorizedApplications -applicationId $webApp.id -applicationIds $applicationIds -delegatedPermissionIds $delegatedPermissionIds)) {
        write-host "preauthorized applications do not exist." -ForegroundColor Green
        return $webApp.api.preAuthorizedApplications
    }

    $uri = [string]::format($graphAPIFormat, "applications/$($webApp.Id)")
    $preAuthorizedApplications = [collections.arraylist]::new()
    [void]$preAuthorizedApplications.AddRange($webApp.api.preAuthorizedApplications)
    
    foreach ($applicationId in $applicationIds) {
        # check for existing preauthorized applications and scrub permissions
        $existingApplication = get-preauthorizedApplications -applicationId $webApp.id -applicationIds $applicationId -delegatedPermissionIds $delegatedPermissionIds
        if (!$existingApplication) {
            continue
        }

        $scrubbedPermissions = [collections.arraylist]::new()
        [void]$scrubbedPermissions.AddRange($existingApplication.delegatedPermissionIds)
        
        foreach ($existingPermission in $existingApplication.delegatedPermissionIds) {
            if ($delegatedPermissionIds -contains $existingPermission) {
                write-host "removing permission $existingPermission" -ForegroundColor Yellow
                [void]$scrubbedPermissions.Remove($existingPermission)
            }
        }
        
        [void]$preAuthorizedApplications.Remove($existingApplication)

        if ($scrubbedPermissions.Count -gt 0) {
            $preAuthorizedApplications.Add(@{
                    appId                  = $applicationId
                    delegatedPermissionIds = $scrubbedPermissions
                })
        }
    }
    
    $webApp.api.preAuthorizedApplications = $preAuthorizedApplications
    $result = invoke-graphApi -retry -uri $uri -method 'patch' -body @{
        'api' = @{
            "preAuthorizedApplications" = $webApp.api.preAuthorizedApplications
        }
    }
    
    if ($result) {
        $null = wait-forResult -functionPointer (get-item function:\get-preauthorizedApplications) `
            -message "waiting for preauthorized applications completion" `
            -waitForNullResult `
            -applicationId $webApp.id `
            -applicationIds $applicationIds `
            -delegatedPermissionIds $delegatedPermissionIds
    }
    
    return $preAuthorizedApplications
}

function remove-servicePrincipal() {
    $result = $true
    $webApp = get-appRegistration -WebApplicationUri $WebApplicationUri

    if ($webApp) {
        $servicePrincipal = get-servicePrincipal -webApp $webApp
        if ($servicePrincipal) {
            $ConfigObj.ServicePrincipalId = $servicePrincipal.Id
            $uri = [string]::Format($graphAPIFormat, "servicePrincipals/$($servicePrincipal.id)")
            $result = $result -and (invoke-graphApi -uri $uri -method 'delete')

            if ($result) {
                $null = wait-forResult -functionPointer (get-item function:\get-servicePrincipal) `
                    -message "waiting for web spn delete to complete..." `
                    -waitForNullResult `
                    -webApp $webApp
            }
        }
    }

    return $result
}

function remove-servicePrincipalNa() {
    $result = $true
    $nativeApp = get-nativeClient -NativeClientApplicationName $NativeClientApplicationName -WebApplicationUri $WebApplicationUri

    if ($nativeApp) {
        $servicePrincipalNa = get-servicePrincipal -webApp $nativeApp
        if ($servicePrincipalNa) {
            $uri = [string]::Format($graphAPIFormat, "servicePrincipals/$($servicePrincipalNa.id)")
            $result = invoke-graphApi -uri $uri -method 'delete'
            if ($result) {
                $null = wait-forResult -functionPointer (get-item function:\get-servicePrincipal) `
                    -message "waiting for native spn delete to complete..." `
                    -waitForNullResult `
                    -webApp $nativeApp
            }
        }
    }

    return $result
}

function setup-Applications() {
    Write-Host 'TenantId = ' $TenantId
    $ConfigObj.ClusterName = $clusterName
    $ConfigObj.TenantId = $TenantId
    $webApp = $null

    if (!$webApplicationName) {
        $webApplicationName = "ServiceFabricCluster"
    }

    if (!$WebApplicationUri) {
        $WebApplicationUri = "https://ServiceFabricCluster"
    }

    if (!$NativeClientApplicationName) {
        $NativeClientApplicationName = "ServiceFabricClusterNativeClient"
    }

    # MS Graph access User.Read
    $requiredResourceAccess = @(@{
            resourceAppId  = $msGraphUserReadAppId
            resourceAccess = @(@{
                    id   = $msGraphUserReadId
                    type = "Scope"
                })
        })

    # cleanup
    if ($Remove) {
        write-host "removing web service principals"
        $result = remove-servicePrincipal

        write-host "removing web service principals"
        $result = $result -and (remove-servicePrincipalNa)

        write-warning "removing app registration"
        $result = $result -and (remove-appRegistration -WebApplicationUri $WebApplicationUri)

        write-warning "removing native app registration"
        $result = $result -and (remove-nativeClient -nativeClientApplicationName $NativeClientApplicationName)

        write-host "removal complete result:$result" -ForegroundColor Green
        return $ConfigObj
    }

    # check / add app registration
    $webApp = get-appRegistration -WebApplicationUri $WebApplicationUri
    if (!$webApp) {
        $webApp = add-appRegistration -WebApplicationUri $WebApplicationUri `
            -SpaApplicationReplyUrl $SpaApplicationReplyUrl `
            -requiredResourceAccess $requiredResourceAccess
    }

    assert-notNull $webApp 'Web Application Creation Failed'
    $ConfigObj.WebAppId = $webApp.appId
    Write-Host "Web Application Created: $($webApp.appId)"

    # check / add oauth user_impersonation permissions
    $oauthPermissionsId = get-oauthPermissions -webApp $webApp
    if (!$oauthPermissionsId) {
        $oauthPermissionsId = add-oauthPermissions -webApp $webApp -WebApplicationName $webApplicationName
    }
    assert-notNull $oauthPermissionsId 'Web Application Oauth permissions Failed'
    Write-Host "Web Application Oauth permissions created: $($oauthPermissionsId|convertto-json)"  -ForegroundColor Green

    # check / add visual studio preauthorized applications
    confirm-visualStudioAccess -webApp $webApp -oauthPermissionsId $oauthPermissionsId

    # check / add servicePrincipal
    $servicePrincipal = get-servicePrincipal -webApp $webApp
    if (!$servicePrincipal) {
        $servicePrincipal = add-servicePrincipal -webApp $webApp -assignmentRequired $true
    }
    assert-notNull $servicePrincipal 'service principal configuration failed'
    Write-Host "Service Principal Created: $($servicePrincipal.appId)" -ForegroundColor Green
    $ConfigObj.ServicePrincipalId = $servicePrincipal.Id

    # check / add native app
    $nativeApp = get-nativeClient -NativeClientApplicationName $NativeClientApplicationName -WebApplicationUri $WebApplicationUri
    if (!$nativeApp) {
        $nativeApp = add-nativeClient -webApp $webApp -requiredResourceAccess $requiredResourceAccess -oauthPermissionsId $oauthPermissionsId
    }
    assert-notNull $nativeApp 'Native Client Application Creation Failed'
    Write-Host "Native Client Application Created: $($nativeApp.appId)"  -ForegroundColor Green
    $ConfigObj.NativeClientAppId = $nativeApp.appId

    # check / add native app service principal
    $servicePrincipalNa = get-servicePrincipal -webApp $nativeApp
    if (!$servicePrincipalNa) {
        $servicePrincipalNa = add-servicePrincipal -webApp $nativeApp -assignmentRequired $false
    }
    assert-notNull $servicePrincipalNa 'native app service principal configuration failed'
    Write-Host "Native app service principal created: $($servicePrincipalNa.appId)" -ForegroundColor Green

    # check / add native app service principal AAD
    $servicePrincipalAAD = add-servicePrincipalGrants -servicePrincipalNa $servicePrincipalNa `
        -servicePrincipal $servicePrincipal

    assert-notNull $servicePrincipalAAD 'aad app service principal configuration failed'
    Write-Host "AAD Application Configured: $($servicePrincipalAAD)"  -ForegroundColor Green
    write-host "ConfigObj: $($ConfigObj|convertto-json)"

    #ARM template AAD resource
    write-host "-----ARM template-----"
    write-host "`"azureActiveDirectory`": $(@{
        tenantId           = $ConfigObj.tenantId
        clusterApplication = $ConfigObj.WebAppId
        clientApplication  = $ConfigObj.NativeClientAppId
    } | ConvertTo-Json)," -ForegroundColor Cyan

    return $ConfigObj
}

main
