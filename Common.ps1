<#
.SYNOPSIS
Common script, do not call directly.

.DESCRIPTION
version: 231112

#>
param(
    [guid]$TenantId,
    [string]$ClusterName = $null,
    [string]$Location = $null,
    [guid]$MGClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e', # well-known ps graph client id generated on connect
    [string]$MGClientSecret = $null,
    [string]$MGGrantType = 'urn:ietf:params:oauth:grant-type:device_code', #'client_credentials', #'authorization_code'
    [guid]$WebApplicationId,
    [switch]$Force
)

$global:graphStatusCode = $null
$sleepSeconds = 1

function main () {
    # Regional settings
    switch ($Location) {
        "china" {
            $resourceUrl = "https://graph.chinacloudapi.cn"
            $authString = "https://login.partner.microsoftonline.cn"
        }

        "us" {
            $resourceUrl = "https://graph.microsoft.us"
            $authString = "https://login.microsoftonline.us"
        }

        default {
            $resourceUrl = "https://graph.microsoft.com"
            $authString = "https://login.microsoftonline.com"
        }
    }

    # if cluster name is provided, use it to create app names
    if ($ClusterName) {
        $WebApplicationName = $ClusterName + "_Cluster"
        $NativeClientApplicationName = $ClusterName + "_Client"
    }

    if ($global:ConfigObj -and !$TenantId) {
        $TenantId = $global:ConfigObj.TenantId
    }
    # don't continue if no tenantId
    assert-notNull -obj $TenantId -msg 'tenantId required. do not call common.ps1 directly. use setup*.ps1 scripts'

    if (!$global:ConfigObj -or $Force) {
        # set / reset global config object defaults
        $global:ConfigObj = [ordered]@{
            ClusterName                 = $ClusterName
            GraphAPIFormat              = "$($resourceUrl)/v1.0/$($TenantId)/{0}"
            Headers                     = $null
            NativeClientAppId           = $null
            NativeClientApplicationName = $NativeClientApplicationName
            ServicePrincipalId          = $null
            TenantId                    = $TenantId
            WebAppId                    = $WebApplicationId
            WebApplicationName          = $WebApplicationName
        }
    }

    $global:ConfigObj.Headers = get-RESTHeaders -tenantId $TenantId -authString $authString -force:$Force
    return
}

function assert-notNull($obj, $msg) {
    if ($obj -eq $null -or $obj.Length -eq 0) {
        Write-Error $msg
        #exit
        throw "assertion failure: object:$obj message:$msg"
    }
}

function confirm-graphApiRetry($statusCode) {
    # timing issues can cause 400 or 404 return
    $retval = $false

    if ($statusCode -eq 400 -or $statusCode -eq 404) {
        $retval = $true
    }

    write-host "confirm-graphApiRetry returning:$retval"
    return $retval
}

function confirm-statusCodeSuccess($statusCode, $method) {
    write-host "checking status code:$statusCode method:$method"
    $retval = $false

    switch ($statusCode) {
        { $psitem -eq 200 } {
            $retval = $true
            break
        }
        { $psitem -eq 201 -and $method -ieq 'post' } {
            $retval = $true
            break
        }
        { $psitem -eq 204 -and $method -ieq 'patch' -or $method -ieq 'delete' } {
            $retval = $true
            break
        }

        default {
            $retval = $false
            break
        }
    }

    if ($retval) {
        write-host "$method successful." -ForegroundColor Green
    }

    write-host "confirm-statusCodeSuccess returning:$retval"
    return $retval

}

function get-cloudInstance() {
    $isCloudInstance = $PSVersionTable.Platform -ieq 'unix' -and ($env:ACC_CLOUD)
    write-host "cloud instance: $isCloudInstance"
    return $isCloudInstance
}

function get-restAuthGraph([guid]$tenantId, [guid]$clientId, $scope, $uri = $global:ConfigObj.AuthString) {
    # authenticate to Graph using device code

    write-host "auth request" -ForegroundColor Green
    $error.clear()
    $uri = "$uri/$tenantId/oauth2/v2.0/devicecode"

    $Body = @{
        'client_id' = $clientId
        'scope'     = $scope
    }

    $params = @{
        ContentType = 'application/x-www-form-urlencoded'
        Body        = $Body
        Method      = 'post'
        URI         = $uri
    }

    Write-Verbose ($params | convertto-json)
    $error.Clear()
    write-host "invoke-restMethod $uri" -ForegroundColor Cyan
    $global:authresult = Invoke-RestMethod @params -Verbose -Debug
    write-host "auth result: $($global:authresult | convertto-json)"
    write-host "rest auth finished"

    return $global:authresult
}

