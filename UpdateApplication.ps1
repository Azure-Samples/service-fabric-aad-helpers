[cmdletbinding()]
Param
(
    [Parameter(ParameterSetName = 'Customize')]	
    [String]
    $webApplicationId,
    [Parameter(ParameterSetName = 'Customize')]
    [int]
    $timeoutMin = 5,
    [Parameter(ParameterSetName = 'Customize')]
    [int]
    $httpPort = 19080,
    [Parameter(ParameterSetName = 'Customize')]
    [string]
    $logFile
)


$headers = $null
. "$PSScriptRoot\Common.ps1"
$graphAPIFormat = $resourceUrl + "/v1.0/{0}"
$global:ConfigObj = @{}
$sleepSeconds = 5
$msGraphUserReadAppId = '00000003-0000-0000-c000-000000000000'
$msGraphUserReadId = 'e1fe6dd8-ba31-4d61-89e7-88639da4683d'


function main () {
    try {
        if ($logFile) {
            Start-Transcript -path $logFile -Force
        }

        update-Application
    }
    catch [Exception] {
        $errorString = "exception: $($psitem.Exception.Response.StatusCode.value__)`r`nexception:`r`n$($psitem.Exception.Message)`r`n$($error | out-string)`r`n$($psitem.ScriptStackTrace)"
        write-error $errorString
    }
    finally {
        if ($logFile) {
            Stop-Transcript
        }
    }
}

function update-Application() {
    $webApplication = get-appRegistration -WebApplicationUri $webApplicationId
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
        if ($replyUri.Port -eq $httpPort) {

            # rewrite to use the new stricter format expectation
            $newUri = $replyUri.Authority + "/Explorer/index.html"
           
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

function update-appRegistration($id, $webAppUpdate) {
    $uri = [string]::Format($graphAPIFormat, "applications/$id")
   
    invoke-graphApi -uri $uri -method 'patch' -body $webAppUpdate
}

function get-appRegistration($WebApplicationUri) {
    # check for existing app by WebApplicationUri
    $uri = [string]::Format($graphAPIFormat, "applications?`$search=`"appId:$WebApplicationUri`"")
   
    $webApp = (invoke-graphApi -uri $uri -method 'get').value
    return $webApp[0]
}

main