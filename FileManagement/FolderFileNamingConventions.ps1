Param(
    $path
)
# Get-ChildItem -Path $path -Recurse | 
# ForEach-Object {
#     Write-Host "$($_.Name)"
#     If($_.Name -match " ")
#     {
#         Write-Host "This string has a space"
#         Rename-Item -Path "$($_.FullName)" -NewName "$($_.Name -replace " ", "_")" 
#     }
#     else
#     {
#         Write-Host "This string does not have a space"
#     }
# }

$Path = $path | Get-ChildItem -Recurse |
Rename-Item -NewName { $_.Name -replace '\s', '_' }