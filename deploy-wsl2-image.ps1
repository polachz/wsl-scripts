<#
	.Synopsis
		 Deploy new WSL2 Linux system instance from specified image
    .Description
		This script automates deployment of fresh WSL2 instances from
		specified imege or exported backup. By this script is possible to
		deploy fresh WSL2 instance without interaction with MS Windows Store

       		
	.Parameter InstanceName    
        Specifies the name of the new WSL2 Linux instance
	
	.Parameter UserName
	    Username of user account to create insid the wsl2 Linux instance. 
		Sudo will be also allowes for the user
		
    .Parameter Destination    
        Folder where the vmdx file for the WSL2 instance will be created
		If not specified, current directory will be used. 
		Mutual exclusive with DisksDir

	.Parameter DisksDir
		Folder where subdir with InstanceName will be created to store
		WSL2 instance ext4.vmdx virtual disk file.
		This parameter allows to organize WSL2 Instances vhdx inside 
		this folder by this way
		- DisksDir
		   - Instance1\ext4.vhdx
		   - Instance2\ext4.vhdx
		   - .....
		   - InstanceX\ext4.vhdx

	.Parameter Image   
		Path to image from which the instance will be cloned 
		Mutual Exclusive with UbuntuImageDir
    
	.Parameter UbuntuImageDir
		Path where the Ubuntu 20.04 image will be downloaded if not exists
		And then used for deplyment. Mutual Exclusive with Image parameter
		
	.Parameter ForceDownload
		If specified, image will be re-dowloaded to UbuntuImageDir even if exists
		If UbuntuImageDir is not pecified, parameter is ignored
    
	.Example
        clone_ubuntu.ps1 Ubuntu22 c:\WSL2_Disks linux_user
		
		Creates Ubuntu instance with name Ubuntu22, store disk in 
		c:\WSL2_disks folder and create new default user with name linux_user

    .Notes
        NAME:      deploy-wsl2-image.ps1
        AUTHOR:    Zdenek Polach
		WEBSITE:   https://polach.me
#>

[CmdletBinding(SupportsShouldProcess=$True)]
param (
	[Parameter(Mandatory)][string]$InstanceName,
    [Parameter(Mandatory)][string]$UserName,
	[string]$Destination,
	[string]$DisksDir,
	[string]$Image,
	[string]$UbuntuImageDir,
	[bool]$ForceDownload=$false,
	[string]$BootstrapRootScript,
	[string]$BootstrapUserScript

)

$ubuntu_image_url = 'https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64-wsl.rootfs.tar.gz'

$default_root_bootstrap_script_name = "root_bootstrap"
$default_user_bootstrap_script_name = "user_bootstrap"


$CreateDestDir = $False

$imageUrl = ""
$imageDir = ""
$DoDownload = $False
$ByImageDir = $False


$image_root_bootstrap=""
$image_user_bootstrap=""

function CheckMutualExclusiveParam {
	param (
		[string[]]$all_params_array,
		[object] $where_to_find
	)
	$specified_params = @()
	$all_params_array | ForEach-Object { if ( $where_to_find.ContainsKey( $_ ) ) { $specified_params += $_ } }
	if ( $specified_params.Length -gt 1 ) {
		$oval = ( $specified_params ) -join ", "
		Write-Host "Is not possible to specify these parameters together: $oval" -foregroundcolor red
		Write-Host "Please specify only one of them!"
		return $False
	}
	if ( $specified_params.Length -lt 1 ){
		$oval = ( $all_params_array ) -join ", "
		Write-Host "Missing parameter. Please specify one of these parameters: $oval" -foregroundcolor red
		return $False
	}
	return $True
}

function FinScript {
	Write-Host "Unable to continue...."
	exit
}

function CopyBootstrapAndRun {
	param (
		[string]$bootstrap_file,
		[object] $userName='root'
	)
	$pure_file_name = Split-Path $bootstrap_file -Leaf
	#Build path as will be used on WSL
	if($userName -eq "root"){
		$wsl_dest_file= '/root/' + $pure_file_name
	}else{
		$wsl_dest_file= '/home/'+$userName
		$wsl_dest_file+='/'
		$wsl_dest_file+=$pure_file_name
	}
	#to make copy successfull, we have to use
	#mounted windows disk as source, aka:
	#/mnt/c/Windows..... 
	$mnt_file_path = $bootstrap_file
	$disk_char = $mnt_file_path.Substring(0,1)
	$disk_char = $disk_char.ToLower()
	$mnt_file_path = $mnt_file_path.Substring(1)
	$mnt_file_path = $disk_char +  $mnt_file_path
	#then transform it on linux path -> replace \ for / and remove : from disk name
	$mnt_file_path = $mnt_file_path -Replace "\\", "/" 
	$mnt_file_path = $mnt_file_path -Replace  ":", "" 
	$mnt_file_path = "'/mnt/" + $mnt_file_path +"'"
	#copy file
	wsl -d $InstanceName -u $userName cp $mnt_file_path $wsl_dest_file
	#change rights
	wsl -d $InstanceName -u $userName chmod 740 $wsl_dest_file
	#execute the file
	wsl -d $InstanceName -u $userName sh -c  $wsl_dest_file
}
##
########## main script #####################
##

