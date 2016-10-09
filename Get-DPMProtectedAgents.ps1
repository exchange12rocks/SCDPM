<# MIT License
 
Copyright (c) 2015 Kirill Nikolaev
 
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
 
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
 
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE. #>

<#
.SYNOPSIS
Returns active protected agents connected to an SCDPM server.

.DESCRIPTION
Returns every computer with installed SCDPM agent, connected to the chosen SCDPM server and having protected any datasource at this SCDPM server.

.PARAMETER DPMServerName
A single name (FQDN ot NetBIOS) of an SCDPM server or a collection of such.

.EXAMPLE
C:\PS> .\Get-DPMProtectedAgents.ps1 -DPMServerName bckpsrv1.example.com
WARNING: Connecting to DPM server: bckpsrv1.example.com

ServerName                                      ClusterName                                     Domain                                          ServerProtectionState
----------                                      -----------                                     ------                                          ---------------------
SRV1                                                                                            example.net                                     HasDatasourcesProtected
SRV2                                            CL1.example.com                                 example.com                                     HasDatasourcesProtected

.EXAMPLE
C:\PS> 'bckpsrv1.example.com','bckpsrv2.example.com' | .\Get-DPMProtectedAgents.ps1
WARNING: Connecting to DPM server: bckpsrv1.example.com

ServerName                                      ClusterName                                     Domain                                          ServerProtectionState
----------                                      -----------                                     ------                                          ---------------------
SRV1                                                                                            example.net                                     HasDatasourcesProtected
SRV2                                            CL1.example.com                                 example.com                                     HasDatasourcesProtected
WARNING: Connecting to DPM server: bckpsrv2.example.com
SRV3                                                                                            example.net                                     HasDatasourcesProtected
SRV4                                            CL2.example.com                                 example.com                                     HasDatasourcesProtected
SRV5                                            CL2.example.com                                 example.com                                     HasDatasourcesProtected

.EXAMPLE
C:\PS> .\Get-DPMProtectedAgents.ps1 | %{ Disable-DPMProductionServer $_ -Confirm:$false }
C:\PS>

.INPUTS
System.String[]. An array of names of SCDPM servers.

.OUTPUTS
System.Object[]. A collection of Microsoft.Internal.EnterpriseStorage.Dls.UI.ObjectModel.OMCommon.ProductionServer
#>

[CmdletBinding()]
[OutputType([System.Object[]])]
Param(
	[Parameter(Mandatory=$false,
	ValueFromPipeline=$true)]
	[string[]]$DPMServerName = 'localhost' #We need something in $DPMServerName for the cycle to work.
)

PROCESS {
    foreach ($Name in $DPMServerName) {
        Disconnect-DPMServer
        if ($Name -eq '' -or $Name -eq 'localhost') {
	        $ProductionServers = Get-DPMProductionServer #Execution of DPM cmdlets with given server name doesn't work in PSSessions. So, we have to use two branches of code here.
        }
        else {
	        $ProductionServers = Get-DPMProductionServer -DPMServerName $Name
        }

        $ProtectedServers = $ProductionServers | where {$_.ServerProtectionState -eq 'HasDatasourcesProtected'}
        Write-Debug "ProtectedServers at $Name"
        if ($ProtectedServers) {
            Write-Debug ([string]$ProtectedServers)
        }
        else {
            Write-Debug 'No ProtectedServers found'
        }

        $ProtectedServersStandAlone = $ProtectedServers | where {$_.ClusterName -eq ''}
        Write-Debug "ProtectedServersStandAlone at $Name"
        if ($ProtectedServersStandAlone) {
            Write-Debug ([string]$ProtectedServersStandAlone)
        }
        else {
            Write-Debug 'No ProtectedServersStandAlone found'
        }

        $ProtectedServersClustered = $ProtectedServers | where {$_.ClusterName -ne ''} #Need to split clustered resources and cluster nodes from stand-alone servers, because if we don't protect cluster node itself, it will not shows up in $ProtectedServers and we'll find it through properties of the clustered resource.
        Write-Debug "ProtectedServersClustered at $Name"
        if ($ProtectedServersClustered) {
            Write-Debug ([string]$ProtectedServersClustered)
        }
        else {
            Write-Debug 'No ProtectedServersClustered found'
        }

        $ClusteredResouces = $ProtectedServersClustered | where {$_.PossibleOwners} #Select only clustered resources, not nodes itself.
        Write-Debug "ClusteredResouces at $Name"
        if ($ClusteredResouces) {
            Write-Debug ([string]$ClusteredResouces)
        }
        else {
            Write-Debug 'No ClusteredResouces found'
        }

        $ClusterNodesDNSNames = @()
        $ClusteredResouces | %{$ClusterNodesDNSNames += $_.PossibleOwners}
        Write-Debug "ClusterNodesDNSNames at $Name"
        if ($ClusterNodesDNSNames) {
            Write-Debug ([string]$ClusterNodesDNSNames)
        }
        else {
            Write-Debug 'No ClusterNodesDNSNames found'
        }

        $ClusterNodesDNSNames = $ClusterNodesDNSNames | Select-Object -Unique
        Write-Debug "Unique ClusterNodesDNSNames at $Name"
        if ($ClusterNodesDNSNames) {
            Write-Debug ([string]$ClusterNodesDNSNames)
        }
        else {
            Write-Debug 'No ClusterNodesDNSNames found'
        }

        $ClusterNodesNames = @()
        $ClusterNodesDNSNames | %{$_ -match '(.+?)\..+' | Out-Null; $ClusterNodesNames += $Matches[1]} #Extract hostnames from DNS names to pass them to SCDPM cmdlets.
        Write-Debug "ClusterNodesNames at $Name"
        if ($ClusterNodesNames) {
            Write-Debug ([string]$ClusterNodesNames)
        }
        else {
            Write-Debug 'No ClusterNodesNames found'
        }

        $ClusterNodes = @()
        $ClusterNodes += $ProtectedServersClustered | where {$_ -notin $ClusteredResouces} #Select only clustered nodes.
        foreach ($NodeName in $ClusterNodesNames) {
	        $ClusterNodes += $ProductionServers | where {$_.ServerName -eq $NodeName}
        }
        Write-Debug "ClusterNodes at $Name"
        if ($ClusterNodes) {
            Write-Debug ([string]$ClusterNodes)
        }
        else {
            Write-Debug 'No ClusterNodes found'
        }

        $ProtectedAgents = $ProtectedServersStandAlone + $ClusterNodes | Select-Object -Unique
        Write-Debug "ProtectedAgents at $Name"
        if ($ProtectedAgents) {
            Write-Debug ([string]$ProtectedAgents)
        }
        else {
            Write-Debug 'No ProtectedAgents found'
        }

        Write-Output $ProtectedAgents
    }
}