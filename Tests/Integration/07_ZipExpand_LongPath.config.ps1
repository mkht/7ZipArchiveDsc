Configuration $configurationName
{
    Import-DscResource -ModuleName 7ZipArchiveDsc
    Node localhost
    {
        $LongName = 'a4cffe08-444f-4e4e-8ec1-79b91b9f803e-5e4fc109-dbd2-4f29-bbcc-8722304c397e-9280fbca-4aa6-4f02-bd94-fd5742f0a34f-1658b2e4-8122-41eb-99a2-c41f7122ad95-29fc9a27-99fc-498c-ab8f-0c7e084bb6ce-ab55af1d-c9e8-4c9c-920d-682ea39ff8dc'
        x7ZipArchive Integration_Test {
            Path        = (Join-Path $TestDrive "$script:TestGuid\TestLongPath.zip")
            Destination =  (Join-Path $TestDrive "$script:TestGuid\$LongName\$LongName\$LongName\Destination")
            Clean       = $true
            Validate    = $true
            Checksum    = 'CRC'
        }
    }
}
