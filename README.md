I am by no means an efficient script writer.  I can read scripts, understand what they're doing, and bend them to my will (eventually).  However, when I'm done, they look like Frankenstein's monster. Use these as an example, and be careful with them.   I have validated their basic function in a lab, but have not let them loose in a large Production environment.


NOTE: Most scripts require PowerCLI (https://my.vmware.com/web/vmware/details?downloadGroup=PCLI650R1&productId=614) and/or Nutanix CmdLets (which can be downloaded from the user menu in Prism).

Collection of scripts used for Nutanix Services:

maint_cycle.ps1: customer request  -  roll ESX cluster into Maintenance Mode for a 10 minute period.  Used to apply NSX vib updates without needing a host reboot.  Validates Nutanix cluster status before starting, and after each CVM is brought up, before moving on to next host.

host_maint_enter.ps1: customer request - Scripted Nutanix cluster status validation as UP, CVM shutdown, and host to enter Maintenance mode.

host_maint_enter.ps1: customer request - Scripted Host to exit Maintenance Mode, start CVM, wait for valid Nutanix cluster status UP.

Please report any bugs here. 