#Check if imagename is not duplicit
$Instances = wsl --list --all
if ( $Instances.Contains( $InstanceName ) ){
    Write-Host "The instance ""$InstanceName"" already exists!!" -foregroundcolor red
	FinScript
}
$dst_all_params_array = @('DisksDir', 'Destination')
if ( -not ( CheckMutualExclusiveParam -all_params_array $dst_all_params_array -where_to_find $PSBoundParameters) ) {
	FinScript
}

if ( $PSBoundParameters.ContainsKey('Destination') ){
	if ( -not (Test-Path -Path $Destination -PathType Container ) ){
		Write-Host "Destination folder ""$Destination"" does not exist!!" -foregroundcolor red
		FinScript
	}	
} elseif ( $PSBoundParameters.ContainsKey('DisksDir') ){
	if ( -not (Test-Path -Path $DisksDir -PathType Container ) ){
		Write-Host "DisksDir folder ""$DisksDir"" does not exist!!" -foregroundcolor red
		FinScript
	}	
	#We will deploy to the $InstanceName subdir.
	$CreateDestDir=$true
	$Destination = Join-Path $DisksDir $InstanceName
	if ( -not (Test-Path -Path $Destination -PathType Container ) ){
		$CreateDestDir=$true
	}
}

#Handle the destination folder for vhdx
$file_exists = Test-Path -Path $Destination -PathType Container  
if ( $file_exists -eq $True ){
	$vhdx_check = Join-Path -Path $Destination, -ChildPath "ext4.vhdx"
	$file_exists = Test-Path -Path $vhdx_check -PathType Leaf
	if ( $file_exists -eq $True ){
		Write-Host "VHDX disk image already exists in the ""$Destination""." -foregroundcolor red
		FinScript
	}
}

#Now image options
$img_all_params_array = @('Image', 'UbuntuImageDir')
if ( -not ( CheckMutualExclusiveParam -all_params_array $img_all_params_array  -where_to_find $PSBoundParameters) ) {
	FinScript
}

#now if image is specified, it have to be file....
if ( $PSBoundParameters.ContainsKey('Image') ){
	if ( -not (Test-Path -Path $Image -PathType Leaf) ){
		Write-Host "Specified Image ""$Image"" does not exist!!" -foregroundcolor red
	    FinScript
	}else{
		$image_full_path=$Image
		$image_name = Split-Path $image_full_path -Leaf
		$imageDir = Split-Path $image_full_path -Parent
	}
}elseif ( $PSBoundParameters.ContainsKey('UbuntuImageDir') ){    
	$imageUrl = $ubuntu_image_url
	$imageDir = $UbuntuImageDir
	$ByImageDir = $True
	$image_full_path = ""
	$possible_script = Join-Path  -Path $PSScriptRoot -ChildPath 'ubuntu_root_bootstrap'
	$file_exists = Test-Path -Path $possible_script -PathType Leaf 
	#Check if we have right bootstrap files for the image 
	#at same folder as script resides
	if ($file_exists -eq $True ){
		$image_root_bootstrap = $possible_script
	}
	$possible_script = Join-Path  -Path $PSScriptRoot -ChildPath 'ubuntu_user_bootstrap'
	$file_exists = Test-Path -Path $possible_script -PathType Leaf 
	if ($file_exists -eq $True ){
		$image_user_bootstrap = $possible_script
	}
}
#elseif (in future ....another image option....) 



if ($ByImageDir){
	if ( -not (Test-Path -Path $ImageDir -PathType Container -ErrorAction Stop) ){
		Write-Host "ImageDir ""$ImageDir"" does not exist!!" -foregroundcolor red
		FinScript
	}
	$image_name = Split-Path $imageUrl -Leaf
	$image_full_path = Join-Path $ImageDir $image_name
	$file_exists = Test-Path -Path $image_full_path -PathType Leaf 
	if ($file_exists -eq $True ){
		#image already exists
		if ( $ForceDownload ) {
			Write-Host "The Image file ""$image_name"" already exists inside the Image directory, but ForceDownload is requested"
			Write-Host "Original image will be discarded and fresh new will be downloaded."
			Remove-Item -Path $image_full_path -Force
			$DoDownload = $True
		}else{
			Write-Host "The Image file already exists inside the Image directory"
			Write-Host "We will use this image for instance clone"
			$DoDownload = $False
		}
	}else{
		Write-Host "The Image file doesn't exist inside the Image directory"
		Write-Host "We will try to download the image..."
		$DoDownload = $True
	}
}

if( $DoDownload ) {
	Write-Host "Downloading image:"
	Write-Host "   ""$imageUrl""..."
	Invoke-WebRequest -Uri $imageUrl -OutFile $image_full_path -UseBasicParsing
	if ( -not (Test-Path -Path $image_full_path -PathType Leaf -ErrorAction Stop) ){
	   Write-Host "Image download failed!" -foregroundcolor red
	   FinScript
	}else{
		Write-Host "Image downloaded successfuly."
	}
}

