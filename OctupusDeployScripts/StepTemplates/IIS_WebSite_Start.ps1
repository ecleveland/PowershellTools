# Summary: Starts a website in IIS.
# Parameters: 
#{WebsiteName} - The name of the site in IIS

# Load IIS module:
Import-Module WebAdministration

# Set a name of the site we want to start
$webSiteName = $OctopusParameters['webSiteName']

if(Test-Path IIS:\Sites\$webSiteName) {
    # Get web site object
    $webSite = Get-Item "IIS:\Sites\$webSiteName"
    
    Write-Output "Starting IIS web site $webSiteName"
    $webSite.Start()
} else {
    Write-Output "Website ($webSiteName) does not exist"
}