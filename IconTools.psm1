# IconTools - PowerShell Module for extracting and compiling Windows Icon resources
# Auto-loads the appropriate compiled C# assembly based on PowerShell edition.

$ErrorActionPreference = 'Stop'

# Determine the correct binary directory based on the PowerShell Edition (Core/7 vs Desktop/5.1)
$AssemblyPath = ""
if ($PSVersionTable.PSEdition -eq "Core")
{
    $AssemblyPath = Join-Path $PSScriptRoot "bin/net6.0-windows/IconTools.dll"
}
else
{
    $AssemblyPath = Join-Path $PSScriptRoot "bin/net48/IconTools.dll"
}

if (-not (Test-Path $AssemblyPath))
{
    # Non-blocking warning during module check, but throws error if cmdlets are actually executed
    Write-Warning "IconTools binary dependency not found at '$AssemblyPath'. Please run 'build.ps1' to compile the assembly before using module functions."
}
else
{
    Write-Verbose "Loading IconTools binary assembly from '$AssemblyPath'..."
    Add-Type -LiteralPath $AssemblyPath
}

<#
.SYNOPSIS
    Lists all icon group resources embedded inside a Windows executable or DLL.
.DESCRIPTION
    Scans a Windows Portable Executable (PE) binary (such as .exe or .dll) for icon group resources (RT_GROUP_ICON) and lists their metadata, including name/ID, image count, and resolutions.
.PARAMETER Path
    Path to the Windows executable or library. Supports pipeline input and wildcards.
.EXAMPLE
    Get-IconResource -Path C:\Windows\System32\shell32.dll
.EXAMPLE
    Get-ChildItem C:\Windows\*.exe | Get-IconResource
#>
function Get-IconResource
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Path
    )

    process
    {
        # Check if type is loaded
        if (-not ([System.Management.Automation.PSTypeName]'IconTools.IconExtractor').Type)
        {
            throw "IconTools type not loaded. Please build the assembly by running build.ps1."
        }

        foreach ($p in $Path)
        {
            try
            {
                $resolvedPaths = Resolve-Path -Path $p | Select-Object -ExpandProperty Path
                foreach ($resolvedPath in $resolvedPaths)
                {
                    Write-Verbose "Scanning icon resources in: $resolvedPath"
                    $groups = [IconTools.IconExtractor]::GetIconGroups($resolvedPath)
                    foreach ($group in $groups)
                    {
                        # Add SourcePath to output object
                        $group | Add-Member -MemberType NoteProperty -Name "SourcePath" -Value $resolvedPath -PassThru
                    }
                }
            }
            catch
            {
                Write-Error $_
            }
        }
    }
}

<#
.SYNOPSIS
    Exports embedded icon resources from a Windows executable or DLL.
.DESCRIPTION
    Extracts specified or all icon group resources from a PE file and saves them to disk.
    Supports exporting as standard multi-resolution .ico files, individual .png frames, or both.
.PARAMETER Path
    Path to the Windows executable or library. Supports pipeline input and wildcards.
.PARAMETER OutputPath
    Directory where the exported icon files will be written.
.PARAMETER Name
    The specific resource name(s) or ID(s) to export. If not specified, all icon resources are exported. Example: "APP_ICON", "#101".
.PARAMETER Format
    The export format: 'Ico' (default), 'Png' (extracts individual frames), or 'All' (both .ico and .png frames).
.PARAMETER Force
    Overwrites existing files in the output directory.
.PARAMETER PassThru
    Returns custom objects representing the created files.
.EXAMPLE
    Export-IconResource -Path C:\Windows\explorer.exe -OutputPath C:\temp\extracted -Format All
.EXAMPLE
    Get-IconResource -Path C:\Windows\notepad.exe | Export-IconResource -OutputPath C:\temp\notepad_icons
