param($sourceId,$managedEntityId,$vCenterServerName)

if (Test-path C:\vCenter\Server.txt){
    $Server=(Get-content C:\vCenter\Server.txt).Trim()
    $vCenterServerName=$Server
}
 
Function ExitPrematurely ($Message) {
	$discoveryData.IsSnapshot = $false
	$api.LogScriptEvent($ScriptName,1985,2,$Message)
	$discoveryData
	exit
}

Function LogScriptEvent {
	Param (
		
		#0 = Informational
		#1 = Error
		#2 = Warning
		[parameter(Mandatory=$true)]
		[ValidateRange(0,2)]
		[int]$EventLevel
		,
		
		[parameter(Mandatory=$true)]
		[string]$Message
	)

	$api.LogScriptEvent($ScriptName,1985,$EventLevel,$Message)
}

Function DefaultErrorLogging {
	LogScriptEvent -EventLevel 1 -Message ("$_`rType:$($_.Exception.GetType().FullName)`r$($_.InvocationInfo.PositionMessage)`rReceivedParam:`rsourceId:$sourceId`rmanagedEntityId:$managedEntityId`rvCenterServerName:$vCenterServerName")
}

$ScriptName = 'Community.VMware.Discovery.VirtualMachineNetworkReference.ps1'
$api = new-object -comObject 'MOM.ScriptAPI'
$discoveryData = $api.CreateDiscoveryData(0, $sourceId, $managedEntityId)

Try {Import-Module OperationsManager}
Catch {DefaultErrorLogging}

Try {New-SCOMManagementGroupConnection 'localhost'}
Catch {DefaultErrorLogging}

Try {$MGconn = Get-SCOMManagementGroupConnection | Where {$_.IsActive -eq $true}}
Catch {DefaultErrorLogging}

If(!$MGconn){
	ExitPrematurely ("Unable to connect to the local management group")
}

#Get Already Discovered Virtual Machines from SCOM
Try {$VMobjs = Get-SCOMClass -Name 'Community.VMware.Class.VirtualMachine' | Get-SCOMClassInstance | Where {$_.'[Community.VMware.Class.vCenter].vCenterServerName'.Value -eq $vCenterServerName}}
Catch {DefaultErrorLogging}

#Exit if no VMs are discovered, because there is no relationship to build
If (!$VMobjs){
	ExitPrematurely ("No VMs found discovered in SCOM for vCenter " + $vCenterServerName)
}

#Get Already Discovered Networks from SCOM
Try {$VMnetworkObjs = Get-SCOMClass -Name 'Community.VMware.Class.Network' | Get-SCOMClassInstance | Where {$_.'[Community.VMware.Class.vCenter].vCenterServerName'.Value -eq $vCenterServerName}}
Catch {DefaultErrorLogging}

Try {
	Import-Module VMware.VimAutomation.Core
} Catch {
	Start-Sleep -Seconds 10
	Try {
		Import-Module VMware.VimAutomation.Core
	} Catch {
		DefaultErrorLogging
		Exit
	}
}

Try {
	$connection = Connect-VIServer -Server $vCenterServerName -Force:$true -NotDefault
} Catch {
	Start-Sleep -Seconds 10
	Try {
		$connection = Connect-VIServer -Server $vCenterServerName -Force:$true -NotDefault
	} Catch {
		DefaultErrorLogging
	}
}

If ($connection.IsConnected -ne $True){
	ExitPrematurely ("Unable to connect to vCenter server " + $vCenterServerName)
}

Try {$VMwareVirtualMachines = (Get-View -Server $connection -ViewType VirtualMachine -Property Summary,Network -Filter @{"Config.Template"="false"}) | Select Summary,Network}
Catch {DefaultErrorLogging}

If (!$VMwareVirtualMachines){
	Try {Disconnect-VIServer -Server $connection -Confirm:$false}
	Catch {DefaultErrorLogging}
	ExitPrematurely ("No VMs found in vCenter " + $vCenterServerName)
}

ForEach ($VM in $VMwareVirtualMachines){

	If ($VMobjs | Where {$_.'[Community.VMware.Class.VirtualMachine].VirtualMachineId'.Value -eq [string]$VM.Summary.Vm}){

		#Virtual Machine Obj (already discovered)
		$VMInstance = $discoveryData.CreateClassInstance("$MPElement[Name='Community.VMware.Class.VirtualMachine']$")
		$VMInstance.AddProperty("$MPElement[Name='Community.VMware.Class.VirtualMachine']/VirtualMachineId$", [string]$VM.Summary.Vm )
		$VMInstance.AddProperty("$MPElement[Name='Community.VMware.Class.vCenter']/vCenterServerName$", $vCenterServerName )
		
		ForEach ($VMnetwork in $VM.Network){
		
			$MatchingNetwork = $VMnetworkObjs | Where {$_.'[Community.VMware.Class.Network].NetworkId'.Value -eq [string]$VMnetwork}
			If ($MatchingNetwork){
			
				#Network Obj (already discovered)
				$VMnetworkInstance = $discoveryData.CreateClassInstance("$MPElement[Name='Community.VMware.Class.Network']$")
				$VMnetworkInstance.AddProperty("$MPElement[Name='Community.VMware.Class.Network']/NetworkId$", [string]$MatchingNetwork.'[Community.VMware.Class.Network].NetworkId'.Value )
				$VMnetworkInstance.AddProperty("$MPElement[Name='Community.VMware.Class.vCenter']/vCenterServerName$", $vCenterServerName )
				
				#VM references Network
				$rel1 = $discoveryData.CreateRelationshipInstance("$MPElement[Name='Community.VMware.Relationship.VirtualMachineReferencesNetwork']$")
				$rel1.Source = $VMInstance
				$rel1.Target = $VMnetworkInstance
				$discoveryData.AddInstance($rel1)
			}
		}
	}
}
Try {Disconnect-VIServer -Server $connection -Confirm:$false}
Catch {DefaultErrorLogging}
$discoveryData