# Summary: Consolidates all Release Notes between the last successful release in the current Environment and this one by merging or concatenating them.
# Parameters: 
# #{Consolidate_ApiKey} - The API Key to use for authentication
# #{Consolidate_Dedupe} = True - Whether to remove duplicate lines when constructing release notes
# #{Consolidate_RemoveWhitespace} = True - Whether to remove blank lines when constructing release notes
# #{Consolidate_Order} = Newest - The order in which to append release notes

$baseUri = $OctopusParameters['Octopus.Web.BaseUrl']
$reqheaders = @{"X-Octopus-ApiKey" = $Consolidate_ApiKey }
$putReqHeaders = @{"X-HTTP-Method-Override" = "PUT"; "X-Octopus-ApiKey" = $Consolidate_ApiKey }

$remWhiteSpace = [bool]::Parse($Consolidate_RemoveWhitespace)
$deDupe = [bool]::Parse($Consolidate_Dedupe)
$reverse = ($Consolidate_Order -eq "Oldest")

# Get details we'll need
$projectId = $OctopusParameters['Octopus.Project.Id']
$thisReleaseNumber = $OctopusParameters['Octopus.Release.Number']
$lastSuccessfulReleaseId = $OctopusParameters['Octopus.Release.CurrentForEnvironment.Id']
$lastSuccessfulReleaseNumber = $OctopusParameters['Octopus.Release.CurrentForEnvironment.Number']

# Get all previous releases to this environment
$releaseUri = "$baseUri/api/projects/$projectId/releases"
try {
    $allReleases = Invoke-WebRequest $releaseUri -Headers $reqheaders -UseBasicParsing | ConvertFrom-Json
} catch {
    if ($_.Exception.Response.StatusCode.Value__ -ne 404) {
        $result = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.Io.StreamReader($result);
        $responseBody = $reader.ReadToEnd();
        throw "Error occurred: $responseBody"
    }
}

# Find and aggregate release notes
$aggregateNotes = @()

Write-Host "Finding all release notes between the last successful release: $lastSuccessfulReleaseNumber and this release: $thisReleaseNumber"
foreach ($rel in $allReleases.Items) {
    if ($rel.Id -ne $lastSuccessfulReleaseId) {
        Write-Host "Found release notes for $($rel.Version)"
        $theseNotes = @()
        #split into lines
        $lines = $rel.ReleaseNotes -split "`n"
        foreach ($line in $lines) {
            if (-not $remWhitespace -or -not [string]::IsNullOrWhiteSpace($line)) {
                if (-not $deDupe -or -not $aggregateNotes.Contains($line)) {
                    $theseNotes = $theseNotes + $line
                }
            }
        }
        if ($reverse) {
            $aggregateNotes = $theseNotes + $aggregateNotes
        } else {
            $aggregateNotes = $aggregateNotes + $theseNotes
        }
    } else {
        break
    }
}
$aggregateNotesText = $aggregateNotes -join "`n`n"

# Get the current release
$releaseUri = "$baseUri/api/projects/$projectId/releases/$thisReleaseNumber"
try {
    $currentRelease = Invoke-WebRequest $releaseUri -Headers $reqheaders -UseBasicParsing | ConvertFrom-Json
} catch {
    if ($_.Exception.Response.StatusCode.Value__ -ne 404) {
        $result = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.Io.StreamReader($result);
        $responseBody = $reader.ReadToEnd();
        throw "Error occurred: $responseBody"
    }
}

# Update the release notes for the current release
$currentRelease.ReleaseNotes = $aggregateNotesText
Write-Host "Updating release notes for $thisReleaseNumber`:`n`n"
Write-Host $aggregateNotesText
try {
    $releaseUri = "$baseUri/api/releases/$($currentRelease.Id)"
    $currentReleaseBody = $currentRelease | ConvertTo-Json
    $result = Invoke-WebRequest $releaseUri -Method Post -Headers $putReqHeaders -Body $currentReleaseBody -UseBasicParsing | ConvertFrom-Json
} catch {
    $result = $_.Exception.Response.GetResponseStream()
    $reader = New-Object System.Io.StreamReader($result);
    $responseBody = $reader.ReadToEnd();
    Write-Host $responseBody
    throw "Error occurred: $responseBody"
}