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
Exports an Image Version from an Azure Compute Gallery.
.DESCRIPTION
Exports a VHD of a Managed Disk created from an Image Version in an Azure Compute Gallery.  The VHD is saved to the Downloads folder in the user's profile that is running the script.
.PARAMETER AzCopyDownloadUrl
The download URL for AzCopy installer in ZIP format.
.PARAMETER ComputeGalleryName
The name of the Azure Compute Gallery.
.PARAMETER ComputeGalleryResourceGroupName
The name of the Resource Group that contains the Azure Compute Gallery.
.PARAMETER ImageDefinitionName
The name of the Image Definition in the Azure Compute Gallery.
.PARAMETER ImageVersionName
The name of the Image Version in the Azure Compute Gallery.
.NOTES
  Version:              2.0
  Author:               Jason Masten
  Creation Date:        2022-05-11
  Last Modified Date:   2026-10-13
.EXAMPLE
.\Export-AzureComputeGalleryImageVersion.ps1 `
    -ComputeGalleryName 'cg_shared_d_va' `
    -ComputeGalleryResourceGroupName 'rg-images-d-va' `
    -ImageDefinitionName 'WindowsServer2019Datacenter' `
    -ImageVersionName '1.0.0'

This example creates a Managed Disk from an Image Version in an Azure Compute Gallery. Downloads the VHD of the Managed Disk to the user's Downloads folder and validates the auto-generated MD5 hash.  Once the download completes, the Managed Disk is deleted. 
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

    [parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ImageDefinitionName,

    [parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ImageVersionName
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

# Download and extract AzCopy
Invoke-WebRequest -Uri $AzCopyDownloadUrl -OutFile 'azcopy.zip'
Expand-Archive -Path 'azcopy.zip' -Force
$AzCopyExe = (Get-ChildItem -Path . -Filter 'azcopy.exe' -Recurse).FullName

# Gets the location of the resource group containing the Azure Compute Gallery
$ResourceGroupPath = '/subscriptions/' + $SubscriptionId + '/resourcegroups/' + $ComputeGalleryResourceGroupName + '?api-version=2021-04-01'
$Location = ((Invoke-AzRestMethod -Method 'Get' -Path $ResourceGroupPath).Content | ConvertFrom-Json).location

# Gets the Image Version
$ImageVersionPath = '/subscriptions/' + $SubscriptionId + '/resourceGroups/' + $ComputeGalleryResourceGroupName + '/providers/Microsoft.Compute/galleries/' + $ComputeGalleryName + '/images/' + $ImageDefinitionName + '/versions/' + $ImageVersionName + '?api-version=2025-03-03'
$ImageVersion = ((Invoke-AzRestMethod -Method 'Get' -Path $ImageVersionPath).Content | ConvertFrom-Json)

# Gets the Image Definition
$ImageDefinitionPath = '/subscriptions/' + $SubscriptionId + '/resourceGroups/' + $ComputeGalleryResourceGroupName + '/providers/Microsoft.Compute/galleries/' + $ComputeGalleryName + '/images/' + $ImageDefinitionName + '?api-version=2025-03-03'
$ImageDefinition = (Invoke-AzRestMethod -Method 'Get' -Path $ImageDefinitionPath).Content | ConvertFrom-Json

$ImageDisksCount = $ImageVersion.properties.storageProfile.osDiskImage.Count + $ImageVersion.properties.storageProfile.dataDiskImages.Count
for($i = 0; $i -lt $ImageDisksCount; $i++)
{    
    $GalleryImageReference = if($i -eq 0)
    {
        @{Id = $ImageVersion.Id}
    }
    else{
        @{Id = $ImageVersion.Id; Lun = $($i - 1)}
    }

    $DiskName = $DiskPrefix + $i.ToString()

    # Creates a Managed Disk using the Image Version in the Compute Gallery
    $DiskPayload = @{
        location = $Location
        properties = @{
            creationData = @{
                createOption = 'FromImage'
                galleryImageReference = $GalleryImageReference
            }
            osType = $ImageDefinition.properties.osType
            securityProfile = @{
                securityType = if ($($ImageDefinition.properties.features | Where-Object { $_.Name -eq 'SecurityType' } | Select-Object -ExpandProperty Value) -eq "TrustedLaunch") { 'TrustedLaunch' } else { $NULL }
            }
        }
        sku = @{
            name = 'Premium_LRS'
            tier = 'Premium'
        }
    } | ConvertTo-Json -Depth 4
    $DiskPath = '/subscriptions/' + $SubscriptionId + '/resourceGroups/' + $ComputeGalleryResourceGroupName + '/providers/Microsoft.Compute/disks/' + $DiskName + '?api-version=2026-03-02'
    Invoke-AzRestMethod -Method 'PUT' -Path $DiskPath -Payload $DiskPayload -WaitForCompletion | Out-Null

    # Creates a URI with a SAS Token to download the VHD of the Managed Disk
    $DiskGrantAccessPayload = @{
        access = 'Read'
        durationInSeconds = 14400
        fileFormat = 'VHD'
    } | ConvertTo-Json
    $DiskGrantAccessPath = '/subscriptions/' + $SubscriptionId + '/resourceGroups/' + $ComputeGalleryResourceGroupName + '/providers/Microsoft.Compute/disks/' + $DiskName + '/beginGetAccess?api-version=2026-03-02'
    $DiskGrantAccess = Invoke-AzRestMethod -Method 'POST' -Path $DiskGrantAccessPath -Payload $DiskGrantAccessPayload
    $AccessSAS = (Invoke-AzRestMethod -Method 'GET' -Uri $DiskGrantAccess.Headers.Location.AbsoluteUri).Content | ConvertFrom-Json | Select-Object -ExpandProperty accessSAS

    # Downloads the VHD using AzCopy and validates the MD5 hash
    $Destination = "$($HOME)\Downloads\$($DiskName).vhd"
    $AzCopyExitCode = (Start-Process -FilePath $AzCopyExe -ArgumentList "copy $AccessSAS $Destination --check-md5=FailIfDifferent" -Wait -PassThru -NoNewWindow).ExitCode

    # Revokes the SAS Token to download the VHD
    $DiskRevokeAccessPath = '/subscriptions/' + $SubscriptionId + '/resourceGroups/' + $ComputeGalleryResourceGroupName + '/providers/Microsoft.Compute/disks/' + $DiskName + '/endGetAccess?api-version=2026-03-02'
    $DiskRevokeAccess = Invoke-AzRestMethod -Method 'POST' -Path $DiskRevokeAccessPath

    if ($DiskRevokeAccess.StatusCode -notin 200, 202) {
        throw "Unable to revoke disk access. HTTP $($DiskRevokeAccess.StatusCode): $($DiskRevokeAccess.Content)"
    }

    if ($AzCopyExitCode -ne 0) {
        Write-Host "AzCopy failed with exit code $AzCopyExitCode."
        throw
    } else {
        Write-Host "AzCopy download completed successfully for $DiskName"
    }

    # Deletes the Managed Disk
    $DiskDeletePath = '/subscriptions/' + $SubscriptionId + '/resourceGroups/' + $ComputeGalleryResourceGroupName + '/providers/Microsoft.Compute/disks/' + $DiskName + '?api-version=2026-03-02'
    Invoke-AzRestMethod -Method 'DELETE' -Path $DiskDeletePath | Out-Null
}