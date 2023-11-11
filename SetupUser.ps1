<#
.SYNOPSIS
Setup user in a Service Fabric cluster Azure Active Directory tenant.

.DESCRIPTION
This script can create 2 types of users: Admin user assigned admin app role; Read-only user assigned readonly app role.

version: 2.0.1

Prerequisites:
1. An Azure Active Directory Tenant
2. Service Fabric web and native client applications are setup. Or run SetupApplications.ps1.

.PARAMETER TenantId
ID of tenant hosting Service Fabric cluster.

.PARAMETER WebApplicationId
ObjectId of web application representing Service Fabric cluster.

.PARAMETER UserName,
Username of new user.

.PARAMETER Password
Password of new user.

.PARAMETER IsAdmin
User is assigned admin app role if indicated; otherwise, readonly app role.

.PARAMETER ConfigObj
Temporary variable of tenant setup result returned by SetupApplications.ps1.

.PARAMETER Location
Used to set metadata for specific region (for example: china). Ignore it in global environment.

.PARAMETER Domain
Domain is the verified domain being used for user account configuration.

.PARAMETER timeoutMin
Script execution retry wait timeout in minutes. Default is 5 minutes. If script times out, it can be re-executed and will continue configuration as script is idempotent.

.PARAMETER force
Use Force switch to force removal of AAD user account if specifying -remove.

.PARAMETER remove
Use Remove to remove AAD configuration and optionally user.

.EXAMPLE
. Scripts\SetupUser.ps1 -ConfigObj $ConfigObj -UserName 'SFuser' -Password 'Test4321'

Setup up a read-only user with return SetupApplications.ps1

.EXAMPLE
. Scripts\SetupUser.ps1 -TenantId '7b25ab7e-cd25-4f0c-be06-939424dc9cc9' -WebApplicationId '9bf7c6f3-53ce-4c63-8ab3-928c7bf4200b' -UserName 'SFAdmin' -Password 'Test4321' -IsAdmin

Setup up an admin user providing values for parameters
#>
[cmdletbinding()]
Param
(
    [Parameter(ParameterSetName = 'Setting', Mandatory = $true)]
    [String]
    $TenantId,

    [Parameter(ParameterSetName = 'Setting', Mandatory = $true)]
    [String]
    $WebApplicationId,

    [Parameter(ParameterSetName = 'Setting')]
    [Parameter(ParameterSetName = 'ConfigObj')]
    [String]
    $UserName,

    [Parameter(ParameterSetName = 'Setting', Mandatory = $true)]
    [Parameter(ParameterSetName = 'ConfigObj', Mandatory = $true)]
    [String]
    $Password,

    [Parameter(ParameterSetName = 'Setting')]
    [Parameter(ParameterSetName = 'ConfigObj')]
    [Switch]
    $IsAdmin,

    [Parameter(ParameterSetName = 'ConfigObj', Mandatory = $true)]
    [Hashtable]
    $ConfigObj,

    [Parameter(ParameterSetName = 'Setting')]
    [Parameter(ParameterSetName = 'ConfigObj')]
    [ValidateSet('us', 'china')]
    [String]
    $Location,

    [Parameter(ParameterSetName = 'Setting')]
    [Parameter(ParameterSetName = 'ConfigObj')]
    [String]
    $Domain,

    [Parameter(ParameterSetName = 'Setting')]
    [Parameter(ParameterSetName = 'ConfigObj')]
    [int]
    $TimeoutMin = 5,

    [Parameter(ParameterSetName = 'Setting')]
    [Parameter(ParameterSetName = 'ConfigObj')]
    [string]
    $LogFile,

    [Parameter(ParameterSetName = 'Setting')]
    [Parameter(ParameterSetName = 'ConfigObj')]
    [Switch]
    $Remove,

    [Parameter(ParameterSetName = 'Setting')]
    [Parameter(ParameterSetName = 'ConfigObj')]
    [Switch]
    $Force
)

# load common functions
. "$PSScriptRoot\Common.ps1"

$graphAPIFormat = $global:ConfigObj.GraphAPIFormat
$servicePrincipalId = $null
$WebApplicationId = $null
$sleepSeconds = 5

