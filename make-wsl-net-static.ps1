<#
.SYNOPSIS
  Create or recreate WSL network with fixed stubnet and static Gateway IP
.DESCRIPTION
  - This script create or recreate the WSL network on Windows side with
    with fixed IP subnet and fixed IP gateway address
  - This script manages other Hyper-V VMs connected to WSL network too.
  - The sctipt allows to define and maintain firewall rules to allow
    connections from WSL machines to host. For example Ansible scripts
    can be developed by this way.
 .NOTES
  - This script must Run As Administrator from a Windows PowerShell prompt,
    or from the elevated bat file or scheduled task (Run As Administrator).
  - Any WSL command starts the WSL machine if not started already, and
    creates the NetAdapter 'vEthernet (WSL)' if it does not exist already
    (Windows deletes it on Windows power down). However this script creates
    the first, so WSL will re-use it.
  - Windows assigns the correct DNS nameserver if everything happened in the
    correct order i.e. WSL2 lightweight utility virtual machine is down and
    all Hyper-V VMs using WSL VMSwitch are down too before WSL network is
    recreated.
  - The DNS resolution works in any situation however you are connected to
    the Internet, and with or without VPN.
  - You should connect all VMs in Hyper-V to the VMSwitch 'WSL' too.
  - Script allows to define and maintain firewall rules defined for the
    'vEthernet (WSL)' switch. By default Windows creates only DNS rules
    (HNS Container Networking - DNS ... ). By proper defined rules is
    possible to connect by SSH or ansible to host computer for example.
    These rules are defined by json config file and rebind to new
    WSL network instances after Windows reboot. More details you can find
    at related github repo (see LINK)
  - The script is based on https://github.com/ocroz/wsl2-boot repository.
    Main credit goes to this author. I only addef FW rules possibilities
    and modified workflow little bit.

.LINK
  https://github.com/ocroz/wsl2-boot
#>

[CmdletBinding()] Param(
    [parameter(Mandatory=$false)] [Switch] $UpdateFwRules = $False,
    [parameter(Mandatory=$false)] [Switch] $RemoveFwRules = $False,
    [parameter(Mandatory=$false)] [String] $ConfigFile = $null,
    [parameter(Mandatory=$false)] [String] $WslSubnet = $null,
    [parameter(Mandatory=$false)] [String] $Name = "WSL",
    [parameter(Mandatory=$false)] [String] $distribution = $null,
    [parameter(Mandatory=$false)] [Switch] $force = $False,
    [parameter(Mandatory=$false)] [Switch] $reboot = $False
  )

$hasConfig = $false
$defaultConfigFileName="wsl-config.json"

$rulesArray = @()

function Convert-Int64toIPV4 ([int64]$int) {
  (([math]::truncate($int / 16777216)).tostring() + "." + ([math]::truncate(($int % 16777216) / 65536)).tostring() + "." + ([math]::truncate(($int % 65536) / 256)).tostring() + "." + ([math]::truncate($int % 256)).tostring() )
}

function Split-IPV4Subnet(){
  Param(
  [parameter(Mandatory=$true)] [String] $SubnetString #192.168.1.1/24
)

  if ($SubnetString -match '/\d') {
      $IPandMask = $SubnetString -Split '/'
      $IP = $IPandMask[0]
      $Mask = $IPandMask[1]
  }else{
      throw "Subnet mask was not specified!"
  }
  if ($Mask -notin 0..32) {
      throw "Subnet mask must be within 0-32!!"
  }

  $IPAddr = [ipaddress]::Parse($IP)
  $MaskAddr = [ipaddress]::Parse((Convert-Int64toIPV4 -int ([convert]::ToInt64(("1" * $Mask + "0" * (32 - $Mask)), 2))))
  $NetworkAddr = [ipaddress]($MaskAddr.address -band $IPAddr.address)
  $BroadcastAddr = [ipaddress](([ipaddress]::parse("255.255.255.255").address -bxor $MaskAddr.address -bor $NetworkAddr.address))


  return [pscustomobject]@{
      IPAddress        = $IPAddr
      MaskBits         = $Mask
      NetworkAddress   = $NetworkAddr
      BroadcastAddress = $broadcastaddr
      SubnetMask       = $MaskAddr
      Range            = "$networkaddr ~ $broadcastaddr"
  }

}

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
	return $True
}

