<#
	.Synopsis
		 Create new WSL2 Ubuntu 20.04 LTS Instance  
    .Description
		This script automates cloning Ubuntu 20.04 WSL2 instances
		By this script, you can create fresh WSL2 instance without
		Interaction with MS Windows Store

       		
	.Parameter InstanceName    
        Specifies the name of the new WSL2 Linux instance
	
	.Parameter UserName
	    Username of user account to create insid the wsl2 Linux instance. 
		Sudo will be also allowes for the user
		
    .Parameter Destination    
        Folder where the vmdx file for the WSL2 instance will be created
		If not specified, current directory will be used
	
	.Parameter Image   
        Path to image from which the instance will be cloned 
    
	.Parameter ImageDir
	    Path where the image will be downloaded if not exists
		
	.Parameter ForceDownload
		If specified, image will be re-dowloaded to ImageDir
		If ImageDir is not pecified, paremeter is ignored
    
	.Example
        clone_ubuntu.ps1 Ubuntu22 c:\WSL2_Disks linux_user
		
		Creates Ubuntu instance with name Ubuntu22, store disk in 
		c:\WSL2_disks folder and create new default user with name linux_user

    .Notes
        NAME:      clone_ubuntu.ps1
        AUTHOR:    Zdenek Polach
		WEBSITE:   https://polach.me
#>

[CmdletBinding(SupportsShouldProcess=$True)]
param (
	[Parameter(Mandatory)][string]$InstanceName,
    [Parameter(Mandatory)][string]$UserName,
    [string]$Destination=".\",
	[string]$Image,
	[string]$ImageDir,
	[bool]$ForceDownload=$false
)

$image_url='https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64-wsl.rootfs.tar.gz'
$image_name=Split-Path $image_url -Leaf

#Check if imagename is not duplicit
$Instances = wsl --list --all

if ( $Instances.Contains( $InstanceName ) ){
    Write-Host "The instance ""$InstanceName"" already exists!! Unable to continue..." -foregroundcolor red
	exit
}
#Destination folder have to be specified
if ( -not (Test-Path -Path $Destination -PathType Container ) ){
	Write-Host "Destination folder ""$Destination"" does not exist!! Unable to continue..." -foregroundcolor red
	exit
}
#now if image is pecified, it have to be file and will be used for clone
if ( -not $PSBoundParameters.ContainsKey('Image') ){
    if ( -not $PSBoundParameters.ContainsKey('ImageDir') ){
	     Write-Host "No Image file nor Image file Dir is specified. Unable to continue" -foregroundcolor red
		 Write-Host "Please specify full path to the image, or dir where image will be downloaded if not exits"
		 exit
	}else{
		if ( -not (Test-Path -Path $ImageDir -PathType Container ) ){
			Write-Host "ImageDir ""$ImageDir"" does not exist!! Unable to continue..." -foregroundcolor red
			exit
		}else{
			$image_full_path = Join-Path $ImageDir $image_name
			if ( Test-Path -Path $image_full_path -PathType Leaf ){
				#image already exists
				if ( $ForceDownload ) {
					Write-Host "The Image file already exists inside the Image directory, but ForceDownload is requested"
					Write-Host "Original image will be discarded and fresh new will be downloaded."
					Remove-Item -Path $image_full_path -Force
					$image_full_path=""
				}else{
					Write-Host "The Image file already exists inside the Image directory"
					Write-Host "We will use this image for instance clone"
				}
			}else{
				Write-Host "The Image file doesn't exist inside the Image directory"
				Write-Host "We will try to download the image..."
				$image_full_path=""
			}
		}
	}
}else{
	if ( -not (Test-Path -Path $Image -PathType Leaf) ){
		Write-Host "Specified Image ""$Image"" does not exist!! Unable to continue..." -foregroundcolor red
	    exit
	}else{
		$image_full_path=$Image
	}
}
if( $image_full_path -eq "" ) {
	$image_name=Split-Path $image_url -Leaf
	$image_full_path = Join-Path $ImageDir $image_name
	Write-Host "Downloading image:"
	Write-Host "   ""$image_url""..."
	Invoke-WebRequest -Uri $image_url -OutFile $image_full_path -UseBasicParsing
	if ( -not (Test-Path -Path $image_full_path -PathType Leaf -ErrorAction Stop) ){
	   Write-Host "Image download failed... Unable to Continue" -foregroundcolor red
	   exit
	}else{
		Write-Host "Image downloaded successfuly."
	}
}
#now all pieces are in place
$image_name=Split-Path $image_full_path -Leaf
Write-Host "Going to create ""$InstanceName"" from image ""$image_name"" to ""$Destination"""
wsl --import $InstanceName $Destination $image_full_path
Write-Host "The WSL Instance ""$InstanceName"" has been created successfuly"
Write-Host "Updating the instance to latest packages..."
wsl -d $InstanceName apt-get update '&&' apt-get -y upgrade
#bootstraping
#cp .\clone_ubuntu.ps1 \\wsl$\$InstanceName\root\
#wsl -d $InstanceName -e sh -c "/root/bootstrap_root.sh"

Write-Host "Creating default user: ""$UserName"""
$default_cnt="echo default=""$UserName"" >> /etc/wsl.conf"
wsl -d $InstanceName -e sh -c "echo '[user]' > /etc/wsl.conf"
wsl -d $InstanceName -e sh -c """$default_cnt"""
wsl -d $InstanceName adduser --gecos $UserName $UserName '&&' adduser $UserName sudo
wsl --terminate Ubut1
Write-Host "Done. Instance ""$InstanceName"" has been created successfuly"
Write-Host "Welcome in your fresh Linux box..."
wsl -d $InstanceName

	