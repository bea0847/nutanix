<#
.SYNOPSIS
  This script cycles checks the health of a Nutanix Cluster and puts a single ESX host in Maintenance Mode 
.DESCRIPTION
  Script finds the local CVMs on the ESX host specified.  It validates the associated CVM's cluster status, and shut
  CVM down if healthy.  Then the host is itself put into maintenance mode.   Associated host_maint_exit.ps1 script to 
  exit Maintenance mode and restart the cluster.
.PARAMETER help
  Displays a help message 
.PARAMETER history
  Displays a release history for this script 
.PARAMETER log
  Specifies that you want the output messages to be written in a log file as well as on the screen.
.PARAMETER debugme
  Turns off SilentlyContinue on unexpected error messages.
.PARAMETER vcenter
  VMware vCenter server hostname. Default is localhost. You can specify several hostnames by separating entries with commas.
.PARAMETER esxhost
  Name of ESXi host. If not specified, script fails
.EXAMPLE
  Configure all CVMs in the vCenter server of your choice:
  PS> .\host_maint_enter.ps1 -vcenter myvcenter.local -esxhost myhost-01.local
.LINK
  http://www.nutanix.com/services
.NOTES
  Author: Mike Beadle (mbeadle@nutanix.com), Script Flow, Logic, Comments, and Sarcasm by Stephane Bourdeaud.
  Revision: December 7th, 2017
#>

#region parameters
######################################
##   parameters and initial setup   ##
######################################
#let's start with some command line parsing
Param
(
    #[parameter(valuefrompipeline = $true, mandatory = $true)] [PSObject]$myParam1,
    [parameter(mandatory = $false)] [switch]$help,
    [parameter(mandatory = $false)] [switch]$history,
    [parameter(mandatory = $false)] [switch]$log,
    [parameter(mandatory = $false)] [switch]$debugme,
    [parameter(mandatory = $false)] [string]$vcenter,
	[parameter(mandatory = $false)] [string]$esxhost
)
#endregion

#region functions
########################
##   main functions   ##
########################

#this function is used to output log data
Function OutputLogData 
{
	#input: log category, log message
	#output: text to standard output
<#
.SYNOPSIS
  Outputs messages to the screen and/or log file.
.DESCRIPTION
  This function is used to produce screen and log output which is categorized, time stamped and color coded.
.NOTES
  Author: Stephane Bourdeaud
.PARAMETER myCategory
  This the category of message being outputed. If you want color coding, use either "INFO", "WARNING", "ERROR" or "SUM".
.PARAMETER myMessage
  This is the actual message you want to display.
.EXAMPLE
  PS> OutputLogData -mycategory "ERROR" -mymessage "You must specify a cluster name!"
#>
	param
	(
		[string] $category,
		[string] $message
	)

    begin
    {
	    $myvarDate = get-date
	    $myvarFgColor = "Gray"
	    switch ($category)
	    {
		    "INFO" {$myvarFgColor = "Green"}
		    "WARNING" {$myvarFgColor = "Yellow"}
		    "ERROR" {$myvarFgColor = "Red"}
		    "SUM" {$myvarFgColor = "Magenta"}
	    }
    }

    process
    {
	    Write-Host -ForegroundColor $myvarFgColor "$myvarDate [$category] $message"
	    if ($log) {Write-Output "$myvarDate [$category] $message" >>$myvarOutputLogFile}
    }

    end
    {
        Remove-variable category
        Remove-variable message
        Remove-variable myvarDate
        Remove-variable myvarFgColor
    }
}#end function OutputLogData
#endregion

#region prepwork
# get rid of annoying error messages
if (!$debugme) {$ErrorActionPreference = "SilentlyContinue"}

#check if we need to display help and/or history
$HistoryText = @'
 Maintenance Log
 Date       By   Updates (newest updates at the top)
 ---------- ---- ---------------------------------------------------------------
 12/6/2017   MB   Initial release.
 
################################################################################
'@
$myvarScriptName = ".\maint_cycle.ps1"
 
if ($help) {get-help $myvarScriptName; exit}
if ($History) {$HistoryText; exit}



#let's make sure the PowerCLI modules are being used
if (!($myvarPowerCLI = Get-PSSnapin VMware.VimAutomation.Core -Registered)) {
    if (!($myvarPowerCLI = Get-Module VMware.VimAutomation.Core)) {
        Import-Module -Name VMware.VimAutomation.Core
        $myvarPowerCLI = Get-Module VMware.VimAutomation.Core
    }
}
try {
    if ($myvarPowerCLI.Version.Major -ge 6) {
        if ($myvarPowerCLI.Version.Minor -ge 5) {
            Import-Module VMware.VimAutomation.Vds -ErrorAction Stop
            OutputLogData -category "INFO" -message "PowerCLI 6.5+ module imported"
        } else {
            throw "This script requires PowerCLI version 6.5 or later which can be downloaded from https://my.vmware.com/web/vmware/details?downloadGroup=PCLI650R1&productId=614"
        }
    } else {
        throw "This script requires PowerCLI version 6.5 or later which can be downloaded from https://my.vmware.com/web/vmware/details?downloadGroup=PCLI650R1&productId=614"
    }
}
catch {throw "Could not load the required VMware.VimAutomation.Vds cmdlets"}
#endregion

