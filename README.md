# wsl-scripts
Various scripts to make life with **Windows Subsystem for Linux** ( WSL2 ) easier:

* **Download Script to create WSL2 Image from any DockerHub image** --  [_download-wsl2-imgage.ps1_](#download-script)
* **Deploy Script to create new WSL2 Linux instance from an WSL2 Image** --  [_deploy-wsl2-image.ps1_](#deploy-script)

##### Hint:

To bypass Power Shell policy, you can use this trick from PowerShell console:

    PowerShell.exe -ExecutionPolicy Bypass -File script_to_run.ps1 <params...>
      
### Download Script

The script is able to download and create deployable WSL2 image from a DockerHub image. The image can be deployed as WSL2 instance directly by _wsl.exe --import_ command or by the script [_deploy-wsl2-image.ps1_](#deploy-script) then.

##### Usage:

`download-wsl2-imgage.ps1 -Image library/ubuntu -Destination E:\WSL_ubuntu`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; Downloads the latest ubuntu image and stores it at 'E:\WSL_ubuntu' folder

`download-wsl2-imgage.ps1 -Image library/fedora -Tag 32 -Destination E:\WSL -MakeDir`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; Downloads the fedora 32 image and stores it at 'E:\WSL\fedora_32' folder

###### Parameters:

* **Image** (Mandatory) - Specifies the docker hub image name. Consider that Dcoker Official images has prefix library, then Fedora official image name is library/fedora. Official Ubuntu image name is library/ubuntu etc... 

* **Destination** (Mandatory) -  Folder where the created WSL2 Linux instance image will be stored or where sub-folder will be created if the **-MakeDir** parameter is specified.

* **Tag** (default value = **latest**) - Specifies the DockerHub image Tag. If not specified the **'latest'** tag is used.

* **MakeDir** - If specified then the script will create sub-folder at Destination with name 'Image_Tag' and then downloads the image here. If the Tag is not specified, only the 'Image' sub-folder is created

* **Force** - If specified and image already exists then image is overwritten by new one. Otherwise the script prints warning and exits.
### IMPORTANT NOTICE

Because native Windows tar executable doesn't support **--combine** option and this is essential for correct script functionality, the external tar Windows executable (renamed to **_img-pkg.exe_**) is included into the repository. If you do not trust this file then find your own tar executable with **--combine** supported option and rename it to **img-pkg.exe**. 

-----------------------------------------------------------------------------------------------------------------------------------------------------------------

### Deploy Script

This script automates deployment of fresh WSL2 instances from specified image or exported backup. By this script is possible to deploy fresh WSL2 instance without interaction with MS Windows Store. For Ubuntu 20.04 is supported automatic image download from Ubuntu servers, then deployment is as easy as possible (see _UbuntuImageDir_ parameter)

Script also allows bootstrapping of the deployed image by specified scripts. These bootstap scripts can be run as root, normal user or both and by this mechanism is possible to  customise image automatically.

##### Usage:

`deploy-wsl2-image.ps1 Ubuntu22 linux_user -DisksDir e:\WSL\Disks -Image E:\WSL\Ubu.tar.gz`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Deploy WSL instance with name Ubuntu22, store disk in the folder 'e:\WSL\Disks' and<br>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;creates new default user with name 'linux_user'. As source uses image 'E:\WSL\Ubu.tar.gz'

###### Parameters:

* **InstanceName** (Mandatory) - Name of the WSL Instance. Can be specified also as the first positional parameter of the script. Must be unique and Windows WSL will use this name to identify the instance. If instance with same name already exists, script generates error and fail. I
* **UserName** - Name of the user account to be created at the WSL Instance. Can be specified also as the second positional parameter of the script. if user already exists inside the WSL instance then creating and bootstrapping for the user is skipped.
* **Destination** (Mutual exclusive with _DisksDir_) - Folder where the vmdx file for the WSL2 instance will be created. The ext4.vhdx file can't exist in the folder. otherwise the script generates error and stop.
* **DisksDir** (Mutual exclusive with _Destination_) - Folder where subdir with _InstanceName_ will be created to store WSL2 Instance ext4.vmdx virtual disk file.
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
* **UbuntuImageDir** (Mutual exclusive with _Image_) - Path where the Ubuntu 20.04 image will be downloaded if not already exists and then used for deplyment. This allows easy unatended Ubuntu 20.04 deployment without MS Store assistance
* **ForceDownload** Makes sense only for Well-known images (As for Ubuntu 20.04 for example). Otherwise is ignored. If specified then the Well-known image will be re-downloaded from distribution point even if already exists in the Image folder.
* **BootstrapRootScript** If specified then the file is copied to /root folder inside the new fresh image and run as shell script under the root user account. It allows to provide necessary modifications to deployed image as install required software packages, update image by package manager to latest versions etc...
* **BootstrapUserScript** If specified then the file is copied to /home/<UserNAme> folder inside the new fresh image and run as shell script under the <UserNAme> user account. It allows to provide custom modifications to deployed image as deploy coinfigs, dot files and other user related stuff.

##### Bootstrapping

The deployment process can be customized by run of the bootstrap script(s). The script will run inside the deployed image and it can be run as root script or user script. Is possible to run only one or both bootstrap scripts during the deployment process. 

The Bootstrap script can be specified by three ways

1. Explicitly by parameter (*BootstrapRootScript, *BootstrapUserScript)

1. Can be placed to same folder as image and have to have specific filename:
   * **root_bootstrap** For bootstrap script run as root 
   * **user_bootstrap** For bootstrap script run as user with name specified by UserName parameter
   
   Then it's connected with the image and is used always when the image is deployed
   
1. For Well Known image ( UbuntuImageDir ) the default script located in the same directory as the main PowerShell script can be used (ubuntu_root_bootstrap) This option is valid only for well known image as the Ubuntu and this script for Ubuntu is member file of the repository.


