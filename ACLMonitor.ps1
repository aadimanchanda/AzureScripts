#requires -Version 3.0 -Modules Az.Resources

$ErrorActionPreference = 'Stop'
#$ErrorActionPreference = 'SilentlyContinue'

## Functions
# Login function to facilitate login to azure subscription in case not already logged in
function Login {
    $needLogin = $true
    Try {
        $content = Get-AzContext
        if ($content) {
            $needLogin = ([string]::IsNullOrEmpty($content.Account))
        } 
    } 
    Catch {
        if ($_ -like "*Login-AzAccount to login*") {
            $needLogin = $true
        } 
        else {
            throw
        }
    }

    if ($needLogin) {
        Login-AzAccount
    }
}

# Function to select subscription for listing storage accounts. Please select 'Q' to quit or 'S' to switch subscription
Function Select-Subs {
    CLS
    $ErrorActionPreference = 'SilentlyContinue'
    $Menu = 0
    $Subs = @(Get-AzSubscription | select Name, ID, TenantId)

    Write-Host "Please select the subscription you want to use:" ;
    % {Write-Host ""}
    $Subs | % {Write-Host "[$($Menu)]" -NoNewline ; Write-host ". $($_.Name)"; $Menu++; }
    % {Write-Host ""}
    % {Write-Host "[S]" -NoNewline ; Write-host ". To switch Azure Account."}
    % {Write-Host ""}
    % {Write-Host "[Q]" -NoNewline ; Write-host ". To quit."}
    % {Write-Host ""}
    $selection = Read-Host "Please select the Subscription Number - Valid numbers are 0 - $($Subs.count -1), S to switch Azure Account or Q to quit"
    If ($selection -eq 'S') { 
        Get-AzContext | ForEach-Object {Clear-AzContext -Scope CurrentUser -Force}
        Login
        Select-Subs
    }
    If ($selection -eq 'Q') { 
        Clear-Host
        Exit
    }
    If ($Subs.item($selection) -ne $null)
    { Return @{name = $subs[$selection].Name; ID = $subs[$selection].ID} 
    }

}

# Function to select ADLS Gen 2 storage accounts. ACL permissions will be listed for all the containers under choosen storage account. Please select 'Q' to quit or 'S' to switch subscription
Function Select-StorageAccount {
    CLS
    $ErrorActionPreference = 'SilentlyContinue'
    $Menu = 0
    $StorageAccount = @(Get-AzStorageAccount | select StorageAccountName)

    Write-Host "Please select the Storage Account Name you want to use:";
    % {Write-Host ""}
    $StorageAccount | % {Write-Host "[$($Menu)]"  -NoNewline ; Write-host ". $($_.StorageAccountName)"; $Menu++; }
    % {Write-Host ""}
    % {Write-Host "[Q]"  -NoNewline ; Write-host ". To quit."}
    % {Write-Host ""}
    $selection = Read-Host "Please select the Storage Account Number - Valid numbers are 0 - $($StorageAccount.count -1), Q to quit"
    If ($selection -eq 'Q') { 
        Clear-Host
        Exit
    }
    If ($StorageAccount.item($selection) -ne $null)
    { Return @{StorageAccountName = $StorageAccount[$selection].StorageAccountName} 
    }

}

## Main Part of Script

Login

$SubscriptionSelection = Select-Subs
# Set context of powershell script to selected subscription
Select-AzSubscription -SubscriptionName $SubscriptionSelection.Name -ErrorAction Stop

$storageaccount = Select-StorageAccount

CLS

Write-host "Storage account selected : $($storageaccount.StorageAccountName)"

# Set context of powershell script to selected storage account within subscription
$ctx = New-AzStorageContext -StorageAccountName $storageaccount.StorageAccountName -UseConnectedAccount

#Fetch all containers in selected storage account
$containerlist = Get-AzStorageContainer  -Context $ctx 


# Loop through all the directories in all the containers of selected storage account and fetch ACL permissions
$acloutput =	foreach($filesystem in $containerlist) 
			{   
					$rootdir	= Get-AzDataLakeGen2Item -Context $ctx -FileSystem $filesystem.Name 
				    $directory = Get-AzDataLakeGen2ChildItem -Context $ctx -FileSystem $filesystem.Name -Recurse -FetchProperty -OutputUserPrincipalName | Where-Object IsDirectory -eq $True 
					$dirlist =  $directory + $rootdir 
					foreach($dir in $dirlist)
					{
						Write-host "Directory name to retrieve ACL : $($filesystem.Name)/$($dir.Path)"
						$dir.ACL | Select AccessControlType ,Permissions,
						@{Name = 'UserObjectId'
						Expression = { if ($_.EntityId -ne $null) {$_.EntityId}
						if ($_.AccessControlType -eq 'User' -and $_.EntityId -eq $null) {$dir.Owner}
						if ($_.AccessControlType -eq 'Group' -and $_.EntityId -eq $null) {$dir.Group} 
						 }
						},
						@{Name = 'DirectoryName'
						Expression = { $dir.Path }
						},						
						@{Name = 'ContainerName'
						Expression = { $filesystem.Name }
						}
					}					
			} 

#$acloutput 
# Export ACL permissions to CSV file
$output = $acloutput | Export-CSV -path $($PSScriptRoot + "\" + $storageaccount.StorageAccountName +"_ACL.csv") -NoTypeInformation
