# wsl-scripts
Various scripts to make life with WSL easier

* **Deploy Script to create new wsl instance** --  _deploy-wsl2-image.ps1_

### Deploy Script

This script automates deployment of fresh WSL2 instances from specified image or exported backup. By this script is possible to deploy fresh WSL2 instance without interaction with MS Windows Store. For Ubuntu 20.04 is supported automatic image download from Ubuntu servers, then deployment is as easy as possible (see _UbuntuImageDir_ parameter)

Script also allows bootstrapping of the deployed image by specified scripts. These bootstap scripts can be run as root, normal user or both and by this mechanism is possible to  customise image automatically.

##### Usage:

deploy-wsl2-image.ps1 Ubuntu22 linux_user -DisksDir e:\WSL\Disks -Image E:\WSL\Ubu.tar.gz


###### Parameters:

* **InstanceName** (Mandatory) - Name of the WSL Instance. Can be specified also as the first positional parameter of the script. Must be unique and Windows WSL will use this name to identify the instance. If instance with same name already exists, script generates error and fail. I
* **UserName** (Mandatory) - Name of the user account to be created at the WSL Instance. Can be specified also as the second positional parameter of the script.
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
   * **user_bootstrap** For bootstrap script run as user with name specified by UserName mandatory parameter
   
   Then it's connected with the image and is used always when the image is deployed
   
1. For Well Known image ( UbuntuImageDir ) the default script located in the same directory as the main PowerShell script can be used (ubuntu_root_bootstrap) This option is valid only for well known image as the Ubuntu and this script for Ubuntu is member file of the repository.


