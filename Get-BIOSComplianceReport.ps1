#Requires -Version 7.0
<#
.SYNOPSIS
    Sample: BIOS Firmware Compliance Report
.DESCRIPTION
    Demonstrates how to pull managed device inventory from Microsoft Intune via
    Graph API, compare each device's reported BIOS version against a reference
    catalog version, and emit a structured compliance summary.

    NOTE: Illustrative snippet. Production solution includes:
    - A separate catalog runbook that fetches current firmware versions from the
      vendor's public XML catalog and stores them in Log Analytics
    - Data Collection Rules (DCR) for ingesting device-side detection results
    - A multi-tab Azure Monitor Workbook that joins all three tables with KQL
    - Full vendor model-to-machine-type-model mapping
    All secrets are Automation Account encrypted variables.

.REQUIREMENTS
    - App registration with DeviceManagementManagedDevices.Read.All Graph permission
    - Reference BIOS catalog loaded as an Automation Account variable (JSON)
    - PowerShell 7.2 on Azure Automation
#>

param (
    [string]$ManufacturerFilter = 'Lenovo'
)

# ── Authentication ─────────────────────────────────────────────────────────────
$tenantId  = Get-AutomationVariable -Name 'TenantId'
$clientId  = Get-AutomationVariable -Name 'AppClientId'
$certThumb = Get-AutomationVariable -Name 'GraphCertThumbprint'

$cert      = Get-Item "Cert:\LocalMachine\My\$certThumb"
$tokenBody = @{
    grant_type            = 'client_credentials'
    client_id             = $clientId
    client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
    client_assertion      = (New-GraphJwtAssertion -Certificate $cert -ClientId $clientId -TenantId $tenantId)
    scope                 = 'https://graph.microsoft.com/.default'
}
$token       = (Invoke-RestMethod "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Method Post -Body $tokenBody).access_token
$authHeaders = @{ Authorization = "Bearer $token" }

# ── Load reference catalog (stored as JSON Automation variable) ────────────────
# Schema: [{ "modelFamily": "ThinkPad X1 Carbon Gen 11", "latestBiosVersion": "N3HET82W" }, ...]
$catalogJson   = Get-AutomationVariable -Name 'BiosCatalogJson'
$biosCatalog   = $catalogJson | ConvertFrom-Json
$catalogLookup = @{}
foreach ($entry in $biosCatalog) { $catalogLookup[$entry.modelFamily] = $entry.latestBiosVersion }

# ── Fetch managed devices from Intune ─────────────────────────────────────────
$selectFields = 'id,deviceName,manufacturer,model,biosVersion,operatingSystem,complianceState'
$deviceUrl    = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=manufacturer eq '$ManufacturerFilter'&`$select=$selectFields"

$devices = @()
do {
    $response  = Invoke-RestMethod $deviceUrl -Headers $authHeaders
    $devices  += $response.value
    $deviceUrl  = $response.'@odata.nextLink'
} while ($deviceUrl)

Write-Output "Fetched $($devices.Count) $ManufacturerFilter devices from Intune"

# ── Evaluate compliance ────────────────────────────────────────────────────────
$compliant    = @()
$nonCompliant = @()

foreach ($device in $devices) {
    $latestVersion = $catalogLookup[$device.model]

    if (-not $latestVersion) {
        # Model not in catalog — skip or flag for manual review
        continue
    }

    $deviceResult = [PSCustomObject]@{
        DeviceName      = $device.deviceName
        Model           = $device.model
        CurrentBIOS     = $device.biosVersion
        LatestBIOS      = $latestVersion
        IsCompliant     = ($device.biosVersion -eq $latestVersion)
        IntuneCompliance = $device.complianceState
    }

    if ($deviceResult.IsCompliant) { $compliant    += $deviceResult }
    else                           { $nonCompliant += $deviceResult }
}

# ── Summary output ─────────────────────────────────────────────────────────────
$summary = [PSCustomObject]@{
    TotalEvaluated      = $compliant.Count + $nonCompliant.Count
    CompliantCount      = $compliant.Count
    NonCompliantCount   = $nonCompliant.Count
    ComplianceRatePct   = [math]::Round(($compliant.Count / ($compliant.Count + $nonCompliant.Count)) * 100, 1)
    NonCompliantDevices = $nonCompliant
}

Write-Output "Compliance rate: $($summary.ComplianceRatePct)% ($($summary.CompliantCount)/$($summary.TotalEvaluated))"
$summary | ConvertTo-Json -Depth 4 | Write-Output

<#
── Sample KQL to query ingested results in Log Analytics ──────────────────────

LenovoDeviceBIOS_CL
| where TimeGenerated > ago(7d)
| summarize arg_max(TimeGenerated, *) by DeviceName_s
| join kind=leftouter (
    LenovoCatalog_CL | summarize arg_max(TimeGenerated, *) by ModelFamily_s
) on $left.Model_s == $right.ModelFamily_s
| extend IsCompliant = (BiosVersion_s == LatestBiosVersion_s)
| summarize
    Compliant    = countif(IsCompliant),
    NonCompliant = countif(not(IsCompliant)),
    Total        = count()
| extend ComplianceRate = round(100.0 * Compliant / Total, 1)

#>
