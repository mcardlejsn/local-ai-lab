#requires -Version 5.1

<#
.SYNOPSIS
Checks whether a public Hugging Face GGUF repository is a suitable candidate
for the Local AI Lab downloadable-model catalog.

.DESCRIPTION
The script reads repository and file metadata only. It does not download model
weights, edit the app, or mark a model as device-verified.

A PASS means the repository mechanically satisfies the initial catalog rules.
The exact artifact must still be downloaded through Local AI Lab and tested on
the target phone before its generated CatalogModel record is added to the app.

.EXAMPLE
.\tools\check_model_candidate.ps1 "Qwen/Qwen2.5-1.5B-Instruct-GGUF"
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateNotNullOrEmpty()]
  [string]$Repository
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$maximumSizeBytes = [int64]3000000000
$failReasons = @()
$reviewReasons = @()

function Get-PropertyValue {
  param(
    [Parameter(Mandatory = $true)]
    [object]$InputObject,

    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  if ($null -eq $InputObject) {
    return $null
  }

  $property = $InputObject.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }

  return $property.Value
}

function ConvertTo-EncodedPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  return (($Path -split '/') | ForEach-Object {
      [Uri]::EscapeDataString($_)
    }) -join '/'
}

function ConvertTo-DartSingleQuotedString {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  return $Value.Replace('\', '\\').Replace("'", "\'")
}

function Resolve-LocalPromptFormat {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FileName
  )

  # Keep these checks synchronized with resolvePromptFormat in
  # lib/services/model_manager_service.dart.
  $name = $FileName.ToLowerInvariant()

  if ($name.Contains('smollm3')) {
    return 'smollm3'
  }
  if ($name.Contains('smollm2')) {
    return 'smollm2'
  }
  if ($name.Contains('chatml') -or $name.Contains('hermes')) {
    return 'chatml'
  }
  $isQwen35 = $name.Contains('qwen3.5') -or
    $name.Contains('qwen-3.5') -or
    $name.Contains('qwen_3.5')
  if (-not $isQwen35 -and
      ($name.Contains('qwen3') -or
       $name.Contains('qwen-3') -or
       $name.Contains('qwen_3'))) {
    return 'qwen3'
  }
  if ($name.Contains('gemma')) {
    return 'gemma'
  }
  if ($name.Contains('llama-3') -or
      $name.Contains('llama3') -or
      $name.Contains('llama_3')) {
    return 'llama3'
  }
  if ($name.Contains('mistral') -or $name.Contains('mixtral')) {
    return 'mistral'
  }
  if ($name.Contains('qwen')) {
    return 'chatml'
  }

  return 'plain'
}

$trimmedRepository = $Repository.Trim().Trim('/')
$repositoryParts = @($trimmedRepository -split '/')
if ($repositoryParts.Count -ne 2 -or
    [string]::IsNullOrWhiteSpace($repositoryParts[0]) -or
    [string]::IsNullOrWhiteSpace($repositoryParts[1])) {
  Write-Error 'Repository must use the Hugging Face owner/name form.'
  exit 3
}

$encodedRepository = ConvertTo-EncodedPath -Path $trimmedRepository
$apiUrl = "https://huggingface.co/api/models/${encodedRepository}?blobs=true"

try {
  $metadata = Invoke-RestMethod `
    -Uri $apiUrl `
    -Method Get `
    -Headers @{ 'User-Agent' = 'Local-AI-Lab-Curation-Tool/1.0' } `
    -TimeoutSec 30
} catch {
  Write-Error ("Hugging Face metadata request failed: {0}" -f $_.Exception.Message)
  exit 3
}

$repositoryIdValue = Get-PropertyValue -InputObject $metadata -Name 'id'
$repositoryId = if ([string]::IsNullOrWhiteSpace([string]$repositoryIdValue)) {
  $trimmedRepository
} else {
  [string]$repositoryIdValue
}

$commitValue = Get-PropertyValue -InputObject $metadata -Name 'sha'
$commit = if ($null -eq $commitValue) { '' } else { [string]$commitValue }
if ($commit -notmatch '^[0-9a-fA-F]{40}$') {
  $reviewReasons += 'The repository did not provide a complete 40-character commit hash.'
}