function ParseConfigRules {
    param(
        [parameter(Mandatory=$true)][object] $cfgRulesArray
    )

    $result = @()
    $cfgRulesArray | ForEach-Object  {
        $name = $_.name
        $locPortStr = $_.localport
        $proto = $_.protocol
        $ports = $locPortStr -split ","
        $direct = $_.direction
        $raStr = $_.remoteaddress
        $ra = $raStr -split ","
        $icmp = $_.icmptype

        $obj = [pscustomobject]@{
            Name        = $name
            Protocol = $proto
            LocalPorts = $ports
            Direction = $direct
            RemoteAddress = $ra
            IcmpType =$icmp
        }
        $result+=($obj)
    }
    return $result
}

function CHeckIfFwRuleExists {
    param(
        [object] $rule
    )

    $fwRule = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
    if ($null -eq $fwRule){
        return $false
    }
    return $true

}

function RebindFwRules {
    param(
       [object] $rulesArr
    )

    $rulesArr | ForEach-Object {
        if (CHeckIfFwRuleExists $_) {
            Get-NetFirewallRule -DisplayName $_.Name  |  Get-NetFirewallInterfaceFilter | Set-NetFirewallInterfaceFilter -InterfaceAlias "vEthernet ($Name)"
             Write-Host "The Fw Rule $($_.Name) has been rebinded to new iface instance"
        } else {
            Write-Host "The Fw Rule $($_.Name) doesn't exist. Can't be rebinded"
        }
    }
}

function UpdateFwRules {
    param(
       [object] $rulesArr
    )

    $rulesArr | ForEach-Object {

      if (CHeckIfFwRuleExists $_ ) {
        if(($_.protocol -eq "ICMPv4") -or ($_.protocol -eq "ICMPv6")){
          Set-NetFirewallRule  -DisplayName $_.Name -Direction $_.Direction `
              -Protocol $_.Protocol -IcmpType $_.IcmpType `
              -RemoteAddress $_.RemoteAddress -InterfaceAlias "vEthernet ($Name)" -ErrorAction Stop
        } else {
          Set-NetFirewallRule  -DisplayName $_.Name -Direction $_.Direction `
              -Protocol $_.Protocol -LocalPort $_.LocalPorts `
              -RemoteAddress $_.RemoteAddress -InterfaceAlias "vEthernet ($Name)" -ErrorAction Stop
        }
        Write-Host "The Fw Rule $($_.Name) has been updated."
      } else {
        if(($_.protocol -eq "ICMPv4") -or ($_.protocol -eq "ICMPv6")){
          New-NetFirewallRule -DisplayName $_.Name -Direction $_.Direction `
            -Protocol $_.Protocol -IcmpType $_.IcmpType `
            -RemoteAddress $_.RemoteAddress -InterfaceAlias "vEthernet ($Name)" -ErrorAction Stop
        } else {
            New-NetFirewallRule -DisplayName $_.Name -Direction $_.Direction `
                -Protocol $_.Protocol -LocalPort $_.LocalPorts `
                -RemoteAddress $_.RemoteAddress -InterfaceAlias "vEthernet ($Name)" -ErrorAction Stop
        }
        Write-Host "The Fw Rule $($_.Name) has been created."
      }
    }

}
function DeleteFwRules {
    param(
        [object] $rulesArr
    )

    $rulesArr | ForEach-Object {
        if (CHeckIfFwRuleExists $_) {
            Remove-NetFirewallRule  -DisplayName $_.Name
            Write-Host "The Fw Rule $($_.Name) has been deleted."
        } else {
            Write-Host "The Fw Rule $($_.Name) doesn't exist. Nothing deleted."
        }
    }
}

