# Summary: Deploy a package using Git to a HTTPS server. Performs a clone, overwrites the repository with the files from your package, then merges the hotfix into master.
# Parameters:
#{RepoName} - The name of the repository in VSTS
#{Username} - Username to use when authenticating with the HTTPS server.
#{Password} - Password to use when authenticating with the HTTPS server. You should create a sensitive variable in your project variables, and then bind this value.
#{GitHttpsPackageStepName} - Name of the previously-deployed package step that contains the files that you want to push.

[System.Reflection.Assembly]::LoadWithPartialName("System.Web")

# A collection of functions that can be used by script steps to determine where packages installed
# by previous steps are located on the filesystem.

function Find-InstallLocations {
    $result = @()
    
    $OctopusParameters.Keys | foreach {
        if ($_.EndsWith('].Output.Package.InstallationDirectoryPath')) {
           $result += $OctopusParameters[$_]
        }
    }
    
    return $result
}

function Find-InstallLocation($stepName) {
    $result = $OctopusParameters.Keys | where {
        $_.Equals("Octopus.Action[$stepName].Output.Package.InstallationDirectoryPath",  [System.StringComparison]::OrdinalIgnoreCase)
    } | select -first 1

    if ($result) {
        return $OctopusParameters[$result]
    }
    
     throw "No install location found for step: $stepName"
}

function Find-SingleInstallLocation {
    $all = @(Find-InstallLocations)
    
    if ($all.Length -eq 1) {
        return $all[0]
    }
    
    if ($all.Length -eq 0) {
        throw "No package steps found"
    }
    
    throw "Multiple package steps have run; please specify a single step"
}

function Format-UriWithCredentials($url, $username, $password) {
    $uri = New-Object "System.Uri" $url
    
    $url = $uri.Scheme + "://"

    if (-not [string]::IsNullOrEmpty($username)) {
        $url = $url + [System.Web.HttpUtility]::UrlEncode($username)
        
        if (-not [string]::IsNullOrEmpty($password)) {
            $url = $url + ":" + [System.Web.HttpUtility]::UrlEncode($password)  
        }
        
        $url = $url + "@"    
    } elseif (-not [string]::IsNullOrEmpty($uri.UserInfo)) {
        $url = $uri.UserInfo + "@"
    }

    $url = $url + $uri.Host + $uri.PathAndQuery
    return $url
}

function Test-LastExit($cmd) {
    if ($LastExitCode -ne 0) {
        Write-Host "##octopus[stderr-error]"
        write-error "$cmd failed with exit code: $LastExitCode"
    }
}

$tempDirectoryPath = $OctopusParameters['Octopus.Tentacle.Agent.ApplicationDirectoryPath']
$tempDirectoryPath = join-path $tempDirectoryPath "GitMerge" 
$tempDirectoryPath = join-path $tempDirectoryPath $OctopusParameters['Octopus.Environment.Name']
$tempDirectoryPath = join-path $tempDirectoryPath $OctopusParameters['Octopus.Project.Name']
$tempDirectoryPath = join-path $tempDirectoryPath $OctopusParameters['Octopus.Action.Name']

$stepName = $OctopusParameters['GitHttpsPackageStepName']

$stepPath = ""

if (-not [string]::IsNullOrEmpty($stepName)) {
    Write-Host "Finding path to package step: $stepName"
    $stepPath = Find-InstallLocation $stepName
} else {
    $stepPath = Find-SingleInstallLocation
}

Write-Host "Package was installed to: $stepPath"

Write-Host "Repository will be cloned to: $tempDirectoryPath"

# Step 1: Ensure we have the latest version of the repository

mkdir $tempDirectoryPath -ErrorAction SilentlyContinue
cd $tempDirectoryPath

Write-Host "##octopus[stderr-progress]"

git init

$branch = git rev-parse --abbrev-ref head
Test-LastExit "git init"

$url = Format-UriWithCredentials -url 'https://pier1.visualstudio.com/DefaultCollection/Ecommerce/_git/'+$OctopusParameters['RepoName'] -username $OctopusParameters['Username'] -password $OctopusParameters['Password']

git remote remove origin
git remote add origin $url

git fetch origin
git checkout master

git merge $branch

git push -u origin master

cd ..
remove-item -recurse -force $tempDirectoryPath