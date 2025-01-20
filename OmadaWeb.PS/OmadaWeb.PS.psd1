#
# Module manifest for module 'OmadaWeb.PS'
#
# Generated by: Mark van Eijken
#
# Generated on: 23-09-2023
#

@{

    # Script module or binary module file associated with this manifest.
    # RootModule = ''

    # Supported PSEditions
    CompatiblePSEditions = @(
        'Desktop',
        'Core'
    )

    # Version number of this module.
    ModuleVersion        = '0.0'

    # ID used to uniquely identify this module
    GUID                 = '148b46ca-255f-456d-92c9-e612ba971e09'

    # Author of this module
    Author               = 'Mark van Eijken'

    # Company or vendor of this module
    CompanyName          = 'Fortigi'

    # Copyright statement for this module
    Copyright            = '(C) {0} Fortigi All rights reserved.'

    # Description of the functionality provided by this module
    Description          = 'Module containing PowerShell commands to manage data via Omada web and OData endpoints in the cloud or on-prem. This module adds support for additional authentication types like OAuth2 based on client credentials and browser based login.'

    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion    = '5.1'

    # Name of the Windows PowerShell host required by this module
    # PowerShellHostName = ''

    # Minimum version of the Windows PowerShell host required by this module
    # PowerShellHostVersion = ''

    # Minimum version of Microsoft .NET Framework required by this module
    # DotNetFrameworkVersion = ''

    # Minimum version of the common language runtime (CLR) required by this module
    # CLRVersion = ''

    # Processor architecture (None, X86, Amd64) required by this module
    # ProcessorArchitecture = ''

    # Modules that must be imported into the global environment prior to importing this module
    # RequiredModules = @()

    # Assemblies that must be loaded prior to importing this module
    # RequiredAssemblies = @()

    # Script files (.ps1) that are run in the caller's environment prior to importing this module.
    # ScriptsToProcess = @()

    # Type files (.ps1xml) to be loaded when importing this module
    # TypesToProcess = @()

    # Format files (.ps1xml) to be loaded when importing this module
    # FormatsToProcess = @()

    # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
    NestedModules        = @(
        'OmadaWeb.PS.psm1'
    )

    # Functions to export from this module
    FunctionsToExport    = @(
        'Invoke-OmadaRestMethod',
        'Invoke-OmadaWebRequest'
    )

    # Cmdlets to export from this module
    CmdletsToExport      = '*'

    # Variables to export from this module
    VariablesToExport    = '*'

    # Aliases to export from this module
    AliasesToExport      = '*'

    # List of all modules packaged with this module
    # ModuleList = @()

    # List of all files packaged with this module
    # FileList = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData          = @{

        PSData = @{

            # Tags applied to this module. These help with module discovery in online galleries.
            Tags       = @('Omada', 'Windows')

            # A URL to the license for this module.
            LicenseUri = 'https://github.com/Fortigi/OmadaWeb.PS/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/Fortigi/OmadaWeb.PS'

        }

    }

    # HelpInfo URI of this module
    # HelpInfoURI = ''

    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    # DefaultCommandPrefix = ''

}