function New-HnsNetwork() {
  Param(
    [parameter(Mandatory=$true)] [String] $Name,          # "WSL"
    [parameter(Mandatory=$true)] [String] $AddressPrefix, # "192.168.50.0/24"
    [parameter(Mandatory=$true)] [String] $GatewayAddress # "192.168.50.1"
  )
  Write-Debug "New-HnsNetwork() with Name $Name, AddressPrefix $AddressPrefix, GatewayAddress $GatewayAddress ..."

  # Helper functions first
  function Get-HcnMethods() {
    $DebugPreference = "SilentlyContinue"
    $signature = @'
      [DllImport("computenetwork.dll")] public static extern System.Int64 HcnCreateNetwork(
        [MarshalAs(UnmanagedType.LPStruct)] Guid Id,
        [MarshalAs(UnmanagedType.LPWStr)]   string Settings,
        [MarshalAs(UnmanagedType.SysUInt)]  out IntPtr Network,
        [MarshalAs(UnmanagedType.LPWStr)]   out string Result
      );
'@
    Add-Type -MemberDefinition $signature -Namespace ComputeNetwork.HNS.PrivatePInvoke -Name NativeMethods -PassThru
  }
  function Write-HcnErr {
      $errorOutput = ""
      if($Hr -ne 0) {
        $errorOutput += "HRESULT: $($Hr). "
      }
      if(-NOT [string]::IsNullOrWhiteSpace($Result)) {
        $errorOutput += "Result: $($Result)"
      }
      if(-NOT [string]::IsNullOrWhiteSpace($errorOutput)) {
        $errString = "$($FunctionName) -- $($errorOutput)"
        throw $errString
      }
  }

  # Create this network
  $settings = @"
    {
      "Name" : "WSL",
      "Flags": 9,
      "Type": "ICS",
      "IPv6": false,
      "IsolateSwitch": true,
      "MaxConcurrentEndpoints": 1,
      "Subnets" : [
        {
          "ObjectType": 5,
          "AddressPrefix" : "$AddressPrefix",
          "GatewayAddress" : "$GatewayAddress",
          "IpSubnets" : [
            {
              "Flags": 3,
              "IpAddressPrefix": "$AddressPrefix",
              "ObjectType": 6
            }
          ]
        }
      ],
      "DNSServerList" : "$GatewayAddress"
    }
"@
  Write-Debug "Creating network with these parameters: $settings"

  $hcnClientApi = Get-HcnMethods
  $id = "B95D0C5E-57D4-412B-B571-18A81A16E005"
  $handle = 0
  $result = ""
  $hr = $hcnClientApi::HcnCreateNetwork($id, $settings, [ref] $handle, [ref] $result)
  Write-HcnErr -FunctionName HcnCreateNetwork -Hr $hr -Result $result

  # Function 'echo' fails if calling ps1 from another ps1
  Write-Host "Network created with these parameters: $settings"
}

function Set-VpnToggle() {
  Param(
    [parameter(Mandatory=$false)] [String] $Name = "WSL",
    [parameter(Mandatory=$false)] [String] $distribution = $null,
    [parameter(Mandatory=$false)] [Bool] $reboot = $False
  )
  if ($distribution) { $d = "-d" }
  Write-Debug "Set-VpnToggle() with Name=$Name, reboot=$reboot ..."

  # There must be only one VMSwitch for WSL always
  if ((Get-VMSwitch -Name $Name -ea "SilentlyContinue").Count -gt 1) {
    Throw "More than one VMSwitch named $Name exist. Please reboot your computer to clean them all."
  }

  # Get connected VPN
  $vpnStrings = @("Cisco AnyConnect", "Juniper", "VPN")
  $vpnNet = Get-NetAdapter | Where-Object { $_.status -eq 'Up' } | Where-Object {
    $found=$False
    Foreach($str in $vpnStrings) {
      if ($_.InterfaceDescription.contains($str)) {$found=$True;break}
    }
    $found
  }

  # > To adjust Mtu to VPN capability
  $phyMtu = Get-NetAdapter -Physical | Where-Object { $_.status -eq 'Up' } | Get-NetIPInterface -AddressFamily IPv4 | Select-Object -ExpandProperty NlMtu
  $wslMtu = Get-NetIPInterface -InterfaceAlias "vEthernet ($Name)" -AddressFamily IPv4 | Get-NetIPInterface -AddressFamily IPv4 | Select-Object -ExpandProperty NlMtu
  Write-Debug "phyMtu=$phyMtu,wslMtu=$wslMtu"

  # > To patch DNS nameserver under VPN
  $dnsIP = "" # Let Windows determine default dnsIP
  if ($reboot) { Write-Debug "wsl --shutdown"; wsl --shutdown } # Take default dnsIP if not using VPN
  wsl $d $distribution --list --running >$null; if ($?) { $dnsIP = $GatewayIP } # Force dnsIP = GatewayIP if VPN disconnected
  Write-Debug "dnsIP=$dnsIP"

  # Different actions if or if not under VPN
  if ($vpnNet) {
    # Apply changes if using VPN

    # If WSL2 lost connectivity under VPN (not the case for me)
    # $vpnNet | Set-NetIPInterface -InterfaceMetric 6000

    # Adjust Mtu to VPN capability
    $vpnMtu = $vpnNet | Get-NetIPInterface -AddressFamily IPv4 | Select-Object -ExpandProperty NlMtu
    if ($vpnMtu -lt $phyMtu -and $wslMtu -ne $vpnMtu) {
      Write-Host "Patching NetIPInterface ""vEthernet ($Name)"" with NlMtu=$vpnMtu ..."
      Get-NetIPInterface -InterfaceAlias "vEthernet ($Name)" | Set-NetIPInterface -NlMtu $vpnMtu
      $wslMtu = $vpnMtu
    }

    # Patch DNS nameserver under VPN
    $dnsIPs = $vpnNet | Get-DnsClientServerAddress -AddressFamily IPv4 | Select-Object -ExpandProperty ServerAddresses
    $dnsIP = $dnsIPs[0]

    # Patch DNS search under VPN
    $dnsSearches = Get-DnsClientGlobalSetting | ForEach-Object { $_.SuffixSearchList }
    $dnsSearch = $dnsSearches[0]
  } else {
    # Revert any change if not using VPN

    # Set defaults when there is no Internet connection
    if ($null -eq $phyMtu) {
      $phyMtu = Get-NetAdapter -Physical | Get-NetIPInterface -AddressFamily IPv4 | Select-Object -ExpandProperty NlMtu
      $phyMtu = $phyMtu[0]
    }

    if ($wslMtu -ne $phyMtu)  {
      Write-Host "Patching NetIPInterface ""vEthernet ($Name)"" with NlMtu=$phyMtu ..."
      Get-NetIPInterface -InterfaceAlias "vEthernet ($Name)" | Set-NetIPInterface -NlMtu $phyMtu
      $wslMtu = $phyMtu
    }

    # No need to patch MTU on Linux side if WSL has been shutdown
    if (-not $dnsIP) { $wslMtu = "" }
  }

  # Return settings to apply on Linux side too
  Write-Debug "dnsIP=$dnsIP,dnsSearch=$dnsSearch,wslMtu=$wslMtu."
  return $dnsIP,$dnsSearch,$wslMtu
}

