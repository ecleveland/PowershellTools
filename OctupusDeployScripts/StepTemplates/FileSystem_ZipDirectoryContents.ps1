# Summary: Creates a zip archive that contains the files and directories from the specified directory, uses the specified compression level, and optionally includes the base directory. - Requires .NET 4.5 as it relies on the `System.IO.Compression.ZipFile` class.
# Parameters:
#{SourceDirectoryName} - The path to the directory to be archived, specified as a relative or absolute path.
#{DestinationArchiveFileName} - The path of the archive to be created, specified as a relative or absolute path.
#{CompressionLevel} = Optimal - Indicates whether to emphasize speed or compression effectiveness when creating the entry.
#{IncludeBaseDirectory} - Include the directory name from Source Directory at the root of the archive.
#{OverwriteDestination} - Overwrite the destination archive file if it already exists.

$SourceDirectoryName = $OctopusParameters['SourceDirectoryName']
$DestinationArchiveFileName = $OctopusParameters['DestinationArchiveFileName']
$CompressionLevel = $OctopusParameters['CompressionLevel']
$IncludeBaseDirectory = $OctopusParameters['IncludeBaseDirectory']
$OverwriteDestination = $OctopusParameters['OverwriteDestination']

if (!$SourceDirectoryName)
{
    Write-Error "No Source Directory name was specified. Please specify the name of the directory to that will be zipped."
    exit -2
}

if (!$DestinationArchiveFileName)
{
    Write-Error "No Destination Archive File name was specified. Please specify the name of the zip file to be created."
    exit -2
}

if (($OverwriteDestination) -and (Test-Path $DestinationArchiveFileName))
{
    Write-Host "$DestinationArchiveFileName already exists. Will delete it before we create a new zip file with the same name."
    Remove-Item $DestinationArchiveFileName
}

Write-Host "Creating Zip file $DestinationArchiveFileName with the contents of directory $SourceDirectoryName using compression level $CompressionLevel"

[Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem")
[System.IO.Compression.ZipFile]::CreateFromDirectory($SourceDirectoryName, $DestinationArchiveFileName, $CompressionLevel, $IncludeBaseDirectory)
