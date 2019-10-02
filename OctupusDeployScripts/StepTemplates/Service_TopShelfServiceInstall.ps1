# Summary: Installs a top shelf service the way we want. Don't expect all the configurations, here.
# Parameters:
#{InstanceName}
#{Username}
#{Password}
#{ExeName} - The executable name to run, relative to the custom installation directory path.
#{PackageID} - The ID of the package you want to install.
#{RunConfigVariables} = True - Replace appSettings and connectionString entries in any .config files
#{RunConfigTransforms} = True - Runs configuration file transforms, such as Web.Release.config
#{AdditionalConfigTransforms} - A comma- or newline-separated list of additional configuration transformation file rules. Example: > Web.Release.config => Web.config
<# 
    .Foo.config => *.config crossdomainpolicy.#{Octopus.Environment.Name}.xml => crossdomainpolicy.xml If your configuration file is named Bar.xml, and your transformation file is named Foo.xml, you should enter Foo.xml=>Bar.xml. Wildcards are supported so if you have config files named xyz.Bar.config and abc.Bar.config, and you have transform files named xyz.Foo.config and abc.Foo.config, you may enter *.Foo.config=>.Bar.config
#>
#{ServiceName} - The name of the service to install
#{InstallationDirectory} - The directory to install the package to.
#{InstallationDirectoryPurge} = True - Clear installation directory before install.
#{StartRoles} - The service will be started only on machines with these roles. Comma separated. Empty list will run on all roles.

# Pre deployment script

# Deployment script

# Post deployment script
$exe = $OctopusParameters['Octopus.Action.Package.CustomInstallationDirectory'] + "`\" + $OctopusParameters['ExeName']
$ServiceName = $OctopusParameters['ServiceName']
$InstanceName = $OctopusParameters['InstanceName']
$Username = $OctopusParameters['Username']
$Password = $OctopusParameters['Password']
$RolesToRunString = $OctopusParameters['StartRoles']
$MachineRolesString = $OctopusParameters['Octopus.Machine.Roles']

$RolesToRun = $null
if(![string]::IsNullOrWhiteSpace($RolesToRunString)){
    $RolesToRun = $RolesToRunString.Split(',').Trim()
}

[string[]]$MachineRoles = @()
if(![string]::IsNullOrWhiteSpace($MachineRolesString)){
    $MachineRoles = $MachineRolesString.Split(',').Trim()
}


$ServiceNameFull = $ServiceName
[System.String[]]$paramArr = @("install")
if(![string]::IsNullOrWhiteSpace($InstanceName))
{
    $ServiceNameFull += "$" + $InstanceName
    $paramArr += ("-instance:" + $InstanceName)
}
if(![string]::IsNullOrWhiteSpace($Username) -and ![string]::IsNullOrWhiteSpace($Password))
{
    $paramArr += ("-username:" + $Username)
    $paramArr += ("-password:" + $Password)
}

$StartService = $false
write-host "Only running on roles:" 
write-host $RolesToRun
write-host "Machine has roles:" 
write-host $MachineRoles
if($RolesToRun -eq $null -or ($RolesToRun | ?{$MachineRoles -contains $_})){
    $StartService = $true
} 

if($StartService)
{
    $paramArr += "--autostart"
}
else 
{
    $paramArr += "--manual"
}

write-host "Installing service:  $ServiceNameFull"
write-host "Executable:  $exe"
& $exe $paramArr
write-host "Service installed:  $ServiceNameFull"
if($StartService)
{
    Start-Service $ServiceNameFull
    write-host "Service started:  $ServiceNameFull"
}