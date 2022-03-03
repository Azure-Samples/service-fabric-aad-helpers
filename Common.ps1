﻿<#
.VERSION
1.0.4

.SYNOPSIS
Common script, do not call it directly.
#>

if ($headers) {
    Exit
}

Try {
    # Install latest AD client library
    $nuget = "nuget.exe"
    if (!(test-path $nuget)) {
        $nugetDownloadUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
        invoke-webRequest $nugetDownloadUrl -outFile $nuget
    }

    $env:path = $env:path.replace(";$pwd;", "") + ";$pwd;"
    $ADPackage = "Microsoft.IdentityModel.Clients.ActiveDirectory"
    & nuget.exe install $ADPackage > nuget.log

    # Target .NET Framework version of the DLL
    $FilePath = (Get-Item .\\Microsoft.IdentityModel.Clients.ActiveDirectory.[0-9].[0-9].[0-9]\\lib\\net[0-9][0-9]\\Microsoft.IdentityModel.Clients.ActiveDirectory.dll).FullName | Resolve-Path -Relative
    Add-Type -Path $FilePath
}
Catch {
    Write-Warning $_.Exception.Message
}

function GetRESTHeaders() {
    # Use common client 
    $clientId = "1950a258-227b-4e31-a9cf-717495945fc2"
    $redirectUrl = "urn:ietf:wg:oauth:2.0:oob"
    
    $authenticationContext = New-Object Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext -ArgumentList $authString, $FALSE
    
    $PromptBehavior = [Microsoft.IdentityModel.Clients.ActiveDirectory.PromptBehavior]::RefreshSession
    $PlatformParameters = New-Object Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters -ArgumentList $PromptBehavior
    $accessToken = $authenticationContext.AcquireTokenAsync($resourceUrl, $clientId, $redirectUrl, $PlatformParameters).Result.AccessToken

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", $accessToken)
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

$headers = GetRESTHeaders

if ($ClusterName) {
    $WebApplicationName = $ClusterName + "_Cluster"
    $WebApplicationUri = "https://$ClusterName"
    $NativeClientApplicationName = $ClusterName + "_Client"
}
