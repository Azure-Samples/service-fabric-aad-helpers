<#
.SYNOPSIS
adds 'azureActiveDirectory' json configuration to given Microsoft.ServiceFabric/clusters resource

.DESCRIPTION
requires azure module 'az'
install-module az
version: 231112

.PARAMETER ConfigObj
    hashtable containing configuration values

.PARAMETER TenantId
    tenant id of the application to update

.PARAMETER ClusterApplication
    the application id of the cluster application

.PARAMETER ClientApplication
    the application id of the client application

.PARAMETER ResourceGroupName
    the resource group name of the cluster

.PARAMETER ClusterName
    the name of the cluster

.PARAMETER DeploymentName
    the name of the deployment

.PARAMETER TemplateFile
    the path to the template file

.PARAMETER WhatIf
    the switch to run the script in whatif mode

.PARAMETER Force
    the switch to force overwrite of template file

.EXAMPLE
.\setupClusterResource.ps1 -tenantId 'cb4dc457-01c8-40c7-855a-5468ebd5bc74' `
        -clusterApplication 'e6bba8d5-3fb6-47ac-9927-2a50cf763d36' `
        -clientApplication '2324af84-f14b-4ee8-a695-6b464f8dbb92' `
        -resourceGroupName 'mysftestcluster' `
        -clusterName 'mysftestcluster'

.EXAMPLE
.\setupClusterResource.ps1
        -ConfigObj $ConfigObj `
        -resourceGroupName 'mysftestcluster' `
        -clusterName 'mysftestcluster'
#>
[cmdletbinding()]
param(
    [Parameter(ParameterSetName = 'customobj', Mandatory = $true)]
    [hashtable]$ConfigObj = @{},

    [Parameter(ParameterSetName = 'values', Mandatory = $true)]
    [string]$TenantId = '', # guid

    [Parameter(ParameterSetName = 'values', Mandatory = $true)]
    [string]$ClusterApplication = '', # guid

    [Parameter(ParameterSetName = 'values', Mandatory = $true)]
    [string]$ClientApplication = '', # guid

    [Parameter(ParameterSetName = 'values', Mandatory = $true)]
    [Parameter(ParameterSetName = 'customobj', Mandatory = $true)]
    [string]$ResourceGroupName = '',

    [Parameter(ParameterSetName = 'values', Mandatory = $true)]
    [string]$ClusterName = '',

    [Parameter(ParameterSetName = 'values')]
    [Parameter(ParameterSetName = 'customobj')]
    [string]$DeploymentName = "add-azureactivedirectory-$((get-date).tostring('yy-MM-dd-HH-mm-ss'))",

    [Parameter(ParameterSetName = 'values')]
    [Parameter(ParameterSetName = 'customobj')]
    [string]$TemplateFile = "$pwd/template-$DeploymentName.json",

    [Parameter(ParameterSetName = 'values')]
    [Parameter(ParameterSetName = 'customobj')]
    [switch]$WhatIf,

    [Parameter(ParameterSetName = 'values')]
    [Parameter(ParameterSetName = 'customobj')]
    [switch]$Force
)

$PSModuleAutoLoadingPreference = 2

if ($ConfigObj) {
    write-host "using ConfigObj"
    $TenantId = $ConfigObj.TenantId
    $ClusterApplication = $ConfigObj.WebAppId
    $ClientApplication = $ConfigObj.NativeClientAppId
    $ClusterName = $ConfigObj.ClusterName
}

$azureActiveDirectory = @{
    azureActiveDirectory = @{
        tenantId           = $TenantId
        clusterApplication = $ClusterApplication
        clientApplication  = $ClientApplication
    }
}

$azureActiveDirectory | convertto-json

if ((test-path $TemplateFile) -and $Force) {
    remove-item $TemplateFile -Force
}

if (!(get-command get-azcontext)) {
    write-warning "azure az module is required to run this script. 'ctrl-c' to exit script or {enter} to continue."
    if (!$Force) {
        pause
    }
    install-module az -Force -AllowClobber
}

if (!(Get-AzContext) -or ((Get-AzContext).Tenant.id -ine $TenantId)) {
    if (!(Connect-AzAccount -Tenant $TenantId)) {
        write-error "authentication error"
        return
    }
}

write-host "`$resources = @(get-azresource -Name $ClusterName | Where-Object ResourceType -imatch 'Microsoft.ServiceFabric')"
$resources = @(get-azresource -Name $ClusterName | Where-Object ResourceType -imatch 'Microsoft.ServiceFabric')

if ($resources.count -ine 1) {
    if ($resources.Count -lt 1) {
        write-error "unable to find cluster $ClusterName"
    }
    else {
        write-error "multiple clusters found $($resources | Format-List *)"
    }

    return
}

$clusterResource = $resources[0].ResourceId
$resourceType = $resources[0].ResourceType

write-host "
Export-AzResourceGroup -ResourceGroupName $ResourceGroupName ``
    -Path $TemplateFile ``
    -Resource $clusterResource ``
    -IncludeComments ``
    -SkipAllParameterization ``
    -Verbose
"

Export-AzResourceGroup -ResourceGroupName $ResourceGroupName `
    -Path $TemplateFile `
    -Resource $clusterResource `
    -IncludeComments `
    -SkipAllParameterization `
    -Verbose

# modify template file
$templateJson = get-content -raw $TemplateFile
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
    $clusterObj.properties.azureActiveDirectory = $azureActiveDirectory.azureActiveDirectory
}

$templateJson = $global:templateObj | convertto-json -depth 99
$templateJson

$templateJson | out-file $TemplateFile

write-host "
Test-azResourceGroupDeployment -ResourceGroupName $ResourceGroupName ``
    -TemplateFile $TemplateFile ``
    -Mode Complete
"

$ret = Test-azResourceGroupDeployment -ResourceGroupName $ResourceGroupName `
    -TemplateFile $TemplateFile `
    -Mode Complete

if ($ret) {
    Write-Error "template validation failed. error: `n`n$($ret.Code)`n`n$($ret.Message)`n`n$($ret.Details)"
    return
}
else {
    write-host "template valid: $TemplateFile" -ForegroundColor Green
}

write-host "
New-AzResourceGroupDeployment -Name `"$DeploymentName`" ``
    -ResourceGroupName $ResourceGroupName ``
    -Mode Incremental ``
    -DeploymentDebugLogLevel All ``
    -TemplateFile $TemplateFile ``
    -Verbose
" -ForegroundColor Yellow

if (!$WhatIf) {
    New-AzResourceGroupDeployment -Name "$DeploymentName" `
        -ResourceGroupName $ResourceGroupName `
        -Mode Incremental `
        -DeploymentDebugLogLevel All `
        -TemplateFile $TemplateFile `
        -Verbose
}
else {
    write-host "execute command above or rerun script without -whatif when ready to update cluster." -ForegroundColor Green
}

write-host "updated template file: $($TemplateFile)" -ForegroundColor Cyan
write-host "finished"
