# Summary: Makes a GET request to a HTTP(S) end point and verifies that a particular status code and response (optional) is returned within a specified period of time
# Parameters: 
#{Uri} - The full Uri of the endpoint
#{ExpectedCode} = 200 - The expected HTTP status code
#{TimeoutSeconds} = 60 - The number of seconds before the step fails and times out
#{BasicAuthUsername} - Username for Basic authentication. Leave blank to use Anonymous.
#{BasicAuthPassword} - Password for Basic authentication. Leave blank for Anonymous.
#{UseWindowsAuth} = False - Should the request be made passing windows authentication (kerberos) credentials
#{ExpectedResponse} - The response should be this text

$uri = $OctopusParameters['Uri']
$expectedCode = [int] $OctopusParameters['ExpectedCode']
$timeoutSeconds = [int] $OctopusParameters['TimeoutSeconds']
$Username = $OctopusParameters['AuthUsername']
$Password = $OctopusParameters['AuthPassword']
$UseWindowsAuth = $OctopusParameters['UseWindowsAuth']
$ExpectedResponse = $OctopusParameters['ExpectedResponse']


Write-Host "Starting verification request to $uri"
Write-Host "Expecting response code $expectedCode."
Write-Host "Expecting response: $ExpectedResponse."


$timer = [System.Diagnostics.Stopwatch]::StartNew()
$success = $false
do
{
    try
    {
        if ($Username -and $Password -and $UseWindowsAuth)
			{
			    Write-Host "Making request to $uri using windows authentication for user $Username"
			    $request = [system.Net.WebRequest]::Create($uri)
			    $Credential = New-Object System.Management.Automation.PSCredential -ArgumentList $Username, $(ConvertTo-SecureString -String $Password -AsPlainText -Force)
                $request.Credentials = $Credential 
                
                try
                {
                    $response = $request.GetResponse()
                }
                catch [System.Net.WebException]
                {
                    Write-Host "Request failed :-( System.Net.WebException"
                    Write-Host $_.Exception
                    $response = $_.Exception.Response
                }
                
			}
		elseif ($Username -and $Password)
			{
			    Write-Host "Making request to $uri using basic authentication for user $Username"
				$Credential = New-Object System.Management.Automation.PSCredential -ArgumentList $Username, $(ConvertTo-SecureString -String $Password -AsPlainText -Force)
				$response = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -Credential $Credential
			}
		else
			{
			    Write-Host "Making request to $uri using anonymous authentication"
				$response = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing
			}
        
        $code = $response.StatusCode
        $body = $response.Content;
        Write-Host "Recieved response code: $code"
        Write-Host "Recieved response: $body"

        if($response.StatusCode -eq $expectedCode)
        {
            $success = $true
        }
        if ($success -and $ExpectedResponse)
        {
            $success = ($ExpectedResponse -eq $body)
        }
    }
    catch
    {
        # Anything other than a 200 will throw an exception so
        # we check the exception message which may contain the 
        # actual status code to verify
        
        Write-Host "Request failed :-("
        Write-Host $_.Exception

        if($_.Exception -like "*($expectedCode)*")
        {
            $success = $true
        }
    }

    if(!$success)
    {
        Write-Host "Trying again in 5 seconds..."
        Start-Sleep -s 5
    }
}
while(!$success -and $timer.Elapsed -le (New-TimeSpan -Seconds $timeoutSeconds))

$timer.Stop()

# Verify result

if(!$success)
{
    throw "Verification failed - giving up."
}

Write-Host "Sucesss! Found status code $expectedCode"