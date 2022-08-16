<#
.VERSION
2.0.0

.SYNOPSIS
Setup user in a Service Fabric cluster Azure Active Directory tenant.

.DESCRIPTION
This script can create 2 types of users: Admin user assigned admin app role; Read-only user assigned readonly app role.

.PREREQUISITE
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
Used to set metadata for specific region (for example: china, germany). Ignore it in global environment.

.EXAMPLE
. Scripts\SetupUser.ps1 -ConfigObj $ConfigObj -UserName 'SFuser' -Password 'Test4321'

Setup up a read-only user with return SetupApplications.ps1

.EXAMPLE
. Scripts\SetupUser.ps1 -TenantId '7b25ab7e-cd25-4f0c-be06-939424dc9cc9' -WebApplicationId '9bf7c6f3-53ce-4c63-8ab3-928c7bf4200b' -UserName 'SFAdmin' -Password 'Test4321' -IsAdmin

Setup up an admin user providing values for parameters
#>

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
    [Switch]
    $remove,

    [Parameter(ParameterSetName = 'Setting')]
    [Parameter(ParameterSetName = 'ConfigObj')]
    [Switch]
    $force
)

if ($ConfigObj) {
    $TenantId = $ConfigObj.TenantId
}

$headers = $null
. "$PSScriptRoot\Common.ps1"
$graphAPIFormat = $resourceUrl + "/v1.0/" + $TenantId + "/{0}"
$servicePrincipalId = $null
$WebApplicationId = $null
$sleepSeconds = 5

function main() {
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
    if ($remove) {
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

function add-roleAssignment($userId, $roleId, $servicePrincipalId) {
    #add user role assignments
    $uri = [string]::Format($graphAPIFormat, "servicePrincipals/$servicePrincipalId/appRoleAssignedTo")
    $appRoleAssignments = @{
        appRoleId   = $roleId
        principalId = $userId
        resourceId  = $servicePrincipalId
    }

    $result = call-graphApi -uri $uri -body $appRoleAssignments
    write-host "create role result: $($result | convertto-json -Depth 2)"

    if ($result) {
        while (!(get-roleAssignment -userId $userId -roleId $roleId -servicePrincipalId $servicePrincipalId)) {
            write-host "waiting for user role assignment $roleId to complete..." -ForegroundColor Magenta
            start-sleep -seconds $sleepSeconds
        }
    }
    elseif ($global:graphStatusCode -eq 400) {
        write-host "waiting for user role assignment $roleId to complete retry..." -ForegroundColor Magenta
        start-sleep -seconds $sleepSeconds
        $result = add-roleAssignment -userId $userId -roleId $roleId -servicePrincipalId $servicePrincipalId
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
            $userId = (call-graphApi -uri $uri -body $newUser).id
            assert-notNull $userId 'Admin User Creation Failed'
            Write-Host 'Admin User Created:' $userId
        }
        #Read-Only User
        else {
            Write-Host 'Creating Read-Only User: Name = ' $UserName 'Password = ' $Password
            $userId = (call-graphApi -uri $uri -body $newUser).id
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

    $results = call-graphApi -uri $uri -method 'get'
    write-host "current available assignments from $servicePrincipalId : $($results | convertto-json -depth 5)"

    $appRoles = @($results.value)
    $appRoleAssignment = $appRoles | Where-Object { ($psitem.appRoleId -ieq $roleId) -and ($psitem.principalId -ieq $userId) }

    write-host "current app role assignment:$appRoleAssignment"
    return $appRoleAssignment
}

function get-user($UserPrincipalName) {
    $uri = [string]::Format($graphAPIFormat, "users?`$search=`"userPrincipalName:$userPrincipalName`"")
    $user = (call-graphApi -uri $uri -method 'get')
    write-host "user: $($user | convertto-json -depth 2)"
    return $user
}

function get-verifiedDomain() {
    if (!$domain) {
        $uri = [string]::Format($graphAPIFormat, "domains", "")
        $domains = @((call-graphApi -uri $uri -method 'get').value)
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
        $servicePrincipalId = (call-graphApi -uri $uri -method 'get').value.id #objectId
    }

    write-host "returning servicePrincipalId:$servicePrincipalId"
    return $servicePrincipalId
}

function get-appRoles() {
    $uri = [string]::Format($graphAPIFormat, "applications?`$search=`"appId:$WebApplicationId`"")
    $appRoles = (call-graphApi -uri $uri -method 'get').value.appRoles

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

    if (!$force -and (read-host "removing user $userName from Azure AD. do you want to continue?[y|n]") -imatch "n") {
        return
    }

    $uri = [string]::Format($graphAPIFormat, "users/$userPrincipalName")
    $result = call-graphApi -uri $uri -method 'delete'

    write-host "removal complete" -ForegroundColor Green

    if ($result) {
        while ((get-user -UserPrincipalName $userPrincipalName).value) {
            write-host "waiting for user $userPrincipalName delete to complete..." -ForegroundColor Magenta
            start-sleep -seconds $sleepSeconds
        }
    }

    return $result
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