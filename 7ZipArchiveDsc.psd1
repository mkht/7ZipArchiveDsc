@{
    RootModule           = '7ZipArchiveDsc.psm1'
    ModuleVersion        = '1.5.0'
    GUID                 = '9c9688ed-1172-4d5a-9c80-772e086edda6'
    Author               = 'mkht'
    CompanyName          = ''
    Copyright            = '(c) 2021 mkht. All rights reserved.'
    Description          = 'PowerShell DSC Resource to expand an archive file to a specific path. '
    PowerShellVersion    = '5.0'
    FunctionsToExport    = @(
        'Expand-7ZipArchive',
        'Compress-7ZipArchive'
    )
    CmdletsToExport      = @()
    VariablesToExport    = '*'
    AliasesToExport      = @()
    DscResourcesToExport = @('x7ZipArchive')
    PrivateData          = @{
        PSData = @{
            Tags       = @('DSC', 'ZIP', '7-Zip')
            LicenseUri = 'https://github.com/mkht/7ZipArchiveDsc/blob/master/LICENSE'
            ProjectUri = 'https://github.com/mkht/7ZipArchiveDsc'
        }
    }
}
