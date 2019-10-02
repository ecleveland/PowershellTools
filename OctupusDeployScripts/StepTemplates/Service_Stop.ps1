# Summary: Stops a Windows Service if it is running.
# Parameters:
#{ServiceName} - Name of the Windows Service (this is not always the display name).

$serviceName = $OctopusParameters['ServiceName']

Write-Output "Stopping $serviceName..."

$serviceInstance = Get-Service $serviceName -ErrorAction SilentlyContinue
if ($serviceInstance -ne $null) {
    Stop-Service $serviceName -Force
    $serviceInstance.WaitForStatus('Stopped', '00:01:00')
    Write-Output "Service $serviceName stopped."
} else {
    Write-Output "The $serviceName service could not be located."
}
