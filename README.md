# BIOS & OS Compliance Dashboard — Sample

A PowerShell 7 snippet demonstrating how to pull device inventory from Microsoft Intune via Graph API, compare BIOS firmware versions against a reference catalog, and produce a structured compliance report. Includes a sample KQL query for Azure Monitor Workbooks.

## What it shows
- Certificate-based authentication against Microsoft Graph
- Fetching managed device inventory from Intune with field projection
- Comparing current BIOS version against a versioned reference catalog
- Emitting a per-device compliance result with summary statistics
- KQL query pattern for joining device data and catalog data in Log Analytics

## Part of a larger solution
This snippet is extracted from an end-to-end **firmware compliance platform** that runs vendor catalog fetch runbooks on a schedule, ingests device-side detection results via Intune Proactive Remediations and Data Collection Rules (DCR), and visualises fleet-wide compliance in a 4-tab Azure Monitor Workbook.

## Stack
`PowerShell 7` · `Azure Automation` · `Microsoft Graph API` · `Microsoft Intune` · `Log Analytics / KQL` · `Azure Monitor Workbooks` · `Data Collection Rules (DCR)` · `Azure Table Storage`