function get-RESTHeaders([guid]$tenantId, 
    [string]$authString,
    [guid]$clientId = $MGClientId, 
    [string]$clientSecret = $MGClientSecret, 
    [string]$grantType = $MGGrantType, 
    [switch]$force
) {
    write-host "get-RESTHeaders -tenantId $tenantId -clientId $clientId" -ForegroundColor Green
    $token = $null
    if (get-cloudInstance) {
        $token = get-RESTHeadersCloud
    }

    if (!$token) {
        $token = get-RESTHeadersGraph -tenantId $tenantId -authString $authString -clientId $clientId -clientSecret $clientSecret -grantType $grantType -force:$force
    }

    $authHeader = @{
        'Content-Type'     = 'application/json'
        'Authorization'    = 'Bearer ' + $token
        'ConsistencyLevel' = 'eventual'
    }

    return $authHeader
}

function get-RESTHeadersCloud($resourceUrl = $global:ConfigObj.ResourceUrl) {
    # https://docs.microsoft.com/en-us/azure/cloud-shell/msi-authorization
    try {
        # will fail on local cloud shell
        $response = invoke-webRequest -method post `
            -uri 'http://localhost:50342/oauth2/token' `
            -body "resource=$resourceUrl" `
            -header @{'metadata' = 'true' }

        write-host $response | convertto-json
        $token = ($response | convertfrom-json).access_token
        return $token
    }
    catch {
        return $null
    }
}

function get-RESTHeadersGraph([guid]$tenantId, [string]$authString, [guid]$clientId, [string]$clientSecret, [string]$grantType, [switch]$force) {
    assert-notNull -obj $tenantId -msg 'tenantId required'
    write-host "get-RESTHeadersGraph -tenantId $tenantId -authString $authString -clientId $clientId -clientSecret *** -grantType $grantType -force:$force" -ForegroundColor Green
    # Use common client
    #$clientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e' # well-known ps graph client id generated on connect
    #$grantType = 'urn:ietf:params:oauth:grant-type:device_code' #'client_credentials', #'authorization_code'
    $scope = 'user.read openid profile Application.ReadWrite.All User.ReadWrite.All Directory.ReadWrite.All Directory.Read.All Domain.Read.All AppRoleAssignment.ReadWrite.All'
    if (!$global:accessToken -or ($global:accessTokenExpiration -lt (get-date)) -or $force) {
        $accessToken = get-RESTTokenGraph -tenantId $tenantId -grantType $grantType -clientId $clientId -clientSecret $clientSecret -scope $scope -uri $authString
    }
    return $accessToken
}

function get-RESTTokenGraph([guid]$tenantId, [string]$grantType, [guid]$clientId, [string]$clientSecret, [string]$scope, [string]$uri) {
    # requires app registration
    # will retry on device code until complete
    write-host "get-RESTTokenGraph -tenantId $tenantId -grantType $grantType -clientId $clientId -clientSecret *** -scope $scope -uri $authString"
    write-host "token request" -ForegroundColor Green
    $global:logonResult = $null
    $error.clear()
    $authString = $uri
    $uri = "$uri/$tenantId/oauth2/v2.0/token"
    $headers = @{
        'content-type' = 'application/x-www-form-urlencoded'
        'accept'       = 'application/json'
    }

    if ($grantType -ieq 'urn:ietf:params:oauth:grant-type:device_code') {
        $global:authResult = get-restAuthGraph -tenantId $tenantId -clientId $clientId -scope $scope -uri $authString
        $Body = @{
            'client_id'   = $clientId
            'device_code' = $global:authresult.device_code
            'grant_type'  = $grantType
        }
    }
    elseif ($grantType -ieq 'client_credentials') {
        $Body = @{
            'client_id'     = $clientId
            'client_secret' = $clientSecret
            'grant_type'    = $grantType
        }
    }
    elseif ($grantType -ieq 'authorization_code') {
        $global:authResult = get-restAuthGraph -tenantId $tenantId -clientId $clientId -scope $scope -uri $authString
        $Body = @{
            'client_id'  = $clientId
            'code'       = $global:authresult.code
            'grant_type' = $grantType
        }
    }

    $params = @{
        Headers = $headers
        Body    = $Body
        Method  = 'Post'
        URI     = $uri
    }

    write-verbose ($params | convertto-json)
    write-host "invoke-restMethod $uri" -ForegroundColor Cyan

    $endTime = (get-date).AddSeconds($global:authresult.expires_in / 2)

    while ($endTime -gt (get-date)) {
        write-verbose "logon timeout: $endTime current time: $(get-date)"
        $error.Clear()

        try {
            $global:logonResult = Invoke-RestMethod @params -Verbose -Debug
            write-host "logon result: $($global:logonResult | convertto-json)"
            $global:accessToken = $global:logonResult.access_token
            $global:accessTokenExpiration = ((get-date).AddSeconds($global:logonResult.expires_in))
            return $global:accessToken
        }
        catch [System.Exception] {
            $errorMessage = ($psitem | convertfrom-json)

            if ($errorMessage -and ($errorMessage.error -ieq 'authorization_pending')) {
                write-host "waiting for device token result..." -ForegroundColor Yellow
                write-host "$($global:authresult.message)" -ForegroundColor Green
                start-sleep -seconds $global:authresult.interval
            }
            else {
                write-host "exception: $($error | out-string)`r`n this: $($_)`r`n"
                write-host "logon error: $($errorMessage | convertto-json)"
                write-host "breaking"
                break
            }
        }
    }

    write-host "rest logon returning"
    return $global:accessToken
}

function invoke-graphApiCall($uri, $headers = $global:ConfigObj.Headers, $body = '', $method = 'post') {
    try {
        $error.clear()
        $global:graphStatusCode = $null
        $json = $body | ConvertTo-Json -Depth 99 -Compress
        $logHeaders = $headers.clone()
        $logHeaders.Authorization = $logHeaders.Authorization.substring(0, 30) + '...'

        if ($method -ieq 'post' -or $method -ieq 'patch') {
            write-host "Invoke-WebRequest $uri`r`n`t-method $method`r`n`t-headers $($logHeaders | convertto-json)`r`n`t-body $($body | convertto-json -depth 99)" -ForegroundColor Green
            $result = Invoke-WebRequest $uri -Method $method -Headers $headers -Body $json
        }
        else {
            write-host "Invoke-WebRequest $uri`r`n`t-method $method`r`n`t-headers $($logHeaders | convertto-json)" -ForegroundColor Green
            $result = Invoke-WebRequest $uri -Method $method -Headers $headers
        }

        $resultObj = $result.Content | convertfrom-json
        $resultJson = $resultObj | convertto-json -depth 99
        write-host "Invoke-WebRequest result:`r`n`t$resultJson" -ForegroundColor cyan
        $global:graphStatusCode = $result.StatusCode

        if (confirm-statusCodeSuccess -statusCode $global:graphStatusCode -method $method) {
            if ($resultObj) {
                return $resultObj
            }
            return $true
        }

        return $null
    }
    catch [System.Exception] {
        # 404 400
        $global:graphStatusCode = $psitem.Exception.Response.StatusCode.value__
        $errorString = "invoke-graphApiCall status: $($psitem.Exception.Response.StatusCode.value__)`r`nexception:`r`n$($psitem.Exception.Message)`r`n$($error | out-string)`r`n$($psitem.ScriptStackTrace)"

        if (!(confirm-graphApiRetry -statusCode $global:graphStatusCode)) {
            write-warning $errorString
        }
        else {
            Write-Verbose $errorString
            Write-Warning "invoke-graphApiCall response status: $global:graphStatusCode"
        }

        if (!$global:graphStatusCode) {
            # not a web exception
            throw $psitem.Exception
        }

        return $null
    }
}