#region variables
#initialize variables
	#misc variables
	$myvarElapsedTime = [System.Diagnostics.Stopwatch]::StartNew() #used to store script begin timestamp
	$myvarvCenterServers = @() #used to store the list of all the vCenter servers we must connect to
	$myvarOutputLogFile = (Get-Date -UFormat "%Y_%m_%d_%H_%M_")
	$myvarOutputLogFile += "OutputLog.log"
#endregion

#region parameters validation
	############################################################################
	# command line arguments initialization
	############################################################################	
	#let's initialize parameters if they haven't been specified
	if (!$vcenter) {$vcenter = read-host "Enter vCenter server name or IP address"}#prompt for vcenter server name
	$myvarvCenterServers = $vcenter.Split(",") #make sure we parse the argument in case it contains several entries
    if (!$esxhost) {$esxhost = read-host "Enter the ESX host name"}
#endregion	

#region processing
	################################
	##  foreach vCenter loop      ##
	################################
	foreach ($myvarvCenter in $myvarvCenterServers)	
	{
		OutputLogData -category "INFO" -message "Connecting to vCenter server $myvarvCenter..."
		if (!($myvarvCenterObject = Connect-VIServer $myvarvCenter))#make sure we connect to the vcenter server OK...
		{#make sure we can connect to the vCenter server
			$myvarerror = $error[0].Exception.Message
			OutputLogData -category "ERROR" -message "$myvarerror"
			return
		}
		else #...otherwise show the error message
		{
			OutputLogData -category "INFO" -message "Connected to vCenter server $myvarvCenter."
		}#endelse
		
		if ($myvarvCenterObject)
		{
		
			######################
			#main processing here#
			######################
			OutputLogData -category "INFO" -message "Determining CVM associated with ESXi Host $esxhost..."
			if ($esxhost)
			{
				$myvarCVM = Get-VMHost -Name $esxhost | Get-VM -Name ntnx-*-cvm 
                }
			else
			{
				 OutputLogData -category "ERROR" -message "ESX Host name not provided.  Please use -esxhost switch or enter hostname when prompted"
			     return

			}
			

                #Begin CVM Shutdown and Maintenance Loop

			    #Use the IP address of the CVM to connect to it with SSH
			    $myvarCVMip = $myvarCVM.guest.IPAddress[0]
    			$myvarCVMname = $myvarCVM.Name
				
                #Using the default user/pass
			    New-SshSession -ComputerName $myvarCVMip -Username 'nutanix' -Password 'nutanix/4u' | Out-Null
    
			    #Check cluster status to validate all services are healthy.  
			    OutputLogData -category "INFO" -message "Checking Nutanix Cluster Status Health, this may take a bit depending on the cluster size..."
                $myvarresult = Invoke-SshCommand -ComputerName $myvarCVMip -Command '/home/nutanix/cluster/bin/cluster status | grep -v UP ' -Quiet
			    Remove-SshSession -RemoveAll | Out-Null
    
			    #MaintenanceLoop - Shutting down a CVM if there are no CVMs DOWN and SSH connection was successful
			    If ($myvarresult -notlike "* down*" -and $myvarresult -notlike "*No SSH session found*" -and $myvarresult -NotLike "*Failed to reach a node*") 
                    {
			        OutputLogData -category "INFO" -message "Cluster Status is Healthy.  Shutting down $myvarCVMname"
			        Shutdown-VMGuest $myvarCVMname -Confirm:$false | Out-Null
        
			        #Wait a period of time to make sure the CVM is shutdown before issuing host maint request
			        sleep 60
					
			        #Put host in Maintenance Mode
					OutputLogData -category "INFO" -message "Entering Maintenance Mode on $esxHost"
					Set-VMhost $esxHost -State maintenance -Evacuate | Out-Null  #May need to change State to ConnectionState in the future	        
			        OutputLogData -category "INFO" -message "Host $esxHost in Maintenance Mode. "
					}
				Else 
                    {
                     OutputLogData -category "ERROR" -message "Cluster Status Reports a CVM or Service as Down, please investigate"
			            return   	
				     }
                  
			} ## end CVM Shutdown and Maintenance Loop
		}#endif
        OutputLogData -category "INFO" -message "Disconnecting from vCenter server $vcenter..."
		Disconnect-viserver -Confirm:$False #cleanup after ourselves and disconnect from vcenter
	#}#end foreach vCenter
#endregion

#region cleanup
#########################
##       cleanup       ##
#########################

	#let's figure out how much time this all took
	OutputLogData -category "SUM" -message "total processing time: $($myvarElapsedTime.Elapsed.ToString())"
	
	#cleanup after ourselves and delete all custom variables
	Remove-Variable myvar* -ErrorAction SilentlyContinue
	Remove-Variable ErrorActionPreference -ErrorAction SilentlyContinue
	Remove-Variable help -ErrorAction SilentlyContinue
    Remove-Variable history -ErrorAction SilentlyContinue
	Remove-Variable log -ErrorAction SilentlyContinue
	Remove-Variable vcenter -ErrorAction SilentlyContinue
    Remove-Variable debugme -ErrorAction SilentlyContinue
	Remove-Variable esxhost -ErrorAction SilentlyContinue
#endregion