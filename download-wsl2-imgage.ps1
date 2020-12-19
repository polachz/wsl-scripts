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
		Specifies the DckerHub image Tag
		If not specified, then the latest tag is used
    
    .Parameter Destination    
        Folder where the downloaded image will be stored

	.Example
        download-wsl2-imgage.ps1 -Image library/fedora -Tag 32 -Destination E:\WSL
		
		Downloads the fedora 32 image and store it at e:\WSL folder

    .Notes
        NAME:      download-wsl2-imgage.ps1
        AUTHOR:    Zdenek Polach
		WEBSITE:   https://polach.me
#>

[CmdletBinding(SupportsShouldProcess=$True)]
param (
    [Parameter(Mandatory)][string]$Image,
    [Parameter(Mandatory)][string]$Destination,
    [string]$Tag = ( "latest")

)


#$image="library/fedora"
#$image="library/ubuntu"
$version=$tag
#$workDir="S:\wkDir"
$workDir=$Destination
Function UnpackGzipFile{
    Param(
        $infile,
        $outfile = ($infile -replace '\.gz$','')
        )
    $inputData = New-Object System.IO.FileStream $inFile, ([IO.FileMode]::Open), ([IO.FileAccess]::Read), ([IO.FileShare]::Read)
    $output = New-Object System.IO.FileStream $outFile, ([IO.FileMode]::Create), ([IO.FileAccess]::Write), ([IO.FileShare]::None)
    $gzipStream = New-Object System.IO.Compression.GzipStream $inputData, ([IO.Compression.CompressionMode]::Decompress)
    $buffer = New-Object byte[](1024)
    while($true){
        $read = $gzipstream.Read($buffer, 0, 1024)
        if ($read -le 0){break}
        $output.Write($buffer, 0, $read)
        }
    $gzipStream.Close()
    $output.Close()
    $inputData.Close()
}

Write-Host "Beginning..."
$authUrl="https://auth.docker.io/token?service=registry.docker.io&scope=repository:" +$image + ":pull"

$response=Invoke-RestMethod -Uri $authUrl

$token = $response.token;
#Get Image descriptor. We are interested in blobs list
$header= @{
    "Authorization" = "Bearer $token" 
}
$layers=Invoke-RestMethod -Headers $header -Uri "https://registry-1.docker.io:/v2/$image/manifests/$version"
#Extract names of blob (sha256:xxyyzz......)
$allBlobSums= $layers.fsLayers | ForEach-Object -MemberName blobSum
#sometimes we can see duplicates in list (Fedore32 for example, then try to kick them off)
#but because layers are applied in specific order, we have to kick off all previous duplicates
#and leave only the latest
#then reverse array
[array]::Reverse($allBlobSums)
#is not specified order to process list in Select-Object - -Unique
#then to be sure, this method is disabled
###$uniqueBlobs = $allBlobSums | Select-Object -Unique 
#And we can try something more conservative, but where the order is granted
$uniqueBlobs=@()
foreach($blobSum in $allBlobSums){
    if ( -not ( $uniqueBlobs -contains $blobSum)){
        $uniqueBlobs += $blobSum
    }
}
#finally, reverse order back, so we have unique blob list, from the oldest to newer
[array]::Reverse($uniqueBlobs)

New-Item -ItemType Directory -Force -Path $workDir -ErrorAction Stop | Out-Null
$imgName=Split-Path -path $image -Leaf
$imgName = $imgName+"_"+$version + ".tar"

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
    Invoke-WebRequest -Headers $header -OutFile $outName -Uri "https://registry-1.docker.io/v2/$image/blobs/$blobName"
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
$imgName = Join-Path -Path $workDir -ChildPath $imgName
Rename-Item -Path $finalTar -NewName $imgName


