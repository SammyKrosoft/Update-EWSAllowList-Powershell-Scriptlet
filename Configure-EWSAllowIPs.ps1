# Load EWS App IDs from a plain text file, with one GUID per line.
# By default, use EWS-AppIDs.txt in the same folder as this script.
# The supplied text file contains the 81 previously identified App IDs:
# 79 from the script CSV files, plus Office and Power Query from the earlier M365 report.
# Run in an Exchange Online PowerShell session that is already connected.
# Without -Apply: read and preview. With -Apply: back up, merge, and apply.
# Existing allowed App IDs are preserved. Removing a line does not revoke existing access.
# Applications missing from the reviewed inventories may not be covered.

[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$AppIdsPath = (Join-Path $PSScriptRoot 'EWS-AppIDs.txt'),
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

# Resolve the full path to the App ID text file and ensure it exists.
$appIdFilePath = (Resolve-Path -LiteralPath $AppIdsPath -ErrorAction Stop).ProviderPath
if (-not (Test-Path -LiteralPath $appIdFilePath -PathType Leaf)) {
    throw "The App ID path must point to a text file: $AppIdsPath"
}

# Read one App ID per line. Ignore blank lines and full-line comments starting with #.
# Validate the entire file before querying or modifying Exchange Online.
$appIdLines = @(Get-Content -LiteralPath $appIdFilePath -Encoding UTF8 -ErrorAction Stop)
# Import and validate the App IDs from the text file.
$importedAppIds = @(
    for ($lineIndex = 0; $lineIndex -lt $appIdLines.Count; $lineIndex++) {
        $line = $appIdLines[$lineIndex].Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            continue
        }

        $parsedAppId = [guid]::Empty
        if (-not [guid]::TryParse($line, [ref]$parsedAppId)) {
            throw "Invalid App ID on line $($lineIndex + 1) in '$appIdFilePath': $line. Use one GUID per line."
        }
        $parsedAppId.ToString()
    }
)

# Sort and remove duplicate App IDs. Ensure there is at least one valid App ID.
$importedAppIds = @($importedAppIds | Sort-Object -Unique)
# Ensure that there is at least one valid App ID after importing and deduplicating.
if ($importedAppIds.Count -eq 0) {
    throw "The App ID file contains no App IDs: $appIdFilePath"
}

# Retrieve the current Exchange Online configuration for EWS allowed App IDs.
$configBefore = Get-OrganizationConfig -RetrieveEwsOperationAccessPolicy -ErrorAction Stop
# Ensure that the configuration was retrieved successfully.
if ($null -eq $configBefore) {
    throw 'Unable to retrieve the Exchange Online configuration.'
}
# Ensure that the EwsAllowedAppIDs property exists in the retrieved configuration.
if ($null -eq $configBefore.PSObject.Properties['EwsAllowedAppIDs']) {
    throw 'The EwsAllowedAppIDs property is missing. Check the Exchange Online session and permissions.'
}

# Extract the existing EWS allowed App IDs from the current configuration.
$existingAppIds = @(
    ((@($configBefore.EwsAllowedAppIDs) -join ',') -split ',') |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
)

# Validate and normalize GUIDs. An unexpected value stops processing.
$finalAppIds = @(
    ($existingAppIds + $importedAppIds) |
        ForEach-Object { ([guid]$_).ToString() } |
        Sort-Object -Unique
)

# Display a summary of the configuration before applying any changes.
Write-Host "`nConfiguration summary:" -ForegroundColor Cyan
# Create a custom object to summarize the current and proposed EWS App ID configuration.
[pscustomobject]@{
    AppIdFilePath = $appIdFilePath
    ImportedAppIdCount = $importedAppIds.Count
    UniqueExistingAppIdCount = @($existingAppIds | Sort-Object -Unique).Count
    MergedAppIdCount = $finalAppIds.Count
    PreviousEwsEnabled = if ([string]::IsNullOrWhiteSpace([string]$configBefore.EwsEnabled)) {
        '$null'
    }
    else {
        $configBefore.EwsEnabled
    }
    # Display the final merged list of EWS allowed App IDs.
} | Format-List | Out-String -Stream | ForEach-Object {
    Write-Host $_ -ForegroundColor Cyan
}

# Display the complete proposed list of EWS allowed App IDs.
Write-Host "`nComplete proposed list:" -ForegroundColor White
foreach ($appId in $finalAppIds) {
    Write-Host $appId -ForegroundColor Gray
}
# Display the EwsAllowedAppIDs value as a comma-separated string.
Write-Host "`nEwsAllowedAppIDs value:" -ForegroundColor Magenta
# Join the final App IDs into a single comma-separated string for display.
Write-Host ($finalAppIds -join ',') -ForegroundColor Magenta

# Indicate whether the script is running in preview mode or applying changes.
if (-not $Apply) {
    Write-Host "`nPREVIEW ONLY: No changes made. To apply the configuration, run this script again with -Apply." -ForegroundColor Yellow
}
else {
    # Back up both properties as JSON before making any changes.
    $backupPath = Join-Path $PSScriptRoot ('EWS-config-before-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.json')
    [pscustomobject]@{
        CapturedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        EwsEnabled = $configBefore.EwsEnabled
        EwsAllowedAppIDs = $configBefore.EwsAllowedAppIDs
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $backupPath -Encoding UTF8 -ErrorAction Stop
    Write-Host ("`nBackup saved: " + $backupPath) -ForegroundColor Green

    # Apply the new EWS configuration to Exchange Online.
    Write-Host "`nApplying the EWS configuration..." -ForegroundColor Yellow
    # Execute the command to update the EWS allowed App IDs with the final merged list.
    Set-OrganizationConfig -EwsEnabled $true -EwsAllowedAppIDs ($finalAppIds -join ',') -ErrorAction Stop
    # Display a message indicating that the configuration has been saved.
    Write-Host "`nSaved configuration (service propagation may be delayed):" -ForegroundColor Green
    # Retrieve and display the updated EWS configuration to confirm the changes.
    Get-OrganizationConfig -RetrieveEwsOperationAccessPolicy -ErrorAction Stop |
        Format-List EwsEnabled, EwsAllowedAppIDs |
        Out-String -Stream | ForEach-Object {
            Write-Host $_ -ForegroundColor Green
        }
}
