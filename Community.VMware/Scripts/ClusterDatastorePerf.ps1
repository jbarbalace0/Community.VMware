﻿param($vCenterServerName)

if (Test-path C:\vCenter\Server.txt){
    $Server=(Get-content C:\vCenter\Server.txt).Trim()
    $vCenterServerName=$Server
}

$ScriptName = 'Community.VMware.Probe.ClusterDatastorePerf.ps1'
$api = new-object -comObject 'MOM.ScriptAPI'

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
	LogScriptEvent -EventLevel 1 -Message ("$_`rType:$($_.Exception.GetType().FullName)`r$($_.InvocationInfo.PositionMessage)`rReceivedParam:`rvCenterServerName:$vCenterServerName")
}

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
		Exit
	}
}

Try {$VMclustersView = Get-View -Server $connection -ViewType ComputeResource -Property Datastore | Select Datastore,MoRef}
Catch {DefaultErrorLogging}

If (!$VMclustersView){
	LogScriptEvent 0 ("No clusters found in vCenter server " + $vCenterServerName)
	Try {Disconnect-VIServer -Server $connection -Confirm:$false}
	Catch {DefaultErrorLogging}
	exit
}

Try {$VMdatastores = Get-View -Server $connection -ViewType Datastore -Property Summary | Select Summary}
Catch {DefaultErrorLogging}

If (!$VMdatastores){
	LogScriptEvent 0 ("No datastores found in vCenter server " + $vCenterServerName)
	Try {Disconnect-VIServer -Server $connection -Confirm:$false}
	Catch {DefaultErrorLogging}
	exit
}

ForEach ($VMcluster in $VMclustersView){

	$CAPACITY_GB	= 0
	$FREE_GB		= 0
	$USED_GB		= 0
	$FREE_Percent	= 0
	$USED_Percent	= 0
	
	ForEach ($VMclusterDataStore in $VMcluster.Datastore){
	
		$VMdatastoreView = $VMdatastores | Where {$_.Summary.Datastore -eq [string]$VMclusterDataStore}
		
		If ($VMdatastoreView){
		
			$Store_CAPACITY_GB	= $VMdatastoreView.Summary.Capacity * (9.31323e-10)
			$Store_FREE_GB		= $VMdatastoreView.Summary.FreeSpace * (9.31323e-10)
			$Store_USED_GB		= ($VMdatastoreView.Summary.Capacity - $VMdatastoreView.Summary.FreeSpace)*(9.31323e-10)
			
			$CAPACITY_GB	= $CAPACITY_GB + $Store_CAPACITY_GB
			$FREE_GB		= $FREE_GB + $Store_FREE_GB
			$USED_GB		= $USED_GB + $Store_USED_GB
		}
	}
	
	If ($CAPACITY_GB -ne 0){
		$FREE_Percent	= [math]::Round((($FREE_GB * 100)/$CAPACITY_GB) , 2)
		$USED_Percent	= [math]::Round((($USED_GB * 100)/$CAPACITY_GB) , 2)
	}
	$CAPACITY_GB	= [math]::Round($CAPACITY_GB, 2)
	$FREE_GB		= [math]::Round($FREE_GB, 2) 
	$USED_GB		= [math]::Round($USED_GB, 2)
	
	$bag = $api.CreatePropertyBag()
	$bag.AddValue('ClusterId', [string]$VMcluster.MoRef)
	$bag.AddValue('vCenterServerName',$vCenterServerName)
	$bag.AddValue('CAPACITY_GB',$CAPACITY_GB)
	$bag.AddValue('FREE_GB',$FREE_GB)
	$bag.AddValue('USED_GB',$USED_GB)
	$bag.AddValue('FREE_Percent',$FREE_Percent)
	$bag.AddValue('USED_Percent',$USED_Percent)
	$bag
}
Try {Disconnect-VIServer -Server $connection -Confirm:$false}
Catch {DefaultErrorLogging}