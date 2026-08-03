[CmdletBinding()]
param(
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$projectPath = Join-Path $repositoryRoot "BOCADONISADOITConnector.proj"

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $resolvedOutputDirectory = Join-Path $repositoryRoot "dist"
}
elseif ([System.IO.Path]::IsPathRooted($OutputDirectory)) {
    $resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
}
else {
    $resolvedOutputDirectory = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $OutputDirectory))
}

if (-not (Test-Path -LiteralPath $projectPath -PathType Leaf)) {
    throw "Project file not found: $projectPath"
}

$project = New-Object System.Xml.XmlDocument
$project.PreserveWhitespace = $true
$project.Load($projectPath)

$namespaceManager = New-Object System.Xml.XmlNamespaceManager($project.NameTable)
$namespaceManager.AddNamespace("msb", $project.DocumentElement.NamespaceURI)
$contentNodes = @($project.SelectNodes("//msb:MezContent", $namespaceManager))

if ($contentNodes.Count -eq 0) {
    throw "The project does not declare any MezContent items."
}

$contentItems = @(
    $contentNodes | ForEach-Object {
        $include = $_.GetAttribute("Include")
        if ([string]::IsNullOrWhiteSpace($include)) {
            throw "A MezContent item has an empty Include attribute."
        }
        $include
    }
)

$packageNames = @($contentItems | ForEach-Object { [System.IO.Path]::GetFileName($_) })
$duplicateItems = @(
    $packageNames |
        Group-Object { $_.ToLowerInvariant() } |
        Where-Object Count -GT 1
)
if ($duplicateItems.Count -gt 0) {
    throw "Multiple MezContent items would have the same package name: $($duplicateItems.Name -join ', ')"
}

$repositoryPrefix = $repositoryRoot.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
) + [System.IO.Path]::DirectorySeparatorChar

$packageSources = foreach ($item in $contentItems) {
    if ([System.IO.Path]::IsPathRooted($item)) {
        throw "MezContent paths must be relative: $item"
    }

    $sourcePath = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $item))
    if (-not $sourcePath.StartsWith($repositoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "MezContent path leaves the repository: $item"
    }
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "MezContent file not found: $item"
    }

    [pscustomobject]@{
        Include = $item
        PackagePath = [System.IO.Path]::GetFileName($item)
        Source = $sourcePath
    }
}

$connectorSourcePath = Join-Path $repositoryRoot "BOCADONISADOITConnector.pq"
$connectorSource = Get-Content -LiteralPath $connectorSourcePath -Raw -Encoding UTF8
if ($connectorSource -notmatch "(?m)^section\s+BOCADONISADOITConnector;\s*$") {
    throw "The connector source does not declare section BOCADONISADOITConnector."
}

$resourcePath = Join-Path $repositoryRoot "resources.resx"
$resourceDocument = New-Object System.Xml.XmlDocument
$resourceDocument.Load($resourcePath)

New-Item -ItemType Directory -Force -Path $resolvedOutputDirectory | Out-Null
$artifactPath = Join-Path $resolvedOutputDirectory "BOCADONISADOITConnector.mez"
$checksumPath = "$artifactPath.sha256"

$temporaryBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
)
$temporaryRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $temporaryBase ("BOCADONISADOITConnector-" + [System.Guid]::NewGuid().ToString("N")))
)
if ((Split-Path -Parent $temporaryRoot) -ne $temporaryBase) {
    throw "Unexpected temporary directory: $temporaryRoot"
}
$stagingDirectory = Join-Path $temporaryRoot "package"

try {
    New-Item -ItemType Directory -Force -Path $stagingDirectory | Out-Null

    foreach ($packageSource in $packageSources) {
        $destination = Join-Path $stagingDirectory $packageSource.PackagePath
        $destinationDirectory = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $destinationDirectory)) {
            New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
        }
        Copy-Item -LiteralPath $packageSource.Source -Destination $destination
    }

    if ([System.IO.File]::Exists($artifactPath)) {
        [System.IO.File]::Delete($artifactPath)
    }
    if ([System.IO.File]::Exists($checksumPath)) {
        [System.IO.File]::Delete($checksumPath)
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $stagingDirectory,
        $artifactPath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )

    $archive = [System.IO.Compression.ZipFile]::OpenRead($artifactPath)
    try {
        $actualEntries = @($archive.Entries | ForEach-Object FullName | Sort-Object)
    }
    finally {
        $archive.Dispose()
    }

    $expectedEntries = @($packageSources | ForEach-Object PackagePath | Sort-Object)
    $entryDifference = @(Compare-Object -ReferenceObject $expectedEntries -DifferenceObject $actualEntries)
    if ($entryDifference.Count -gt 0) {
        throw "The generated package contents do not match the project manifest: $($entryDifference | Out-String)"
    }

    $artifactHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
    [System.IO.File]::WriteAllText(
        $checksumPath,
        "$artifactHash  $([System.IO.Path]::GetFileName($artifactPath))`n",
        [System.Text.Encoding]::ASCII
    )

    Write-Host "Built $artifactPath"
    Write-Host "SHA256 $artifactHash"
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
