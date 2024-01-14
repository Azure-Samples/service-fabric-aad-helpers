<#
test sf aad scripts

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