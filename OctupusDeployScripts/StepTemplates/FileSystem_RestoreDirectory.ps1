# Summary: Restores a folder and it's contents (files and sub-folders).
# Parameters:
#{Source} - The source directory where files and folders will be copied from
#{Destination} - The Destination where the files will be copied to.

$source = $OctopusParameters['Source']
$destination = $OctopusParameters['Destination']

if(Test-Path $destination)
{
    ## Clean the destination folder
    Write-Host "Cleaning $destination"
    Remove-Item $destination -Recurse
}

## Copy recursively
Write-Host "Copying from $source to $destination"
Copy-Item $source $destination -Recurse