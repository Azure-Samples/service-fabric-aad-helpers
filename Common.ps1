<#
.VERSION
1.0.4

.SYNOPSIS
Common script, do not call it directly.
#>

function logon-msal() {
    try {
        . "$PSScriptRoot\msal-logon"
        if (!$global:msal) {
            Write-error "error getting token."
        }

        $global:msal.Logon($resourceUrl) #.authenticationResult
        $msalResults = $global:msal.authenticationResult
        write-host "msal results $($msalResults | convertto-json)"
        return $msalResults
    }
    catch {
        Write-Warning $_.Exception.Message
    }

}

function GetRESTHeaders($msalResults) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", $msalResults.accessToken)
    return $headers
}

function CallGraphAPI($uri, $headers, $body, $method = "Post") {
    $json = $body | ConvertTo-Json -Depth 4 -Compress
    return (Invoke-RestMethod $uri -Method $method -Headers $headers -Body $json -ContentType "application/json")
}

function AssertNotNull($obj, $msg) {
    if ($obj -eq $null -or $obj.Length -eq 0) { 
        Write-Warning $msg
        Exit
    }
}

# Regional settings
switch ($Location) {
    "china" {
        $resourceUrl = "https://graph.chinacloudapi.cn"
        $authString = "https://login.partner.microsoftonline.cn/" + $TenantId
    }
    
    "germany" {
        $resourceUrl = "https://graph.cloudapi.de"
        $authString = "https://login.microsoftonline.de/" + $TenantId   
    }

    default {
        $resourceUrl = "https://graph.windows.net"
        $authString = "https://login.microsoftonline.com/" + $TenantId
    }
}

$headers = GetRESTHeaders -msalResults (logon-msal)

if ($ClusterName) {
    $WebApplicationName = $ClusterName + "_Cluster"
    $WebApplicationUri = "https://$ClusterName"
    $NativeClientApplicationName = $ClusterName + "_Client"
}
