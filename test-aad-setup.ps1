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
    [switch]$force
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

    $ConfigObj = .\SetupApplications.ps1 -TenantId $tenantId `
        -ClusterName $clusterName `
        -SpaApplicationReplyUrl $replyUrl `
        -AddResourceAccess `
        -WebApplicationUri $webApplicationUri `
        -logFile $translog `
        -Verbose `
        -remove:$remove

    #write-host $ConfigObj
    $ConfigObj

    .\SetupUser.ps1 -ConfigObj $ConfigObj `
        -UserName 'TestUser' `
        -Password 'P@ssword!123' `
        -Verbose `
        -logFile $translog `
        -remove:$remove `
        -force:$force

    .\SetupUser.ps1 -ConfigObj $ConfigObj `
        -UserName 'TestAdmin' `
        -Password 'P@ssword!123' `
        -IsAdmin `
        -Verbose `
        -logFile $translog `
        -remove:$remove `
        -force:$force

    .\SetupClusterResource.ps1 -configObj $ConfigObj `
        -resourceGroupName $resourceGroupName

}
finally {
    write-host "$(get-date) stopping transcript $translog"
    #stop-transcript
    set-location $curDir
}