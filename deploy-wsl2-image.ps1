<#
	.Synopsis
		Deploy new WSL2 Linux system instance from specified image
    .Description
		This script automates deployment of fresh WSL2 instances from
		specified imege or exported backup. By this script is possible to
		deploy fresh WSL2 instance without interaction with MS Windows Store

		Script also allows bootstrapping of the deployed image by
		specified scripts. These bootstap scripts can be run as
		root, normal user or both and by this mechanism is possible
		to  customise image automatically.

	.Parameter InstanceName
		Specifies the name of the new WSL2 Linux instance. Must be unique.

	.Parameter UserName
		Username of user account to create inside the wsl2 Linux instance.
		Sudo will be also allowed for the user

    .Parameter Destination
        Folder where the vmdx file for the WSL2 instance will be created.
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

	.Parameter BootstrapRootScript
		If specified then the file is copied to /root folder inside the new fresh
		image and run as shell script under the root user account.
		It allows to provide necessary modifications to deployed image as install
		required software packages, update image by package manager to latest versions etc...

	.Parameter BootstrapUserScript
		If specified, script copies this file inside the new fresh image and run
		it inside the shell as user specified by UserName parameter.
		It allows to provide necessary modifications to deployed image
		for the user account, as copied dot files and other configs, etc...

	.Example
		deploy-wsl2-image.ps1 Ubuntu22 linux_user -DisksDir e:\WSL\Disks -Image E:\WSL\Ubu.tar.gz

		Deploy WSL instance with name Ubuntu22, store disk in
		e:\WSL\Disks and create new default user with name linux_user
		As source use image E:\WSL\Ubu.tar.gz

	.Notes
		NAME:      deploy-wsl2-image.ps1
		AUTHOR:    Zdenek Polach
		WEBSITE:   https://polach.me
#>