function Start-WslBoot() {
  Write-Debug "Start-WslBoot() in debug mode"

  # Check any existing WSL network
  $wslNetwork = Get-HnsNetwork | Where-Object { $_.Name -eq $Name }
  if ($null -ne $wslNetwork) { $wslNetworkJson = $wslNetwork | ConvertTo-Json; Write-Debug "Current wslNetwork: $wslNetworkJson" }

  # Create or recreate WSL network if necessary
  if ($force -Or $null -eq $wslNetwork -Or $wslNetwork.Subnets.AddressPrefix -ne $WslPureSubnet) {
    # To cleanly delete the VMSwitch named WSL along with WSL Network (see: Get-VMSwitch -Name WSL)
    # and to assign correct DNS nameserver after WSL Network is recreated and WSL host is restarted:
    # - Cleanly shutdown all WSL hosts, and
    # - Cleanly stop all Hyper-V VMs using WSL VMSwitch too
    Write-Host "Stopping all WSL hosts and all Hyper-V VMs connected to VMSwitch $Name ..."
    wsl --shutdown
    $wslVMs = Get-VM | Where-Object { $_.State -eq 'Running' } | Get-VMNetworkAdapter | Where-Object { $_.SwitchName -eq $Name }
    $wslVMs | ForEach-Object { Stop-VM -Name $_.VMName }

    # Delete existing network
    Write-Host "Deleting existing WSL network and other conflicting NAT network ..."
    $wslNetwork | Remove-HnsNetwork

    # Check WSL network is deleted
    $wslNetwork = Get-HnsNetwork | Where-Object { $_.Name -eq $Name }
    if ($null -ne $wslNetwork) {
      $wslNetworkJson = $wslNetwork | ConvertTo-Json
      Throw "Current wslNetwork could not be deleted: $wslNetworkJson"
    }

    # Destroy WSL network may fail if it happened in the wrong order like if it was done manually
    if (Get-VMSwitch -Name $Name -ea "SilentlyContinue") {
      Throw "One more VMSwitch named $Name remains after destroying WSL network. Please reboot your computer to clean it up."
    }

    # Delete conflicting NetNat
    $wslNetNat = Get-NetNat | Where-Object {$_.InternalIPInterfaceAddressPrefix -Match $AddressPrefix}
    $wslNetNat | ForEach-Object {Remove-NetNat -Confirm:$False -Name:$_.Name}

    # Create new WSL network
    New-HnsNetwork -Name $Name -AddressPrefix $WslPureSubnet -GatewayAddress $GatewayIP

    # Switch all misconfigured Hyper-V VMs to newly created Virtual VMSwitch 'WSL'
    Write-Host "Switching all misconfigured Hyper-V VMs to newly created VMSwitch $Name ..."
    Get-VM | Get-VMNetworkAdapter | Where-Object { $null -eq $_.SwitchName } | Connect-VMNetworkAdapter -SwitchName $Name

    # Restart all VMs which failed to start due to network misconfiguration
    # as Virtual switch 'WSL' got deleted at Windows power down
    Get-VM | Where-Object { $_.State -Eq 'Saved' } | Start-VM

    # Restart all previously started Hyper-V VMs connected to VMSwitch WSL
    if ($wslVMs) {
      Write-Host "Restarting all Hyper-V VMs connected to VMSwitch $Name ..."
      $wslVMs | ForEach-Object { Start-VM -Name $_.VMName }
    }
  }

  # Apply changes to WSL network if or if not using VPN
  $dnsIP,$dnsSearch,$wslMtu = Set-VpnToggle -Name $Name -reboot $reboot

  # I do not use this approach - better is to configure the WSL instance directly
  # problem may be the VPN MTU - can be modified in the future
  # wsl-boot.sh updates primary ip addr to $WslHostIP and starts few services on Linux side.
  #$n = $null; if ($dnsIP)     { $n = "-n" }
  #$s = $null; if ($dnsSearch) { $s = "-s" }
  #$m = $null; if ($wslMtu)    { $m = "-m" }
  #wsl $d $distribution -u root /boot/wsl-boot.sh -p $WslSubnetPrefix -g $GatewayIP -i $WslHostIP $n $dnsIP $s $dnsSearch $m $wslMtu

  # Kind exit message
  Write-Host "wsl-boot completed !"
}

