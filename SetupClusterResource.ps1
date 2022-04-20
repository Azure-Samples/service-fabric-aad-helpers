<#
.SYNOPSIS
adds 'azureActiveDirectory' json configuration to given Microsoft.ServiceFabric/clusters resource

requires azure module 'az'
install-module az
v 1.1

.EXAMPLE
.\setupClusterResource.ps1 -tenantId cb4dc457-01c8-40c7-855a-5468ebd5bc74 `
    -clusterApplication e6bba8d5-3fb6-47ac-9927-2a50cf763d36 `
    -clientApplication 2324af84-f14b-4ee8-a695-6b464f8dbb92 `
    -resourceGroupName 'mysftestcluster' `
    -clusterName 'mysftestcluster'
#>

param(
    [Parameter(ParameterSetName='customobj',Mandatory = $true)]
    [hashtable]$configObj = @{},

    [Parameter(ParameterSetName='values',Mandatory = $true)]
    [string]$tenantId = '', # guid
    
    [Parameter(ParameterSetName='values',Mandatory = $true)]
    [string]$clusterApplication = '', # guid
    
    [Parameter(ParameterSetName='values',Mandatory = $true)]
    [string]$clientApplication = '', # guid
    
    [Parameter(ParameterSetName='values',Mandatory = $true)]
    [Parameter(ParameterSetName='customobj',Mandatory = $true)]
    [string]$resourceGroupName = '',
    
    [Parameter(ParameterSetName='values',Mandatory = $true)]
    [string]$clusterName = '',

    [Parameter(ParameterSetName='values')]
    [Parameter(ParameterSetName='customobj')]
    [string]$deploymentName = "add-azureactivedirectory-$((get-date).tostring('yy-MM-dd-HH-mm-ss'))",
    
    [Parameter(ParameterSetName='values')]
    [Parameter(ParameterSetName='customobj')]
    [string]$templateFile = "$pwd\template-$deploymentName.json",
    
    [Parameter(ParameterSetName='values')]
    [Parameter(ParameterSetName='customobj')]
    [switch]$whatIf,
    
    [Parameter(ParameterSetName='values')]
    [Parameter(ParameterSetName='customobj')]
    [switch]$force
)

$PSModuleAutoLoadingPreference = 2

if($configObj) {
    write-host "using configobj"
    $tenantId = $configObj.TenantId
    $clusterApplication = $configObj.WebAppId
    $clientApplication = $configObj.NativeClientAppId
}

$azureActiveDirectory = @{ 
    azureActiveDirectory = @{
        tenantId           = $tenantId
        clusterApplication = $clusterApplication
        clientApplication  = $clientApplication
    }
}

$azureActiveDirectory | convertto-json

if ((test-path $templateFile) -and $force) {
    remove-item $templateFile -Force
}

if (!(get-command get-azcontext)) {
    write-warning "azure az module is required to run this script. 'ctrl-c' to exit script or {enter} to continue."
    if (!$force) {
        pause
    }
    install-module az -Force -AllowClobber
}

if (!(Get-AzContext)) { Connect-AzAccount }

$resources = @(get-azresource -Name $clusterName | Where-Object ResourceType -imatch 'Microsoft.ServiceFabric')

if ($resources.Count -ne 1) {
    write-error "unable to find cluster $(resources)"
    return
}

$clusterResource = $resources[0].ResourceId
$resourceType = $resources[0].ResourceType

write-host "
Export-AzResourceGroup -ResourceGroupName $resourceGroupName ``
    -Path $templateFile ``
    -Resource $clusterResource ``
    -IncludeComments ``
    -SkipAllParameterization ``
    -Verbose
"

Export-AzResourceGroup -ResourceGroupName $resourceGroupName `
    -Path $templateFile `
    -Resource $clusterResource `
    -IncludeComments `
    -SkipAllParameterization `
    -Verbose

# modify template file
$templateJson = get-content -raw $templateFile
$templateJson
$global:templateObj = $templateJson | convertfrom-json 
$clusterObj = $global:templateObj.resources | Where-Object type -ieq $resourceType

if (!$clusterObj) {
    write-error "unable to find cluster resource"
    return
}

if (!($clusterObj.properties.azureActiveDirectory)) {
    write-host "adding $azureActiveDirectory"
    Add-Member -InputObject $clusterObj.properties `
        -TypeName System.Management.Automation.PSCustomObject `
        -NotePropertyMembers $azureActiveDirectory
}
else {
    write-warning "modifying $($clusterObj.properties.azureActiveDirectory)"
    $clusterObj.properties.azureActiveDirectory = $azureActiveDirectory
}

$templateJson = $global:templateObj | convertto-json -depth 99
$templateJson

$templateJson | out-file $templateFile

write-host "
Test-azResourceGroupDeployment -ResourceGroupName $resourceGroupName ``
    -TemplateFile $templateFile ``
    -Mode Complete
"

$ret = Test-azResourceGroupDeployment -ResourceGroupName $resourceGroupName `
    -TemplateFile $templateFile `
    -Mode Complete

if ($ret) {
    Write-Error "template validation failed. error: `n`n$($ret.Code)`n`n$($ret.Message)`n`n$($ret.Details)"
    return
}
else {
    write-host "template valid: $templateFile" -ForegroundColor Green
}

write-host "New-AzResourceGroupDeployment -Name `"$deploymentName`" ``
    -ResourceGroupName $resourceGroupName ``
    -Mode Incremental ``
    -DeploymentDebugLogLevel All ``
    -TemplateFile $templateFile ``
    -Verbose
" -ForegroundColor Yellow

if (!$whatIf) {
    New-AzResourceGroupDeployment -Name "$deploymentName" `
        -ResourceGroupName $resourceGroupName `
        -Mode Incremental `
        -DeploymentDebugLogLevel All `
        -TemplateFile $templateFile `
        -Verbose
}
else {
    write-host "execute command above or rerun script without -whatif when ready to update cluster." -ForegroundColor Green
}

write-host "updated template file: $($templateFile)" -ForegroundColor Cyan
write-host "finished"
