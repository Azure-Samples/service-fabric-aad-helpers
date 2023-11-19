<#
.SYNOPSIS
Update applications in a Service Fabric cluster Entra tenant to migrate the web redirect URIs to SPA redirect URIs.

.DESCRIPTION
version: 231112

.PARAMETER WebApplicationId
WebApplicationId of the application to update

.PARAMETER TimeoutMin
Timeout in minutes for the script to run

.PARAMETER HttpPort
Port to search for in the redirect URIs

.PARAMETER LogFile
Path to the log file

.PARAMETER TenantId
Tenant id of the application to update

.PARAMETER WhatIf
Switch to run the script in whatif mode

.PARAMETER MGClientId
Optional AAD client id for management group. If not provided, it will use default client id.

.PARAMETER MGClientSecret
Optional AAD client secret for management group.

.PARAMETER MGGrantType
Optional AAD grant type for management group. Default is 'device_code'.

.EXAMPLE
    .\UpdateApplication.ps1 -WebApplicationId 'https://mysftestcluster.contoso.com' `
        -TenantId '00000000-0000-0000-0000-000000000000' `
        -TimeoutMin 5 `
        -HttpPort 19080 `
        -LogFile 'C:\temp\update-app.log' `
        -WhatIf

#>
[cmdletbinding()]
Param
(
    [Parameter(ParameterSetName = 'Customize', Mandatory = $true)]
    [guid]
    $WebApplicationId,

    [Parameter(ParameterSetName = 'Customize')]
    [int]
    $TimeoutMin = 5,

    [Parameter(ParameterSetName = 'Customize')]
    [int]
    $HttpPort = 19080,

    [Parameter(ParameterSetName = 'Customize')]
    [string]
    $LogFile,

    [Parameter(ParameterSetName = 'Customize', Mandatory = $true)]
    [guid]
    $TenantId,

    [Parameter(ParameterSetName = 'Customize')]
    [Switch]
    $WhatIf,

    [Parameter(ParameterSetName = 'Customize')]
    [guid]
    $MGClientId,

    [Parameter(ParameterSetName = 'Customize')]
    [string]
    $MGClientSecret,

    [Parameter(ParameterSetName = 'Customize')]
    [string]
    $MGGrantType
)

# load common functions
. "$PSScriptRoot\Common.ps1" @PSBoundParameters
$graphAPIFormat = $global:ConfigObj.GraphAPIFormat

function main () {
    try {
        if ($LogFile) {
            Start-Transcript -path $LogFile -Force | Out-Null
        }

        update-Application
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

function update-Application() {
    $webApplication = get-appRegistration -WebApplicationUri $WebApplicationId
    assert-notNull $webApplication 'web application not found'

    # web URIs that should be removed from the web URI redirects
    $webUrisToRemove = @()

    #web URIs that will be converted to spa URIs
    $newSpaUris = @()

    #track the spa URIs that will be updated, including existing spa URIs
    $spaUrisToUpdate = @($webApplication.spa.redirectUris)

    foreach ($uri in $webApplication.web.redirectUris) {
        $replyUri = [Uri]::new($uri)
        #search critera is any redirect URIs that contain the port from script called
        if ($replyUri.Port -eq $HttpPort) {
            # rewrite to use the new stricter format expectation
            $newUri = $replyUri.Scheme + "://" + $replyUri.Authority + "/Explorer/index.html"
            #dont include duplicate URIs otherwise the request will fail
            if (!($spaUrisToUpdate.Contains($newUri))) {
                $newSpaUris += $newUri
                $spaUrisToUpdate += $newUri

                $webUrisToRemove += $uri
            }
        }
    }

    # remove any web redirect URIs that got converted to spa
    # This should leave any existing web URIs that did not meet the migration condition
    $updatedWebRedirectUris = @()
    foreach ($existingUri in $webApplication.web.redirectUris) {
        if (!$webUrisToRemove.Contains($existingUri)) {
            $updatedWebRedirectUris += $existingUri
        }
    }

    $webApp = @{
        spa = @{
            redirectUris = $spaUrisToUpdate
        }
        web = @{
            redirectUris = $updatedWebRedirectUris
        }
    }

    if ($WhatIf) {
        Write-Host -ForegroundColor yellow `The following $webUrisToRemove.Length Web Redirect URIs would be moved to spa redirect uris`
        foreach ($spa in $webUrisToRemove) {
            Write-Host $spa
        }

        Write-Host -ForegroundColor yellow ` The following $newSpaUris.Length new spa redirect uris would be added`
        foreach ($spa in $newSpaUris) {
            Write-Host $spa
        }
    }
    else {
        Write-Host -ForegroundColor yellow `Attempting to update $newSpaUris.Length from web redirect uris to spa redirect uris`

        update-appRegistration -id $webApplication.id -webAppUpdate $webApp

        if ($global:graphStatusCode -eq 204) {
            Write-Host -ForegroundColor yellow `Completed moving $newSpaUris.Length web redirect uris to spa redirect uris`
            foreach ($spa in $newSpaUris) {
                Write-Host $spa
            }
        }
        else {
            Write-Host -ForegroundColor Red `There was an issue updating the app registration`
        }
    }
}

function update-appRegistration($id, $webAppUpdate) {
    $uri = [string]::Format($graphAPIFormat, "applications/$id")
    invoke-graphApi -uri $uri -method 'patch' -body $webAppUpdate
}

function get-appRegistration($WebApplicationUri) {
    # check for existing app by WebApplicationUri
    $uri = [string]::Format($graphAPIFormat, "applications?`$search=`"appId:$WebApplicationUri`"")

    $webApp = (invoke-graphApi -uri $uri -method 'get').value

    if (!$webApp) {
        return $null
    }
    return $webApp[0]
}

main