if ($PSBoundParameters['Debug']) { $DebugPreference = "Continue" }

# General information
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
  Throw "Please run this script with elevated permission (Run As Administrator)"
}

$dst_all_params_array = @('UpdateFwRules', 'RemoveFwRules')
if ( -not ( CheckMutualExclusiveParam -all_params_array $dst_all_params_array -where_to_find $PSBoundParameters) ) {
	exit
}
if($ConfigFile){
    if( -not ( Test-Path -Path $ConfigFile -PathType Leaf -ErrorAction SilentlyContinue ) ){
        Throw "ConfigFile paremeter is specified but the file doesn't exist!! ($ConfigFile)"
    } else {
        $hasConfig = $true
        $configFilePath = $ConfigFile
    }
} else {
    $configFilePath = Join-Path $PSSCriptRoot $defaultConfigFileName
    if( Test-Path -Path $configFilePath -PathType Leaf -ErrorAction SilentlyContinue ) {
        $hasConfig = $true
    }
}
if( ( $UpdateFwRules -or $RemoveFwRules ) -And -not($hasConfig) ){
     Throw "UpdateFwRules or RemoveFwRules paremeter require configFile"
}
if( ($false -eq $hasConfig) -and ($null -eq $WslSubnet) ){
    Throw "The subnet is not specified. No config file and WSLSubnet parameter either."
}
if($hasConfig){
    $myJson = Get-Content $configFilePath -Raw | ConvertFrom-Json
    $SconfigSubnet = $myJson.Config.subnet
    $rulesArray = ParseConfigRules $myjson.Config.rules

    if($null -eq $SconfigSubnet){
        Throw "Subnet is not defines in the config file!"
    }

    if($UpdateFwRules){
        Write-Host "Going to create or update WSL FW rules"
        UpdateFwRules $rulesArray
        exit
    }
    if($RemoveFwRules){
        Write-Host "Going to delete WSL FW rules"
        DeleteFwRules $rulesArray
        exit
    }
    if( $WslSubnet){
        Write-Host "WslSubnet is specified but config file exists! - config file override the WSlSubnet parameter"
    }
    $WslSubnet = $SconfigSubnet
}

$ParsedSubnet = Split-IPV4Subnet $WslSubnet

$WSLNetAddress=$ParsedSubnet.NetworkAddress
$WSLBitMask=$ParsedSubnet.MaskBits
$WslPureSubnet = "$WSLNetAddress/$WSLBitMask"
$GatewayIP = $ParsedSubnet.IPAddress



#$d = $null; $distro = "default"; if ($distribution) { $d = "-d"; $distro = $distribution }
#Write-Host "Booting $distro distribution with WslSubnetPrefix $WslSubnetPrefix, WslHostIP $WslHostIP ..."

Start-WslBoot

if ( $hasConfig){
  Write-Host "Going to Rebind WSL FW rules"
  RebindFwRules $rulesArray
}
