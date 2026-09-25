# Exchange Online EWS Allowed App IDs Configuration Script

This PowerShell script safely previews or updates the tenant-level `EwsAllowedAppIDs` configuration in Exchange Online from a plain-text list of Microsoft Entra application (client) IDs.

It is designed for administrators preparing an Exchange Online tenant for continued, controlled EWS access. The script uses a **read, merge, and write** approach so that application IDs already configured in the tenant are preserved when new IDs are added.

> \[!IMPORTANT]
> Review and validate every application ID before applying the configuration. The supplied inventory may not include applications that were absent from the reviewed reports, scripts, or reporting periods.

## What the script does

The script:

1. Reads application IDs from a UTF-8 text file containing one GUID per line.
2. Ignores blank lines and full-line comments beginning with `#`.
3. Validates the complete file before querying or modifying Exchange Online.
4. Normalises, sorts, and removes duplicate application IDs.
5. Retrieves the current `EwsEnabled` and `EwsAllowedAppIDs` configuration.
6. Merges imported IDs with the existing tenant allow list.
7. Preserves every valid application ID that is already configured.
8. Displays the proposed merged list and comma-separated value.
9. Runs in preview mode unless the `-Apply` switch is specified.
10. When applying changes, exports the previous EWS configuration to a timestamped JSON backup.
11. Sets `EwsEnabled` to `$true` and writes the complete merged allow list.
12. Retrieves the configuration again so the saved values can be reviewed.

## Safety behaviour

### Preview by default

Running the script without `-Apply` does not change the tenant. It only validates the input, reads the current configuration, and displays the proposed result.

### Existing IDs are preserved

The final value is the union of:

* application IDs already present in `EwsAllowedAppIDs`; and
* application IDs imported from the text file.

Removing an ID from the text file **does not remove it from the tenant configuration** if it is already configured. This script is additive and is not a revocation tool.

### Input is validated before changes

Processing stops if:

* the App ID file cannot be resolved;
* the path does not identify a file;
* a non-comment line is not a valid GUID;
* the file contains no valid application IDs;
* the Exchange Online configuration cannot be retrieved; or
* the `EwsAllowedAppIDs` property is unavailable.

### Backup before modification

When `-Apply` is used, the script creates a JSON file in the script directory before calling `Set-OrganizationConfig`.

Example backup name:

```text
EWS-config-before-20260924-202756-077.json
```

The backup contains:

* the UTC capture time;
* the previous `EwsEnabled` value; and
* the previous `EwsAllowedAppIDs` value.

> \[!NOTE]
> Exchange Online configuration changes may not take effect immediately. Allow for service-side propagation before validating application access.

## Prerequisites

* PowerShell 7 or Windows PowerShell 5.1.
* The Exchange Online PowerShell module.
* An active Exchange Online PowerShell session established before running the script.
* Sufficient Exchange Online permissions to run:

  * `Get-OrganizationConfig -RetrieveEwsOperationAccessPolicy`
  * `Set-OrganizationConfig`
* A reviewed App ID inventory containing Microsoft Entra application **client IDs**, one GUID per line.

Connect to Exchange Online first, for example:

```powershell
Connect-ExchangeOnline
```

## Files

A typical folder layout is:

```text
.
├── Set-EWSAllowedAppIDs.ps1
└── EWS-AppIDs.txt
```

By default, the script looks for `EWS-AppIDs.txt` in the same folder as the script.

## Parameters

|Parameter|Type|Required|Description|
|-|-|-:|-|
|`-AppIdsPath`|`String`|No|Path to the plain-text App ID file. Defaults to `EWS-AppIDs.txt` in the script directory.|
|`-Apply`|`Switch`|No|Creates a backup and applies the merged configuration. Without this switch, the script runs in preview mode.|

## App ID file format

Use one GUID per line. Blank lines and lines whose first non-whitespace character is `#` are ignored.

The following shortened example uses six recognisable applications from the reviewed inventory. The comments are optional and must be on separate lines because inline comments are not supported.

```text
# Microsoft Office / Outlook
d3590ed6-52b3-4102-aeff-aad2292ab01c

# Apple / Apple Mail
f8d98a96-0999-43f5-8af3-69971c7bb423

# Spark Mail
b50c1dbd-1855-4e54-b07c-d3c3029e93d3

# Fantastical
395befa1-fd95-454c-8286-2948ada76320

# Mozilla Thunderbird
9e5f94bc-e8a4-4e73-b8be-63364c29d753

# Zoom Calendar / Contacts integration
fc108d3f-543d-4374-bbff-c7c51f651fe5
```

