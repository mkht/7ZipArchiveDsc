#region HEADER
$script:moduleName = '7ZipArchiveDsc' # TODO: Example 'NetworkingDsc'
$script:moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$global:TestData = Join-Path (Split-Path -Parent $PSScriptRoot) '\TestData'

# Requires Pester 4.2.0 or higher
$newestPesterVersion = [System.Version]((Get-Module Pester -ListAvailable).Version | Sort-Object -Descending | Select-Object -First 1)
if ($newestPesterVersion -lt '4.2.0') { throw "Pester 4.2.0 or higher is required." }

# Initialize test environment
Import-Module -Name (Join-Path -Path $script:moduleRoot -ChildPath '\Tests\TestHelper.psm1') -Force
Initialize-TestEnvironment -ModuleRoot $script:moduleRoot -ModuleName $script:moduleName
#endregion

# Using try/finally to always cleanup.
try {
    #region Integration Tests
    $script:TestGuid = [Guid]::NewGuid()

    $script:ShowDscVerboseMsg = $false

    $ConfigurationData = @{
        AllNodes = @(
            @{
                NodeName                    = 'localhost'
                PSDscAllowPlainTextPassword = $true
            }
        )
    }

    Describe "x7ZipArchive_Integration" -Tag 'Integration' {

        $configurationName = "x7ZipArchive_Config"

        BeforeAll {
            Copy-Item -Path $global:TestData -Destination "TestDrive:\$script:TestGuid" -Recurse -Force
        }

        Context 'ZIPファイルの展開' {

            $config = Join-Path $PSScriptRoot '01_ZipExpand.config.ps1'

            AfterAll {
                if (Test-Path (Join-Path $TestDrive "$script:TestGuid\Destination")) {
                    Remove-Item (Join-Path $TestDrive "$script:TestGuid\Destination") -Recurse -Force
                }
            }

            It 'Should compile and apply the MOF without throwing' {
                {
                    . $config

                    $configurationParameters = @{
                        OutputPath        = $TestDrive
                        ConfigurationData = $ConfigurationData
                    }

                    & $configurationName @configurationParameters

                    $startDscConfigurationParameters = @{
                        Path         = $TestDrive
                        ComputerName = 'localhost'
                        Wait         = $true
                        Verbose      = $script:ShowDscVerboseMsg
                        Force        = $true
                        ErrorAction  = 'Stop'
                    }

                    Start-DscConfiguration @startDscConfigurationParameters
                } | Should -Not -Throw
            }

            It 'Should be able to call Get-DscConfiguration without throwing' {
                {
                    $script:currentConfiguration = Get-DscConfiguration -Verbose:$script:ShowDscVerboseMsg -ErrorAction Stop
                } | Should -Not -Throw
            }

            It 'Should have set the resource and all the parameters should match' {
                $resourceCurrentState = $script:currentConfiguration | Where-Object -FilterScript {
                    $_.ConfigurationName -eq $configurationName `
                        -and $_.ResourceId -eq "[x7ZipArchive]Integration_Test"
                }

                $resourceCurrentState.Ensure | Should -Be 'Present'
                $resourceCurrentState.Path | Should -Be (Join-Path $TestDrive "$script:TestGuid\TestValid.zip")
                $resourceCurrentState.Destination | Should -Be (Join-Path $TestDrive "$script:TestGuid\Destination")
            }

            It 'Should return $true when Test-DscConfiguration is run' {
                Test-DscConfiguration -Verbose:$script:ShowDscVerboseMsg | Should -Be $true
            }

            It 'Should be expanded archive to destination' {
                Test-Path (Join-Path $TestDrive "$script:TestGuid\Destination") | Should -Be $true
                $files = Get-ChildItem -LiteralPath (Join-Path $TestDrive "$script:TestGuid\Destination") -Recurse -Force
                $files | Should -HaveCount 4
                $files | Where-Object { -not $_.PsIsContainer } | Should -HaveCount 3
                $files | Where-Object { $_.PsIsContainer } | Should -HaveCount 1
            }
        }


        Context 'ZIPファイルの展開 (IgnoreRoot)' {

            $config = Join-Path $PSScriptRoot '02_ZipExpand_IgnoreRoot.config.ps1'

            AfterAll {
                if (Test-Path (Join-Path $TestDrive "$script:TestGuid\Destination")) {
                    Remove-Item (Join-Path $TestDrive "$script:TestGuid\Destination") -Recurse -Force
                }
            }

            It 'Should compile and apply the MOF without throwing' {
                {
                    . $config

                    $configurationParameters = @{
                        OutputPath        = $TestDrive
                        ConfigurationData = $ConfigurationData
                    }

                    & $configurationName @configurationParameters

                    $startDscConfigurationParameters = @{
                        Path         = $TestDrive
                        ComputerName = 'localhost'
                        Wait         = $true
                        Verbose      = $script:ShowDscVerboseMsg
                        Force        = $true
                        ErrorAction  = 'Stop'
                    }

                    Start-DscConfiguration @startDscConfigurationParameters
                } | Should -Not -Throw
            }

            It 'Should be able to call Get-DscConfiguration without throwing' {
                {
                    $script:currentConfiguration = Get-DscConfiguration -Verbose:$script:ShowDscVerboseMsg -ErrorAction Stop
                } | Should -Not -Throw
            }

            It 'Should have set the resource and all the parameters should match' {
                $resourceCurrentState = $script:currentConfiguration | Where-Object -FilterScript {
                    $_.ConfigurationName -eq $configurationName `
                        -and $_.ResourceId -eq "[x7ZipArchive]Integration_Test"
                }

                $resourceCurrentState.Ensure | Should -Be 'Present'
                $resourceCurrentState.Path | Should -Be (Join-Path $TestDrive "$script:TestGuid\TestHasRoot.zip")
                $resourceCurrentState.Destination | Should -Be (Join-Path $TestDrive "$script:TestGuid\Destination")
            }

            It 'Should return $true when Test-DscConfiguration is run' {
                Test-DscConfiguration -Verbose:$script:ShowDscVerboseMsg | Should -Be $true
            }

            It 'Should be expanded archive to destination' {
                Test-Path (Join-Path $TestDrive "$script:TestGuid\Destination") | Should -Be $true
                $files = Get-ChildItem -LiteralPath (Join-Path $TestDrive "$script:TestGuid\Destination") -Recurse -Force
                $files | Should -HaveCount 4
                $files | Where-Object { -not $_.PsIsContainer } | Should -HaveCount 3
                $files | Where-Object { $_.PsIsContainer } | Should -HaveCount 1
            }
        }


        Context 'ZIPファイルの展開 (Validate, Checksum="ModifiedDate")' {

            $config = Join-Path $PSScriptRoot '03_ZipExpand_Checksum_ModifiedDate.config.ps1'

            BeforeAll {
                $Destination = (Join-Path $TestDrive "$script:TestGuid\Destination")
                if (-not (Test-Path $Destination)) {
                    New-Item $Destination -ItemType Directory -Force > $null
                }
                '00000' | Out-File (Join-Path $Destination 'Hello Archive.txt')
                Set-ItemProperty (Join-Path $Destination 'Hello Archive.txt') -Name LastWriteTime -Value ([datetime]::Now)
            }

            AfterAll {
                if (Test-Path (Join-Path $TestDrive "$script:TestGuid\Destination")) {
                    Remove-Item (Join-Path $TestDrive "$script:TestGuid\Destination") -Recurse -Force
                }
            }

            It 'Should compile and apply the MOF without throwing' {
                {
                    . $config

                    $configurationParameters = @{
                        OutputPath        = $TestDrive
                        ConfigurationData = $ConfigurationData
                    }

                    & $configurationName @configurationParameters

                    $startDscConfigurationParameters = @{
                        Path         = $TestDrive
                        ComputerName = 'localhost'
                        Wait         = $true
                        Verbose      = $script:ShowDscVerboseMsg
                        Force        = $true
                        ErrorAction  = 'Stop'
                    }

                    Start-DscConfiguration @startDscConfigurationParameters
                } | Should -Not -Throw
            }

            It 'Should be able to call Get-DscConfiguration without throwing' {
                {
                    $script:currentConfiguration = Get-DscConfiguration -Verbose:$script:ShowDscVerboseMsg -ErrorAction Stop
                } | Should -Not -Throw
            }

            It 'Should have set the resource and all the parameters should match' {
                $resourceCurrentState = $script:currentConfiguration | Where-Object -FilterScript {
                    $_.ConfigurationName -eq $configurationName `
                        -and $_.ResourceId -eq "[x7ZipArchive]Integration_Test"
                }

                $resourceCurrentState.Ensure | Should -Be 'Present'
                $resourceCurrentState.Path | Should -Be (Join-Path $TestDrive "$script:TestGuid\TestValid.zip")
                $resourceCurrentState.Destination | Should -Be (Join-Path $TestDrive "$script:TestGuid\Destination")
            }

            It 'Should return $true when Test-DscConfiguration is run' {
                Test-DscConfiguration -Verbose:$script:ShowDscVerboseMsg | Should -Be $true
            }

            It 'Should be expanded archive to destination' {
                Test-Path (Join-Path $TestDrive "$script:TestGuid\Destination") | Should -Be $true
                $item = Get-Item -Path (Join-Path $TestDrive "$script:TestGuid\Destination\Hello Archive.txt")
                $item.LastWriteTimeUtc.ToString('s') | Should -Be '2018-08-08T15:02:18'
                Get-Content $item -Raw | Should -Be 'Hello Archive!'
            }
        }


        Context 'ZIPファイルの展開 (Validate, Checksum="Size")' {

            $config = Join-Path $PSScriptRoot '04_ZipExpand_Checksum_Size.config.ps1'

            BeforeAll {
                $Destination = (Join-Path $TestDrive "$script:TestGuid\Destination")
                if (-not (Test-Path $Destination)) {
                    New-Item $Destination -ItemType Directory -Force > $null
                }
                '0000000000' | Out-File (Join-Path $Destination 'Hello Archive.txt')
            }

            AfterAll {
                if (Test-Path (Join-Path $TestDrive "$script:TestGuid\Destination")) {
                    Remove-Item (Join-Path $TestDrive "$script:TestGuid\Destination") -Recurse -Force
                }
            }

            It 'Should compile and apply the MOF without throwing' {
                {
                    . $config

                    $configurationParameters = @{
                        OutputPath        = $TestDrive
                        ConfigurationData = $ConfigurationData
                    }

                    & $configurationName @configurationParameters

                    $startDscConfigurationParameters = @{
                        Path         = $TestDrive
                        ComputerName = 'localhost'
                        Wait         = $true
                        Verbose      = $script:ShowDscVerboseMsg
                        Force        = $true
                        ErrorAction  = 'Stop'
                    }

                    Start-DscConfiguration @startDscConfigurationParameters
                } | Should -Not -Throw
            }

            It 'Should be able to call Get-DscConfiguration without throwing' {
                {
                    $script:currentConfiguration = Get-DscConfiguration -Verbose:$script:ShowDscVerboseMsg -ErrorAction Stop
                } | Should -Not -Throw
            }

            It 'Should have set the resource and all the parameters should match' {
                $resourceCurrentState = $script:currentConfiguration | Where-Object -FilterScript {
                    $_.ConfigurationName -eq $configurationName `
                        -and $_.ResourceId -eq "[x7ZipArchive]Integration_Test"
                }

                $resourceCurrentState.Ensure | Should -Be 'Present'
                $resourceCurrentState.Path | Should -Be (Join-Path $TestDrive "$script:TestGuid\TestValid.zip")
                $resourceCurrentState.Destination | Should -Be (Join-Path $TestDrive "$script:TestGuid\Destination")
            }

            It 'Should return $true when Test-DscConfiguration is run' {
                Test-DscConfiguration -Verbose:$script:ShowDscVerboseMsg | Should -Be $true
            }

            It 'Should be expanded archive to destination' {
                Test-Path (Join-Path $TestDrive "$script:TestGuid\Destination") | Should -Be $true
                $item = Get-Item -Path (Join-Path $TestDrive "$script:TestGuid\Destination\Hello Archive.txt")
                Get-Content $item -Raw | Should -Be 'Hello Archive!'
            }
        }

        Context 'ZIPファイルの展開 (Clean)' {

            $config = Join-Path $PSScriptRoot '06_ZipExpand_Clean.config.ps1'

            BeforeAll {
                $Destination = (Join-Path $TestDrive "$script:TestGuid\Destination")
                if (-not (Test-Path $Destination)) {
                    New-Item $Destination -ItemType Directory -Force > $null
                }
                '00000' | Out-File (Join-Path $Destination 'something.txt')
            }

            AfterAll {
                if (Test-Path (Join-Path $TestDrive "$script:TestGuid\Destination")) {
                    Remove-Item (Join-Path $TestDrive "$script:TestGuid\Destination") -Recurse -Force
                }
            }

            It 'Should compile and apply the MOF without throwing' {
                {
                    . $config

                    $configurationParameters = @{
                        OutputPath        = $TestDrive
                        ConfigurationData = $ConfigurationData
                    }

                    & $configurationName @configurationParameters

                    $startDscConfigurationParameters = @{
                        Path         = $TestDrive
                        ComputerName = 'localhost'
                        Wait         = $true
                        Verbose      = $script:ShowDscVerboseMsg
                        Force        = $true
                        ErrorAction  = 'Stop'
                    }

                    Start-DscConfiguration @startDscConfigurationParameters
                } | Should -Not -Throw
            }

            It 'Should be able to call Get-DscConfiguration without throwing' {
                {
                    $script:currentConfiguration = Get-DscConfiguration -Verbose:$script:ShowDscVerboseMsg -ErrorAction Stop
                } | Should -Not -Throw
            }

            It 'Should have set the resource and all the parameters should match' {
                $resourceCurrentState = $script:currentConfiguration | Where-Object -FilterScript {
                    $_.ConfigurationName -eq $configurationName `
                        -and $_.ResourceId -eq "[x7ZipArchive]Integration_Test"
                }

                $resourceCurrentState.Ensure | Should -Be 'Present'
                $resourceCurrentState.Path | Should -Be (Join-Path $TestDrive "$script:TestGuid\TestValid.zip")
                $resourceCurrentState.Destination | Should -Be (Join-Path $TestDrive "$script:TestGuid\Destination")
            }

            It 'Should return $true when Test-DscConfiguration is run' {
                Test-DscConfiguration -Verbose:$script:ShowDscVerboseMsg | Should -Be $true
            }

            It 'Should be expanded archive to destination' {
                Test-Path (Join-Path $TestDrive "$script:TestGuid\Destination") | Should -Be $true
                $item = Get-Item -Path (Join-Path $TestDrive "$script:TestGuid\Destination\Hello Archive.txt")
                Get-Content $item -Raw | Should -Be 'Hello Archive!'
            }

            It 'Should be removed existent files in the destination' {
                Test-Path -Path (Join-Path $TestDrive "$script:TestGuid\Destination\something.txt") | Should -Be $false
            }
        }

        Context '7zファイルの展開' {

            $config = Join-Path $PSScriptRoot '05_7zExpand.config.ps1'

            AfterAll {
                if (Test-Path (Join-Path $TestDrive "$script:TestGuid\Destination")) {
                    Remove-Item (Join-Path $TestDrive "$script:TestGuid\Destination") -Recurse -Force
                }
            }

            It 'Should compile and apply the MOF without throwing' {
                {
                    . $config

                    $configurationParameters = @{
                        OutputPath        = $TestDrive
                        ConfigurationData = $ConfigurationData
                    }

                    & $configurationName @configurationParameters

                    $startDscConfigurationParameters = @{
                        Path         = $TestDrive
                        ComputerName = 'localhost'
                        Wait         = $true
                        Verbose      = $script:ShowDscVerboseMsg
                        Force        = $true
                        ErrorAction  = 'Stop'
                    }

                    Start-DscConfiguration @startDscConfigurationParameters
                } | Should -Not -Throw
            }

            It 'Should be able to call Get-DscConfiguration without throwing' {
                {
                    $script:currentConfiguration = Get-DscConfiguration -Verbose:$script:ShowDscVerboseMsg -ErrorAction Stop
                } | Should -Not -Throw
            }

            It 'Should have set the resource and all the parameters should match' {
                $resourceCurrentState = $script:currentConfiguration | Where-Object -FilterScript {
                    $_.ConfigurationName -eq $configurationName `
                        -and $_.ResourceId -eq "[x7ZipArchive]Integration_Test"
                }

                $resourceCurrentState.Ensure | Should -Be 'Present'
                $resourceCurrentState.Path | Should -Be (Join-Path $TestDrive "$script:TestGuid\TestHasRoot.7z")
                $resourceCurrentState.Destination | Should -Be (Join-Path $TestDrive "$script:TestGuid\Destination")
            }

            It 'Should return $true when Test-DscConfiguration is run' {
                Test-DscConfiguration -Verbose:$script:ShowDscVerboseMsg | Should -Be $true
            }

            It 'Should be expanded archive to destination' {
                Test-Path (Join-Path $TestDrive "$script:TestGuid\Destination") | Should -Be $true
                $files = Get-ChildItem -LiteralPath (Join-Path $TestDrive "$script:TestGuid\Destination") -Recurse -Force
                $files | Should -HaveCount 5
                $files | Where-Object { -not $_.PsIsContainer } | Should -HaveCount 3
                $files | Where-Object { $_.PsIsContainer } | Should -HaveCount 2
            }
        }

        Context '260文字を超えるパスでの動作' {

            $config = Join-Path $PSScriptRoot '07_ZipExpand_LongPath.config.ps1'

            BeforeAll {
                $LongName = 'a4cffe08-444f-4e4e-8ec1-79b91b9f803e-5e4fc109-dbd2-4f29-bbcc-8722304c397e-9280fbca-4aa6-4f02-bd94-fd5742f0a34f-1658b2e4-8122-41eb-99a2-c41f7122ad95-29fc9a27-99fc-498c-ab8f-0c7e084bb6ce-ab55af1d-c9e8-4c9c-920d-682ea39ff8dc'
                $Destination = (Join-Path $TestDrive $script:TestGuid)
                $Destination = $Destination + "\$LongName\$LongName\$LongName\Destination"
            }

            AfterAll {
                $Target = (Join-Path $TestDrive "$script:TestGuid\$LongName")
                if ($PSVersionTable.PSVersion.Major -lt 6) {
                    $Target = '\\?\' + $Target
                }
                Remove-Item -LiteralPath $Target -Recurse -force -ErrorAction SilentlyContinue
            }

            It 'Should compile and apply the MOF without throwing' {
                {
                    . $config

                    $configurationParameters = @{
                        OutputPath        = $TestDrive
                        ConfigurationData = $ConfigurationData
                    }

                    & $configurationName @configurationParameters

                    $startDscConfigurationParameters = @{
                        Path         = $TestDrive
                        ComputerName = 'localhost'
                        Wait         = $true
                        Verbose      = $script:ShowDscVerboseMsg
                        Force        = $true
                        ErrorAction  = 'Stop'
                    }

                    Start-DscConfiguration @startDscConfigurationParameters
                } | Should -Not -Throw
            }

            It 'Should be able to call Get-DscConfiguration without throwing' {
                {
                    $script:currentConfiguration = Get-DscConfiguration -Verbose:$script:ShowDscVerboseMsg -ErrorAction Stop
                } | Should -Not -Throw
            }

            It 'Should have set the resource and all the parameters should match' {
                $resourceCurrentState = $script:currentConfiguration | Where-Object -FilterScript {
                    $_.ConfigurationName -eq $configurationName `
                        -and $_.ResourceId -eq "[x7ZipArchive]Integration_Test"
                }

                $LongName = 'a4cffe08-444f-4e4e-8ec1-79b91b9f803e-5e4fc109-dbd2-4f29-bbcc-8722304c397e-9280fbca-4aa6-4f02-bd94-fd5742f0a34f-1658b2e4-8122-41eb-99a2-c41f7122ad95-29fc9a27-99fc-498c-ab8f-0c7e084bb6ce-ab55af1d-c9e8-4c9c-920d-682ea39ff8dc'
                $Destination = (Join-Path $TestDrive $script:TestGuid)
                $Destination = $Destination + "\$LongName\$LongName\$LongName\Destination"

                $resourceCurrentState.Ensure | Should -Be 'Present'
                $resourceCurrentState.Path | Should -Be (Join-Path $TestDrive "$script:TestGuid\TestLongPath.zip")
                $resourceCurrentState.Destination | Should -Be $Destination
            }

            It 'Should return $true when Test-DscConfiguration is run' {
                Test-DscConfiguration -Verbose:$script:ShowDscVerboseMsg | Should -Be $true
            }

            It 'Should be expanded archive to destination' {
                $LongName = 'a4cffe08-444f-4e4e-8ec1-79b91b9f803e-5e4fc109-dbd2-4f29-bbcc-8722304c397e-9280fbca-4aa6-4f02-bd94-fd5742f0a34f-1658b2e4-8122-41eb-99a2-c41f7122ad95-29fc9a27-99fc-498c-ab8f-0c7e084bb6ce-ab55af1d-c9e8-4c9c-920d-682ea39ff8dc'
                $Destination = (Join-Path $TestDrive $script:TestGuid)
                $Destination = $Destination + "\$LongName\$LongName\$LongName\Destination"
                if ($PSVersionTable.PSVersion.Major -lt 6) {
                    $Destination = '\\?\' + $Destination
                }
                Test-Path -LiteralPath $Destination | Should -Be $true
                $item = Get-Item -LiteralPath ($Destination + '\Hello Archive.txt')
                Get-Content -LiteralPath $item -Raw | Should -Be 'Hello Archive!'
            }
        }
    }
    #endregion

}
finally {
    Restore-TestEnvironment -ModuleRoot $script:moduleRoot -ModuleName $script:moduleName
}
