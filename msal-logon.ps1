[cmdletbinding()]
param(
    [string]$identityPackageLocation,
    [string]$token,
    [string]$clientSecret,
    [string]$clientId = "1950a258-227b-4e31-a9cf-717495945fc2",
    [string]$tenantId = "common",
    [string]$redirectUri = "http://localhost", # "urn:ietf:wg:oauth:2.0:oob", #$null
    [bool]$force
)

$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = "continue"
$global:identityPackageLocation  

function AddIdentityPackageType([string]$packageName, [string] $edition) {
    # support ps core on linux
    if ($IsLinux) { 
        $env:USERPROFILE = $env:HOME
    }
    [string]$nugetPackageDirectory = "$($env:USERPROFILE)/.nuget/packages"
    [string]$nugetSource = "https://api.nuget.org/v3/index.json"
    [string]$nugetDownloadUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
    [io.directory]::createDirectory($nugetPackageDirectory)
    [string]$packageDirectory = "$nugetPackageDirectory/$packageName"
    
    $global:identityPackageLocation = @(get-childitem -Path $packageDirectory -Recurse | where-object FullName -imatch "lib.$edition.$packageName\.dll" | select-object FullName)[-1].FullName

    if (!$global:identityPackageLocation) {
        if ($psedition -ieq 'core') {
            $packageVersion = "4.28.0"
            $tempProjectFile = './temp.csproj'
    
            #dotnet new console 
            $csproj = "<Project Sdk=`"Microsoft.NET.Sdk`">
                    <PropertyGroup>
                        <OutputType>Exe</OutputType>
                        <TargetFramework>$edition</TargetFramework>
                    </PropertyGroup>
                    <ItemGroup>
                        <PackageReference Include=`"$packageName`" Version=`"$packageVersion`" />
                    </ItemGroup>
                </Project>
            "

            out-file -InputObject $csproj -FilePath $tempProjectFile
            dotnet restore --packages $packageDirectory --no-cache --no-dependencies $tempProjectFile
    
            remove-item "$pwd/obj" -re -fo
            remove-item -path $tempProjectFile
        }
        else {
            $nuget = "nuget.exe"    
            if (!(test-path $nuget)) {
                $nuget = "$env:temp/nuget.exe"
                if (!(test-path $nuget)) {
                    invoke-webRequest $nugetDownloadUrl -outFile  $nuget
                }
            }
            [string]$localPackages = . $nuget list -Source $nugetPackageDirectory

            if ($force -or !($localPackages -imatch "$edition.$packageName")) {
                write-host "$nuget install $packageName -Source $nugetSource -outputdirectory $nugetPackageDirectory -verbosity detailed"
                . $nuget install $packageName -Source $nugetSource -outputdirectory $nugetPackageDirectory -verbosity detailed
            }
            else {
                write-host "$packageName already installed" -ForegroundColor green
            }
        }
    }
    
    $global:identityPackageLocation = @(get-childitem -Path $packageDirectory -Recurse | where-object FullName -imatch "lib.$edition.$packageName\.dll" | select-object FullName)[-1].FullName
    write-host "identityDll: $($global:identityPackageLocation)" -ForegroundColor Green
    add-type -literalPath $global:identityPackageLocation
    return $true
}

# Install latest AD client library
if ($global:PSVersionTable.PSEdition -eq "Core") {
    if (!(AddIdentityPackageType -packageName "Microsoft.Identity.Client" -edition "netcoreapp2.1")) {
        write-error "unable to add package"
        return $false
    }
}
else {
    if (!(AddIdentityPackageType -packageName "Microsoft.Identity.Client" -edition "net461")) {
        write-error "unable to add package"
        return $false
    }
}

# comment next line after microsoft.identity.client type has been imported into powershell session to troubleshoot 1 of 2
invoke-expression @'

class MsalLogon {
    [string]$identityPackageLocation = $identityPackageLocation
    [object]$authenticationResult
    hidden [Microsoft.Identity.Client.ConfidentialClientApplication] $confidentialClientApplication = $null
    [string]$clientId = $clientId
    hidden [string]$clientSecret = $clientSecret
    [bool]$Force = $force
    hidden [Microsoft.Identity.Client.PublicClientApplication] $publicClientApplication = $null
    [bool]$PipeLine = $null
    [string]$redirectUri = $redirectUri
    [object]$Result = $null
    [object]$ResultObject = $null
    [string]$tenantId = $tenantId
    [string]$token = $token
        
    MsalLogon() { }
    static MsalLogon() { }


    [bool] Logon([string]$resourceUrl) {
        [int]$expirationRefreshMinutes = 15
        [int]$expirationMinutes = 0

        if (!$resourceUrl) {
            write-warning "-resourceUrl required. example: https://{{ kusto cluster }}.kusto.windows.net"
            return $false
        }

        if ($this.authenticationResult) {
            $expirationMinutes = $this.authenticationResult.ExpiresOn.Subtract((get-date)).TotalMinutes
        }
        write-verbose "token expires in: $expirationMinutes minutes"

        if (!$this.Force -and ($expirationMinutes -gt $expirationRefreshMinutes)) {
            write-verbose "token valid: $($this.authenticationResult.ExpiresOn). use -force to force logon"
            return $true
        }
        return $this.LogonMsal($resourceUrl, @("$resourceUrl/msal.read", "$resourceUrl/msal.write"))
    }

