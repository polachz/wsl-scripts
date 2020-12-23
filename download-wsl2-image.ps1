<#
    .Synopsis
        Download a Docker container image then it can be deployed as a WSL2 Linux system instance.
    .Description
        The list of WSL2 supported distro images in the MS Store is 
        very limited.But hopefully the Docer image can be easily transformed
        to WSL instance and then any distro can be run as WSL instance.
        Of course some booststraping is necessary to tune the image
        to comfortable state. For that the deploy-wsl2-image.ps1 script
        can be used. 
			
    .Parameter Image    
        Specifies the docker hub image name. Consider that Dcoker Official images
        has prefix library, then Fedora official image name is library/fedora
        Official Ubuntu image is library/ubuntu etc... 
    
    .Parameter Tag   
        Specifies the DockerHub image Tag 
        If not specified the 'latest' tag is used
    
    .Parameter Destination    
        Folder where the downloaded image will be stored

    .Parameter MakeDir
        If specified then the script will create sub-folder at Destination 
        with name 'Image_Tag' and then downloads the image here.
        If the Tag is not specified, only the 'Image' sub-folder is created

    .Parameter Force
        If specified and image already exists then image is overwritten by new one.
        Otherwise the script prints warning and exit

    .Example
        download-wsl2-image.ps1 -Image library/ubuntu -Destination E:\WSL_ubuntu
            Downloads the latest ubuntu image and stores it at E:\WSL_ubuntu folder

        download-wsl2-image.ps1 -Image library/fedora -Tag 32 -Destination E:\WSL -MakeDir
            Downloads the fedora 32 image and stores it at E:\WSL\fedora_32 folder

    .Notes
        NAME:      download-wsl2-image.ps1
        AUTHOR:    Zdenek Polach
        WEBSITE:   https://polach.me
#>

[CmdletBinding(SupportsShouldProcess=$True)]
param (
    [Parameter(Mandatory)][string]$Image,
    [Parameter(Mandatory)][string]$Destination,
    [string]$Tag = "latest",
    [switch]$MakeDir,
    [switch]$Force

)

function FinScript {
    Write-Host ""
    Write-Host "Unable to continue...."
    Write-Host ""
	exit
}
Function UnpackGzipFile{
    Param(
        $infile,
        $outfile = ($infile -replace '\.gz$','')
        )
    $inputData = New-Object System.IO.FileStream $inFile, ([IO.FileMode]::Open), ([IO.FileAccess]::Read), ([IO.FileShare]::Read)
    $outputData = New-Object System.IO.FileStream $outFile, ([IO.FileMode]::Create), ([IO.FileAccess]::Write), ([IO.FileShare]::None)
    $gzipStream = New-Object System.IO.Compression.GzipStream $inputData, ([IO.Compression.CompressionMode]::Decompress)
    $buffer = New-Object byte[](1024)
    while($true){
        $read = $gzipstream.Read($buffer, 0, 1024)
        if ($read -le 0){break}
        $outputData.Write($buffer, 0, $read)
        }
    $gzipStream.Close()
    $outputData.Close()
    $inputData.Close()
}

Function PackGzipFile{
    Param(
        $infile,
        $outfile =  ($infile -replace '\.tar$','.tgz')
        )
    $inputData = New-Object System.IO.FileStream $inFile, ([IO.FileMode]::Open), ([IO.FileAccess]::Read), ([IO.FileShare]::Read)
    $outputData = New-Object System.IO.FileStream $outFile, ([IO.FileMode]::Create), ([IO.FileAccess]::Write), ([IO.FileShare]::None)
    $gzipStream = New-Object System.IO.Compression.GzipStream $outputData, ([IO.Compression.CompressionMode]::Compress)
    $buffer = New-Object byte[](1024)
    while($true){
        $read = $inputData.Read($buffer, 0, 1024)
        if ($read -le 0){break}
        $gzipStream.Write($buffer, 0, $read)
        }
    $gzipStream.Close()
    $outputData.Close()
    $inputData.Close()
}
#For better readability
Write-Host ""

if (-Not (Test-Path -Path $Destination -PathType Container)){
    Write-Host "The folder ""$Destination"" doesn't exist!" -ForegroundColor Red
    FinScript

}
$imgName=Split-Path -path $Image -Leaf
if(-Not($Tag -eq "latest")){
    $imgName = $imgName + "_" + $Tag
}
if ($MakeDir.IsPresent){
    $workDir=Join-Path -Path $Destination -ChildPath $imgName
}else{
    $workDir=$Destination
}
$tarImgName = $imgName + ".tar"
$gzipImgName = $imgName + ".tgz"
$gzipImgPath = Join-Path -Path $workDir -ChildPath $gzipImgName

