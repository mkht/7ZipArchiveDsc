Configuration $configurationName
{
    Import-DscResource -ModuleName 7ZipArchiveDsc
    Node localhost
    {
        x7ZipArchive Integration_Test {
            Path        = (Join-Path $TestDrive "$script:TestGuid\TestHasRoot.zip")
            Destination =  (Join-Path $TestDrive "$script:TestGuid\Destination")
            IgnoreRoot  = $true
        }
    }
}
