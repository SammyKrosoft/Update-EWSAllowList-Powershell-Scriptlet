# Update-EWSAllowList-Powershell-Scriptlet
Script to update the EWS Allow IP List

```PowerShell

# EWS list: 81 App IDs identified in the sources reviewed on September 24, 2026.
# 79 App IDs from the script CSV files plus Office and Power Query from the earlier M365 report.
# Includes applications with an old sign-in date or no reported sign-in date.
# The 20 M365 App IDs come from the earlier conversation, not a new export.
# Run in an Exchange Online PowerShell session that is already connected.
# Without -Apply: read and preview. With -Apply: back up, merge, and apply.
# Applications missing from the reviewed inventories may not be covered.

[CmdletBinding()]
param(
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

$detectedAppIds = @(
    "9e5f94bc-e8a4-4e73-b8be-63364c29d753" # Thunderbird
    "a672d62c-fc7b-4e81-a576-e60dc46e951d" # Microsoft Power Query for Excel
    "a850aaae-d5a5-4e82-877c-ce54ff916282" # Polycom - Skype for Business Certified Phone
    "d3590ed6-52b3-4102-aeff-aad2292ab01c" # Microsoft Office
    "e0ee12cb-2032-40fc-a44f-d6d9f3fad1eb" # Email
    "f8d98a96-0999-43f5-8af3-69971c7bb423" # iOS Accounts
)

# Retrieve the current Exchange Online configuration, including the EWS operation access policy.
$configBefore = Get-OrganizationConfig -RetrieveEwsOperationAccessPolicy -ErrorAction Stop
if ($null -eq $configBefore) {
    throw 'Unable to retrieve the Exchange Online configuration.'
}
if ($null -eq $configBefore.PSObject.Properties['EwsAllowedAppIDs']) {
    throw 'The EwsAllowedAppIDs property is missing. Check the Exchange Online session and permissions.'
}

# Extract the existing EWS App IDs from the current configuration.
$existingAppIds = @(
    ((@($configBefore.EwsAllowedAppIDs) -join ',') -split ',') |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
)

# Validate and normalize GUIDs. An unexpected value stops processing.
# Combine the existing and newly detected App IDs, normalize them as GUIDs, and remove duplicates.
$finalAppIds = @(
    ($existingAppIds + $detectedAppIds) |
        ForEach-Object { ([guid]$_).ToString() } |
        Sort-Object -Unique
)

# Display a summary of the configuration changes and the proposed final list of EWS App IDs.
Write-Host "`nConfiguration summary:" -ForegroundColor Cyan
[pscustomobject]@{
    DetectedAppIdCount = $detectedAppIds.Count
    UniqueExistingAppIdCount = @($existingAppIds | Sort-Object -Unique).Count
    MergedAppIdCount = $finalAppIds.Count
    PreviousEwsEnabled = if ([string]::IsNullOrWhiteSpace([string]$configBefore.EwsEnabled)) {
        '$null'
    }
    else {
        $configBefore.EwsEnabled
    }
} | Format-List | Out-String -Stream | ForEach-Object {
    Write-Host $_ -ForegroundColor Cyan
}

# Display the complete proposed list of EWS App IDs.
Write-Host "`nComplete proposed list:" -ForegroundColor White
# Iterate through the final list and display each EWS App ID individually.
foreach ($appId in $finalAppIds) {
    Write-Host $appId -ForegroundColor Gray
}
# Display the EwsAllowedAppIDs value as a comma-separated string.
Write-Host "`nEwsAllowedAppIDs value:" -ForegroundColor Magenta
# Join the final list of EWS App IDs into a single comma-separated string for display.
Write-Host ($finalAppIds -join ',') -ForegroundColor Magenta

# Preview or apply the configuration changes based on the -Apply switch.
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
    # Notify the user that the backup has been saved successfully.
    Write-Host ("`nBackup saved: " + $backupPath) -ForegroundColor Green
    # Notify the user that the script is now applying the EWS configuration changes.
    Write-Host "`nApplying the EWS configuration..." -ForegroundColor Yellow
    # Apply the EWS configuration changes to the organization.
    Set-OrganizationConfig -EwsEnabled $true -EwsAllowedAppIDs ($finalAppIds -join ',') -ErrorAction Stop
    # Notify the user that the EWS configuration changes have been applied successfully.
    Write-Host "`nSaved configuration (service propagation may be delayed):" -ForegroundColor Green
    # Display the saved EWS configuration for verification.
    Get-OrganizationConfig -RetrieveEwsOperationAccessPolicy -ErrorAction Stop |
        Format-List EwsEnabled, EwsAllowedAppIDs |
        Out-String -Stream | ForEach-Object {
            Write-Host $_ -ForegroundColor Green
        }
}

```