if(Test-Path -Path $gzipImgPath -PathType Leaf){
    if(-not ($Force.IsPresent)){
        Write-Host "The image file ""$gzipImgName"" already exists!" -ForegroundColor Red
        Write-Host "To overwrite the file by new one use the -Force parameter."
        FinScript
    }else{
        Write-Host "WARNING: The -Force parameter has been specified" -ForegroundColor Yellow 
        Write-Host "WARNING: The image file ""$gzipImgName"" will be overwritten." -ForegroundColor Yellow
        Write-Host ""
    }
}

Write-Host "Downloading Docker image ""$Image::$Tag""..."
Write-Host ""
$authUrl="https://auth.docker.io/token?service=registry.docker.io&scope=repository:" +$Image + ":pull"

$response=Invoke-RestMethod -Uri $authUrl

$token = $response.token;
#Get Image descriptor. We are interested in blobs list
$header= @{
    "Authorization" = "Bearer $token" 
}
$layers=Invoke-RestMethod -Headers $header -Uri "https://registry-1.docker.io:/v2/$Image/manifests/$Tag"
#Extract names of blob (sha256:xxyyzz......)
$allBlobSums= $layers.fsLayers | ForEach-Object -MemberName blobSum
#sometimes duplicates are in the list (Fedora32 for example) then try to kick them off
#Layers are applied in specific order then we have to kick off all previous duplicates
#and leave only the latest - reverse the array
[array]::Reverse($allBlobSums)
#is not specified order to process list in Select-Object -Unique
#Can't use this method ...
###$uniqueBlobs = $allBlobSums | Select-Object -Unique 
#This is little bit conservative, but the order is granted...
$uniqueBlobs=@()
foreach($blobSum in $allBlobSums){
    if ( -not ( $uniqueBlobs -contains $blobSum)){
        $uniqueBlobs += $blobSum
    }
}
#finally reverse the array order again to get unique blob list ordered from the oldest to newer
[array]::Reverse($uniqueBlobs)

New-Item -ItemType Directory -Force -Path $workDir -ErrorAction Stop | Out-Null


$tarList=@()
$ProgressPreference = 'SilentlyContinue'
foreach( $blobName in $uniqueBlobs) {
    $pos = $blobName.IndexOf(":")
    $layerName = $blobName.Substring($pos+1)
    $tarName = $layerName + ".tar"
    $outName = $tarName + ".gz"
    $outName = Join-Path $workDir $outName
    $tarFile = Join-Path $workDir $tarName
    #$tarList += $tarFile
    $tarList += $tarName
    Invoke-WebRequest -Headers $header -OutFile $outName -Uri "https://registry-1.docker.io/v2/$Image/blobs/$blobName"
    UnpackGzipFile -infile $outName
    #Remove gz file, leave tar only
    Remove-Item -Path $outName
}
$ProgressPreference = 'Continue'

#now merge all tar files together
#We are on windows then we can't use approach to decompress all layesrs to one folder
#and then pack it again. By decompressing the tar we will lose linux files attributes.
#Instead we have to use --concatenate tar command. But this is not implemented in 
#native windows tar executable so the executable is packed together with the script
$exepath = Join-Path -Path $PSScriptRoot -ChildPath 'img-pkg.exe'
$finalTar=$tarList[0]
for ($i=1; $i -lt $tarList.Length; $i++){
    $params = "--concatenate --file=$finalTar " + $tarList[$i] 
    #we have to set working directory to grant work --concatenate correctly we have to be in tar files 
    Start-Process -FilePath $exepath -WorkingDirectory $workDir -Wait -NoNewWindow -ArgumentList $params
    $tarToDel = Join-Path -Path $workDir -ChildPath $tarList[$i]
    Remove-Item -Path $tarToDel
}
#rename the meged image to final name ->container name and version
$finalTar = Join-Path  -Path $workDir -ChildPath $finalTar
$tarImgPath = Join-Path -Path $workDir -ChildPath $tarImgName
Rename-Item -Path $finalTar -NewName $tarImgName
#If we are here anf gzip file already exist, then -Force has been specified
#Then remove original anf create new one
if(Test-Path -Path $gzipImgPath -PathType Leaf){
    Remove-Item -Path $gzipImgPath
}
PackGzipFile $tarImgPath

if(Test-Path -Path $gzipImgPath -PathType Leaf){
    Write-Host "The WSL2 image ""$gzipImgName"" has been created successfully." -ForegroundColor Green
    Write-Host ""
}else{
    Write-Host "Creation of the WSL2 image ""$gzipImgName"" failed!" -ForegroundColor Red
    Write-Host ""

}
#remove tar
Remove-Item -Path $tarImgPath





