# Build script for IconTools PowerShell Module C# assembly
$ErrorActionPreference = 'Stop'

Write-Host "Checking for dotnet SDK..." -ForegroundColor Cyan
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Error "dotnet SDK not found. Please install the .NET SDK to build this module."
}

$DotnetVersion = & dotnet --version
Write-Host "Found dotnet version: $DotnetVersion" -ForegroundColor Green

$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$SrcDir = Join-Path $PSScriptRoot "src"
$BinDir = Join-Path $PSScriptRoot "bin"

Write-Host "Building project in $SrcDir..." -ForegroundColor Cyan
# Run dotnet build in the src folder
Push-Location $SrcDir
try {
    & dotnet build -c Release
}
finally {
    Pop-Location
}

Write-Host "Copying assemblies to module bin directory..." -ForegroundColor Cyan
if (Test-Path $BinDir) {
    Remove-Item $BinDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $BinDir -Force | Out-Null

$Targets = @("net48", "net6.0-windows")
foreach ($target in $Targets) {
    $targetSourceDir = Join-Path $SrcDir "bin/Release/$target"
    if (Test-Path $targetSourceDir) {
        $targetBinDir = Join-Path $BinDir $target
        New-Item -ItemType Directory -Path $targetBinDir -Force | Out-Null
        
        Write-Host "Copying $target target to $targetBinDir..." -ForegroundColor Green
        Copy-Item -Path (Join-Path $targetSourceDir "IconTools.dll") -Destination $targetBinDir -Force
        Copy-Item -Path (Join-Path $targetSourceDir "IconTools.pdb") -Destination $targetBinDir -Force -ErrorAction SilentlyContinue
    } else {
        Write-Warning "Could not find build output for target: $target at $targetSourceDir"
    }
}

Write-Host "Build complete!" -ForegroundColor Green