#>
function Export-IconResource
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Path,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [string[]]$Name,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Ico', 'Png', 'All')]
        [string]$Format = 'Ico',

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    process
    {
        if (-not ([System.Management.Automation.PSTypeName]'IconTools.IconExtractor').Type)
        {
            throw "IconTools type not loaded. Please build the assembly by running build.ps1."
        }

        # Resolve OutputPath to absolute path (does not need to exist yet)
        $absoluteOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

        foreach ($p in $Path)
        {
            try
            {
                $resolvedPaths = Resolve-Path -Path $p | Select-Object -ExpandProperty Path
                foreach ($resolvedPath in $resolvedPaths)
                {
                    # Resolve names to export
                    $targetNames = $Name
                    if (-not $targetNames)
                    {
                        # Extract all icon groups if none specified
                        $targetNames = [IconTools.IconExtractor]::GetIconGroups($resolvedPath) | Select-Object -ExpandProperty Name
                    }

                    if (-not $targetNames -or $targetNames.Count -eq 0)
                    {
                        Write-Verbose "No icon resources found in: $resolvedPath"
                        continue
                    }

                    foreach ($nameVal in $targetNames)
                    {
                        # Safe file name construction from resource name
                        $cleanName = $nameVal
                        if ($cleanName.StartsWith('#'))
                        {
                            $cleanName = $cleanName.Substring(1)
                        }

                        $baseFileName = "$(Split-Path -Leaf $resolvedPath -Resolve:$false)_$cleanName"
                        $targetFile = Join-Path $absoluteOutputPath "$baseFileName.ico"

                        # Check overwrite condition for ICO
                        if (-not $Force -and ($Format -eq 'Ico' -or $Format -eq 'All') -and (Test-Path $targetFile))
                        {
                            Write-Warning "File '$targetFile' already exists. Use -Force to overwrite."
                            continue
                        }

                        if ($PSCmdlet.ShouldProcess("Resource '$nameVal' in '$resolvedPath'", "Export to '$absoluteOutputPath' in format '$Format'"))
                        {
                            $exportFormat = [IconTools.ExportFormat]::$Format
                            
                            # Export the icon resource
                            [IconTools.IconExtractor]::ExtractIcon($resolvedPath, $nameVal, $targetFile, $exportFormat)

                            if ($PassThru)
                            {
                                # Output objects representing the created files
                                if ($Format -eq 'Ico' -or $Format -eq 'All')
                                {
                                    $icoFile = if ($Format -eq 'Ico') { $targetFile } else { "$targetFile.ico" }
                                    if (Test-Path $icoFile)
                                    {
                                        [PSCustomObject][Ordered]@{
                                            Path = $icoFile
                                            Format = 'Ico'
                                            ResourceName = $nameVal
                                            SourcePath = $resolvedPath
                                        }
                                    }
                                }
                                if ($Format -eq 'Png' -or $Format -eq 'All')
                                {
                                    # PNG frames are named like [targetFile]_[width]x[height].png
                                    $pngFiles = Get-ChildItem -Path $absoluteOutputPath -Filter "$baseFileName`_*.png"
                                    foreach ($png in $pngFiles)
                                    {
                                        [PSCustomObject][Ordered]@{
                                            Path = $png.FullName
                                            Format = 'Png'
                                            ResourceName = $nameVal
                                            SourcePath = $resolvedPath
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            catch
            {
                Write-Error $_
            }
        }
    }
}

<#
.SYNOPSIS
    Packs multiple PNG images into a single multi-resolution Windows Icon (.ico) file.
.DESCRIPTION
    Reads standard PNG files (such as 16x16, 32x32, 48x48, 256x256), parses their dimensions, and builds a standard .ico file containing these image sizes.
.PARAMETER Path
    Path to the input PNG files. Supports wildcards and pipeline input.
.PARAMETER OutputPath
    Path to the .ico file to create.
.PARAMETER Force
    Overwrites the output file if it already exists.
.EXAMPLE
    New-IconFile -Path C:\temp\my_icon_*.png -OutputPath C:\temp\compiled.ico
.EXAMPLE
    Get-ChildItem C:\temp\icons\*.png | New-IconFile -OutputPath C:\temp\app.ico
#>
function New-IconFile
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Path,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    begin
    {
        if (-not ([System.Management.Automation.PSTypeName]'IconTools.IconExtractor').Type)
        {
            throw "IconTools type not loaded. Please build the assembly by running build.ps1."
        }
        $allPngPaths = New-Object System.Collections.Generic.List[string]
    }

    process
    {
        foreach ($p in $Path)
        {
            $resolvedPaths = Resolve-Path -Path $p | Select-Object -ExpandProperty Path
            foreach ($resolvedPath in $resolvedPaths)
            {
                if (Test-Path $resolvedPath -PathType Leaf)
                {
                    $allPngPaths.Add($resolvedPath)
                }
            }
        }
    }

    end
    {
        if ($allPngPaths.Count -eq 0)
        {
            Write-Error "No input PNG files found to package."
            return
        }

        # Resolve OutputPath to absolute path
        $absoluteOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
        
        if (Test-Path $absoluteOutputPath)
        {
            if (-not $Force)
            {
                Write-Warning "The output file '$absoluteOutputPath' already exists. Use -Force to overwrite."
                return
            }
        }

        if ($PSCmdlet.ShouldProcess($absoluteOutputPath, "Create multi-resolution Icon from $($allPngPaths.Count) PNG files"))
        {
            try
            {
                [IconTools.IconExtractor]::CreateIconFromPngs($allPngPaths.ToArray(), $absoluteOutputPath)
                Write-Verbose "Successfully compiled ICO file at '$absoluteOutputPath'."
            }
            catch
            {
                Write-Error $_
            }
        }
    }
}

# Export the public cmdlets
Export-ModuleMember -Function Get-IconResource, Export-IconResource, New-IconFile
