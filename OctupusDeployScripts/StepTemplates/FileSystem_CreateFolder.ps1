# Summary: Creates a folder structure that is passed in.
# Parameters:
#{FolderPath} - The entire path to the folder, this step will also created nested folders. For example "D:\one\two" will create two folders ('one', and then 'two' under folder 'one'). This script will not remove items from the folders.
$folderPath = $OctopusParameters['FolderPath']
New-Item -ItemType directory -Path $folderPath -force