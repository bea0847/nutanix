<#
.SYNOPSIS
  This script cycles through a Nutanix Cluster and puts each ESX host in Maintenance Mode for 10 minutes.
.DESCRIPTION
  Script finds the list of CVMs and ESX hosts based on a specified ESX Cluster name in a specified vCenter server.
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
.PARAMETER cluster
  Name of compute cluster. If not specified, script fails
.PARAMETER duration
  Sets the duration of time the Hosts will stay in Maintenance mode (in seconds)
.PARAMETER CVMCredentials
  Account Credentials to access CVMs within the Nutanix Cluster
.EXAMPLE
  Configure all CVMs in the vCenter server of your choice:
  PS> .\maint_cycle.ps1 -vcenter myvcenter.local -cluster NTNXCluster1 -duration 600
.LINK
  http://www.nutanix.com/services
.NOTES
  Author: Mike Beadle (mbeadle@nutanix.com), Script Flow, Logic, Comments, and Sarcasm by Stephane Bourdeaud.
  Revision: December 28th, 2017
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
    [parameter(mandatory = $true)] [string]$vcenter,
	[parameter(mandatory = $true)] [string]$cluster,
    [parameter(mandatory = $true)] [string]$duration,
    [parameter(mandatory = $false)] [PSCredential]$CVMCred,
    [parameter(mandatory = $false)] [PSCredential]$VCenterCred
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
 12/26/2017  MB   Update CVM Credentials and sleep timer
 
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
    $CVMCred = Get-Credential -Message "Enter User/ Pass for Nutanix CVM"
    $VcenterCred = Get-Credential -Message "Enter User/ Pass for vCenter $vcenter"
#endregion

#region parameters validation
	############################################################################
	# command line arguments initialization
	############################################################################	
	#let's initialize parameters if they haven't been specified
	if (!$vcenter) {$vcenter = read-host "Enter vCenter server name or IP address"}#prompt for vcenter server name
	$myvarvCenterServers = $vcenter.Split(",") #make sure we parse the argument in case it contains several entries
    if (!$cluster) {$cluster = read-host "Enter the vSphere cluster name"}
#endregion	

#region processing
	################################
	##  foreach vCenter loop      ##
	################################
	foreach ($myvarvCenter in $myvarvCenterServers)	
	{
		OutputLogData -category "INFO" -message "Connecting to vCenter server $myvarvCenter..."
		if (!($myvarvCenterObject = Connect-VIServer $myvarvCenter -User $VCenterCred.UserName -Password $VCenterCred.GetNetworkCredential().Password))#make sure we connect to the vcenter server OK...
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
			OutputLogData -category "INFO" -message "Retrieving CVM objects in Cluster $cluster..."
			if ($cluster)
			{$myvarCVMs = Get-Cluster -Name $cluster | Get-VM -Name ntnx-*-cvm} 
                
			else {$myvarCVMs = Get-VM -Name ntnx-*-cvm } 
			
			foreach ($myvarCVM in $myvarCVMs)
			{

                #Begin CVM Shutdown and Maintenance Loop

			    #Use the IP address of the CVM to connect to it with SSH
			    $myvarCVMip = $myvarCVM.guest.IPAddress[0]
    			$myvarHost = Get-VMHost -VM $myvarCVM
				
			    #Using the default user/pass
			    New-SshSession -ComputerName $myvarCVMip -Username $CVMCred.UserName -Password $CVMCred.GetNetworkCredential().Password | Out-N
    
			    #Check cluster status to ensure all servcies on all CVMs are healthy. 
			    $myvarresult = Invoke-SshCommand -ComputerName $myvarCVMip -Command '/home/nutanix/cluster/bin/cluster status | grep -v UP' -Quiet
			    Remove-SshSession -RemoveAll | Out-Null
    
			    #Shutting down a CVM if there are no CVMs DOWN and SSH connection was successful
			    If ($myvarresult -NotLike "* down*" -and $myvarresult -NotLike "*No SSH session found*" -and $myvarresult -NotLike "*Failed to reach a node*") 
                    {
			        OutputLogData -category "INFO" -message "Shutting down $myvarCVM"
			        Shutdown-VMGuest $myvarCVM -Confirm:$false | Out-Null
        
			        #Wait a period of time to make sure the CVM is shutdown before issuing host maint request
			        sleep 60
					
			        #Put host in Maintenance Mode
					OutputLogData -category "INFO" -message "Entering Maintenance Mode on $myvarHost"
					Set-VMhost $myvarHost -State maintenance -Evacuate | Out-Null  #May need to change State to ConnectionState in the future	        
			        OutputLogData -category "INFO" -message "Host $myvarHost in Maintenance Mode.  Sleeping for $duration seconds"
					
					#Wait for specified period of time (-duration switch) before coming out of Maintenance Mode
					sleep $duration
					
					# Exit maintenance mode
					OutputLogData -category "INFO" -message "Exiting Maintenance mode on $myvarHost"
					Set-VMhost $myvarHost -State Connected | Out-Null  #May need to change State to ConnectionState in the future
					OutputLogData -category "INFO" -message "Host $myvarHost now in Connected State"
					
					#Power-on CVM
			        OutputLogData -category "INFO" -message "Starting $myvarCVM"
			        Start-VM $myvarCVM -Confirm:$false | Out-Null
        
			       
			        #Wait for CVM to start before checking that it is UP
			        sleep 90
			        OutputLogData -category "INFO" -message "Waiting for Nutanix Services to start on CVM $myvarCVM..."
        
			        #Check that the services are started on the CVM before cycling the next CVM, check cluster status output for DOWN
        
			        Do {
							New-SshSession -ComputerName $myvarCVMip -Username $CVMCred.UserName -Password $CVMCred.GetNetworkCredential().Password  | Out-Null
							$myvarresult = Invoke-SshCommand -ComputerName $myvarCVMip -Command "/home/nutanix/cluster/bin/cluster status | grep -v UP" -Quiet
							Remove-SshSession -RemoveAll | Out-Null
            
							#If the services are not started there will be a DOWN in the output
							If ($myvarresult -like "* down*" -or $myvarresult -like "*No SSH session found*" -or $myvarresult -like "*Failed to reach a node*") {OutputLogData -category "INFO" -message "$myvarCVM Still Down or Cluster State not Healthy"}
								#Wait before attempting to make another SSH connection
								sleep 10
						}	
							#Until checks the service is started, there will be no DOWN statement
							Until ($myvarresult -notlike "* down*" -and $myvarresult -notlike "*No SSH session found*" -and $myvarresult -notlike "*Failed to reach a node*")
							OutputLogData -category "INFO" -message "$myvarCVM Up"
				        
				        } ## end Maintenace Loop
				  
				Else 
						{
						OutputLogData -category "ERROR" -message "Cluster Status Reports a CVM or Service as Down, please investigate"
						return   	
						}
				} ## end CVM Shutdown and Maintenance Loop
	
		
		}#endif
        OutputLogData -category "INFO" -message "Disconnecting from vCenter server $vcenter..."
		Disconnect-viserver -Confirm:$False #cleanup after ourselves and disconnect from vcenter
	}#end foreach vCenter
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
    Remove-Variable CVMCred -ErrorAction SilentlyContinue
    Remove-Variable vCenterCred -ErrorAction SilentlyContinue
    Remove-Variable debugme -ErrorAction SilentlyContinue
	Remove-Variable cluster -ErrorAction SilentlyContinue
    Remove-Variable duration -ErrorAction SilentlyContinue
#endregion
