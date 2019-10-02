# Summary: Sets the Load User Profile setting on the app pool to true.
# Parameters:
# #{AppPoolName} - The name of the app pool to load the user profile on.
Import-Module WebAdministration
$AppPoolName = $OctopusParameters['AppPoolName']
Set-ItemProperty ("IIS:\AppPools\" + $AppPoolName) -Name "processModel.loadUserProfile" -Value "True"