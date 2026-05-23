@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'IconTools.psm1'

    # Version number of this module.
    ModuleVersion = '1.0.0'

    # Supported PowerShell Host Editions
    CompatiblePSEditions = @('Desktop', 'Core')

    # ID used to uniquely identify this module
    GUID = 'd7b5ec1e-5eb8-47fb-9eb4-3e9a7e089201'

    # Author of this module
    Author = 'John'

    # Company or vendor of this module
    CompanyName = 'Personal'

    # Copyright statement for this module
    Copyright = '(c) 2026 John. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'PowerShell module to list, extract, and compile Windows Icon (.ico) and PNG resources from executables, DLLs, and image folders.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Functions to export from this module
    FunctionsToExport = @(
        'Get-IconResource',
        'Export-IconResource',
        'New-IconFile'
    )

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule
    PrivateData = @{
        PSData = @{
            Tags = @('Icon', 'Extract', 'Resource', 'PE', 'EXE', 'DLL', 'PNG', 'ICO')
            ProjectUri = 'https://github.com/Personal/IconTools'
        }
    }
}