function main () {
    try {
        if ($logFile) {
            Start-Transcript -path $logFile -Force | Out-Null
        }

        setup-User
    }
    catch [Exception] {
        write-errorMessage $psitem
    }
    finally {
        if ($logFile) {
            Stop-Transcript | Out-Null
        }
    }
}

function add-roleAssignment($userId, $roleId, $servicePrincipalId) {
    #add user role assignments
    $uri = [string]::Format($graphAPIFormat, "servicePrincipals/$servicePrincipalId/appRoleAssignedTo")
    $appRoleAssignments = @{
        appRoleId   = $roleId
        principalId = $userId
        resourceId  = $servicePrincipalId
    }

    $result = invoke-graphApi -retry -uri $uri -body $appRoleAssignments -method 'post'
    write-host "create role result: $($result | convertto-json -Depth 2)"

    if ($result) {
        wait-forResult -functionPointer (get-item function:\get-roleAssignment) `
            -message "waiting for user role assignment $roleId to complete..." `
            -userId $userId `
            -roleId $roleId `
            -servicePrincipalId $servicePrincipalId
    }

    return $result
}

function add-user($userName, $domain, $appRoles) {
    #Create User
    $userPrincipalName = "$userName@$domain"
    $roleId = get-roleId -appRoles $appRoles
    $userId = (get-user -UserPrincipalName $userPrincipalName).value.id

    if (!$userId) {
        $uri = [string]::Format($graphAPIFormat, "users", "")
        $newUser = @{
            accountEnabled    = $true
            displayName       = $UserName
            passwordProfile   = @{
                password = $Password
            }
            mailNickname      = $UserName
            userPrincipalName = $userPrincipalName
        }
        #Admin
        if ($IsAdmin) {
            Write-Host 'Creating Admin User: Name = ' $UserName 'Password = ' $Password
            $userId = (invoke-graphApi -uri $uri -body $newUser -method 'post').id
            assert-notNull $userId 'Admin User Creation Failed'
            Write-Host 'Admin User Created:' $userId
        }
        #Read-Only User
        else {
            Write-Host 'Creating Read-Only User: Name = ' $UserName 'Password = ' $Password
            $userId = (invoke-graphApi -uri $uri -body $newUser -method 'post').id
            assert-notNull $userId 'Read-Only User Creation Failed'
            Write-Host 'Read-Only User Created:' $userId
        }
    }

    write-host "user id: $userId"
    $currentAppRoleAssignment = get-roleAssignment -userId $userId -roleId $roleId -servicePrincipalId $servicePrincipalId

    if (!$currentAppRoleAssignment) {
        $currentAppRoleAssignment = add-roleAssignment -userId $userId -roleId $roleId -servicePrincipalId $servicePrincipalId
    }

    return $currentAppRoleAssignment
}

function get-roleAssignment($userId, $roleId, $servicePrincipalId) {
    #get user role assignments
    $uri = [string]::Format($graphAPIFormat, "servicePrincipals/$servicePrincipalId/appRoleAssignedTo")

    $results = invoke-graphApi -uri $uri -method 'get'
    write-host "current available assignments from $servicePrincipalId : $($results | convertto-json -depth 5)"

    $appRoles = @($results.value)
    $appRoleAssignment = $appRoles | Where-Object { ($psitem.appRoleId -ieq $roleId) -and ($psitem.principalId -ieq $userId) }

    write-host "current app role assignment:$appRoleAssignment"
    return $appRoleAssignment
}

