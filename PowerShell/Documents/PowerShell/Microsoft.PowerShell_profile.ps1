<#
This file chain loads the user cutomizable custom-profile.ps1 file.
This file should not be edited and is monitored for changes by IT Ops Team.
Contact albert.gouws@sandfield.co.nz or arno.grobbelaar@sandfield.co.nz for information.
IT Ops Team 28/05/2025
Updated: 10/09/2025: Replaced $Env:UserName with $env:USERPROFILE to better handle user account name changes.
#>

$filePath = "$env:USERPROFILE\Documents\PowerShell\custom-profile.ps1"
if (Test-Path -Path $filePath) {
    . $filePath
}

