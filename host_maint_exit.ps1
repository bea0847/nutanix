<#
.SYNOPSIS
  This script brings an ESX host out of Maintenance Mode and starts the associated CVM 
.DESCRIPTION
  Script brings the specified ESX Host out of Maintenance Mode. Starts the associated CVM. Then waits for CVMs services to start
  and cluster status to be healthy.  Associated host_maint_enter.ps1 script to enter Maintenance mode and restart the cluster.
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
  Name of ESX host. If not specified, script fails
.PARAMETER CVMCred
  Account Credentials to access CVMs within the Nutanix Cluster
.PARAMETER VCenterCred
  Account Credentials to access vCenter
.EXAMPLE
  Configure all CVMs in the vCenter server of your choice:
  PS> .\host_maint_exit.ps1 -vcenter myvcenter.local -esxhost myhost-01.local
.KNOWN_ISSUES 
  Script doesn't validate host name is valid.  Will process on incorrect Hostname/IP, essentially executing nothing on an invalid or nonexistent host.  
.LINK
  http://www.nutanix.com/services
.NOTES
  Author: Mike Beadle (mbeadle@nutanix.com), Script Flow, Logic, Comments, and Sarcasm by Stephane Bourdeaud.
  Revision: January 2nd, 2018
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
	[parameter(mandatory = $false)] [string]$esxhost,
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
 1/2/2018    MB   Updated to collect credentials instead of hardcoding
################################################################################
'@
$myvarScriptName = ".\host_maint_exit.ps1"
 
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
    if (!$esxhost) {$esxhost = read-host "Enter the ESX host name"}
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
			

                #Begin Exit Maintenance and CVM Startup
                			    
    			$myvarCVMname = $myvarCVM.Name
				
			   	# Exit maintenance mode
				OutputLogData -category "INFO" -message "Exiting Maintenance mode on $esxhost"
				Set-VMhost $esxhost -State Connected | Out-Null  #May need to change State to ConnectionState in the future
				    
                #Wait for Host to Exit Maintenance Mode
				Do {
			            $myvarresult = (get-vmhost $esxhost).ConnectionState 
            
			            #If Maintenance loop back and check again in 5 seconds
			            If ($myvarresult -like '*Maintenance*') {OutputLogData -category "INFO" -message "$esxhost still in Maintenance Mode"}
			            #Wait before attempting to make another SSH connection
			            sleep 5
			        }
			        #Connected State implies host is out of maintenance mode
			        Until ($myvarresult -like '*Connected*')	
                    OutputLogData -category "INFO" -message "Host $esxhost now in Connected State"
                
				#Power-on CVM
			    OutputLogData -category "INFO" -message "Starting $myvarCVMname"
			    Start-VM $myvarCVMname -Confirm:$false | Out-Null
        
			       
			    #Wait for CVM to start before checking that it is Up
			    OutputLogData -category "INFO" -message "Waiting for Nutanix Services to start on CVM $myvarCVMname..."
                sleep 90
                
                #Discover CVM IP address after power on.
                $myvarCVM = Get-VMHost -Name $esxhost | Get-VM -Name ntnx-*-cvm 
                $myvarCVMip = $myvarCVM.guest.IPAddress[0]

                #Check that the services are started on the CVM.
        
			        Do {
							New-SshSession -ComputerName $myvarCVMip -Username $CVMCred.UserName -Password $CVMCred.GetNetworkCredential().Password | Out-Null
							$myvarresult = Invoke-SshCommand -ComputerName $myvarCVMip -Command "/home/nutanix/cluster/bin/cluster status | grep -v UP" -Quiet
							Remove-SshSession -RemoveAll | Out-Null
            
							#Check for DOWN status (trying to exclude "Lockdown"
							If ($myvarresult -like "* down*" -or $myvarresult -like "*No SSH session found*" -or $myvarresult -Like "*Failed to reach a node*") {OutputLogData -category "INFO" -message "$myvarCVM or Services Still Down"} 
							#Wait before attempting to make another SSH connection
							sleep 10
			            }
			         Until ($myvarresult -notlike "* down*"-and $myvarresult -notlike "*No SSH session found*" -and $myvarresult -NotLike "*Failed to reach a node*")
			            OutputLogData -category "INFO" -message "$myvarCVM Up and Cluster Status is Healthy"

				    } ## end Maintenace Loop
				}
	
			
		
        OutputLogData -category "INFO" -message "Disconnecting from vCenter server $vcenter..."
		Disconnect-viserver -Confirm:$False #cleanup after ourselves and disconnect from vcenter
	
#endregion

#region cleanup
#########################
##       cleanup       ##
#########################

	#let's figure out how much time this all took
	OutputLogData -category "SUM" -message "total processing time: $($myvarElapsedTime.Elapsed.ToString())"
	
	#cleanup after ourselves and delete all custom variables
	#Remove-Variable myvar* -ErrorAction SilentlyContinue
	#Remove-Variable ErrorActionPreference -ErrorAction SilentlyContinue
	#Remove-Variable help -ErrorAction SilentlyContinue
    #Remove-Variable history -ErrorAction SilentlyContinue
	#Remove-Variable log -ErrorAction SilentlyContinue
	#Remove-Variable vcenter -ErrorAction SilentlyContinue
    #Remove-Variable debugme -ErrorAction SilentlyContinue
	#Remove-Variable cluster -ErrorAction SilentlyContinue
#endregion