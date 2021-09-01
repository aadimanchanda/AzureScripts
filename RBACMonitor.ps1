#requires -Version 3.0 -Modules Az.Resources

$ErrorActionPreference = 'Stop'


## Functions
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


Function Select-Subs {
    CLS
    $ErrorActionPreference = 'SilentlyContinue'
    $Menu = 0
    $Subs = @(Get-AzSubscription | select Name, ID, TenantId)

    Write-Host "Please select the subscription you want to use:" ;
    % {Write-Host ""}
    $Subs | % {Write-Host "[$($Menu)]"  -NoNewline ; Write-host ". $($_.Name)"; $Menu++; }
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


function Resolve-AzureAdGroupMembers {
    param(
        [guid]
        $GroupObjectId,
        $GroupList = (Get-AzADGroup)
    )
    
    $VerbosePreference = 'continue'
    Write-Verbose -Message ('Resolving {0}' -f $GroupObjectId)
    $group = $GroupList | Where-Object -Property Id -EQ -Value $GroupObjectId
    $groupMembers = Get-AzADGroupMember -GroupObjectId $GroupObjectId
    Write-Verbose -Message ('Found members {0}' -f ($groupMembers.DisplayName -join ', '))
    $parentGroup = $group.DisplayName
    $groupMembers |
        Where-Object -Property Type -NE -Value Group |
        Select-Object -Property Id, DisplayName, @{
        Name       = 'ParentGroup'
        Expression = { $parentGroup }
    }
    $groupMembers |
        Where-Object -Property type -EQ -Value Group |
        ForEach-Object -Process {
        Resolve-AzureAdGroupMembers -GroupObjectId $_.Id -GroupList $GroupList 
    }
}

## Main Part of Script

Login

$SubscriptionSelection = Select-Subs
Select-AzSubscription -SubscriptionName $SubscriptionSelection.Name -ErrorAction Stop


## Get current Azure Subscription
$Azuresub = $SubscriptionSelection.Name -replace , '/'

$roleAssignments = Get-AzRoleAssignment -IncludeClassicAdministrators

$members = $roleAssignments | ForEach-Object -Process {
    Write-Verbose -Message ('Processing Assignment {0}' -f $_.RoleDefinitionName)
    $roleAssignment = $_ 
    
    if ($roleAssignment.ObjectType -eq 'Group') {
        Resolve-AzureAdGroupMembers -GroupObjectId $roleAssignment.ObjectId ` | Sort-Object -Property { $roleAssignment.RoleDefinitionName }, DisplayName `
            | Select-Object -Property Id,
        DisplayName,
        @{
            Name       = 'RoleDefinitionName'
            Expression = { $roleAssignment.RoleDefinitionName }
        }, @{
            Name       = 'Scope'
            Expression = { $roleAssignment.Scope }
        },
        ParentGroup 
    }
    else {
        $roleAssignment | Sort-Object -Property { $roleAssignment.RoleDefinitionName }, DisplayName  | Select-Object -Property DisplayName, ParentGroup,
        @{
            Name       = 'RoleDefinitionName'
            Expression = { $roleAssignment.RoleDefinitionName }
        },
        Scope 
                   
    } 
}


## CSV Save
    $output = $members | Export-CSV -path $($PSScriptRoot + "\" + "$Azuresub" + "_RBAC.csv") -NoTypeInformation
