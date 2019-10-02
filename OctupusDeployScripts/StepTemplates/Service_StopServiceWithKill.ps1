# Summary: This step stops the specified service and in case it does not respond or times out, the service will be killed.
# Parameters:
#{ServiceName} - Name of the service to stop

$svcName = $OctopusParameters['ServiceName']

Write-Host "Checking for service " + $svcName
$svcpid = (get-wmiobject Win32_Service | where{$_.Name -eq $svcName}).ProcessId
Write-Host "Found PID " + $svcpid 

Stop-Service $svcName
Start-Sleep -seconds 10

$service = Get-Service -name $svcName | Select -Property Status
if($service.Status -ne "Stopped"){	Start-Sleep -seconds 5 }

#Check-Service process 
if($svcpid){
    #still exists?
    $p = get-process -id $svcpid -ErrorAction SilentlyContinue
    Write-Host "Rechecking PID"
    if($p){
        Write-Host "Killing Service"
        Stop-Process $p.Id -force
    }
}
