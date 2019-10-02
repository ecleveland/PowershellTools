# Summary: Uninstalls a TopShelf service to prep a deploy.
# Parameters:
#{ServiceName} - The service name (not the display name). Can be found by right clicking a service in the Services window and clicking properties. ONLY copy what comes BEFORE the $. The $ is a separator and everything after it is the Instance Name.
#{InstanceName} - The instance name for this top shelf service. It comes after the $ in the service name in the Services window.

function Get-ServiceExePath ($name)
{
    $service = Get-WmiObject win32_service | ?{$_.Name -eq $name} 
    $path = $service | select @{Name="Path"; Expression={$_.PathName.split('"')[1]}} 
    $path.Path
}

$ServiceName = $OctopusParameters['ServiceName']
$InstanceName = $OctopusParameters['InstanceName']

$ServiceNameFull = $ServiceName
[System.String[]]$paramArr = @("uninstall")
if(![string]::IsNullOrWhiteSpace($InstanceName))
{
    $ServiceNameFull += "$" + $InstanceName
    $paramArr += "-instance:$InstanceName"
}

$ExePath = Get-ServiceExePath $ServiceNameFull

Write-Host "Removing service: $ServiceNameFull"
if ($ExePath)
{
    
    Write-Host "Service executable: $ExePath"
    & $ExePath $paramArr
    Write-Host "Service removed."
}
else
{
    Write-Host "Service not found: $ServiceNameFull"
}