if ( $PSBoundParameters.ContainsKey('BootstrapRootScript') ){
	if ( -not (Test-Path -Path $BootstrapRootScript -PathType Leaf) ){
		Write-Host "Root Bootstrap script ""$BootstrapRootScript"" does not exist!!" -foregroundcolor red
		FinScript
	}
}else{
	#Try to find script in image folder
	$possible_script = Join-Path  -Path $imageDir -ChildPath $default_root_bootstrap_script_name
	$file_exists = Test-Path -Path $possible_script -PathType Leaf 
	if ($file_exists -eq $True ){
		Write-Host "Root Bootstrap script has been detected at Image Folder"
		$BootstrapRootScript = $possible_script
	}else{
		#Try if default bootstrapping is not deployed with thi script for the image
		if (-not ( [string]::IsNullOrEmpty( $image_root_bootstrap ))){
			$file_exists = Test-Path -Path $image_root_bootstrap -PathType Leaf 
			if ($file_exists -eq $True ){
				Write-Host "Default image root user bootstrapping script has been detected at script folder"
				$BootstrapRootScript = $image_root_bootstrap
			}else{
				$BootstrapRootScript = ""	
			}
		}else{
			$BootstrapRootScript = ""
		}
	
		
		
	}
}
if ( $PSBoundParameters.ContainsKey('BootstrapUserScript') ){
	if ( -not (Test-Path -Path $BootstrapUserScript -PathType Leaf) ){
		Write-Host "Root Bootstrap script ""$BootstrapUserScript"" does not exist!!" -foregroundcolor red
		FinScript
	}
}else{
	#Try to find script in image folder
	$possible_script = Join-Path  -Path $imageDir -ChildPath $default_user_bootstrap_script_name
	$file_exists = Test-Path -Path $possible_script -PathType Leaf 
	if ($file_exists -eq $True ){
		Write-Host "User Bootstrap script has been detected at Image Folder"
		$BootstrapUserScript = $possible_script
	}else{
		#Try if default bootstrapping is not deployed with thi script for the image
		if (-not ( [string]::IsNullOrEmpty( $image_user_bootstrap ))){
			$file_exists = Test-Path -Path $image_user_bootstrap -PathType Leaf 
			if ($file_exists -eq $True ){
				Write-Host "Default image user bootstrapping script has been detected at script folder"
				$BootstrapUserScript = $image_user_bootstrap
			}else{
				$BootstrapUserScript = ""		
			}
		} else {
			$BootstrapUserScript = ""	
		}
	}
}


#now all pieces are in place
if ( $CreateDestDir ){
	#Try to create folder folder
	if ( -not (Test-Path -Path $Destination -PathType Container ) ){
		New-Item -Path $DisksDir -Name $InstanceName -ItemType "directory"
		if ( -not (Test-Path -Path $Destination -PathType Container ) ){
			Write-Host "Can't create the folder ""$Destination""!" -foregroundcolor red
			FinScript
		}
	}
}

Write-Host "Going to create ""$InstanceName"" from image ""$image_name"" to ""$Destination"""
wsl --import $InstanceName $Destination $image_full_path
Write-Host "The WSL Instance ""$InstanceName"" has been created successfuly"
#Write-Host "Updating the instance to latest packages..."
#wsl -d $InstanceName apt-get update '&&' apt-get -y upgrade
#start the instance to allow next processing
wsl -d $InstanceName echo "Starting WSL $InstanceName.."
if ($BootstrapRootScript){
	Write-Host "Providing root user bootstrapping in the ""$InstanceName"" wsl instance..."
	CopyBootstrapAndRun $BootstrapRootScript
	Write-Host "Root user bootstrapping in the ""$InstanceName"" wsl instance has been finished"
}
#bootstraping
#cp .\clone_ubuntu.ps1 \\wsl$\$InstanceName\root\
#wsl -d $InstanceName -e sh -c "/root/bootstrap_root.sh"

Write-Host "Creating default user: ""$UserName"""
$default_cnt="echo default=""$UserName"" >> /etc/wsl.conf"
wsl -d $InstanceName -e sh -c "echo '[user]' > /etc/wsl.conf"
wsl -d $InstanceName -e sh -c """$default_cnt"""
wsl -d $InstanceName adduser --gecos $UserName $UserName '&&' adduser $UserName sudo
if ($BootstrapUserScriptScript){
	Write-Host "Providing ""$UserName""" user bootstrapping in the ""$InstanceName"" wsl instance..."
	CopyBootstrapAndRun $BootstrapUserScriptScript -userName $UserName
	Write-Host """$UserName""" user bootstrapping in the ""$InstanceName"" wsl instance has been finished"
}
wsl --terminate Ubut1
Write-Host "Done. Instance ""$InstanceName"" has been created successfuly"
Write-Host "Welcome in your fresh Linux box..."
wsl -d $InstanceName 
