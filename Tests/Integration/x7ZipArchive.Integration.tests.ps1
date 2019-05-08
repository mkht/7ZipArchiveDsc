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
                $item.LastWriteTime.ToString('s') | Should -Be '2018-08-09T00:02:18'
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
    }
    #endregion

}
finally {
    Restore-TestEnvironment -ModuleRoot $script:moduleRoot -ModuleName $script:moduleName
}
