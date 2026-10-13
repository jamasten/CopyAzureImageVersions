<#
MIT License

Copyright (c) 2026 Jason Masten

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

.SYNOPSIS
Imports an Image Version from an Azure Compute Gallery.
.DESCRIPTION
Imports a downloaded VHD as a Managed Disk and is validated using an MD5 hash that is auto-generated.  If the specified Compute Gallery and Image Definition do not exist, it creates those resources.  Next, the Managed Disk is imported as an Image Version.  Once the import completes, the Managed Disk is deleted.
.PARAMETER AzCopyDownloadUrl
The download URL for the AzCopy installer in ZIP format.
.PARAMETER ComputeGalleryName
The name for the Azure Compute Gallery.  It will be created if it does not exist.
.PARAMETER ComputeGalleryResourceGroupName
The name for the Resource Group that contains the Azure Compute Gallery.
.PARAMETER ImageDefinitionAcceleratedNetworking
The accelerated networking feature for the Image Definition.
.PARAMETER ImageDefinitionArchitecture
The processor architecture for the operating system.
.PARAMETER ImageDefinitionHibernation
The hibernation feature for the Image Definition
.PARAMETER ImageDefinitionHyperVGeneration
The Hyper-V Generation for the Image Definition.
.PARAMETER ImageDefinitionName
The name for the Image Definition in the Azure Compute Gallery.  It will be created if it does not exist and should match the value of the image definition specified in the export script.
.PARAMETER ImageDefinitionOffer
The image offer for the Image Defintion.
.PARAMETER ImageDefinitionOsType
The operating system type for the Image Definition.
.PARAMETER ImageDefinitionPublisher
The publisher for the Image Defintion.
.PARAMETER ImageDefinitionSecurityType
The security type for the Image Definition.
.PARAMETER ImageDefinitionSku
The SKU for the Image Defintion.
.PARAMETER ImageDefinitionState
The state for the Image Defintion.
.PARAMETER ImageVersionName
The name for the Image Version.
.NOTES
  Version:              2.0
  Author:               Jason Masten
  Creation Date:        2022-05-11
  Last Modified Date:   2026-10-13
.EXAMPLE
.\Import-AzureComputeGalleryImageVersion.ps1 `
    -AzCopyDownloadUrl 'https://aka.ms/downloadazcopy-v10-windows' `
    -ComputeGalleryName 'cg_shared_d_eu' `
    -ComputeGalleryResourceGroupName 'rg-images-d-eu' `
    -ImageDefinitionAcceleratedNetworking 'False' `
    -ImageDefinitionHibernation 'False' `
    -ImageDefinitionHyperVGeneration 'V2' `
    -ImageDefinitionName 'WindowsServer2019Datacenter' `
    -ImageDefinitionOffer 'WindowsServer' `
    -ImageDefinitionOsType 'Windows' `
    -ImageDefinitionPublisher 'MicrosoftWindowsServer' `
    -ImageDefinitionSecurityType 'TrustedLaunch' `
    -ImageDefinitionSku '2019-datacenter' `
    -ImageDefinitionState 'Generalized' `
    -ImageVersionName '1.0.0'