$privateValue = Get-PropertyValue -InputObject $metadata -Name 'private'
$isPrivate = $false
if ($null -eq $privateValue) {
  $reviewReasons += 'The repository did not report whether it is private.'
} elseif ($privateValue -is [bool]) {
  $isPrivate = [bool]$privateValue
} else {
  $isPrivate = ([string]$privateValue -ine 'false')
}
if ($isPrivate) {
  $failReasons += 'The repository is private.'
}

$gatedValue = Get-PropertyValue -InputObject $metadata -Name 'gated'
$isGated = $false
if ($null -eq $gatedValue) {
  $reviewReasons += 'The repository did not report its gated status.'
} elseif ($gatedValue -is [bool]) {
  $isGated = [bool]$gatedValue
} else {
  $isGated = ([string]$gatedValue -ine 'false')
}
if ($isGated) {
  $failReasons += ("The repository is gated ({0})." -f $gatedValue)
}

$tagsValue = Get-PropertyValue -InputObject $metadata -Name 'tags'
$metadataTags = if ($null -eq $tagsValue) {
  @()
} else {
  @($tagsValue | ForEach-Object { [string]$_ })
}
$hasConversationalTag = $metadataTags -icontains 'conversational'

$cardData = Get-PropertyValue -InputObject $metadata -Name 'cardData'
$licenseValue = if ($null -eq $cardData) {
  $null
} else {
  Get-PropertyValue -InputObject $cardData -Name 'license'
}
$license = if ($null -eq $licenseValue) {
  'Unknown'
} else {
  ([string]$licenseValue).Trim()
}

$catalogLicense = $license
switch ($license.ToLowerInvariant()) {
  'apache-2.0' {
    $catalogLicense = 'Apache-2.0'
    break
  }
  'mit' {
    $catalogLicense = 'MIT'
    break
  }
  'unknown' {
    $reviewReasons += 'The model card does not declare a license.'
    break
  }
  default {
    $reviewReasons += ("License '{0}' requires human review." -f $license)
  }
}

$siblingsValue = Get-PropertyValue -InputObject $metadata -Name 'siblings'
$siblings = @()
if ($null -ne $siblingsValue) {
  $siblings = @($siblingsValue)
}

$q4Files = @($siblings | Where-Object {
    $candidateName = Get-PropertyValue -InputObject $_ -Name 'rfilename'
    ($null -ne $candidateName) -and ([string]$candidateName -match '(?i)q4_k_m.*\.gguf$')
  })

$unshardedQ4Files = @($q4Files | Where-Object {
    $candidateName = [string](Get-PropertyValue -InputObject $_ -Name 'rfilename')
    $candidateName -notmatch '(?i)-\d{5}-of-\d{5}\.gguf$'
  })

if ($q4Files.Count -eq 0) {
  $failReasons += 'No Q4_K_M GGUF file was found.'
} elseif ($unshardedQ4Files.Count -eq 0) {
  $failReasons += 'Q4_K_M exists only as a split/sharded artifact.'
} elseif ($unshardedQ4Files.Count -gt 1) {
  $reviewReasons += ("More than one unsharded Q4_K_M file was found ({0}); choose the intended artifact manually." -f $unshardedQ4Files.Count)
}

$selectedFile = if ($unshardedQ4Files.Count -eq 1) {
  $unshardedQ4Files[0]
} else {
  $null
}

$fileName = ''
$fileSize = $null
$sha256 = ''
$promptFormat = 'not determined'

