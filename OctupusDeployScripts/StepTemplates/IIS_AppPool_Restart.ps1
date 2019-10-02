# Summary: Restarts an IIS Application Pool
# Parameters:
#{AppPoolName} - The name of the application pool in IIS.

# Load IIS module:
Import-Module WebAdministration

# Get AppPool Name
$appPoolName = $OctopusParameters['appPoolName']

if(Test-Path IIS:\AppPools\$appPoolName) {
    Write-Output "Starting IIS app pool $appPoolName"
    Restart-WebAppPool $appPoolName
} else {
    Write-Output "App pool ($appPoolName) does not exist"
}