function invoke-graphApi($uri, $headers = $global:ConfigObj.Headers, $body = '', $method = 'post', [switch]$retry) {
    $global:graphStatusCode = 0
    $stopTime = set-stopTime $TimeoutMin
    $count = 0

    while ((get-date) -le $stopTime) {
        $result = invoke-graphApiCall -uri $uri -headers $headers -body $body -method $method
        write-host "invoke-graphApi count:$(($count++).tostring()) statuscode:$($global:graphStatusCode) -uri $uri -headers $headers -body $body -method $method"

        if ($retry -and !(confirm-graphApiRetry $global:graphStatusCode) -and (confirm-statusCodeSuccess -statusCode $global:graphStatusCode -method $method)) {
            return $result
        }
        elseif (!$retry) {
            return $result
        }

        start-sleep -Seconds $sleepSeconds
    }
}

function set-stopTime($minutes) {
    $stopTime = [datetime]::now.AddMinutes($minutes)
    write-host "setting timeout to:$stopTime"
    return $stopTime
}

function wait-forResult([management.automation.functionInfo]$functionPointer, [string]$message, [datetime]$stopTime = [datetime]::MinValue, [switch]$waitForNullResult) {
    if ($stopTime -eq [datetime]::MinValue) {
        $stopTime = set-stopTime $TimeoutMin
    }

    while ((get-date) -le $stopTime) {

        $result = . $functionPointer.scriptblock @args
        write-host "$message`r`nfunction:$($functionPointer.Name)`r`nargs:$args`r`nresult:$result" -ForegroundColor Magenta

        if ($result -and !$waitForNullResult) {
            write-host "returning result:$($result | convertto-json)"
            return $result
        }
        elseif (!$result -and $waitForNullResult) {
            write-host "returning `$true for null result"
            return $true
        }

        Start-Sleep -Seconds $sleepSeconds
    }

    assert-notNull -obj $result -msg "timed out waiting for:$message"
}

function write-errorMessage($exceptionRecord) {
    $errorString = "exception: 
            $($exceptionRecord.Exception.Response.StatusCode.value__)

            exception message:
            $($exceptionRecord.Exception.Message)
            
            $($exceptionRecord.ScriptStackTrace)
            
            use -force switch to force new authorization to acquire new token.
            set `$global:ConfigObj to null to reset configuration.
        "
    write-error $errorString
    write-verbose  ($global:ConfigObj | convertto-json)
}

main

