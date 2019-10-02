# Summary: Deploys a Service Fabric application using a port of the MSFT VSTS Service Fabric deployment step template.
# Parameters:
#{PublishProfilePath} - The path to the configuration file containing the publish profile settings for specific environments.
#{SFClusterEndpoint} - The url of the service fabric cluster to be deployed to.
#{SFClusterAuthScheme} = None - The authentication method used by the Service Fabric Cluster
#{SFClusterAuthCertThumbprint} - If an authentication method is enabled on the cluster, the thumbprint of the certificate used to secure the cluster is required. If the thumbprint is specified in the publish profile, then this value WILL OVERRIDE the value listed in the publish profile.
#{ApplicationParameterFile} - Path to the application parameters file. If specified, this will override the value in the publish profile.
#{OverridePublishProfileSettings} = False - This will override all upgrade settings with either the value specified below or the default value if not specified.
#{IsUpgrade} = False - No effect unless "Override All Publish Profile Upgrade Settings" above is checked.
#{UpgradeMode} = Monitored - No effect unless the previous two checkboxes are checked.
#{PackageId} - The id of the octopus deploy package that contains the service fabric deployment files.
#{ApplicationPackagePath} - The filename of the service fabric (.sfpkg) package.

# Deployment Script
function Expand-ToFolder
{
    <#
    .SYNOPSIS 
    Unzips the zip file to the specified folder.
    .PARAMETER From
    Source location to unzip
    .PARAMETER Name
    Folder name to expand the files to.
    #>

    [CmdletBinding()]
    Param
    (
        [String]
        $File,
        
        [String]
        $Destination
    )

    if (!(Test-Path $File))
    {
        return
    }    
    
    if (Test-Path $Destination)
    {
        Remove-Item -Path $Destination -Recurse -ErrorAction Stop | Out-Null
    }

    New-Item $Destination -ItemType directory | Out-Null


    Write-Verbose -Message ("Attempting to unzip '" + $File + "' to location '" + $Destination + "'.")
    try 
    {
        [System.Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem") | Out-Null 
        [System.IO.Compression.ZipFile]::ExtractToDirectory("$File", "$Destination") 
    } 
    catch 
    { 
        Write-Error -Message ("Unexpected Error. Error details: " + $_.Exception.Message)
    } 
}

function Get-NamesFromApplicationManifest
{
    <#
    .SYNOPSIS 
    Returns an object containing common information from the application manifest.
    .PARAMETER ApplicationManifestPath
    Path to the application manifest file.    
    #>

    [CmdletBinding()]
    Param
    (
        [String]
        $ApplicationManifestPath
    )

    if (!(Test-Path $ApplicationManifestPath))
    {
        throw ("Path '" + $ApplicationManifestPath + "' does not exist.")
    }

    
    $appXml = [xml] (Get-Content $ApplicationManifestPath)
    if (!$appXml)
    {
        return
    }

    $appMan = $appXml.ApplicationManifest
    $FabricNamespace = 'fabric:'
    $appTypeSuffix = 'Type'

    $h = @{
        FabricNamespace = $FabricNamespace;
        ApplicationTypeName = $appMan.ApplicationTypeName;
        ApplicationTypeVersion = $appMan.ApplicationTypeVersion;
    }   

    Write-Output (New-Object psobject -Property $h)
}

function Get-ImageStoreConnectionStringFromClusterManifest
{
    <#
    .SYNOPSIS 
    Returns the value of the image store connection string from the cluster manifest.
    .PARAMETER ClusterManifest
    Contents of cluster manifest file.
    #>

    [CmdletBinding()]
    Param
    (
        [xml]
        $ClusterManifest
    )

    $managementSection = $ClusterManifest.ClusterManifest.FabricSettings.Section | ? { $_.Name -eq "Management" }
    return $managementSection.ChildNodes | ? { $_.Name -eq "ImageStoreConnectionString" } | Select-Object -Expand Value
}


function Get-ApplicationNameFromApplicationParameterFile
{
    <#
    .SYNOPSIS 
    Returns Application Name from ApplicationParameter xml file.
    .PARAMETER ApplicationParameterFilePath
    Path to the application parameter file
    #>

    [CmdletBinding()]
    Param
    (
        [String]
        $ApplicationParameterFilePath
    )
    
    if (!(Test-Path $ApplicationParameterFilePath))
    {
        $errMsg = ("Path '" + $ApplicationParameterFilePath + "' does not exist.")
        throw $errMsg
    }

    return ([xml] (Get-Content $ApplicationParameterFilePath)).Application.Name
}


function Get-ApplicationParametersFromApplicationParameterFile
{
    <#
    .SYNOPSIS 
    Reads ApplicationParameter xml file and returns HashTable containing ApplicationParameters.
    .PARAMETER ApplicationParameterFilePath
    Path to the application parameter file
    #>

    [CmdletBinding()]
    Param
    (
        [String]
        $ApplicationParameterFilePath
    )
    
    if (!(Test-Path $ApplicationParameterFilePath))
    {
        throw ("Path '" + $ApplicationParameterFilePath + "' does not exist.")
    }
    
    $ParametersXml = ([xml] (Get-Content $ApplicationParameterFilePath)).Application.Parameters

    $hash = @{}
    $ParametersXml.ChildNodes | foreach {
       if ($_.LocalName -eq 'Parameter') {
       $hash[$_.Name] = $_.Value
       }
    }

    return $hash
}

function Merge-HashTables
{
    <#
    .SYNOPSIS 
    Merges 2 hashtables. Key, value pairs form HashTableNew are preserved if any duplciates are found between HashTableOld & HashTableNew.
    .PARAMETER HashTableOld
    First Hashtable.
    
    .PARAMETER HashTableNew
    Second Hashtable 
    #>

    [CmdletBinding()]
    Param
    (
        [HashTable]
        $HashTableOld,
        
        [HashTable]
        $HashTableNew
    )
    
    $keys = $HashTableOld.getenumerator() | foreach-object {$_.key}
    $keys | foreach-object {
        $key = $_
        if ($HashTableNew.containskey($key))
        {
            $HashTableOld.remove($key)
        }
    }
    $HashTableNew = $HashTableOld + $HashTableNew
    return $HashTableNew
}

function Publish-NewServiceFabricApplication
{
    <#
    .SYNOPSIS 
    Publishes a new Service Fabric application type to Service Fabric cluster.
    .DESCRIPTION
    This script registers & creates a Service Fabric application.
    .NOTES
    Connection to service fabric cluster should be established by using 'Connect-ServiceFabricCluster' before invoking this cmdlet.
    WARNING: This script creates a new Service Fabric application in the cluster. If OverwriteExistingApplication switch is provided, it deletes any existing application in the cluster with the same name.
    .PARAMETER ApplicationPackagePath
    Path to the folder containing the Service Fabric application package OR path to the zipped service fabric applciation package.
    .PARAMETER ApplicationParameterFilePath
    Path to the application parameter file which contains Application Name and application parameters to be used for the application.    
    .PARAMETER ApplicationName
    Name of Service Fabric application to be created. If value for this parameter is provided alongwith ApplicationParameterFilePath it will override the Application name specified in ApplicationParameter  file.
    .PARAMETER Action
    Action which this script performs. Available Options are Register, Create, RegisterAndCreate. Default Action is RegisterAndCreate.
    .PARAMETER ApplicationParameter
    Hashtable of the Service Fabric application parameters to be used for the application. If value for this parameter is provided, it will be merged with application parameters
    specified in ApplicationParameter file. In case a parameter is found in application parameter file and on commandline, commandline parameter will override the one specified in application parameter file.
    .PARAMETER OverwriteBehavior
    Overwrite Behavior if an application exists in the cluster with the same name. Available Options are Never, Always, SameAppTypeAndVersion. 
    Never will not remove the existing application. This is the default behavior.
    Always will remove the existing application even if its Application type and Version is different from the application being created. 
    SameAppTypeAndVersion will remove the existing application only if its Application type and Version is same as the application being created.
    .PARAMETER SkipPackageValidation
    Switch signaling whether the package should be validated or not before deployment.
    .EXAMPLE
    Publish-NewServiceFabricApplication -ApplicationPackagePath 'pkg\Debug' -ApplicationParameterFilePath 'Local.xml'
    Registers & Creates an application with AppParameter file containing name of application and values for parameters that are defined in the application manifest.
    Publish-NewServiceFabricApplication -ApplicationPackagePath 'pkg\Debug' -ApplicationName 'fabric:/Application1'
    Registers & Creates an application with the specified application name.
    #>

    [CmdletBinding(DefaultParameterSetName="ApplicationName")]  
    Param
    (
        [Parameter(Mandatory=$true,ParameterSetName="ApplicationParameterFilePath")]
        [Parameter(Mandatory=$true,ParameterSetName="ApplicationName")]
        [String]$ApplicationPackagePath,
    
        [Parameter(Mandatory=$true,ParameterSetName="ApplicationParameterFilePath")]
        [String]$ApplicationParameterFilePath,    

        [Parameter(Mandatory=$true,ParameterSetName="ApplicationName")]
        [Parameter(ParameterSetName="ApplicationParameterFilePath")]
        [String]$ApplicationName,

        [Parameter(ParameterSetName="ApplicationParameterFilePath")]
        [Parameter(ParameterSetName="ApplicationName")]
        [ValidateSet('Register','Create','RegisterAndCreate')]
        [String]$Action = 'RegisterAndCreate',

        [Parameter(ParameterSetName="ApplicationParameterFilePath")]
        [Parameter(ParameterSetName="ApplicationName")]
        [Hashtable]$ApplicationParameter,

        [Parameter(ParameterSetName="ApplicationParameterFilePath")]
        [Parameter(ParameterSetName="ApplicationName")]
        [ValidateSet('Never','Always','SameAppTypeAndVersion')]
        [String]$OverwriteBehavior = 'Never',

        [Parameter(ParameterSetName="ApplicationParameterFilePath")]
        [Parameter(ParameterSetName="ApplicationName")]
        [Switch]$SkipPackageValidation
    )


    if (!(Test-Path $ApplicationPackagePath))
    {
        $errMsg = ("Path '" + $ApplicationPackagePath + "' does not exist.")
        throw $errMsg
    }

    # Check if the ApplicationPackagePath points to a compressed package.
    if (Test-Path $ApplicationPackagePath -PathType Leaf)
    {
        if((Get-Item $ApplicationPackagePath).Extension -eq ".sfpkg")
        {
            $AppPkgPathToUse=[io.path]::combine($env:Temp, (Get-Item $ApplicationPackagePath).BaseName)
            Expand-ToFolder $ApplicationPackagePath $AppPkgPathToUse
        }
        else
        {
            $errMsg = ($ApplicationPackagePath + " is not a valid Service Fabric application package.") 
            throw $errMsg
        }
    }
    else
    {
        $AppPkgPathToUse = $ApplicationPackagePath
    }

    if ($PSBoundParameters.ContainsKey('ApplicationParameterFilePath') -and !(Test-Path $ApplicationParameterFilePath -PathType Leaf))
    {
        $errMsg = ("Path '" + $ApplicationParameterFilePath + "' does not exist.") 
        throw $errMsg
    }

    if(!$SkipPackageValidation)
    {
        $packageValidationSuccess = (Test-ServiceFabricApplicationPackage $AppPkgPathToUse)
        if (!$packageValidationSuccess)
        {
            $errMsg = ("Validation failed for package: " + $ApplicationPackagePath)
            throw $errMsg
        }
    }

    $ApplicationManifestPath = "$AppPkgPathToUse\ApplicationManifest.xml"

    try
    {
        [void](Test-ServiceFabricClusterConnection)
    }
    catch
    {
        Write-Warning "Unable to verify connection to Service Fabric cluster."
        throw
    }    

    # If ApplicationName is not specified on command line get application name from Application Parameter file.
    if(!$ApplicationName)
    {
       $ApplicationName = Get-ApplicationNameFromApplicationParameterFile $ApplicationParameterFilePath
    }

    $names = Get-NamesFromApplicationManifest -ApplicationManifestPath $ApplicationManifestPath
    if (!$names)
    {
        Write-Warning "Unable to read application type and version from application manifest file."
        return
    }

    if($Action.Equals("Register") -or $Action.Equals("RegisterAndCreate"))
    {
        # Apply OverwriteBehavior if an applciation with same name already exists.
        $app = Get-ServiceFabricApplication -ApplicationName $ApplicationName
        if ($app)
        {
            $removeApp = $false
            if($OverwriteBehavior.Equals("Never"))
            {
                $errMsg = ("An application with name '" + $ApplicationName + "' already exists, its type is '" + $app.ApplicationTypeName + "' and version is '" + $app.ApplicationTypeVersion + "'. You must first remove the existing application before a new application can be deployed or provide a new name for the application.")
                throw $errMsg
            }

            if($OverwriteBehavior.Equals("SameAppTypeAndVersion")) 
            {
                if($app.ApplicationTypeVersion -eq $names.ApplicationTypeVersion -and $app.ApplicationTypeName -eq $names.ApplicationTypeName)
                {
                    $removeApp = $true
                }
                else
                {
                    $errMsg = ("An application with name '" + $ApplicationName + "' already exists, its type is '" + $app.ApplicationTypeName + "' and version is '" + $app.ApplicationTypeVersion + "'. You must first remove the existing application before a new application can be deployed or provide a new name for the application.")
                    throw $errMsg
                }             
            }

            if($OverwriteBehavior.Equals("Always"))
            {
                $removeApp = $true
            }            

            if($removeApp)
            {
				Write-Host ("An application with name '" + $ApplicationName + "' already exists in the cluster with application type '" + $app.ApplicationTypeName + "' and version '" + $app.ApplicationTypeVersion + "'. Removing it.") 

                try
				{
				    $app | Remove-ServiceFabricApplication -Force
			    }
				catch [System.TimeoutException]
				{
					# Catch operation timeout and continue with force remove replica.
				}

                foreach ($node in Get-ServiceFabricNode)
                {
                    [void](Get-ServiceFabricDeployedReplica -NodeName $node.NodeName -ApplicationName $ApplicationName | Remove-ServiceFabricReplica -NodeName $node.NodeName -ForceRemove)
                }

                if($OverwriteBehavior.Equals("Always"))
                {                    
                    # Unregsiter AppType and Version if there are no other applciations for the Type and Version. 
                    # It will unregister the existing application's type and version even if its different from the application being created,
                    if((Get-ServiceFabricApplication | Where-Object {$_.ApplicationTypeVersion -eq $($app.ApplicationTypeVersion) -and $_.ApplicationTypeName -eq $($app.ApplicationTypeName)}).Count -eq 0)
                    {
                        Unregister-ServiceFabricApplicationType -ApplicationTypeName $($app.ApplicationTypeName) -ApplicationTypeVersion $($app.ApplicationTypeVersion) -Force
                    }
                }
            }
        }        

        $reg = Get-ServiceFabricApplicationType -ApplicationTypeName $names.ApplicationTypeName | Where-Object  { $_.ApplicationTypeVersion -eq $names.ApplicationTypeVersion }
        if ($reg)
        {
            Write-Host ("Application type '" + $names.ApplicationTypeName + "' and version '" + $names.ApplicationTypeVersion + "' was already registered with the cluster, unregistering it...")
            $reg | Unregister-ServiceFabricApplicationType -Force
            if(!$?)
            {
                throw "Unregistering the existing application type was unsuccessful."
            }
        }

        Write-Host "Copying application to image store..."
        # Get image store connection string
        $clusterManifestText = Get-ServiceFabricClusterManifest
        $imageStoreConnectionString = Get-ImageStoreConnectionStringFromClusterManifest ([xml] $clusterManifestText)

        $applicationPackagePathInImageStore = $names.ApplicationTypeName
        Copy-ServiceFabricApplicationPackage -ApplicationPackagePath $AppPkgPathToUse -ImageStoreConnectionString $imageStoreConnectionString -ApplicationPackagePathInImageStore $applicationPackagePathInImageStore
        if(!$?)
        {
            throw "Copying of application package to image store failed. Cannot continue with registering the application."
        }

        Write-Host  "Registering application type..."
        Register-ServiceFabricApplicationType -ApplicationPathInImageStore $applicationPackagePathInImageStore
        if(!$?)
        {
            throw "Registration of application type failed."
        }

        Write-Host "Removing application package from image store..."
        Remove-ServiceFabricApplicationPackage -ApplicationPackagePathInImageStore $applicationPackagePathInImageStore -ImageStoreConnectionString $imageStoreConnectionString
    }

    if($Action.Equals("Create") -or $Action.Equals("RegisterAndCreate"))
    {
        Write-Host "Creating application..."

        # If application parameters file is specified read values from and merge it with parameters passed on Commandline
        if ($PSBoundParameters.ContainsKey('ApplicationParameterFilePath'))
        {
           $appParamsFromFile = Get-ApplicationParametersFromApplicationParameterFile $ApplicationParameterFilePath        
           if(!$ApplicationParameter)
            {
                $ApplicationParameter = $appParamsFromFile
            }
            else
            {
                $ApplicationParameter = Merge-Hashtables -HashTableOld $appParamsFromFile -HashTableNew $ApplicationParameter
            }    
        }
    
        New-ServiceFabricApplication -ApplicationName $ApplicationName -ApplicationTypeName $names.ApplicationTypeName -ApplicationTypeVersion $names.ApplicationTypeVersion -ApplicationParameter $ApplicationParameter
        if(!$?)
        {
            throw "Creation of application failed."
        }

        Write-Host "Create application succeeded."
    }
}

function Publish-UpgradedServiceFabricApplication
{
    <#
    .SYNOPSIS 
    Publishes and starts an upgrade for an existing Service Fabric application in Service Fabric cluster.
    .DESCRIPTION
    This script registers & starts an upgrade for Service Fabric application.
    .NOTES
    Connection to service fabric cluster should be established by using 'Connect-ServiceFabricCluster' before invoking this cmdlet.
    .PARAMETER ApplicationPackagePath
    Path to the folder containing the Service Fabric application package OR path to the zipped service fabric applciation package.
    .PARAMETER ApplicationParameterFilePath
    Path to the application parameter file which contains Application Name and application parameters to be used for the application.    
    .PARAMETER ApplicationName
    Name of Service Fabric application to be created. If value for this parameter is provided alongwith ApplicationParameterFilePath it will override the Application name specified in ApplicationParameter file.
    .PARAMETER Action
    Action which this script performs. Available Options are Register, Upgrade, RegisterAndUpgrade. Default Action is RegisterAndUpgrade.
    .PARAMETER ApplicationParameter
    Hashtable of the Service Fabric application parameters to be used for the application. If value for this parameter is provided, it will be merged with application parameters
    specified in ApplicationParameter file. In case a parameter is found ina pplication parameter file and on commandline, commandline parameter will override the one specified in application parameter file.
    .PARAMETER UpgradeParameters
    Hashtable of the upgrade parameters to be used for this upgrade. If Upgrade parameters are not specified then script will perform an UnmonitoredAuto upgrade.
    .PARAMETER UnregisterUnusedVersions
    Switch signalling if older vesions of the application need to be unregistered after upgrade.
    .PARAMETER SkipPackageValidation
    Switch signaling whether the package should be validated or not before deployment.
    .EXAMPLE
    Publish-UpgradeServiceFabricApplication -ApplicationPackagePath 'pkg\Debug' -ApplicationParameterFilePath 'AppParameters.Local.xml'
    Registers & Upgrades an application with AppParameter file containing name of application and values for parameters that are defined in the application manifest.
    Publish-UpgradesServiceFabricApplication -ApplicationPackagePath 'pkg\Debug' -ApplicationName 'fabric:/Application1'
    Registers & Upgrades an application with the specified applciation name.
    #>

    [CmdletBinding(DefaultParameterSetName="ApplicationName")]  
    Param
    (
        [Parameter(Mandatory=$true,ParameterSetName="ApplicationParameterFilePath")]
        [Parameter(Mandatory=$true,ParameterSetName="ApplicationName")]
        [String]$ApplicationPackagePath,

        [Parameter(Mandatory=$true,ParameterSetName="ApplicationParameterFilePath")]
        [String]$ApplicationParameterFilePath,

        [Parameter(Mandatory=$true,ParameterSetName="ApplicationName")]
        [String]$ApplicationName,

        [Parameter(ParameterSetName="ApplicationParameterFilePath")]
        [Parameter(ParameterSetName="ApplicationName")]
        [ValidateSet('Register','Upgrade','RegisterAndUpgrade')]
        [String]$Action = 'RegisterAndUpgrade',

        [Parameter(ParameterSetName="ApplicationParameterFilePath")]
        [Parameter(ParameterSetName="ApplicationName")]
        [Hashtable]$ApplicationParameter,

        [Parameter(ParameterSetName="ApplicationParameterFilePath")]
        [Parameter(ParameterSetName="ApplicationName")]
        [Hashtable]$UpgradeParameters = @{UnmonitoredAuto = $true},

        [Parameter(ParameterSetName="ApplicationParameterFilePath")]
        [Parameter(ParameterSetName="ApplicationName")]
        [Switch]$UnregisterUnusedVersions,

        [Parameter(ParameterSetName="ApplicationParameterFilePath")]
        [Parameter(ParameterSetName="ApplicationName")]
        [Switch]$SkipPackageValidation
    )


    if (!(Test-Path $ApplicationPackagePath))
    {
        $errMsg = ("Path '" + $ApplicationPackagePath + "' does not exist.")
        throw $errMsg
    }

    if (Test-Path $ApplicationPackagePath -PathType Leaf)
    {
        if((Get-Item $ApplicationPackagePath).Extension -eq ".sfpkg")
        {
            $AppPkgPathToUse=[io.path]::combine($env:Temp, (Get-Item $ApplicationPackagePath).BaseName)
            Expand-ToFolder $ApplicationPackagePath $AppPkgPathToUse
        }
        else
        {
            $errMsg = ($ApplicationPackagePath + " is not a valid Service Fabric application package.")
            throw $errMsg
        }
    }
    else
    {
        $AppPkgPathToUse = $ApplicationPackagePath
    }

    if ($PSBoundParameters.ContainsKey('ApplicationParameterFilePath') -and !(Test-Path $ApplicationParameterFilePath -PathType Leaf))
    {
        $errMsg = "Path '" + $ApplicationParameterFilePath + "' does not exist."
        throw $errMsg
    }

	# Get image store connection string
    $clusterManifestText = Get-ServiceFabricClusterManifest
	$imageStoreConnectionString = Get-ImageStoreConnectionStringFromClusterManifest ([xml] $clusterManifestText)

    if(!$SkipPackageValidation)
    {
        $packageValidationSuccess = (Test-ServiceFabricApplicationPackage $AppPkgPathToUse -ImageStoreConnectionString $imageStoreConnectionString)
        if (!$packageValidationSuccess)
        {
           $errMsg = ("Validation failed for package: " + $ApplicationPackagePath)
           throw $errMsg
        }
    }

    $ApplicationManifestPath = "$AppPkgPathToUse\ApplicationManifest.xml"    

    try
    {
        [void](Test-ServiceFabricClusterConnection)
    }
    catch
    {
        Write-Warning "Unable to verify connection to Service Fabric cluster."
        throw
    }

    # If ApplicationName is not specified on command line get application name from Application parameter file.
    if(!$ApplicationName)
    {
       $ApplicationName = Get-ApplicationNameFromApplicationParameterFile $ApplicationParameterFilePath
    }

    $names = Get-NamesFromApplicationManifest -ApplicationManifestPath $ApplicationManifestPath
    if (!$names)
    {
        return
    }

    if ($Action.Equals('RegisterAndUpgrade') -or $Action.Equals('Register'))
    {    
        ## Check existence of the application
        $oldApplication = Get-ServiceFabricApplication -ApplicationName $ApplicationName
        
        if (!$oldApplication)
        {
            $errMsg = "Application '" + $ApplicationName + "' doesn't exist in cluster."
            throw $errMsg
        }
        else
        {
            if($oldApplication.ApplicationTypeName -ne $names.ApplicationTypeName)
            {   
                $errMsg = ("Application type of application '" + $ApplicationName + "' doesn't match the application type in the application manifest of the new application package. Please ensure that the application being upgraded has the same application type.")
                throw $errMsg
            }
        }                
    
        ## Check upgrade status
        $upgradeStatus = Get-ServiceFabricApplicationUpgrade -ApplicationName $ApplicationName
        if ($upgradeStatus.UpgradeState -ne "RollingBackCompleted" -and $upgradeStatus.UpgradeState -ne "RollingForwardCompleted")
        {
            $errMsg = ("An upgrade for the application '" + $ApplicationName + "' is already in progress.") 
            throw $errMsg
        }

        $reg = Get-ServiceFabricApplicationType -ApplicationTypeName $names.ApplicationTypeName | Where-Object  { $_.ApplicationTypeVersion -eq $names.ApplicationTypeVersion }
        if ($reg)
        {
            Write-Host ("Application type '" + $names.ApplicationTypeName + "' and version '" + $names.ApplicationTypeVersion + "' was already registered with the cluster, unregistering it...")
            $reg | Unregister-ServiceFabricApplicationType -Force
            Write-Host ("Application type successfully unregistered.")
        }
    
        $applicationPackagePathInImageStore = $names.ApplicationTypeName
        Write-Host "Copying application to image store..."
        Copy-ServiceFabricApplicationPackage -ApplicationPackagePath $AppPkgPathToUse -ImageStoreConnectionString $imageStoreConnectionString -ApplicationPackagePathInImageStore $applicationPackagePathInImageStore
        if(!$?)
        {
            throw "Copying of application package to image store failed. Cannot continue with registering the application."
        }
    
        Write-Host "Registering application type..."
        Register-ServiceFabricApplicationType -ApplicationPathInImageStore $applicationPackagePathInImageStore
        if(!$?)
        {
            throw Write-Host "Registration of application type failed."
        }
     }
    
    if ($Action.Equals('Upgrade') -or $Action.Equals('RegisterAndUpgrade'))
    {
        try
        {
            $UpgradeParameters["ApplicationName"] = $ApplicationName
            $UpgradeParameters["ApplicationTypeVersion"] = $names.ApplicationTypeVersion
        
             # If application parameters file is specified read values from and merge it with parameters passed on Commandline
            if ($PSBoundParameters.ContainsKey('ApplicationParameterFilePath'))
            {
                $appParamsFromFile = Get-ApplicationParametersFromApplicationParameterFile $ApplicationParameterFilePath        
                if(!$ApplicationParameter)
                {
                    $ApplicationParameter = $appParamsFromFile
                }
                else
                {
                    $ApplicationParameter = Merge-Hashtables -HashTableOld $appParamsFromFile -HashTableNew $ApplicationParameter
                }    
            }
     
            $UpgradeParameters["ApplicationParameter"] = $ApplicationParameter

            $serviceTypeHealthPolicyMap = $upgradeParameters["ServiceTypeHealthPolicyMap"]
            if ($serviceTypeHealthPolicyMap -and $serviceTypeHealthPolicyMap -is [string])
            {
                $upgradeParameters["ServiceTypeHealthPolicyMap"] = Invoke-Expression $serviceTypeHealthPolicyMap
            }
        
        
            Write-Host "Start upgrading application..."
            Start-ServiceFabricApplicationUpgrade @UpgradeParameters
        }
        catch
        {
            Write-Host ("Unregistering application type '" + $names.ApplicationTypeName + "' and version '" + $names.ApplicationTypeVersion + "'...") 
            Unregister-ServiceFabricApplicationType -ApplicationTypeName $names.ApplicationTypeName -ApplicationTypeVersion $names.ApplicationTypeVersion -Force
            throw
        }

        if (!$UpgradeParameters["Monitored"] -and !$UpgradeParameters["UnmonitoredAuto"])
        {
            return
        }
    
        do
        {
            Write-Host "Waiting for upgrade..."
            Start-Sleep -Seconds 3
            $upgradeStatus = Get-ServiceFabricApplicationUpgrade -ApplicationName $ApplicationName
        } while ($upgradeStatus.UpgradeState -ne "RollingBackCompleted" -and $upgradeStatus.UpgradeState -ne "RollingForwardCompleted")
    
        if($UnregisterUnusedVersions)
        {
            Write-Host "Unregistering other unused versions for the application type..."
            foreach($registeredAppTypes in Get-ServiceFabricApplicationType -ApplicationTypeName $names.ApplicationTypeName | Where-Object  { $_.ApplicationTypeVersion -ne $names.ApplicationTypeVersion })
            {
                try
                {
                    $registeredAppTypes | Unregister-ServiceFabricApplicationType -Force
                }
                catch [System.Fabric.FabricException]
                {
                    # AppType and Version in use.
                }
            }
        }

        if($upgradeStatus.UpgradeState -eq "RollingForwardCompleted")
        {
            Write-Host "Upgrade completed successfully."
        }
        elseif($upgradeStatus.UpgradeState -eq "RollingBackCompleted")
        {
            Write-Host "Upgrade was rolled back."
        }
    }
}

function Read-XmlElementAsHashtable
{
    Param (
        [System.Xml.XmlElement]
        $Element
    )

    $hashtable = @{}
    if ($Element.Attributes)
    {
        $Element.Attributes | 
            ForEach-Object {
                # Only boolean values are strongly-typed.  All other values are treated as strings.
                $boolVal = $null
                if ([bool]::TryParse($_.Value, [ref]$boolVal)) {
                    $hashtable[$_.Name] = $boolVal
                }
                else {
                    $hashtable[$_.Name] = $_.Value
                }
            }
    }

    return $hashtable
}

function Read-PublishProfile
{
    Param (
        [String]
        $PublishProfileFile
    )

    $publishProfileXml = [Xml] (Get-Content -LiteralPath $PublishProfileFile)
    $publishProfileElement = $publishProfileXml.PublishProfile
    $publishProfile = @{}

    $publishProfile.ClusterConnectionParameters = Read-XmlElementAsHashtable $publishProfileElement.Item("ClusterConnectionParameters")
    $publishProfile.UpgradeDeployment = Read-XmlElementAsHashtable $publishProfileElement.Item("UpgradeDeployment")

    if ($publishProfileElement.Item("UpgradeDeployment"))
    {
        $publishProfile.UpgradeDeployment.Parameters = Read-XmlElementAsHashtable $publishProfileElement.Item("UpgradeDeployment").Item("Parameters")
        if ($publishProfile.UpgradeDeployment["Mode"])
        {
            $publishProfile.UpgradeDeployment.Parameters[$publishProfile.UpgradeDeployment["Mode"]] = $true
        }
    }
    
    $publishProfileFolder = (Split-Path $PublishProfileFile)
    $publishProfile.ApplicationParameterFile = [System.IO.Path]::Combine($publishProfileFolder, $publishProfileElement.ApplicationParameterFile.Path)

    return $publishProfile
}

try {

    #$OctopusParameters = @{
    #    PublishProfilePath = "Wickr.Basket.Horizon/PublishProfiles/Thundera.xml"
    #    ApplicationPackagePath = ($PSScriptRoot + "/Wickr.Basket.Horizon2016.11.10.4.sfpkg")
    #    
    #    SFClusterEndpoint = "http://vmfwsvfabd1:19000"
    #    SFClusterAuthScheme = "None"
    #    SFClusterAuthCertThumbprint = ""
    #
    #    ApplicationParameterFile = "Wickr.Basket.Horizon/ApplicationParameters/Thundera.xml"
    #    OverridePublishProfileSettings = "false"
    #}

    # Collect input values

    $publishProfilePath = $OctopusParameters['PublishProfilePath']
    if ($publishProfilePath)
    {
        $publishProfile = Read-PublishProfile $publishProfilePath
    }

    $applicationPackagePath = ([io.path]::Combine($OctopusParameters['Octopus.Tentacle.Agent.ApplicationDirectoryPath'], $OctopusParameters['Octopus.Environment.Name'], $OctopusParameters['Octopus.Action.Package.NuGetPackageId'], $OctopusParameters['Octopus.Action.Package.NuGetPackageVersion'], $OctopusParameters['ApplicationPackagePath']))

    $clusterEndpoint = $OctopusParameters['SFClusterEndpoint']
    $clusterAuthScheme = $OctopusParameters['SFClusterAuthScheme']
    
    $clusterConnectionParameters = @{}
    
    $regKey = "HKLM:\SOFTWARE\Microsoft\Service Fabric SDK"
    if (!(Test-Path $regKey))
    {
        throw "Error: The service fabric SDK is not installed."
    }

    $connectionEndpointUrl = [System.Uri]$clusterEndpoint
    # Override the publish profile's connection endpoint with the one defined on the associated service endpoint
    $clusterConnectionParameters["ConnectionEndpoint"] = $connectionEndpointUrl.Authority # Authority includes just the hostname and port

    # Configure cluster connection pre-reqs
    if ($clusterAuthScheme -ne "None")
    {
        # Add server cert thumbprint (common to both auth-types)
        if ($OctopusParameters['SFClusterAuthCertThumbprint'])
        {
            $clusterConnectionParameters["ServerCertThumbprint"] = $OctopusParameters['SFClusterAuthCertThumbprint']
        }
        else
        {
            if ($publishProfile)
            {
                $clusterConnectionParameters["ServerCertThumbprint"] = $publishProfile.ClusterConnectionParameters["ServerCertThumbprint"]
            }
            else
            {
                throw "Error: to deploy to a secured cluster, a certificate thumbprint is required. Not found in step configuration or publish profile."
            }
        }

        # Add auth-specific parameters
        if ($clusterAuthScheme -eq "UserNamePassword")
        {
            # Setup the AzureActiveDirectory and ServerCertThumbprint parameters before getting the security token, because getting the security token
            # requires a connection request to the cluster in order to get metadata and so these two parameters are needed for that request.
            $clusterConnectionParameters["AzureActiveDirectory"] = $true

            $securityToken = Get-AadSecurityToken -ClusterConnectionParameters $clusterConnectionParameters -ConnectedServiceEndpoint $connectedServiceEndpoint
            $clusterConnectionParameters["SecurityToken"] = $securityToken
            $clusterConnectionParameters["WarningAction"] = "SilentlyContinue"
        }
        elseif ($clusterAuthScheme -eq "Certificate")
        {
            Add-Certificate -ClusterConnectionParameters $clusterConnectionParameters -ConnectedServiceEndpoint $connectedServiceEndpoint
            $clusterConnectionParameters["X509Credential"] = $true
        }
    }

    # Connect to cluster
    try {
        [void](Connect-ServiceFabricCluster @clusterConnectionParameters)
    }
    catch {
        if ($connectionEndpointUrl.Port -ne "19000") {
            Write-Warning ("The port " + $connectionEndpointUrl.Port + " specified on your connection endpoint does not match the default ClientConnectionEndpoint of '19000'. This might have caused cluster communication failure.")
        }

        throw $_
    }
    
    Write-Host "Successfully connected to cluster."

    $applicationParameterFile = $OctopusParameters['ApplicationParameterFile']
    if ($applicationParameterFile)
    {
        Write-Host ("Overriding application parameter file specified in publish profile with " + $applicationParameterFile + " specified in the task.") 
    }
    elseif ($publishProfile)
    {
        $applicationParameterFile = $publishProfile.ApplicationParameterFile
    }
    else
    {
        throw "An application parameters file or a publish profile must be specified."
    }

    if ($OctopusParameters['OverridePublishProfileSettings'] -eq "true")
    {
        Write-Host "Overriding upgrade settings specified in publish profile with the settings specified in the task."
        $isUpgrade = $OctopusParameters['OverridePublishProfileSettings'] -eq "true"

        if ($isUpgrade)
        {
            $upgradeParameters = Get-VstsUpgradeParameters
        }
    }
    elseif ($publishProfile)
    {
        $isUpgrade = $publishProfile.UpgradeDeployment -and $publishProfile.UpgradeDeployment.Enabled
        $upgradeParameters = $publishProfile.UpgradeDeployment.Parameters
    }
    else
    {
        throw "Upgrade settings must be overridden or a publish profile must be specified in the task."
    }

    $applicationName = Get-ApplicationNameFromApplicationParameterFile $applicationParameterFile
    $app = Get-ServiceFabricApplication -ApplicationName $applicationName
    
    # Do an upgrade if configured to do so and the app actually exists
    if ($isUpgrade -and $app)
    {
        Write-Host ("Installing Application UPGRADE.")
        Publish-UpgradedServiceFabricApplication -ApplicationPackagePath $applicationPackagePath -ApplicationParameterFilePath $applicationParameterFile -Action RegisterAndUpgrade -UpgradeParameters $upgradeParameters -UnregisterUnusedVersions -ErrorAction Stop
    }
    else
    {
        Write-Host ("Installing NEW Application.")
        Publish-NewServiceFabricApplication -ApplicationPackagePath $ApplicationPackagePath -ApplicationParameterFilePath $applicationParameterFile -Action RegisterAndCreate -OverwriteBehavior SameAppTypeAndVersion -ErrorAction Stop 
    }
} catch {
    Write-Host ("UNHANDLED EXCEPTION")
    Write-Host $_.Exception.Message
    exit -1
} finally {
    #Trace-VstsLeavingInvocation $MyInvocation
}
exit 0