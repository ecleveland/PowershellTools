# Summary: Ensures that a set of Windows Features are installed on the system.
# Parameters: 
#{WindowsFeatures} - The set of Windows Features that should be installed on the system. This can be either a single Windows Feature or a comma separated list of Windows Features to check.
<# 
    Example 1: IIS-WebServer
    Example 2: IIS-WebServer, IIS-WindowsAuthentication
#>

#{SuppressReboot} = False - Suppresses reboot. If a reboot is not necessary, then this option does nothing. This option will keep DISM.exe from prompting for a restart, or from restarting automatically).

$requiredFeatures = $OctopusParameters['WindowsFeatures'].split(",") | foreach { $_.trim() }
if(! $requiredFeatures) {
    Write-Output "No required Windows Features specified..."
    exit
}
$requiredFeatures | foreach { $feature = DISM.exe /ONLINE /Get-FeatureInfo /FeatureName:$_; if($feature -like "*Feature name $_ is unknown*") { throw $feature } }

Write-Output "Retrieving all Windows Features..."
$allFeatures = DISM.exe /ONLINE /Get-Features /FORMAT:List | Where-Object { $_.StartsWith("Feature Name") -OR $_.StartsWith("State") } 
$features = new-object System.Collections.ArrayList
for($i = 0; $i -lt $allFeatures.length; $i=$i+2) {
    $feature = $allFeatures[$i]
    $state = $allFeatures[$i+1]
    $features.add(@{feature=$feature.split(":")[1].trim();state=$state.split(":")[1].trim()}) | OUT-NULL
}

Write-Output "Checking for missing Windows Features..."
$missingFeatures = new-object System.Collections.ArrayList
$features | foreach { if( $requiredFeatures -contains $_.feature -and $_.state -eq 'Disabled') { $missingFeatures.add($_.feature) | OUT-NULL } }
if(! $missingFeatures) {
    Write-Output "All required Windows Features are installed"
    exit
}
Write-Output "Installing missing Windows Features..."
$featureNameArgs = ""
$missingFeatures | foreach { $featureNameArgs = $featureNameArgs + " /FeatureName:" + $_ }
$dism = "DISM.exe"
IF ($SuppressReboot)
{
    $arguments = "/NoRestart "
}
ELSE
{
    $arguments = ""
}
$arguments = $arguments + "/ONLINE /Enable-Feature /All $featureNameArgs"
Write-Output "Calling DISM with arguments: $arguments"
start-process -NoNewWindow $dism $arguments