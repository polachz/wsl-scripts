# wsl-scripts
Various scripts to make life with **Windows Subsystem for Linux** ( WSL2 ) easier:

* **Download Script to create WSL2 Image from any DockerHub image** --  [_download-wsl2-image.ps1_](#download-script)
* **Deploy Script to create new WSL2 Linux instance from an WSL2 Image** --  [_deploy-wsl2-image.ps1_](#deploy-script)
* **Script to make WSL subnet static and handle WSL Adapter Firewall rules** -- [_make-wsl-net-static.ps1_](#static-wsl-subnet-script)
##### Hints:

- To bypass Power Shell policy, you can use this trick from PowerShell console:

    `PowerShell.exe -ExecutionPolicy Bypass -File script_to_run.ps1 <params...>`

- You can find example how to use these scripts for daily use at my repo [https://github.com/polachz/wsl](https://github.com/polachz/wsl).
I'm use this to build and bootstrap my favorite Linux distribution - Fedora for my daily operations.

-----------------------------------------------------------------------------------------------------------------------------------------------------------------

### Download Script

The script is able to download and create deployable WSL2 image from a DockerHub image. The image can be deployed as WSL2 instance directly by _wsl.exe --import_ command or by the script [_deploy-wsl2-image.ps1_](#deploy-script) then.

##### Usage:

`download-wsl2-image.ps1 -Image library/ubuntu -Destination E:\WSL_ubuntu`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; Downloads the latest ubuntu image and stores it at 'E:\WSL_ubuntu' folder

`download-wsl2-image.ps1 -Image library/fedora -Tag 32 -Destination E:\WSL -MakeDir`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; Downloads the fedora 32 image and stores it at 'E:\WSL\fedora_32' folder

###### Parameters:

* **Image** (Mandatory) - Specifies the docker hub image name. Consider that Docker Official images has prefix library, then Fedora official image name is library/fedora. Official Ubuntu image name is library/ubuntu etc...

* **Destination** (Mandatory) -  Folder where the created WSL2 Linux instance image will be stored or where sub-folder will be created if the **-MakeDir** parameter is specified.

* **Tag** (default value = **latest**) - Specifies the DockerHub image Tag. If not specified the **'latest'** tag is used.

* **MakeDir** - If specified then the script will create sub-folder at Destination with name 'Image_Tag' and then downloads the image here. If the Tag is not specified, only the 'Image' sub-folder is created

* **Force** - If specified and image already exists then image is overwritten by new one. Otherwise the script prints warning and exits.
### IMPORTANT NOTICE

Because native Windows tar executable doesn't support **--combine** option and this is essential for correct script functionality, the external tar Windows executable (renamed to **_img-pkg.exe_**) is included into the repository. If you do not trust this file then find your own tar executable with **--combine** supported option and rename it to **img-pkg.exe**.

-----------------------------------------------------------------------------------------------------------------------------------------------------------------

### Deploy Script

This script automates deployment of fresh WSL2 instances from specified image or exported backup. By this script is possible to deploy fresh WSL2 instance without interaction with MS Windows Store. For Ubuntu 20.04 is supported automatic image download from Ubuntu servers, then deployment is as easy as possible (see _UbuntuImageDir_ parameter)

Script also allows bootstrapping of the deployed image by specified scripts. These bootstrap scripts can be run as root, normal user or both and by this mechanism is possible to  customize image automatically.

##### Usage:

`deploy-wsl2-image.ps1 Ubuntu22 linux_user -DisksDir e:\WSL\Disks -Image E:\WSL\Ubu.tar.gz`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Deploy WSL instance with name Ubuntu22, store disk in the folder 'e:\WSL\Disks' and<br>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;creates new default user with name 'linux_user'. As source uses image 'E:\WSL\Ubu.tar.gz'

###### Parameters:

* **InstanceName** (Mandatory) - Name of the WSL Instance. Can be specified also as the first positional parameter of the script. Must be unique and Windows WSL will use this name to identify the instance. If instance with same name already exists, script generates error and fail. I
* **UserName** - Name of the user account to be created at the WSL Instance. Can be specified also as the second positional parameter of the script. if user already exists inside the WSL instance then creating and bootstrapping for the user is skipped.
* **Destination** (Mutual exclusive with _DisksDir_) - Folder where the vmdx file for the WSL2 instance will be created. The ext4.vhdx file can't exist in the folder. otherwise the script generates error and stop.
* **DisksDir** (Mutual exclusive with _Destination_) - Folder where sub-directory with _InstanceName_ will be created to store WSL2 Instance ext4.vmdx virtual disk file.
		This parameter allows to organize WSL2 Instances vhdx inside this folder by this way:
    <pre>
    - DisksDir
      - Instance1\ext4.vhdx
      - Instance2\ext4.vhdx
      - <b>InstanceName</b>\ext4.vhdx
      - .....
      - InstanceX\ext4.vhdx
   </pre>
   The InstanceName folder can already exists, but the ext4.vhdx file can't exist in the folder. otherwise the script generates error and stop.

* **Image** (Mutual exclusive with _UbuntuImageDir_) - Path to the image file from which the WSL Instance will be deployed. 
* **UbuntuImageDir** (Mutual exclusive with _Image_) - Path where the Ubuntu 20.04 image will be downloaded if not already exists and then used for deployment. This allows easy unattended Ubuntu 20.04 deployment without MS Store assistance
* **ForceDownload** Makes sense only for Well-known images (As for Ubuntu 20.04 for example). Otherwise is ignored. If specified then the Well-known image will be re-downloaded from distribution point even if already exists in the Image folder.
* **BootstrapRootScript** If specified then the file is copied to /root folder inside the new fresh image and run as shell script under the root user account. It allows to provide necessary modifications to deployed image as install required software packages, update image by package manager to latest versions etc...
* **BootstrapUserScript** If specified then the file is copied to /home/<UserNAme> folder inside the new fresh image and run as shell script under the <UserNAme> user account. It allows to provide custom modifications to deployed image as deploy configs, dot files and other user related stuff.

##### Bootstrapping

The deployment process can be customized by run of the bootstrap script(s). The script will run inside the deployed image and it can be run as root script or user script. Is possible to run only one or both bootstrap scripts during the deployment process.

The Bootstrap script can be specified by three ways

1. Explicitly by parameter (*BootstrapRootScript, *BootstrapUserScript)

1. Can be placed to same folder as image and have to have specific filename:
   * **root_bootstrap** For bootstrap script run as root
   * **user_bootstrap** For bootstrap script run as user with name specified by UserName parameter

   Then it's connected with the image and is used always when the image is deployed

1. For Well Known image ( UbuntuImageDir ) the default script located in the same directory as the main PowerShell script can be used (ubuntu_root_bootstrap) This option is valid only for well known image as the Ubuntu and this script for Ubuntu is member file of the repository.

-----------------------------------------------------------------------------------------------------------------------------------------------------------------

### Static WSL Subnet Script

If you are using WSL subsystem for some network based operations then you must know that WSL subnet get random IP range after every host reboot. Then is not possible to preserve connection parameters between WSL instances and host adapter reboot due this behavior. This make very difficult to develop network services inside the WSL instances (Web services, Docker containers, Kubernetes etc). Also development of ansible scripts or something similar inside the WSL is nightmare if you need to connect to host or some Hyper-V VM by network because IP addresses will be different after reboot. This script solves the problem.

The script remove WSL network with random IP range created by Windows, and then re-creates new one with defined fixed IP range. If this occurs immediately after reboot and before any WSL instance start then everything works smoothly for WSL instances - Internet connections, DHCP, DNS etc.

The script can also handle Windows Firewall rules for the WSL network. By default, Windows only create rules for DNS traffic. All other connection attempts from the WSL instance to the Windows host are blocked by native Windows Firewall. The script is able to create Windows Firewall rules based on the special configuration file in JSON format. Rules are valid only for WSL interface with name _vEthernet (WSL)_. Script rebinds these rule automatically after each reboot to grant functionality. These rules doesn't influence other adapters and connections. They are valid only for WSL subsystem and _vEthernet (WSL)_ adapter.

The script handle things only on the Windows host side. To make IP address static inside the WSL instance must be solved separately (And each Linux distribution solves the network configuration little bit differently). But when you know IP subnet for th WSL network, it can be done easily.

Main credit for this solution goes to github user **ocroz**. I have used many parts of his original work from this repository: [https://github.com/ocroz/wsl2-boot](https://github.com/ocroz/wsl2-boot) I have added the Firewall Support and config file parsing.

**Important note**: The script must be run elevated as Administrator or SYSTEM. Best solution is to schedule run of the script as boot task by Task Scheduler see [Create scheduler task](#how-to-create-scheduled-task).

##### Usage:

`scripts\make-wsl-net-static.ps1 -WslSubnet "192.168.5.1/24`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Re-Create WSL network on Windpows host and assign the subnet _192.168.5.1/24_
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;to the network. Assign IP _192.168.5.1 to_ the host gateway also.

`make-wsl-net-static.ps1 -UpdateFwRules -ConfigFile .\wsl-net.json`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Re-Create WSL network on Windows host and assign subnet and gateway IP specified
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;in the config file to the WSL network> Rebind FW rules specified in the config
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;file to re-created  _vEthernet (WSL)_ adapter.

`make-wsl-net-static.ps1 -UpdateFwRules -ConfigFile .\wsl-net.json`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Create new or update existing Windows Firewall rules specified in the config file.

`make-wsl-net-static.ps1 -RemoveFwRules -ConfigFile .\wsl-net.json`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Remove all FW rules specified in the config file from the Windows Firewall configuration.

###### Parameters:

* **UpdateFwRules** - Create new or update existing Windows Firewall rules specified in the config file.
* **RemoveFwRules** - Remove all FW rules specified in the config file from the Windows Firewall configuration.
* **ConfigFile** - Path to configuration file where the WSL subnet and FW rules are specified. The config file overrides the **WslSubnet** parameter if exists. See [Config File Format](#config-file-format) section.
* **WslSubnet** - Subnet and gateway IP definition for the WSL network in the CIDR format. For example, 192.168.3.5/24 leads to subnet 192.168.3.0 and mask 255.255.255.0 plus Wsl Network Gateway will have IP address 192.168.3.5 This parameter is ignored if ConfigFile is specified. In this case subnet definition from the config file is used.
* **Name** (default value:"WSL" ) - Specifies name of the networking ecosystem. WSL is default. See remarks section for details
* **Force** Provide all script actions even the current WSL subnet IP range and config or parameter specified IP range are same. If not specified, script skip network modification process if ranges are equal.

#### How to getting things up and running

1. Create config file to reflect your IP range and FW Rules requirements: [Config File Format](#config-file-format)
2. Create Fw rules. To do that. run this command:
   ```bat
   make-wsl-net-static.ps1 -UpdateFwRules -ConfigFile .\wsl-net.json
   ```
3. Create task for the Windows Task Scheduler [How to Create scheduler task](#how-to-create-scheduled-task).
4. Run the task manually
   ```bat
   schtasks /run /tn "Make WSL Net Static"
   ```
   or reboot the computer. Verify in the log that no error occurs.

   Optionally you can run the script directly:
   ```bat
   powershell.exe -ExecutionPolicy Bypass -file .\scripts\make-wsl-net-static.ps1 -ConfigFile .\wsl-net.json
   ```
5. Modify WSL instances to use static IP addresses and ranges (if you need this, otherwise DHCP works smoothly here)
6. If you need to modify any Firewall rule, please modify the config file, and then provide actions from the step 2
7. If you need to remove rule or rules, you can
- remove all rules in bulk by call
```bat
   make-wsl-net-static.ps1 -RemoveFwRules -ConfigFile .\wsl-net.json
   ```
   &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; then delete unwanted rules from config and re-create them again by actions from the step 2
- delete rule in the config file and manually from the Windows Firewall by call [**Remove-NetFirewallRule**](https://docs.microsoft.com/en-us/powershell/module/netsecurity/remove-netfirewallrule)

#### Remarks:

Windows use **the Host Networking Service (HNS)** and the **Host Compute Service (HCS)** to provide connections to WSL instances or Hyper-V computers. You can get list of available HNS networks by run PowerShell cmdlet **Get-HnsNetwork**

If you are familiar with Hyper-V then you know that same "Dynamic IP" range mechanism is used here for the Internal Hyper-V switch for example. I don't provide extensive testing for this but you can use this script to assign static IP range for these switches too. You must only change the **Name** parameter to name of the Local switch from the Hyper-V Virtual Switch manager. This opens many more possibilities here and you can also easily connect Hyper-V VMs to WSL network to bring possibility to talk directly between WSL instance and Hyper-V Virtual Machine.

#### Config File Format

Here you can see simple example of the config file:


```json
{
   "Config": {
        "subnet": "192.168.3.5/24",
        "rules":  [
            {
                    "name":           "WSl-Ping",
                    "direction":      "In",
                    "protocol":       "ICMPv4",
                    "icmptype":       "8:0",
                    "remoteaddress":  "Any"
                },
                {
                    "name":           "WSL-HTTP and HTTPS",
					     "direction":      "In",
                    "protocol":       "TCP",
                    "localport":      "80, 443",
                    "remoteaddress":  "Any"
                }
         ]
    }
}
```

The config file format is straightforward I think so is not necessary to make it's description more rich...

The mandatory property is the **subnet** to specify IP range and GW address.

You can also specify one or more Firewall rules. This definition uses subset of possible parameters from the [**New-NetFirewallRule**](https://docs.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule) or [**Set-NetFirewallRule**](https://docs.microsoft.com/en-us/powershell/module/netsecurity/set-netfirewallrule) PowerShell cmdlet. Allowed properties are:

- **name** (Mandatory) - leads to _-DisplayName_ cmdlet parameter
- **direction** - leads to _-Direction_ cmdlet parameter
- **protocol** - leads to _-Protocol_ cmdlet parameter
- **localport** - leads to _-LocalPort_ cmdlet parameter. Makes sense only if the protocol is TCP or UDP
- **icmptype** - leads to _-IcmpType_ cmdlet parameter. Makes sense only if the protocol is ICMPv4 or ICMPv6
- **remoteaddress** - leads to _-RemoteAddress_ cmdlet parameter

To get more detailed description of each parameter, see original cmdlet documentation: [**New-NetFirewallRule**](https://docs.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule)

**Notice:** Do not use comments inside the config file. It can make PowerShell JSON parser mad.


#### How to create scheduled task

My recommended solution is to create bat file to start the PowerShell script with all necessary parameters and redirect output to file as operations log:

```bat
powershell.exe -command "& { powershell.exe -ExecutionPolicy Bypass -file .\scripts\make-wsl-net-static.ps1 -ConfigFile .\wsl-net.json  2>&1 | tee .\boot.log}"
```
and then use this command (as elevated user) to create the task:

```bat
schtasks /create /tn "Make WSL Net Static" /xml ".\make_wsl_static_task.xml"
```

The XML file used to create the task is here. Please update <**Command**> and <**WorkingDirectory**> by your correct full classified paths (C:\xxx\.. for example)
```xml
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Date>2022-08-28T11:34:27.6963841</Date>
    <Author>Administrator</Author>
    <URI>\Make WSL Static</URI>
  </RegistrationInfo>
  <Triggers>
    <BootTrigger>
      <Enabled>true</Enabled>
    </BootTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>true</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>!!! PLACE FULL PATH TO BATCH FILE (C"\xxx\make_wsl_net_static.bat for example) HERE !!! </Command>
      <WorkingDirectory>!!! PLACE FULL PATH TO WORKING DIRECTORY (C"\xxx for example) HERE!!! </WorkingDirectory>
    </Exec>
  </Actions>
</Task>
```