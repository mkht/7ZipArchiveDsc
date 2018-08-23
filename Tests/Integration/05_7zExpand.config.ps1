Configuration $configurationName
{
    Import-DscResource -ModuleName 7ZipArchiveDsc
    Node localhost
    {
        x7ZipArchive Integration_Test {
            Path        = (Join-Path $TestDrive "$script:TestGuid\TestHasRoot.7z")
            Destination =  (Join-Path $TestDrive "$script:TestGuid\Destination")
        }
    }
}