    hidden [bool] LogonMsal([string]$resourceUrl, [string[]]$scopes) {
        try {
            $error.Clear()
            [string[]]$defaultScope = @(".default")
            
            if ($this.clientId -and $this.clientSecret) {
                [string[]]$defaultScope = @("$resourceUrl/.default")
                [Microsoft.Identity.Client.ConfidentialClientApplicationOptions] $cAppOptions = new-Object Microsoft.Identity.Client.ConfidentialClientApplicationOptions
                $cAppOptions.ClientId = $this.clientId
                $cAppOptions.RedirectUri = $this.redirectUri
                $cAppOptions.ClientSecret = $this.clientSecret
                $cAppOptions.TenantId = $this.tenantId

                [Microsoft.Identity.Client.ConfidentialClientApplicationBuilder]$cAppBuilder = [Microsoft.Identity.Client.ConfidentialClientApplicationBuilder]::CreateWithApplicationOptions($cAppOptions)
                $cAppBuilder = $cAppBuilder.WithAuthority([microsoft.identity.client.azureCloudInstance]::AzurePublic, $this.tenantId)

                if ($global:PSVersionTable.PSEdition -eq "Core") {
                    $cAppBuilder = $cAppBuilder.WithLogging($this.MsalLoggingCallback, [Microsoft.Identity.Client.LogLevel]::Verbose, $true, $true )
                }

                $this.confidentialClientApplication = $cAppBuilder.Build()
                write-verbose ($this.confidentialClientApplication | convertto-json)

                try {
                    write-host "acquire token for client" -foregroundcolor green
                    $this.authenticationResult = $this.confidentialClientApplication.AcquireTokenForClient($defaultScope).ExecuteAsync().Result
                }
                catch [Exception] {
                    write-host "error client acquire error: $_`r`n$($error | out-string)" -foregroundColor red
                    $error.clear()
                }
            }
            else {
                # user creds
                [Microsoft.Identity.Client.PublicClientApplicationBuilder]$pAppBuilder = [Microsoft.Identity.Client.PublicClientApplicationBuilder]::Create($this.clientId)
                $pAppBuilder = $pAppBuilder.WithAuthority([microsoft.identity.client.azureCloudInstance]::AzurePublic, $this.tenantId)
                
                if (!($this.publicClientApplication)) {
                    if ($global:PSVersionTable.PSEdition -eq "Core") {
                        $pAppBuilder = $pAppBuilder.WithDefaultRedirectUri()
                        $pAppBuilder = $pAppBuilder.WithLogging($this.MsalLoggingCallback, [Microsoft.Identity.Client.LogLevel]::Verbose, $true, $true )
                    }
                    else {
                        $pAppBuilder = $pAppBuilder.WithRedirectUri($this.redirectUri)
                    }
                    $this.publicClientApplication = $pAppBuilder.Build()
                }
                    
                write-verbose ($this.publicClientApplication | convertto-json)

                [Microsoft.Identity.Client.IAccount]$account = $this.publicClientApplication.GetAccountsAsync().Result[0]
                #preauth with .default scope
                try {
                    write-host "preauth acquire token silent for account: $account" -foregroundcolor green
                    $this.authenticationResult = $this.publicClientApplication.AcquireTokenSilent($defaultScope, $account).ExecuteAsync().Result
                    if (!$this.authenticationResult) { throw }
                }
                catch [Exception] {
                    write-host "preauth acquire error: $_`r`n$($error | out-string)" -foregroundColor yellow
                    $error.clear()
                    try {
                        write-host "preauth acquire token interactive" -foregroundcolor yellow
                        $this.authenticationResult = $this.publicClientApplication.AcquireTokenInteractive($defaultScope).ExecuteAsync().Result
                        if (!$this.authenticationResult) { throw }
                    }
                    catch [Exception] {
                        write-host "preauth acquire token device" -foregroundcolor yellow
                        $this.authenticationResult = $this.publicClientApplication.AcquireTokenWithDeviceCode($defaultScope, $this.MsalDeviceCodeCallback).ExecuteAsync().Result
                        if (!$this.authenticationResult) { throw }
                    }
                }

                write-host "authentication result: $($this.authenticationResult)"
                $account = $this.publicClientApplication.GetAccountsAsync().Result[0]

                #add msal scopes after preauth
                if ($scopes) {
                    try {
                        write-host "msal acquire token silent" -foregroundcolor green
                        $this.authenticationResult = $this.publicClientApplication.AcquireTokenSilent($scopes, $account).ExecuteAsync().Result
                    }
                    catch [Exception] {
                        write-host "msal acquire error: $_`r`n$($error | out-string)" -foregroundColor red
                        $error.clear()
                    }
                }
            }

            if ($this.authenticationResult) {
                write-host "authenticationResult:$($this.authenticationResult | convertto-json)"
                $this.Token = $this.authenticationResult.AccessToken
                return $true
            }
            return $false
        }
        catch {
            Write-Error "$($error | out-string)"
            return $false
        }
    }

    [Threading.Tasks.Task] MsalDeviceCodeCallback([Microsoft.Identity.Client.DeviceCodeResult] $result) {
        write-host "MSAL Device code result: $($result | convertto-json)"
        return [threading.tasks.task]::FromResult(0)
    }

    [void] MsalLoggingCallback([Microsoft.Identity.Client.LogLevel] $level, [string]$message, [bool]$containsPII) {
        write-verbose "MSAL: $level $containsPII $message"
    }    
}

# comment next line after microsoft.identity.client type has been imported into powershell session to troubleshoot 2 of 2
'@ 

$error.Clear()
$global:msal = [MsalLogon]::new()

if ($error) {
    write-verbose ($error | out-string)
    $error.Clear()
}
else {
    write-host ($msal | Get-Member | out-string)
    write-host "use `$msal object to get authentication results" -ForegroundColor Green
}