function get-user($UserPrincipalName) {
    $uri = [string]::Format($graphAPIFormat, "users?`$search=`"userPrincipalName:$userPrincipalName`"")
    $user = (invoke-graphApi -uri $uri -method 'get')
    write-host "user: $($user | convertto-json -depth 2)"
    return $user
}

function get-verifiedDomain() {
    if (!$domain) {
        $uri = [string]::Format($graphAPIFormat, "domains", "")
        $domains = @((invoke-graphApi -uri $uri -method 'get').value)
        write-verbose "domain list: $($domains | convertto-json -depth 2)"

        $verifiedDomains = @($domains | Where-Object isVerified -eq $true)
        write-verbose "verified domain list: $($verifiedDomains | convertto-json -depth 2)"
        $verifiedDomain = @($domains | Where-Object { $_.isVerified -eq $true -and $_.isDefault -eq $true })
        write-verbose "default verified domain: $($verifiedDomain | convertto-json -depth 2)"

        if ($verifiedDomains.count -gt 1 -and $verifiedDomain) {
            write-warning "multiple domains detected. please rerun script using -domain argument for non default domain."
            write-host "verified domains: $($verifiedDomains | convertto-json -depth 2)"
            write-host "using default verified domain: $($verifiedDomain | convertto-json -depth 2)" -ForegroundColor Green
            $domain = $verifiedDomain.id
        }
        elseif ($verifiedDomains.count -gt 1 -and !$verifiedDomain) {
            write-error "multiple domains detected. please rerun script using -domain argument."
            write-host "verified domain list: $($verifiedDomains | convertto-json -depth 2)"
        }
        elseif ($verifiedDomains.count -lt 1) {
            write-error "no domains detected. please rerun script using -domain argument for proper domain."
        }
        else {
            $domain = $verifiedDomains[0].id
        }
    }

    return $domain
}

function get-servicePrincipalId($servicePrincipalId) {
    if (!$servicePrincipalId) {
        $uri = [string]::Format($graphAPIFormat, "servicePrincipals?`$search=`"appId:$WebApplicationId`"")
        $servicePrincipalId = (invoke-graphApi -uri $uri -method 'get').value.id #objectId
    }

    write-host "returning servicePrincipalId:$servicePrincipalId"
    return $servicePrincipalId
}

function get-appRoles() {
    $uri = [string]::Format($graphAPIFormat, "applications?`$search=`"appId:$WebApplicationId`"")
    $appRoles = (invoke-graphApi -uri $uri -method 'get').value.appRoles

    write-host "returning appRoles:$($appRoles | convertto-json)"
    return $appRoles
}

function get-roleId($appRoles) {
    $appRoleType = 'User'
    if ($IsAdmin) {
        $appRoleType = 'Admin'
    }

    $roleId = ($appRoles | Where-Object value -eq $appRoleType | Select-Object id).id
    write-host "roleId: $roleId"
    return  $roleId
}

function remove-user($userName, $domain) {
    $userPrincipalName = "$userName@$domain"
    $userId = (get-user -UserPrincipalName $userPrincipalName).value.id

    if (!$userId) {
        return $true
    }

    if (!$Force -and (read-host "removing user $userName from Azure AD. do you want to continue?[y|n]") -imatch "n") {
        return
    }

    $uri = [string]::Format($graphAPIFormat, "users/$userPrincipalName")
    $result = invoke-graphApi -uri $uri -method 'delete'

    write-host "removal complete" -ForegroundColor Green

    if ($result) {
        $stopTime = set-stopTime $TimeoutMin

        do {
            $deleteResult = wait-forResult -functionPointer (get-item function:\get-user) `
                -message "waiting for user $userPrincipalName delete to complete..." `
                -stopTime $stopTime `
                -UserPrincipalName $userPrincipalName
            start-sleep -Seconds $sleepSeconds
        }
        while ($deleteResult.value)
    }

    return $result
}

function setup-User() {
    Write-Host 'TenantId = ' $TenantId

    if ($ConfigObj) {
        $WebApplicationId = $ConfigObj.WebAppId
        $servicePrincipalId = $ConfigObj.ServicePrincipalId
    }

    # get verified domain
    $domain = get-verifiedDomain
    assert-notNull $domain 'domain is not found'

    # set user name
    $userName = set-userName

    # cleanup
    if ($Remove) {
        return (remove-user -userName $userName -domain $domain)
    }

    # get service principal id
    $servicePrincipalId = get-servicePrincipalId -servicePrincipalId $servicePrincipalId
    assert-notNull $servicePrincipalId 'Service principal of web application is not found'

    # get app roles
    $appRoles = get-appRoles
    assert-notNull $appRoles 'AppRoles of web application is not found'

    # check / create user
    $newUser = add-user -userName $userName -domain $domain -appRoles $appRoles
    assert-notNull $newUser "unable to create new user $userName"
    write-host "user $userName created successfully"
    return $newUser
}

function set-userName() {
    if (!$UserName) {
        if ($IsAdmin) {
            $UserName = 'ServiceFabricAdmin'
        }
        else {
            $UserName = 'ServiceFabricUser'
        }
    }

    return $UserName
}

main