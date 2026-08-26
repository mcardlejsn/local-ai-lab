#requires -Version 5.1

<#
.SYNOPSIS
Checks a maintained list of Hugging Face GGUF repositories for Local AI Lab.

.DESCRIPTION
The script invokes check_model_candidate.ps1 once for each repository. It does
not duplicate that checker's screening rules, download model weights, edit the
app, or mark any model as device-verified.

Blank lines and lines beginning with # are ignored. Each run writes a compact
CSV and JSON summary, complete individual reports, and all passing CatalogModel
records beneath the Flutter build directory.

.EXAMPLE
.\tools\check_model_candidates_batch.ps1

.EXAMPLE
.\tools\check_model_candidates_batch.ps1 `
  -RepositoryList .\tools\another_candidate_list.txt
#>

[CmdletBinding()]
param(
  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [string]$RepositoryList,

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryList)) {
  $RepositoryList = Join-Path `
    $PSScriptRoot `
    'model_candidate_repositories.txt'
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $projectRoot = Split-Path -Parent $PSScriptRoot
  $OutputRoot = Join-Path $projectRoot 'build\model_candidate_checks'
}

function Stop-BatchCheck {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Write-Error $Message -ErrorAction Continue
  exit 3
}

function Get-ReportValue {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Report,

    [Parameter(Mandatory = $true)]
    [string]$Label
  )

  $pattern = '(?m)^' + [regex]::Escape($Label) + '\s*:\s*(.*?)\s*$'
  $match = [regex]::Match($Report, $pattern)
  if (-not $match.Success) {
    return ''
  }

  return $match.Groups[1].Value.Trim()
}

function Get-ReportReasons {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Report,

    [Parameter(Mandatory = $true)]
    [string]$Heading
  )

  $sectionPattern = (
    '(?ms)^' +
    [regex]::Escape($Heading) +
    ':\s*\r?\n(?<Body>.*?)(?:\r?\n\r?\n|\z)'
  )
  $sectionMatch = [regex]::Match($Report, $sectionPattern)
  if (-not $sectionMatch.Success) {
    return @()
  }

  return @([regex]::Matches(
      $sectionMatch.Groups['Body'].Value,
      '(?m)^\s*-\s+(?<Reason>.*?)\s*$'
    ) | ForEach-Object {
      $_.Groups['Reason'].Value
    })
}

function ConvertTo-SafeReportName {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Repository
  )

  return ($Repository -replace '[^A-Za-z0-9._-]+', '__').Trim([char[]]'_')
}

function Convert-StreamItemToText {
  param(
    [Parameter(Mandatory = $true)]
    [object]$InputObject
  )

  if ($InputObject -is [System.Management.Automation.ErrorRecord]) {
    return (($InputObject | Out-String -Width 4096).TrimEnd())
  }

  return ([string]$InputObject).TrimEnd()
}

trap {
  Stop-BatchCheck -Message (
    'Batch candidate check failed: {0}' -f $_.Exception.Message
  )
}

$checkerPath = Join-Path $PSScriptRoot 'check_model_candidate.ps1'
if (-not (Test-Path -LiteralPath $checkerPath -PathType Leaf)) {
  Stop-BatchCheck -Message (
    'The single-model checker was not found: {0}' -f $checkerPath
  )
}

if (-not (Test-Path -LiteralPath $RepositoryList -PathType Leaf)) {
  Stop-BatchCheck -Message (
    'The repository list was not found: {0}' -f $RepositoryList
  )
}

$resolvedCheckerPath = (Resolve-Path -LiteralPath $checkerPath).Path
$resolvedRepositoryList = (Resolve-Path -LiteralPath $RepositoryList).Path

$repositories = @(Get-Content -LiteralPath $resolvedRepositoryList | ForEach-Object {
    $line = $_.Trim()
    if ($line.Length -gt 0 -and -not $line.StartsWith('#')) {
      $line
    }
  })

if ($repositories.Count -eq 0) {
  Stop-BatchCheck -Message (
    'The repository list contains no repository IDs: {0}' -f `
      $resolvedRepositoryList
  )
}

$runTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDirectory = Join-Path $OutputRoot $runTimestamp
$suffix = 2
while (Test-Path -LiteralPath $runDirectory) {
  $runDirectory = Join-Path $OutputRoot ("{0}-{1}" -f $runTimestamp, $suffix)
  $suffix++
}

$reportsDirectory = Join-Path $runDirectory 'reports'
New-Item -ItemType Directory -Path $reportsDirectory -Force | Out-Null

$results = New-Object 'Collections.Generic.List[object]'
$catalogRecords = New-Object 'Collections.Generic.List[string]'

for ($index = 0; $index -lt $repositories.Count; $index++) {
  $repository = $repositories[$index]
  $number = $index + 1

  Write-Progress `
    -Activity 'Checking GGUF candidate repositories' `
    -Status ("{0}/{1}: {2}" -f $number, $repositories.Count, $repository) `
    -PercentComplete (($number / $repositories.Count) * 100)

  $reportBuilder = New-Object Text.StringBuilder
  $invocationError = ''
  $exitCode = 3

  try {
    & $resolvedCheckerPath $repository *>&1 | ForEach-Object {
      $streamText = Convert-StreamItemToText -InputObject $_
      [void]$reportBuilder.AppendLine($streamText)
    }
    $exitCode = $LASTEXITCODE
  } catch {
    $invocationError = $_.Exception.Message
    $errorText = (($_ | Out-String -Width 4096).TrimEnd())
    if ($errorText.Length -gt 0 -and
        -not $reportBuilder.ToString().Contains($errorText)) {
      [void]$reportBuilder.AppendLine($errorText)
    }
  }

  $report = $reportBuilder.ToString().TrimEnd()
  $result = if ($invocationError.Length -gt 0) {
    'ERROR'
  } else {
    switch ($exitCode) {
      0 { 'PASS'; break }
      1 { 'REVIEW'; break }
      2 { 'FAIL'; break }
      default { 'ERROR' }
    }
  }

  $catalogRecord = ''
  if ($result -eq 'PASS') {
    $catalogMatch = [regex]::Match(
      $report,
      '(?ms)^CatalogModel\(\r?\n.*?^\),\s*$'
    )
    if ($catalogMatch.Success) {
      $catalogRecord = $catalogMatch.Value.TrimEnd()
      $catalogRecords.Add($catalogRecord)
    } else {
      $result = 'ERROR'
      $invocationError = (
        'The checker returned PASS but no CatalogModel record could be extracted.'
      )
    }
  }

  $selectedFile = Get-ReportValue -Report $report -Label 'Selected file'
  if ($selectedFile -eq 'None') {
    $selectedFile = ''
  }

  $sizeBytes = $null
  $sizeText = Get-ReportValue -Report $report -Label 'Size'
  if ($sizeText -match '^([0-9]+) bytes$') {
    $sizeBytes = [int64]$Matches[1]
  }

  $promptFormat = Get-ReportValue -Report $report -Label 'Prompt format'
  $failureReasons = @(Get-ReportReasons `
      -Report $report `
      -Heading 'Failure reasons')
  $reviewReasons = @(Get-ReportReasons `
      -Report $report `
      -Heading 'Review reasons')

  $safeRepositoryName = ConvertTo-SafeReportName -Repository $repository
  $reportFileName = ('{0:D3}_{1}.txt' -f $number, $safeRepositoryName)
  $reportPath = Join-Path $reportsDirectory $reportFileName
  $report | Set-Content -LiteralPath $reportPath -Encoding UTF8

  $results.Add([pscustomobject][ordered]@{
      Order = $number
      Repository = $repository
      Result = $result
      ExitCode = $exitCode
      SelectedFile = $selectedFile
      SizeBytes = $sizeBytes
      PromptFormat = $promptFormat
      FailureReasons = $failureReasons
      ReviewReasons = $reviewReasons
      ErrorMessage = $invocationError
      ReportFile = ('reports/{0}' -f $reportFileName)
    })
}

Write-Progress -Activity 'Checking GGUF candidate repositories' -Completed

$totals = [ordered]@{
  PASS = @($results | Where-Object { $_.Result -eq 'PASS' }).Count
  REVIEW = @($results | Where-Object { $_.Result -eq 'REVIEW' }).Count
  FAIL = @($results | Where-Object { $_.Result -eq 'FAIL' }).Count
  ERROR = @($results | Where-Object { $_.Result -eq 'ERROR' }).Count
}

$csvRows = @($results | ForEach-Object {
    [pscustomobject][ordered]@{
      Order = $_.Order
      Repository = $_.Repository
      Result = $_.Result
      ExitCode = $_.ExitCode
      SelectedFile = $_.SelectedFile
      SizeBytes = $_.SizeBytes
      PromptFormat = $_.PromptFormat
      FailureReasons = ($_.FailureReasons -join ' | ')
      ReviewReasons = ($_.ReviewReasons -join ' | ')
      ErrorMessage = $_.ErrorMessage
      ReportFile = $_.ReportFile
    }
  })

$csvPath = Join-Path $runDirectory 'summary.csv'
$csvRows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

$jsonCandidates = @($results | ForEach-Object {
    [ordered]@{
      order = $_.Order
      repository = $_.Repository
      result = $_.Result
      exitCode = $_.ExitCode
      selectedFile = $_.SelectedFile
      sizeBytes = $_.SizeBytes
      promptFormat = $_.PromptFormat
      failureReasons = @($_.FailureReasons)
      reviewReasons = @($_.ReviewReasons)
      errorMessage = $_.ErrorMessage
      reportFile = $_.ReportFile
    }
  })

$jsonSummary = [ordered]@{
  generatedAtUtc = [DateTime]::UtcNow.ToString('o')
  repositoryList = $resolvedRepositoryList
  checker = $resolvedCheckerPath
  totals = $totals
  candidates = $jsonCandidates
}

$jsonPath = Join-Path $runDirectory 'summary.json'
$jsonSummary |
  ConvertTo-Json -Depth 6 |
  Set-Content -LiteralPath $jsonPath -Encoding UTF8

$catalogPath = Join-Path $runDirectory 'passing_catalog_models.txt'
$catalogOutput = New-Object 'Collections.Generic.List[string]'
$catalogOutput.Add(
  '// Candidate CatalogModel records produced by the batch mechanical screen.'
)
$catalogOutput.Add(
  '// Do not add a record until its exact pinned artifact passes the phone benchmark.'
)
$catalogOutput.Add('')

if ($catalogRecords.Count -eq 0) {
  $catalogOutput.Add('// No repositories returned PASS in this run.')
} else {
  for ($index = 0; $index -lt $catalogRecords.Count; $index++) {
    if ($index -gt 0) {
      $catalogOutput.Add('')
    }
    $catalogOutput.Add($catalogRecords[$index])
  }
}

$catalogOutput | Set-Content -LiteralPath $catalogPath -Encoding UTF8

Write-Output ''
Write-Output 'Local AI Lab GGUF candidate batch summary'
Write-Output '-----------------------------------------'
$results |
  Select-Object `
    @{ Name = '#'; Expression = { $_.Order } }, `
    Repository, `
    Result, `
    @{ Name = 'Size MiB'; Expression = {
        if ($null -eq $_.SizeBytes) {
          ''
        } else {
          [Math]::Round($_.SizeBytes / 1MB, 1)
        }
      } }, `
    PromptFormat |
  Format-Table -AutoSize |
  Out-Host

Write-Output (
  'Totals: PASS {0} | REVIEW {1} | FAIL {2} | ERROR {3}' -f `
    $totals.PASS,
    $totals.REVIEW,
    $totals.FAIL,
    $totals.ERROR
)
Write-Output ("Results: {0}" -f (Resolve-Path -LiteralPath $runDirectory).Path)

exit 0