if ($null -ne $selectedFile) {
  $fileName = [string](Get-PropertyValue -InputObject $selectedFile -Name 'rfilename')

  $lfs = Get-PropertyValue -InputObject $selectedFile -Name 'lfs'
  $sizeValue = Get-PropertyValue -InputObject $selectedFile -Name 'size'
  if ($null -eq $sizeValue -and $null -ne $lfs) {
    $sizeValue = Get-PropertyValue -InputObject $lfs -Name 'size'
  }
  if ($null -ne $sizeValue) {
    try {
      $fileSize = [int64]$sizeValue
    } catch {
      $fileSize = $null
    }
  }

  if ($null -eq $fileSize -or $fileSize -le 0) {
    $reviewReasons += 'The selected file does not provide a valid exact size.'
  } elseif ($fileSize -gt $maximumSizeBytes) {
    $failReasons += ("The selected file is larger than the 3 GB initial limit ({0} bytes)." -f $fileSize)
  }

  $shaValue = if ($null -eq $lfs) {
    $null
  } else {
    Get-PropertyValue -InputObject $lfs -Name 'sha256'
  }
  if ($null -ne $shaValue) {
    $sha256 = ([string]$shaValue).ToLowerInvariant()
  }
  if ($sha256 -notmatch '^[0-9a-f]{64}$') {
    $reviewReasons += 'The selected file does not provide a valid LFS SHA256.'
  }

  $promptFormat = Resolve-LocalPromptFormat -FileName $fileName
  if ($promptFormat -eq 'plain') {
    $reviewReasons += 'The filename is not recognized by Local AI Lab''s prompt-format resolver.'
  }
}

$identityText = ("{0} {1}" -f $repositoryId, $fileName)

# Qwen3.5 2B uses Gated DeltaNet layers. llama.cpp added the required
# GATED_DELTA_NET operation in b8233, while Local AI Lab currently bundles
# b8201 through llama_flutter_android 0.2.6.
if ($identityText -match '(?i)qwen3\.5[-_]?2b') {
  $failReasons += 'Qwen3.5 2B requires llama.cpp GATED_DELTA_NET support added in b8233; Local AI Lab bundles b8201.'
}

if ($identityText -match '(?i)(?:^|[-_./ ])base(?:$|[-_./ ])') {
  $purpose = 'base'
  $failReasons += 'The repository or artifact is explicitly labeled as a base model.'
} elseif ($identityText -match '(?i)(?:^|[-_./ ])(?:instruct(?:ion|ed)?|chat|it)(?:$|[-_./ ])') {
  $purpose = 'instruction/chat'
} elseif ($hasConversationalTag) {
  $purpose = 'instruction/chat'
} else {
  $purpose = 'unclear'
  $reviewReasons += 'The name does not clearly indicate Instruct, Chat, or IT tuning.'
}

$parameterMatches = [regex]::Matches(
  $identityText,
  '(?i)(?<![0-9.])([0-9]+(?:\.[0-9]+)?)b(?![a-z])'
)
$parameterValues = @($parameterMatches | ForEach-Object {
    [double]::Parse(
      $_.Groups[1].Value,
      [Globalization.CultureInfo]::InvariantCulture
    )
  } | Select-Object -Unique)

$parameterLabel = 'Unknown'
if ($parameterValues.Count -eq 0) {
  $reviewReasons += 'The parameter count could not be determined from the repository or filename.'
} elseif ($parameterValues.Count -gt 1) {
  $parameterLabel = (($parameterValues | ForEach-Object { "{0}B" -f $_ }) -join ', ')
  $reviewReasons += ("More than one parameter count was detected ({0})." -f $parameterLabel)
} else {
  $parameterCount = [double]$parameterValues[0]
  $parameterLabel = ("{0}B" -f $parameterCount.ToString(
      '0.###',
      [Globalization.CultureInfo]::InvariantCulture
    ))
  if ($parameterCount -lt 0.5 -or $parameterCount -gt 4.0) {
    $failReasons += ("The detected parameter count {0} is outside the 0.5B-4B initial range." -f $parameterLabel)
  }
}

$result = if ($failReasons.Count -gt 0) {
  'FAIL'
} elseif ($reviewReasons.Count -gt 0) {
  'REVIEW'
} else {
  'PASS'
}

$accessLabel = if ($isGated -or $isPrivate) {
  'Restricted'
} elseif ($null -eq $gatedValue -or $null -eq $privateValue) {
  'Unknown; review required'
} else {
  'Public and ungated'
}

