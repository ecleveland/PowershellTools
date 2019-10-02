#{BackupSource} - The source directory where files and folders will be copied from
#{BackupDestination} - The Destination where the files will be copied to.
#{Options} = /E /V - Robocopy accepts a few command line options (e.g. /S /E /Z). List of these http://ss64.com/nt/robocopy.html
#{CreateStampedBackupFolder} = True - If set to True then it will create a dated backup folder under the destination folder (e.g. c:\backup\2014-05-11)
function Get-Stamped-Destination($BackupDestination) {
	$stampedFolderName = get-date -format "yyyy-MM-dd"
	$count = 1
	$stampedDestination = Join-Path $BackupDestination $stampedFolderName
	while(Test-Path $stampedDestination) {
		$count++
		$stamped = $stampedFolderName + "(" + $count + ")"
		$stampedDestination = Join-Path $BackupDestination $stamped
	}
	return $stampedDestination
}

$BackupSource = $OctopusParameters['BackupSource']
$BackupDestination = $OctopusParameters['BackupDestination']
$CreateStampedBackupFolder = $OctopusParameters['CreateStampedBackupFolder']
if($CreateStampedBackupFolder -like "True" ) {
	$BackupDestination = get-stamped-destination $BackupDestination
}

$options = $OctopusParameters['Options'] -split "\s+"

if(Test-Path -Path $BackupSource) {
    robocopy $BackupSource $BackupDestination $options
}

if($LastExitCode -gt 8) {
    exit 1
}
else {
    exit 0
}
