<#
.SYNOPSIS
    script used to test entra / aad setup scripts for service fabric cluster with aad integration enabled
.DESCRIPTION
    script used to test entra / aad setup scriptis for service fabric cluster with aad integration enabled.
    requires test service fabric cluster
    requires admin access to azure ad / entra / graph

    Typical usage: .\test-aad-setup.ps1 -resourceGroupName 'myrg' -clusterName 'mysfcluster' -setupReadonlyUser -setupAdminUser -setupClusterResource -addVisualStudioAccess
        executes: .\SetupApplications.ps1 -TenantId $tenantId -ClusterName $clusterName -SpaApplicationReplyUrl $replyUrl -AddResourceAccess -WebApplicationUri $webApplicationUri -AddVisualStudioAccess:$addVisualStudioAccess -logFile $translog -Verbose -force:$force -remove:$remove
        executes: .\SetupUser.ps1 -ConfigObj $ConfigObj -UserName 'TestReadOnly' -Password 'P@ssword!123' -IsReadOnly -Verbose -logFile $translog -remove:$remove -force:$force
        executes: .\SetupUser.ps1 -ConfigObj $ConfigObj -UserName 'TestAdmin' -Password 'P@ssword!123' -IsAdmin -Verbose -logFile $translog -remove:$remove -force:$force
        executes: .\SetupClusterResource.ps1 -resourceGroupName $resourceGroupName -ConfigObj $($ConfigObj | convertto-json -depth 99)

.EXAMPLE
    .\test-aad-setup.ps1 -resourceGroupName 'myrg'
.EXAMPLE
    .\test-aad-setup.ps1 -resourceGroupName 'myrg' -clusterName 'mysfcluster'
.EXAMPLE
    .\test-aad-setup.ps1 -resourceGroupName 'myrg' -clusterName 'mysfcluster' -setupReadonlyUser
.EXAMPLE
    .\test-aad-setup.ps1 -resourceGroupName 'myrg' -clusterName 'mysfcluster' -setupReadonlyUser -setupAdminUser
.EXAMPLE
    .\test-aad-setup.ps1 -resourceGroupName 'myrg' -clusterName 'mysfcluster' -setupReadonlyUser -setupAdminUser -setupClusterResource
.EXAMPLE
    .\test-aad-setup.ps1 -resourceGroupName 'myrg' -clusterName 'mysfcluster' -setupReadonlyUser -setupAdminUser -setupClusterResource -addVisualStudioAccess
.EXAMPLE
    .\test-aad-setup.ps1 -resourceGroupName 'myrg' -clusterName 'mysfcluster' -setupReadonlyUser -setupAdminUser -setupClusterResource -addVisualStudioAccess -MGClientId '14d82eec-204b-4c2f-b7e8-296a70dab67e' -MGClientSecret 'mysecret'
.PARAMETER resourceGroupName
    resource group name of the test cluster
.PARAMETER tenantId
    tenant id for resource group. defaults to current az context tenant id
.PARAMETER clusterName
    test cluster name if different than resource group name
.PARAMETER setupReadonlyUser
    setup readonly user 'TestReadOnly' with read only access to cluster
.PARAMETER setupAdminUser
    setup test admin user 'TestAdmin' with read / write access to cluster
.PARAMETER setupClusterResource
    setup cluster resource with new application registration client id
.PARAMETER addVisualStudioAccess
    add visual studio application registration ids to the cluster resource for deployment access from visual studio
.PARAMETER remove
    remove
.PARAMETER force
    force
.PARAMETER MGClientId
    optional Microsoft Graph Client Id if not using default
.PARAMETER MGClientSecret
    optional Microsoft Graph Client Secret
.PARAMETER MGGrantType
    optional Microsoft Graph Grant Type (default: urn:ietf:params:oauth:grant-type:device_code)