Write-Output ''
Write-Output 'Local AI Lab model candidate check'
Write-Output '----------------------------------'
Write-Output ("Repository     : {0}" -f $repositoryId)
Write-Output ("Commit         : {0}" -f $(if ($commit) { $commit } else { 'Unknown' }))
Write-Output ("Access         : {0}" -f $accessLabel)
Write-Output ("License        : {0}" -f $license)
Write-Output ("Purpose        : {0}" -f $purpose)
Write-Output ("Parameters     : {0}" -f $parameterLabel)
Write-Output ("Q4_K_M files   : {0} total, {1} unsharded" -f $q4Files.Count, $unshardedQ4Files.Count)
foreach ($candidateFile in $q4Files) {
  $candidateFileName = [string](Get-PropertyValue -InputObject $candidateFile -Name 'rfilename')
  $candidateKind = if ($candidateFileName -match '(?i)-\d{5}-of-\d{5}\.gguf$') {
    'shard'
  } else {
    'complete file'
  }
  Write-Output ("                  - {0} [{1}]" -f $candidateFileName, $candidateKind)
}
Write-Output ("Selected file  : {0}" -f $(if ($fileName) { $fileName } else { 'None' }))
Write-Output ("Size           : {0}" -f $(if ($null -ne $fileSize) { "${fileSize} bytes" } else { 'Unknown' }))
Write-Output ("SHA256         : {0}" -f $(if ($sha256) { $sha256 } else { 'Unknown' }))
Write-Output ("Prompt format  : {0}" -f $promptFormat)
Write-Output ''

$resultColor = switch ($result) {
  'PASS' { 'Green' }
  'REVIEW' { 'Yellow' }
  default { 'Red' }
}
Write-Host ("RESULT: {0}" -f $result) -ForegroundColor $resultColor

if ($failReasons.Count -gt 0) {
  Write-Output ''
  Write-Output 'Failure reasons:'
  foreach ($reason in $failReasons) {
    Write-Output ("  - {0}" -f $reason)
  }
}

if ($reviewReasons.Count -gt 0) {
  Write-Output ''
  Write-Output 'Review reasons:'
  foreach ($reason in $reviewReasons) {
    Write-Output ("  - {0}" -f $reason)
  }
}

if ($result -eq 'PASS') {
  $encodedFileName = ConvertTo-EncodedPath -Path $fileName
  $downloadUrl = "https://huggingface.co/${encodedRepository}/resolve/${commit}/${encodedFileName}"
  $sourcePage = "https://huggingface.co/${encodedRepository}"

  $catalogId = [IO.Path]::GetFileNameWithoutExtension($fileName).ToLowerInvariant()
  $catalogId = ($catalogId -replace '[^a-z0-9._-]+', '-').Trim([char[]]'-')

  $repositoryName = ($repositoryId -split '/')[-1]
  $displayBase = $repositoryName -replace '(?i)[-_]?gguf$', ''
  $displayBase = (($displayBase -replace '[-_]+', ' ') -replace '\s+', ' ').Trim()
  $displayName = "${displayBase} (Q4_K_M)"

  $dartId = ConvertTo-DartSingleQuotedString -Value $catalogId
  $dartDisplayName = ConvertTo-DartSingleQuotedString -Value $displayName
  $dartFileName = ConvertTo-DartSingleQuotedString -Value $fileName
  $dartUrl = ConvertTo-DartSingleQuotedString -Value $downloadUrl
  $dartSha256 = ConvertTo-DartSingleQuotedString -Value $sha256
  $dartLicense = ConvertTo-DartSingleQuotedString -Value $catalogLicense
  $dartSourcePage = ConvertTo-DartSingleQuotedString -Value $sourcePage

  Write-Output ''
  Write-Output 'Candidate CatalogModel record:'
  Write-Output 'Do not add this record until this exact pinned artifact passes the phone benchmark.'
  Write-Output ''
  Write-Output @"
CatalogModel(
  id: '$dartId',
  displayName: '$dartDisplayName',
  fileName: '$dartFileName',
  url: '$dartUrl',
  sizeBytes: $fileSize,
  sha256: '$dartSha256',
  license: '$dartLicense',
  sourcePage: '$dartSourcePage',
),
"@
}

switch ($result) {
  'PASS' { exit 0 }
  'REVIEW' { exit 1 }
  default { exit 2 }
}
