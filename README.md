# AzureScripts
Powershell scripts for OSP Azure tasks

RBACMonitor.ps1 -
    Retrives the RBAC roles assigned at subscription level. Let's you choose the subscription to provide RBAC details.

ACLMonitor.ps1 -
    Fetches ACL details for a ADLS Gen 2 storage account within Azure Subscription. Let's you choose the subscription and storage account to fetch ACL details for.  If the container/directory is created using Shared Key, an Account SAS, or a Service SAS, then the owner and owning group are set to $superuser
