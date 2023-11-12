<#
test sf aad scripts
place in clouddrive dir in shell.azure.com

#>
param(
    [parameter(Mandatory = $true)]
    $resourceGroupName,
    $tenantId = "$((get-azcontext).tenant.id)",
    $clusterName = $resourceGroupName,
    [switch]$remove,
    [switch]$force,
    [switch]$noClusterResourceSetup,
    [switch]$addVisualStudioAccess
)

$errorActionPreference = 'continue'
$curDir = $pwd
$startTime = get-date
$translog = "$pwd/tran-$($startTime.tostring('yyMMddhhmmss')).log"

try {
    write-host "$(get-date) starting transcript $translog"
    $location = (get-azResourceGroup -Name $resourceGroupName).location
    if (!$location) {
        throw "resource group $resourceGroupName not found"
    }

    $replyUrl = "https://$clusterName.$location.cloudapp.azure.com:19080/Explorer/index.html" # <--- client browser redirect url

    #$webApplicationUri = 'https://mysftestcluster.contoso.com' # <--- must be verified domain due to AAD changes
    $webApplicationUri = "api://$tenantId/$clusterName" # <--- does not have to be verified domain

    write-host ".\SetupApplications.ps1 -TenantId $tenantId ``
        -ClusterName $clusterName ``
        -SpaApplicationReplyUrl $replyUrl ``
        -AddResourceAccess ``
        -AddVisualStudioAccess:$addVisualStudioAccess ``
        -WebApplicationUri $webApplicationUri ``
        -logFile $translog ``
        -Verbose ``
        -force:$force ``
        -remove:$remove
    " -ForegroundColor Cyan

    $ConfigObj = .\SetupApplications.ps1 -TenantId $tenantId `
        -ClusterName $clusterName `
        -SpaApplicationReplyUrl $replyUrl `
        -AddResourceAccess `
        -AddVisualStudioAccess:$addVisualStudioAccess `
        -WebApplicationUri $webApplicationUri `
        -logFile $translog `
        -Verbose `
        -force:$force `
        -remove:$remove

    write-host "ConfigObj:" -ForegroundColor Cyan
    $ConfigObj

    write-host ".\SetupUser.ps1 -UserName 'TestUser' ``
        -Password 'P@ssword!123' ``
        -Verbose ``
        -logFile $translog ``
        -remove:$remove ``
        -force:$force ``
        -ConfigObj $($ConfigObj | convertto-json -depth 99)
    " -ForegroundColor Cyan

    .\SetupUser.ps1 -ConfigObj $ConfigObj `
        -UserName 'TestUser' `
        -Password 'P@ssword!123' `
        -Verbose `
        -logFile $translog `
        -remove:$remove `
        -force:$force

    write-host ".\SetupUser.ps1 -UserName 'TestAdmin' ``
        -Password 'P@ssword!123' ``
        -IsAdmin ``
        -Verbose ``
        -logFile $translog ``
        -remove:$remove ``
        -force:$force
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

    if($noClusterResourceSetup) {
        write-host "skipping cluster resource setup" -ForegroundColor Cyan
        return
    }
    write-host ".\SetupClusterResource.ps1 -resourceGroupName $resourceGroupName
        -ConfigObj $($ConfigObj | convertto-json -depth 99)
    " -ForegroundColor Cyan

    .\SetupClusterResource.ps1 -configObj $ConfigObj `
        -resourceGroupName $resourceGroupName

}
finally {
    write-host "$(get-date) stopping transcript $translog"
    #stop-transcript
    set-location $curDir
}