> \[!WARNING]
> The sample is illustrative only. Do not treat it as a universal or complete EWS allow list. Build the production file from applications confirmed to require EWS in your tenant.

## Usage examples

### 1\. Preview using the default App ID file

If `EWS-AppIDs.txt` is in the same directory as the script:

```powershell
.\\Set-EWSAllowedAppIDs.ps1
```

The script displays:

* the resolved App ID file path;
* the number of imported unique IDs;
* the number of existing unique IDs;
* the size of the merged list;
* the previous `EwsEnabled` value;
* the complete proposed list; and
* the comma-separated value that would be submitted.

No Exchange Online configuration is changed.

### 2\. Preview using a different App ID file

```powershell
.\\Set-EWSAllowedAppIDs.ps1 -AppIdsPath 'C:\\ChangeData\\Reviewed-EWS-AppIDs.txt'
```

This is useful when the reviewed inventory is stored outside the script directory.

### 3\. Apply using the default App ID file

```powershell
.\\Set-EWSAllowedAppIDs.ps1 -Apply
```

The script:

1. validates the input;
2. retrieves and merges the current allow list;
3. creates the timestamped JSON backup;
4. sets `EwsEnabled` to `$true`;
5. writes the complete merged `EwsAllowedAppIDs` value; and
6. retrieves and displays the saved configuration.

### 4\. Apply using a specific App ID file

```powershell
.\\Set-EWSAllowedAppIDs.ps1 `
    -AppIdsPath 'C:\\ChangeData\\Approved-EWS-AppIDs.txt' `
    -Apply
```

## Example preview summary

Values will vary by tenant and input file.

```text
Configuration summary:

AppIdFilePath           : C:\\Scripts\\EWS-AppIDs.txt
ImportedAppIdCount      : 81
UniqueExistingAppIdCount: 4
MergedAppIdCount        : 83
PreviousEwsEnabled      : True

PREVIEW ONLY: No changes made. To apply the configuration, run this script again with -Apply.
```

The merged count can be smaller than the sum of imported and existing counts because duplicate IDs are removed.

## Important operational considerations

* **Use client IDs:** `EwsAllowedAppIDs` expects the application/client ID of the application calling EWS.
* **Treat the inventory as tenant-specific:** Include only applications that have been reviewed and approved for continued EWS access.
* **Preserve the complete list:** Updating `EwsAllowedAppIDs` writes the supplied list as the configuration value. This script protects existing entries by merging them before writing.
* **Removing access requires a separate process:** Deleting an entry from `EWS-AppIDs.txt` is not sufficient because existing tenant entries are preserved.
* **Keep the backup:** Store the JSON backup with the associated change record so the previous state remains available.
* **Test after propagation:** Do not interpret an immediate test result as proof that the new allow list has fully propagated.
* **Review other EWS controls separately:** `EwsAllowedAppIDs` is based on Microsoft Entra application IDs. It is distinct from older user-agent-based settings such as `EwsApplicationAccessPolicy`, `EWSAllowList`, and `EWSBlockList`.

## Limitations

* The script does not discover EWS applications.
* It does not verify whether an imported application currently calls EWS.
* It does not map application IDs to application names.
* It does not remove or revoke existing allowed application IDs.
* It does not test application authentication, consent, permissions, or mailbox access.
* It does not guarantee that the source inventory is complete.
* It enables EWS at the organisation level when `-Apply` is used.

## Recommended change workflow

1. Inventory EWS-dependent applications using the reporting and discovery sources approved for your environment.
2. Review application ownership, business need, and application/client IDs.
3. Prepare `EWS-AppIDs.txt` with one approved GUID per line.
4. Connect to Exchange Online PowerShell.
5. Run the script without `-Apply`.
6. Save or review the preview output as part of the change record.
7. Confirm that existing App IDs are present in the merged result.
8. Run the script with `-Apply` during the approved change window.
9. Retain the JSON backup.
10. After service propagation, validate each required EWS-dependent application.

## Microsoft documentation

* [Deprecation of Exchange Web Services in Exchange Online](https://techcommunity.microsoft.com/blog/exchange/introducing-ewsallowedappids-preparing-for-the-final-phase-of-ews-retirement/4529471)

especially the following paragraph:
>**Build an AppID allow list**
>Create an EWSAllowedAppIDs allow list containing only applications that are known to still require EWS. This includes Microsoft first-party client apps such as Office, Power Query for Excel etc. If >the app shows up in your usage report, and you want to keep using it, you need to add it to the list.  

## Disclaimer

Test the script and the resulting configuration in a suitable non-production environment wherever possible. The administrator running the script is responsible for validating the application inventory, approving the change, and confirming application functionality after the configuration has propagated.