#>
param(
    [parameter(Mandatory = $true)]
    [string]$resourceGroupName,
    [string]$tenantId = "$((get-azcontext).tenant.id)",
    [string]$clusterName = $resourceGroupName,
    [switch]$setupReadonlyUser,
    [switch]$setupAdminUser,
    [switch]$setupClusterResource,
    [switch]$remove,
    [switch]$force,
    [switch]$addVisualStudioAccess,
    [guid]$MGClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e', # well-known ps graph client id generated on connect
    [string]$MGClientSecret = $null,
    [string]$MGGrantType = 'urn:ietf:params:oauth:grant-type:device_code' #'client_credentials', #'authorization_code'
)

$errorActionPreference = 'continue'
$curDir = $pwd
$startTime = get-date
$replyUrl = ""
$webApplicationUri = ""

function main() {
    try {

        $location = (get-azResourceGroup -Name $resourceGroupName).location
        if (!$location) {
            throw "resource group $resourceGroupName not found"
        }
        $replyUrl = "https://$clusterName.$location.cloudapp.azure.com:19080/Explorer/index.html" # <--- client browser redirect url

        #$webApplicationUri = 'https://mysftestcluster.contoso.com' # <--- must be verified domain due to AAD changes
        $webApplicationUri = "api://$tenantId/$clusterName" # <--- does not have to be verified domain

        if ($MGClientSecret) {
            setup-applicationMG

            write-host "ConfigObj:" -ForegroundColor Cyan
            $ConfigObj

            if ($setupReadonlyUser) {
                setup-readOnlyUserMG
            }
            if ($setupAdminUser) {
                setup-adminUserMG
            }

            write-host "ConfigObj:" -ForegroundColor Cyan
            $ConfigObj

        }
        else {
            setup-application

            write-host "ConfigObj:" -ForegroundColor Cyan
            $ConfigObj

            if ($setupReadonlyUser) {
                setup-readOnlyUser
            }
            if ($setupAdminUser) {
                setup-adminUser
            }

            write-host "ConfigObj:" -ForegroundColor Cyan
            $ConfigObj

        }

        if ($setupClusterResource) {
            write-host ".\SetupClusterResource.ps1 -resourceGroupName $resourceGroupName
            -ConfigObj $($ConfigObj | convertto-json -depth 99)
        " -ForegroundColor Cyan

            .\SetupClusterResource.ps1 -configObj $ConfigObj -resourceGroupName $resourceGroupName
        }
    }
    finally {
        set-location $curDir
    }
}

function setup-application() {
    $translog = "$pwd/setup-application-$($startTime.tostring('yyMMddhhmmss')).log"

    write-host ".\SetupApplications.ps1 -TenantId $tenantId ``
    -ClusterName $clusterName ``
    -SpaApplicationReplyUrl $replyUrl ``
    -AddResourceAccess ``
    -WebApplicationUri $webApplicationUri ``
    -logFile $translog ``
    -AddVisualStudioAccess:`$$addVisualStudioAccess ``
    -Verbose ``
    -force:`$$force ``
    -remove:`$$remove
" -ForegroundColor Cyan

    $ConfigObj = .\SetupApplications.ps1 -TenantId $tenantId `
        -ClusterName $clusterName `
        -SpaApplicationReplyUrl $replyUrl `
        -AddResourceAccess `
        -WebApplicationUri $webApplicationUri `
        -AddVisualStudioAccess:$addVisualStudioAccess `
        -logFile $translog `
        -Verbose `
        -force:$force `
        -remove:$remove
}