This example imports the VHD as a Managed Disk, creates a new Image Defintion, and imports the Managed Disk as a new Image Version into the new Image Defintion.
.EXAMPLE
.\Import-AzureComputeGalleryImageVersion.ps1 `
    -AzCopyDownloadUrl 'https://aka.ms/downloadazcopy-v10-windows' `
    -ComputeGalleryName 'cg_shared_d_eu' `
    -ComputeGalleryResourceGroupName 'rg-images-d-eu' `
    -ImageDefinitionName 'WindowsServer2019Datacenter' `
    -ImageVersionName '1.0.0'

This example imports a VHD as a Managed Disk and imports the Managed Disk as a new Image Version into an existing Image Defintion.
#>
[Cmdletbinding()]
param(
    [parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AzCopyDownloadUrl,

    [parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputeGalleryName,

    [parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputeGalleryResourceGroupName,

    [parameter(Mandatory = $false)]
    [ValidateSet('True', 'False')]
    [string]$ImageDefinitionAcceleratedNetworking = 'True',

    [parameter(Mandatory = $false)]
    [ValidateSet('x64', 'Arm64')]
    [string]$ImageDefinitionArchitecture = 'x64',

    [parameter(Mandatory = $false)]
    [ValidateSet('SCSI', 'SCSI,NVME')]
    [string]$ImageDefinitionDiskControllerType = 'SCSI, NVME',

    [parameter(Mandatory = $false)]
    [ValidateSet('True', 'False')]
    [string]$ImageDefinitionHibernation = 'False',

    [parameter(Mandatory = $false)]
    [ValidateSet('V1', 'V2')]
    [string]$ImageDefinitionHyperVGeneration = 'V2',

    [parameter(Mandatory)]
    [ValidateLength(1, 80)]
    [string]$ImageDefinitionName,

    [parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ImageDefinitionOffer,

    [parameter(Mandatory = $false)]
    [ValidateSet('Windows', 'Linux')]
    [string]$ImageDefinitionOsType = 'Windows',

    [parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ImageDefinitionPublisher,

    [parameter(Mandatory = $false)]
    [ValidateSet('TrustedLaunchAndConfidentialVMSupported', 'TrustedLaunchSupported')]
    [string]$ImageDefinitionSecurityType = 'TrustedLaunchSupported',

    [parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ImageDefinitionSku,

    [parameter(Mandatory = $false)]
    [ValidateSet('Generalized', 'Specialized')]
    [string]$ImageDefinitionState = 'Generalized',

    [parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ImageVersionName = '1.0.0'
)

#Requires -Modules Az.Accounts

$ErrorActionPreference = 'Stop'

# Set variables
$DiskPrefix = "disk-$($ImageDefinitionName)-"
try {
    $SubscriptionId = (Get-AzContext).Subscription.Id
}
catch {
    throw "Failed to get the current Azure subscription context. Run Connect-AzAccount first."
}

# Download and extract AzCopy if it doesn't already exist
if (-Not (Get-ChildItem -Path . -Filter 'azcopy.exe' -Recurse).FullName) {
    Invoke-WebRequest -Uri $AzCopyDownloadUrl -OutFile 'azcopy.zip'
    Expand-Archive -Path 'azcopy.zip' -Force
}
$AzCopyExe = (Get-ChildItem -Path . -Filter 'azcopy.exe' -Recurse).FullName

# Gets the location of the resource group containing the Azure Compute Gallery
$ResourceGroupPath = '/subscriptions/' + $SubscriptionId + '/resourcegroups/' + $ComputeGalleryResourceGroupName + '?api-version=2021-04-01'
$Location = ((Invoke-AzRestMethod -Method 'Get' -Path $ResourceGroupPath).Content | ConvertFrom-Json).location

# Checks if the Compute Gallery exists
$GalleryPath = '/subscriptions/' + $SubscriptionId + '/resourceGroups/' + $ComputeGalleryResourceGroupName + '/providers/Microsoft.Compute/galleries/' + $ComputeGalleryName + '?api-version=2025-12-03'
$Gallery = Invoke-AzRestMethod -Method 'Get' -Path $GalleryPath

# Create Compute Gallery if it doesn't exist
if ($Gallery.StatusCode -ne 200) { 
    $GalleryPayload = @{
        location = $Location
    } | ConvertTo-Json
    Invoke-AzRestMethod -Method 'Put' -Path $GalleryPath -Payload $GalleryPayload -WaitForCompletion | Out-Null
}

# Checks if the Image Definition exists
$ImageDefinitionPath = '/subscriptions/' + $SubscriptionId + '/resourceGroups/' + $ComputeGalleryResourceGroupName + '/providers/Microsoft.Compute/galleries/' + $ComputeGalleryName + '/images/' + $ImageDefinitionName + '?api-version=2025-12-03'
$ImageDefinition = Invoke-AzRestMethod -Method 'Get' -Path $ImageDefinitionPath

# Create the Image Definition if it doesn't exist
if ($ImageDefinition.StatusCode -ne 200) {
    $ImageDefinitionPayload = @{
        location   = $Location
        properties = @{
            architecture     = $ImageDefinitionArchitecture
            features         = @(
                @{Name = 'DiskControllerTypes'; Value = $ImageDefinitionDiskControllerType },
                @{Name = 'IsAcceleratedNetworkSupported'; Value = $ImageDefinitionAcceleratedNetworking },
                @{Name = 'IsHibernateSupported'; Value = $ImageDefinitionHibernation },
                @{Name = 'SecurityType'; Value = $ImageDefinitionSecurityType }
            )
            hyperVGeneration = $ImageDefinitionHyperVGeneration
            identifier       = @{
                publisher = $ImageDefinitionPublisher
                offer     = $ImageDefinitionOffer
                sku       = $ImageDefinitionSku
            }
            osType           = $ImageDefinitionOsType
            osState          = $ImageDefinitionState
        }
    } | ConvertTo-Json -Depth 4
    Invoke-AzRestMethod -Method 'Put' -Path $ImageDefinitionPath -Payload $ImageDefinitionPayload -WaitForCompletion | Out-Null
}

# Get the downloaded disks / VHDs from the Downloads folder
$Vhds = Get-ChildItem -Path "$($HOME)\Downloads\disk-$($ImageDefinitionName)-*.vhd"

# Throw an error if the disks are not found
if ($Vhds.Count -eq 0) {
    Write-Host -Message 'Disks were not found. Be sure to use the same Image Definition Name used in the export script.' -ForegroundColor 'Red'
    throw
}

$DataDiskImage = @()
for ($i = 0; $i -lt $Vhds.Count; $i++) {

    $DiskName = $DiskPrefix + $i.ToString()

    # Get exact VHD upload size
    $Vhd = Get-Item -LiteralPath $Vhds[$i].FullName
    $UploadSizeBytes = $Vhd.Length

    # Create an empty managed disk for direct upload
    $DiskPath = '/subscriptions/' + $SubscriptionId + '/resourceGroups/' + $ComputeGalleryResourceGroupName + '/providers/Microsoft.Compute/disks/' + $DiskName + '?api-version=2026-03-02'
    $DiskPayload = @{
        location   = $Location
        properties = @{
            creationData = @{
                createOption    = "Upload"
                uploadSizeBytes = $UploadSizeBytes
            }
            hyperVGeneration = $ImageDefinitionHyperVGeneration
            osType = $ImageDefinitionOsType
            supportedCapabilities = @{
                acceleratedNetwork =  if ($ImageDefinitionAcceleratedNetworking -eq 'True') { $true } else { $false }
                diskControllerTypes = $ImageDefinitionDiskControllerType
                supportedSecurityOption = $ImageDefinitionSupportedSecurityOption
            }
            supportsHibernation =  if ($ImageDefinitionHibernation -eq 'True') { $true } else { $false }
        }
        sku        = @{
            name = 'Premium_LRS'
        }
    } | ConvertTo-Json -Depth 5
    $Disk = Invoke-AzRestMethod -Method 'PUT' -Path $DiskPath -Payload $DiskPayload -WaitForCompletion

    if ($Disk.StatusCode -notin 200, 201, 202) {
        throw "Managed disk creation failed. HTTP $($Disk.StatusCode): $($Disk.Content)"
    }

    # Request Managed Disk SAS
    $DiskGrantAccessPath = '/subscriptions/' + $SubscriptionId + '/resourceGroups/' + $ComputeGalleryResourceGroupName + '/providers/Microsoft.Compute/disks/' + $DiskName + '/beginGetAccess?api-version=2026-03-02'
    $DiskGrantAccessPayload = @{
        access            = "Write"
        durationInSeconds = 86400
    } | ConvertTo-Json
    $DiskGrantAccess = Invoke-AzRestMethod -Method 'POST' -Path $DiskGrantAccessPath -Payload $DiskGrantAccessPayload

    if ($DiskGrantAccess.StatusCode -notin 200, 202) {
        throw "Unable to grant write access. HTTP $($DiskGrantAccess.StatusCode): $($DiskGrantAccess.Content)"
    } 

    $AccessSAS = (Invoke-AzRestMethod -Method 'GET' -Uri $DiskGrantAccess.Headers.Location.AbsoluteUri).Content | ConvertFrom-Json | Select-Object -ExpandProperty accessSAS
    
    if ([string]::IsNullOrWhiteSpace($AccessSAS)) {
        throw "Azure did not return an accessSAS value."
    }

    # Upload the VHD to a Managed Disk using AzCopy
    Write-Host " Uploading VHD with AzCopy..."
    $AzCopyExitCode = (Start-Process -FilePath $AzCopyExe -ArgumentList "copy $($Vhds[$i].FullName) $AccessSAS --blob-type PageBlob" -Wait -PassThru -NoNewWindow).ExitCode

    # Revoke Managed Disk SAS
    $DiskRevokeAccessPath = '/subscriptions/' + $SubscriptionId + '/resourceGroups/' + $ComputeGalleryResourceGroupName + '/providers/Microsoft.Compute/disks/' + $DiskName + '/endGetAccess?api-version=2026-03-02'
    $DiskRevokeAccess = Invoke-AzRestMethod -Method 'POST' -Path $DiskRevokeAccessPath 

    if ($DiskRevokeAccess.StatusCode -notin 200, 202) {
        throw "Unable to revoke disk access. HTTP $($DiskRevokeAccess.StatusCode): $($DiskRevokeAccess.Content)"
    }

    if ($AzCopyExitCode -ne 0) {
        Write-Host "AzCopy failed with exit code $AzCopyExitCode."
        throw
    } else {
        Write-Host "AzCopy upload completed successfully for $($Vhds[$i].FullName)"
    }

    # Gets the information for the Managed Disk
    $DiskResourceId = ($Disk.Content | ConvertFrom-Json).id

    if ($i -eq 0) {
        # Defines the Source object used to create the OS disk for the Image Version
        $OsDiskImage = @{Source = @{Id = $DiskResourceId } }
    }
    else {
        # Defines the Source object used to create a data disk for the Image Version
        $DataDisk = @{Source = @{Id = $DiskResourceId }; Lun = ($i - 1) }
        $DataDiskImage += $DataDisk
    }
}

# Create a new Image Version using the Managed Disk(s)
$ImageVersionPayload = @{
    location = $Location
    properties = @{
        publishingProfile = @{
            targetRegions = @(@{name = $Location})
        }
        storageProfile = @{
            osDiskImage = $OsDiskImage
        }
    }
}

if ($Vhds.Count -gt 1) {
    $ImageVersionPayload.properties.storageProfile.Add('dataDiskImages', $DataDiskImage)
}

$ImageVersionPath = '/subscriptions/' + $SubscriptionId + '/resourceGroups/' + $ComputeGalleryResourceGroupName + '/providers/Microsoft.Compute/galleries/' + $ComputeGalleryName + '/images/' + $ImageDefinitionName + '/versions/' + $ImageVersionName + '?api-version=2025-03-03'
$ImageVersion = Invoke-AzRestMethod -Method 'PUT' -Path $ImageVersionPath -Payload $($ImageVersionPayload | ConvertTo-Json -Depth 5) -WaitForCompletion

if ($ImageVersion.StatusCode -notin 200, 201, 202) {
    throw "Failed to create the Image Version. HTTP $($ImageVersion.StatusCode): $($ImageVersion.Content)"
}

# Deletes the Managed Disk(s)
for ($i = 0; $i -lt $Vhds.Count; $i++) {
    $DiskName = $DiskPrefix + $i.ToString()
    $DiskDeletePath = '/subscriptions/' + $SubscriptionId + '/resourceGroups/' + $ComputeGalleryResourceGroupName + '/providers/Microsoft.Compute/disks/' + $DiskName + '?api-version=2026-03-02'
    Invoke-AzRestMethod -Method 'DELETE' -Path $DiskDeletePath | Out-Null
}