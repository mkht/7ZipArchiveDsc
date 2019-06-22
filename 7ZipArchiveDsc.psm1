$modulePath = $PSScriptRoot
$subModulePath = @(
    '\DSCResources\x7ZipArchive\x7ZipArchive.psm1'
)

$subModulePath.ForEach( {
        Import-Module (Join-Path $modulePath $_)
    })