function setup-applicationMG() {
    $translog = "$pwd/setup-application-$($startTime.tostring('yyMMddhhmmss')).log"

    write-host ".\SetupApplications.ps1 -TenantId $tenantId ``
    -ClusterName $clusterName ``
    -SpaApplicationReplyUrl $replyUrl ``
    -AddResourceAccess ``
    -WebApplicationUri $webApplicationUri ``
    -logFile $translog ``
    -AddVisualStudioAccess:`$$addVisualStudioAccess ``
    -Verbose ``
    -force:`$$force ``
    -remove:`$$remove ``
    -MGClientId $MGClientId ``
    -MGClientSecret $MGClientSecret ``
    -MGGrantType $MGGrantType
" -ForegroundColor Cyan

    $ConfigObj = .\SetupApplications.ps1 -TenantId $tenantId `
        -ClusterName $clusterName `
        -SpaApplicationReplyUrl $replyUrl `
        -AddResourceAccess `
        -WebApplicationUri $webApplicationUri `
        -AddVisualStudioAccess:$addVisualStudioAccess `
        -logFile $translog `
        -Verbose `
        -force:$force `
        -remove:$remove `
        -MGClientId $MGClientId `
        -MGClientSecret $MGClientSecret `
        -MGGrantType $MGGrantType
}

function setup-readOnlyUser() {
    $translog = "$pwd/setup-readonly-$($startTime.tostring('yyMMddhhmmss')).log"

    write-host ".\SetupUser.ps1 -UserName 'TestReadOnly' ``
    -Password 'P@ssword!123' ``
    -IsReadOnly ``
    -Verbose ``
    -logFile $translog ``
    -remove:`$$remove ``
    -force:`$$force
    -ConfigObj $($ConfigObj | convertto-json -depth 99)
" -ForegroundColor Cyan

    .\SetupUser.ps1 -ConfigObj $ConfigObj `
        -UserName 'TestReadOnly' `
        -Password 'P@ssword!123' `
        -IsReadOnly `
        -Verbose `
        -logFile $translog `
        -remove:$remove `
        -force:$force
}

function setup-readOnlyUserMG() {
    $translog = "$pwd/setup-readonly-$($startTime.tostring('yyMMddhhmmss')).log"

    write-host ".\SetupUser.ps1 -UserName 'TestReadOnly' ``
    -Password 'P@ssword!123' ``
    -IsReadOnly ``
    -Verbose ``
    -logFile $translog ``
    -remove:`$$remove ``
    -force:`$$force
    -ConfigObj $($ConfigObj | convertto-json -depth 99)
    -MGClientId $MGClientId `
    -MGClientSecret $MGClientSecret `
    -MGGrantType $MGGrantType
" -ForegroundColor Cyan

    .\SetupUser.ps1 -ConfigObj $ConfigObj `
        -UserName 'TestReadOnly' `
        -Password 'P@ssword!123' `
        -IsReadOnly `
        -Verbose `
        -logFile $translog `
        -remove:$remove `
        -force:$force `
        -MGClientId $MGClientId `
        -MGClientSecret $MGClientSecret `
        -MGGrantType $MGGrantType
}

function setup-adminUser() {
    $translog = "$pwd/setup-admin-$($startTime.tostring('yyMMddhhmmss')).log"

    write-host ".\SetupUser.ps1 -UserName 'TestAdmin' ``
    -Password 'P@ssword!123' ``
    -IsAdmin ``
    -Verbose ``
    -logFile $translog ``
    -remove:`$$remove ``
    -force:`$$force
    -ConfigObj $($ConfigObj | convertto-json -depth 99)
" -ForegroundColor Cyan

    .\SetupUser.ps1 -ConfigObj $ConfigObj `
        -UserName 'TestAdmin' `
        -Password 'P@ssword!123' `
        -IsAdmin `
        -Verbose `
        -logFile $translog `
        -remove:$remove `
        -force:$force
}

function setup-adminUserMG() {
    $translog = "$pwd/setup-admin-$($startTime.tostring('yyMMddhhmmss')).log"

    write-host ".\SetupUser.ps1 -UserName 'TestAdmin' ``
    -Password 'P@ssword!123' ``
    -IsAdmin ``
    -Verbose ``
    -logFile $translog ``
    -remove:`$$remove ``
    -force:`$$force
    -ConfigObj $($ConfigObj | convertto-json -depth 99)
    -MGClientId $MGClientId `
    -MGClientSecret $MGClientSecret `
    -MGGrantType $MGGrantType
" -ForegroundColor Cyan

    .\SetupUser.ps1 -ConfigObj $ConfigObj `
        -UserName 'TestAdmin' `
        -Password 'P@ssword!123' `
        -IsAdmin `
        -Verbose `
        -logFile $translog `
        -remove:$remove `
        -force:$force `
        -MGClientId $MGClientId `
        -MGClientSecret $MGClientSecret `
        -MGGrantType $MGGrantType
}

main