[CmdletBinding(SupportsShouldProcess=$True)]
param (
	[Parameter(Mandatory)][string]$InstanceName,
    [string]$UserName,
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

enum PackageManagers
{
	apt
	dnf
	yum
	unknown
}

$package_manager = [PackageManagers]::unknown

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

function CopyFileFromWinToWSL {
    param (
        [string] $instanceName,
        [string] $winFilePath,
        [string] $wslFilePath,
        [string] $userName='root',
        [string] $linuxRights='640'
    )
    if ( -not (Test-Path -Path $winFilePath -PathType Leaf -ErrorAction SilentlyContinue) ){
		Write-Host "The WinFile ""$winFilePath"" doesn't exist. Can't be copied to WSL" -foregroundcolor red
		return $False
	}
    $temp_file = New-TemporaryFile
    #to be sure that file is on WSL mapped disk, use temp file in temp folder
    Copy-Item $winFilePath -Destination $temp_file
    #to make copy successfull, we have to use
	#mounted windows disk as source, aka:
	#/mnt/c/Windows.....
	$mnt_file_path = $temp_file.FullName
	$disk_char = $mnt_file_path.Substring(0,1)
	$disk_char = $disk_char.ToLower()
	$mnt_file_path = $mnt_file_path.Substring(1)
	$mnt_file_path = $disk_char +  $mnt_file_path
	#then transform it on linux path -> replace \ for / and remove : from disk name
	$mnt_file_path = $mnt_file_path -Replace "\\", "/"
	$mnt_file_path = $mnt_file_path -Replace  ":", ""
	$mnt_file_path = "'/mnt/" + $mnt_file_path +"'"
	#copy file
    wsl -d $instanceName -u $userName cp $mnt_file_path $wslFilePath
    Remove-Item $temp_file
    if( -Not (CheckIfLinuxFileOnPathExists -instanceName $instanceName -filePath $wslFilePath) ){
        Write-Host "Copy to the file ""$wslFilePath"" failed." -ForegroundColor Red
        return $False
    }
    #change rights
    #$script = "chmod $linuxRights $wslFilePath"
    #wsl -d $instanceName -u $userName -e sh -c "$script"
	wsl -d $instanceName -u $userName chmod $linuxRights $wslFilePath
    return $True
}

function CopyBootstrapAndRun {
	param (
		[string] $instanceName,
		[string] $bootstrapFile,
		[string] $userName='root'
	)
	$pure_file_name = Split-Path $bootstrapfile -Leaf
	#Build path as will be used on WSL
	if($userName -eq "root"){
		$wsl_dest_file= '/root/' + $pure_file_name
	}else{
		$wsl_dest_file= '/home/'+$userName
		$wsl_dest_file+='/'
		$wsl_dest_file+=$pure_file_name
	}
	$copied = CopyFileFromWinToWSL -instanceName $instanceName -winFilePath $bootstrapFile `
		-wslFilePath $wsl_dest_file -userName $userName -linuxRights '740'
	#execute the file
	if ($copied -eq $True) {
		wsl -d $instanceName -u $userName sh -c  $wsl_dest_file
		#and remove file - not necessary anymore
		wsl -d $instanceName -u $userName -- rm -f $wsl_dest_file
	}
}

function CheckIfLinuxUserExists {
	param (
		[string] $instanceName,
		[string] $userName
	)
	$test_output = wsl -d $instanceName id -u $userName 2>&1
	$user_exists = -not ( $test_output -match 'no such user' )
	return $user_exists
}

function CheckIfLinuxBinaryExists {
	param (
        [string] $instanceName,
		[string] $binaryName
	)
    $test_output = wsl -d $instanceName -u "root" whereis -b $binaryName 2>&1
    $exe_exists = $test_output -match "/$binaryName"
	return $exe_exists
}
function CheckIfLinuxFileOnPathExists {
    param (
        [string] $instanceName,
		[string] $filePath
    )
    $script = "[ -f '$filePath' ] && echo exists"
    $test_output = wsl -d $instanceName -u "root" -e sh -c "$script"
    $file_exists = $test_output -match "exists"
	return $file_exists
}

function CheckIfLinuxDirectoryOnPathExists {
    param (
        [string] $instanceName,
		[string] $dirPath
    )
    $script = "[ -d '$dirPath' ] && echo exists"
    $test_output = wsl -d $instanceName -u "root" -e sh -c "$script"
    $dir_exists = $test_output -match "exists"
	return $dir_exists
}

function CheckIfLinuxGroupExists {
    param (
        [string] $instanceName,
		[string] $group
    )
    $script = "cat /etc/group | grep $group"
    $test_output = wsl -d $instanceName -u "root" -e sh -c "$script"
    $group_exists = $test_output -match "$group"
	return $group_exists
}
function DetectPackageManager {
    param (
        [string] $instanceName
	)
    if( CheckIfLinuxBinaryExists -instanceName $instanceName -binaryName 'dnf' ) {
        return [PackageManagers]::dnf
    }
    if( CheckIfLinuxBinaryExists -instanceName $instanceName -binaryName 'apt-get' ) {
        return [PackageManagers]::apt
    }
    if( CheckIfLinuxBinaryExists -instanceName $instanceName -binaryName 'yum' ) {
        return [PackageManagers]::yum
    }
    return [PackageManagers]::unknown
}

function UpdateImageToLatestPackages {
    param (
        [string] $instanceName,
        [PackageManagers] $manager
    )
    Write-Host "Updating the ""$instanceName"" instance to latest packages..." -ForegroundColor Blue
    switch($manager)
    {
        apt {
			wsl -d $instanceName -u 'root' -e sh -c "apt-get -y update && apt-get -y upgrade"
        }
        dnf {
			wsl -d $instanceName -u 'root' dnf -y update
        }
        yum {
			wsl -d $instanceName -u 'root' yum -y update
        }
        unknown {
            Write-Host "Unknown package manager. Unable to update the ""$instanceName"" to latest packages" -ForegroundColor Red
        }
	}
	Write-Host "The ""$instanceName"" has been updated successfully." -ForegroundColor Green
}
function InstallPackageToWSL {
    param (
        [string] $instanceName,
        [PackageManagers] $manager,
        [string] $packageName
    )

    switch($manager)
    {
        apt {
			Write-Host "Installing the ""$packageName"" by apt-get" -ForegroundColor Blue
			wsl -d $instanceName -u 'root' apt-get -y install $packageName
        }
        dnf {
			Write-Host "Installing the ""$packageName"" by dnf" -ForegroundColor Blue
			wsl -d $instanceName -u 'root' dnf -y install $packageName
        }
        yum {
			Write-Host "Installing the ""$packageName"" by yum" -ForegroundColor Blue
			wsl -d $instanceName -u 'root' yum -y install $packageName
        }
        unknown {
            Write-Host "Unknown package manager. Unable to install ""$packageName""." -ForegroundColor Red
        }
    }
}
function AllowSudoForUSer {
	param (
        [string] $instanceName,
        [string] $userName
	)
	if( CheckIfLinuxGroupExists -instanceName $instanceName -group 'wheel' ) {
		Write-Host "Adding user ""$userName"" to the ""wheel"" group..." -ForegroundColor Blue
		wsl -d $instanceName -u 'root' -e sh -c "usermod -aG wheel $userName"
		return
	}
	if( CheckIfLinuxGroupExists -instanceName $instanceName -group 'sudo' ) {
		Write-Host "Adding user ""$userName"" to the ""sudo"" group..." -ForegroundColor Blue
		wsl -d $instanceName -u 'root' -e sh -c "usermod -aG sudo $userName"
		return
	}
	Write-Host "No ""sudo"" or ""wheel"" group detected. Unable to allow sudo for user ""$userName""" -ForegroundColor Yellow

}
function CreateLinuxUser {
	param (
        [string] $instanceName,
        [PackageManagers] $manager,
        [string] $userName
	)

	if( CheckIfLinuxUserExists -instanceName $instanceName -userName $userName ) {
		Write-Host "WARNING: The Linux user ""$userName"" already exists. Skipping actions for the user...." -ForegroundColor Yellow
		return $False
	}
	Write-Host "Creating default user: ""$userName""" -ForegroundColor Blue
	if( -Not (CheckIfLinuxFileOnPathExists -instanceName $instanceName -filePath '/bin/bash') ){
		Write-Host "The Bash package is missing. User ""$userName"" can't be created." -ForegroundColor Red
		return $False
	}
	if( -Not (CheckIfLinuxFileOnPathExists -instanceName $instanceName -filePath '/usr/bin/passwd') ){
		InstallPackageToWSL -instanceName $instanceName -manager $manager -packageName 'passwd'
		if( -Not (CheckIfLinuxFileOnPathExists -instanceName $instanceName -filePath '/usr/bin/passwd') ){
			Write-Host "Unable to install missing passwd package. User ""$userName"" can't be created." -ForegroundColor Red
			return $False
		}
	}
	if(($manager -eq [PackageManagers]::dnf)-or ($manager -eq [PackageManagers]::yum)){
		if( -Not (CheckIfLinuxFileOnPathExists -instanceName $instanceName -filePath '/usr/share/cracklib/pw_dict.pwd') ){
			wsl -d $instanceName -u 'root' dnf -y install 'cracklib-dicts'
		}
    }

	if( -Not (CheckIfLinuxFileOnPathExists -instanceName $instanceName -filePath '/usr/bin/sudo') ){
		InstallPackageToWSL -instanceName $instanceName -manager $manager -packageName 'sudo'
		if( -Not (CheckIfLinuxFileOnPathExists -instanceName $instanceName -filePath '/usr/bin/sudo') ){
			Write-Host "Unable to install missing sudo package. User ""$userName"" can't be created." -ForegroundColor Red
			return $False
		}
	}
	wsl -d $InstanceName -e sh -c "useradd -m -s /bin/bash $userName"

	if( -not (CheckIfLinuxUserExists -instanceName $InstanceName -userName $userName) ) {
		Write-Host "The default user: ""$userName"" was not created!" -ForegroundColor Red
		return $False
	}
	Write-Host "Creating password for user ""$userName""..." -ForegroundColor Blue
	wsl -d $InstanceName -e sh -c "passwd $userName"
	AllowSudoForUSer -instanceName $instanceName -userName $userName
	#create wsl.conf file
	Write-Host "Creating /etc/wsl.conf file..." -ForegroundColor Blue
	$lnx_hostname=$instanceName.ToLower()
	wsl -d $InstanceName -- eval "echo -e '[user]\ndefault=\""$userName\""\n\n[network]\nhostname=\""$lnx_hostname\""' > /etc/wsl.conf"

	Write-Host "The default user: ""$userName"" created successfully" -ForegroundColor Green
	Write-Host "The hostname: ""$lnx_hostname"" has been set successfully" -ForegroundColor Green

	########### This is less echo implementation sdependent version, but now commented out ######
	########### preserved if will be on some distro necessary when echo -e will not work ########

	# wsl -d $InstanceName -- eval "echo '[user]' > /etc/wsl.conf"
	# wsl -d $InstanceName -- eval "echo default=""$userName"" >> /etc/wsl.conf"
	# Write-Host "The default user: ""$userName"" created successfully" -ForegroundColor Green
	# wsl -d $InstanceName -- eval 'echo "" >> /etc/wsl.conf'
	# wsl -d $InstanceName -- eval 'echo ''[network]'' >> /etc/wsl.conf'
	# wsl -d $InstanceName -- eval "echo hostname=""$lnx_hostname"" >> /etc/wsl.conf"
	# Write-Host "The hostname: ""$lnx_hostname"" has been set successfully" -ForegroundColor Green

	###############################################################################################

	if ($BootstrapUserScript){
		Write-Host "Providing ""$userName"" user bootstrapping in the ""$InstanceName"" wsl instance..." -ForegroundColor Blue
		CopyBootstrapAndRun -instanceName $instanceName -bootstrapFile $BootstrapUserScript -userName $userName
		Write-Host """$userName"" user bootstrapping in the ""$InstanceName"" wsl instance has been finished" -ForegroundColor Green
	}
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
	$vhdx_check = Join-Path -Path $Destination -ChildPath "ext4.vhdx"
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
		Write-Host "Root Bootstrap script has been detected at Image Folder" -ForegroundColor Yellow
		$BootstrapRootScript = $possible_script
	}else{
		#Try if default bootstrapping is not deployed with this script for the image
		if (-not ( [string]::IsNullOrEmpty( $image_root_bootstrap ))){
			$file_exists = Test-Path -Path $image_root_bootstrap -PathType Leaf
			if ($file_exists -eq $True ){
				Write-Host "Default image root user bootstrapping script has been detected at script folder" -ForegroundColor Yellow
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
		Write-Host "User Bootstrap script has been detected at Image Folder" -ForegroundColor Yellow
		$BootstrapUserScript = $possible_script
	}else{
		#Try if default bootstrapping is not deployed with thi script for the image
		if (-not ( [string]::IsNullOrEmpty( $image_user_bootstrap ))){
			$file_exists = Test-Path -Path $image_user_bootstrap -PathType Leaf
			if ($file_exists -eq $True ){
				Write-Host "Default image user bootstrapping script has been detected at script folder" -ForegroundColor Yellow
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
		New-Item -Path $DisksDir -Name $InstanceName -ItemType "directory"  -ErrorAction Stop | Out-Null
		if ( -not (Test-Path -Path $Destination -PathType Container ) ){
			Write-Host "Can't create the folder ""$Destination""!" -foregroundcolor red
			FinScript
		}
	}
}

Write-Host "Going to create ""$InstanceName"" from image ""$image_name"" to ""$Destination"""
wsl --import $InstanceName $Destination $image_full_path
Write-Host "The WSL Instance ""$InstanceName"" has been created successfuly"

#start the instance to allow next processing
wsl -d $InstanceName echo "Starting WSL $InstanceName.."

$package_manager = DetectPackageManager -instanceName $InstanceName
UpdateImageToLatestPackages -instanceName $InstanceName -manager $package_manager
if ($BootstrapRootScript){
	Write-Host "Providing root user bootstrapping in the ""$InstanceName"" wsl instance..." -ForegroundColor Blue
	CopyBootstrapAndRun -instanceName $instanceName -bootstrapFile $BootstrapRootScript
	Write-Host "Root user bootstrapping in the ""$InstanceName"" wsl instance has been finished"
}
#Own exports often contains users -> then no longer UserName parameter is mandatory
if ( $PSBoundParameters.ContainsKey('UserName') ){
	CreateLinuxUser -instanceName $InstanceName -manager $package_manager -userName $UserName
}
Write-Host ""
Write-Host "Done. Instance ""$InstanceName"" has been created successfuly" -ForegroundColor Green
Write-Host "Restarting the ""$InstanceName"" Linux Instance..." -ForegroundColor Blue
wsl -t $InstanceName
Write-Host ""
Write-Host "Welcome in your fresh Linux box..." -ForegroundColor Blue
Write-Host ""
wsl -d $InstanceName
