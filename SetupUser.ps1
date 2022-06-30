<#
.VERSION
1.0.3

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
    $Domain
)

if ($ConfigObj) {
    $TenantId = $ConfigObj.TenantId
}

$headers = $null
. "$PSScriptRoot\Common.ps1"
$graphAPIFormat = $resourceUrl + "/v1.0/" + $TenantId + "/{0}"
#$graphAPIFormat = $resourceUrl + "/beta/" + $TenantId + "/{0}"
$servicePrincipalId = $null
$WebApplicationId = $null

function main() {
    Write-Host 'TenantId = ' $TenantId

    if ($ConfigObj) {
        $WebApplicationId = $ConfigObj.WebAppId
        $servicePrincipalId = $ConfigObj.NativeClientAppId # $ConfigObj.ServicePrincipalId
    }

    # get verified domain
    $domain = get-verifiedDomain
    assert-notNull $domain 'domain is not found'
    
    # get service principal id
    $servicePrincipalId = get-servicePrincipalId
    assert-notNull $servicePrincipalId 'Service principal of web application is not found'

    # get app roles
    $appRoles = get-appRoles
    assert-notNull $appRoles 'AppRoles of web application is not found'

    # set user name
    $userName = set-userName

    # create user
    $newUser = create-user -userName $userName -domain $domain -appRoles $appRoles
    assert-notNull $newUser 'unable to create new user $userName'
    return $newUser
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

function get-servicePrincipalId() {
    if (!$servicePrincipalId) {
        #$uri = [string]::Format($graphAPIFormat, "servicePrincipals", [string]::Format('&$filter=appId eq ''{0}''', $WebApplicationId))
        $uri = [string]::Format($graphAPIFormat, "servicePrincipals?`$search=`"appId:$WebApplicationId`"")
        $servicePrincipalId = (call-graphApi -uri $uri -method 'get').value.id #objectId
    }

    return $servicePrincipalId
}

function get-appRoles() {
    $uri = [string]::Format($graphAPIFormat, "applications?`$search=`"appId:$WebApplicationId`"")
    $appRoles = (call-graphApi -uri $uri -method 'get').value.appRoles
    
    return $appRoles
}

function get-roleId($appRoles) {
    $appRoleType = 'User'
    if ($IsAdmin) {
        $appRoleType = 'Admin'
    }

    $roleId = ($appRoles | Where-Object value -eq $appRoleType | Select-Object id).id
    write-verbose "roleId: $roleId"
    return  $roleId
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

function get-user($UserPrincipalName) {
    #$uri = [string]::Format($graphAPIFormat, "users", [string]::Format('&$filter=displayName eq ''{0}''', $UserName))
    $uri = [string]::Format($graphAPIFormat, "users?`$search=`"userPrincipalName:$userPrincipalName`"")
    $user = (call-graphApi -uri $uri -method 'get')
    write-verbose "user: $($user | convertto-json -depth 2)"
    return $user
}

function create-user($userName, $domain, $appRoles) {
    #Create User
    $userPrincipalName = [string]::Format("{0}@{1}", $UserName, $domain)
    $roleId = get-roleId -appRoles $appRoles
    $userId = (get-user -UserPrincipalName $userPrincipalName).value.id #.objectId

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
            $userId = (call-graphApi -uri $uri -body $newUser).value.id #.objectId
            assert-notNull $userId 'Admin User Creation Failed'
            Write-Host 'Admin User Created:' $userId
        }
        #Read-Only User
        else {
            Write-Host 'Creating Read-Only User: Name = ' $UserName 'Password = ' $Password
            $userId = (call-graphApi -uri $uri -body $newUser).value.id #.objectId
            assert-notNull $userId 'Read-Only User Creation Failed'
            Write-Host 'Read-Only User Created:' $userId
        }
    }
    
    write-host "role id: $roleId"
    $roles = create-userRole -userId $userId -roleId $roleId -servicePrincipalId $servicePrincipalId
    return $roles
}

function create-userRole($userId, $roleId, $servicePrincipalId) {
    #User Role
    $uri = [string]::Format($graphAPIFormat, "users/$userId/appRoleAssignments")
    $appRoleAssignments = @{
        id            = $roleId
        principalId   = $userId
        principalType = "User"
        resourceId    = $servicePrincipalId
    }

    $results = call-graphApi -uri $uri -body $appRoleAssignments
    write-host "create role results: $($results | convertto-json -Depth 2)"
    return $results
}

main