#region HEADER
# Requires Pester 4.2.0 or higher
$newestPesterVersion = [System.Version]((Get-Module Pester -ListAvailable).Version | Sort-Object -Descending | Select-Object -First 1)
if ($newestPesterVersion -lt '4.2.0') { throw "Pester 4.2.0 or higher is required." }

$script:moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $script:moduleRoot '\DSCResources\x7ZipArchive\x7ZipArchive.psm1') -Force
$global:TestData = Join-Path (Split-Path -Parent $PSScriptRoot) '\TestData'
#endregion HEADER

#region Begin Testing
InModuleScope 'x7ZipArchive' {
    #region Set variables for testing
    $script:TestGuid = [Guid]::NewGuid()
    $testUsername = 'TestUsername'
    $testPassword = 'TestPassword'
    $secureTestPassword = ConvertTo-SecureString -String $testPassword -AsPlainText -Force
    $script:TestCredential = New-Object -TypeName 'System.Management.Automation.PSCredential' -ArgumentList @( $testUsername, $secureTestPassword )
    #endregion Set variables for testing


    #region Tests for Get-TargetResource
    Describe 'x7ZipArchive/Get-TargetResource' -Tag 'Unit' {

        BeforeAll {
            Copy-Item -Path $global:TestData -Destination "TestDrive:\$script:TestGuid" -Recurse -Force
            $ErrorActionPreference = 'Stop'
        }

        Context 'エラーパターン' {

            It '指定されたアーカイブパスが存在しない場合は例外発生' {
                $PathNotExist = 'TestDrive:\NotExist\Nothing.zip'
                $PathOfDestination = "TestDrive:\$script:TestGuid\Destination"

                $getParam = @{
                    Path        = $PathNotExist
                    Destination = $PathOfDestination
                }

                { Get-TargetResource @getParam } | Should -Throw "The path $PathNotExist does not exist or is not a file"
            }

            It '指定されたアーカイブパスが存在するが、ファイルではなくフォルダの場合は例外発生' {
                $PathOfFolder = "TestDrive:\$script:TestGuid\Folder"
                $PathOfDestination = "TestDrive:\$script:TestGuid\Destination"
                New-Item -Path $PathOfFolder -ItemType Container -ErrorAction SilentlyContinue >$null

                $getParam = @{
                    Path        = $PathOfFolder
                    Destination = $PathOfDestination
                }

                { Get-TargetResource @getParam } | Should -Throw "The path $PathOfFolder does not exist or is not a file"
            }

            It 'Checksumが指定されているが、ValidateがFalseの場合は例外発生' {
                $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                $PathOfDestination = "TestDrive:\$script:TestGuid\Destination"

                $getParam = @{
                    Path        = $PathOfArchive
                    Destination = $PathOfDestination
                    Validate    = $false
                    Checksum    = 'ModifiedDate'
                }

                { Get-TargetResource @getParam } | Should -Throw "Please specify the Validate parameter as true to use the Checksum parameter."
            }


            It 'Test-ArchiveExistsAtDestinationで例外発生した場合は例外発生' {
                Mock Test-ArchiveExistsAtDestination -MockWith { throw 'Exception' }
                $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                $PathOfDestination = "TestDrive:\$script:TestGuid\Destination"

                $getParam = @{
                    Path        = $PathOfArchive
                    Destination = $PathOfDestination
                }

                { Get-TargetResource @getParam } | Should -Throw
                Assert-MockCalled -CommandName 'Test-ArchiveExistsAtDestination' -Times 1 -Exactly -Scope It
            }
        }

        Context '正しいアーカイブパスと展開先が指定されている場合' {

            Context '展開先にアーカイブが展開されていない場合' {

                Mock Test-ArchiveExistsAtDestination { return $false }

                $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                $PathOfEmptyFolder = "TestDrive:\$script:TestGuid\EmptyFolder"
                New-Item -Path $PathOfEmptyFolder -ItemType Container >$null

                It 'EnsureプロパティがAbsentのHashTableを返す' {
                    $getParam = @{
                        Path        = $PathOfArchive
                        Destination = $PathOfEmptyFolder
                    }

                    $result = Get-TargetResource @getParam

                    Assert-MockCalled -CommandName 'Test-ArchiveExistsAtDestination' -Times 1 -Scope It
                    $result | Should -BeOfType 'HashTable'
                    $result.Ensure | Should -Be 'Absent'
                    $result.Path | Should -Be $PathOfArchive
                    $result.Destination | Should -Be $PathOfEmptyFolder
                }
            }

            Context '展開先にアーカイブが展開済みの場合' {

                Mock Test-ArchiveExistsAtDestination { return $true } -ParameterFilter { -not $Checksum }
                Mock Test-ArchiveExistsAtDestination { return $true } -ParameterFilter { $IgnoreRoot }
                Mock Test-ArchiveExistsAtDestination { return $true } -ParameterFilter { $Checksum -eq 'ModifiedDate' }
                Mock Test-ArchiveExistsAtDestination { return $false } -ParameterFilter { $Checksum -eq 'Size' }
                Mock Test-ArchiveExistsAtDestination { return $false }

                Mock Mount-PSDriveWithCredential { @{Name = 'drivename' } } -ParameterFilter { $Credential -and ($Credential.UserName -eq $script:TestCredential.UserName) }
                Mock UnMount-PSDrive { }

                BeforeAll {
                    $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    $PathOfAlreadyExpanded = "TestDrive:\$script:TestGuid\AlreadyExpanded"
                    New-Item $PathOfAlreadyExpanded -ItemType Container >$null
                    # Expand-Archive -Path $PathOfArchive -DestinationPath $PathOfAlreadyExpanded -Force
                }

                Context 'Validateが指定されていない場合' {
                    $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    $PathOfAlreadyExpanded = "TestDrive:\$script:TestGuid\AlreadyExpanded"

                    It 'EnsureプロパティがPresentのHashTableを返す' {
                        $getParam = @{
                            Path        = $PathOfArchive
                            Destination = $PathOfAlreadyExpanded
                        }

                        $result = Get-TargetResource @getParam

                        Assert-MockCalled -CommandName 'Test-ArchiveExistsAtDestination' -Times 1 -Scope It

                        $result.Ensure | Should -Be 'Present'
                        $result.Path | Should -Be $PathOfArchive
                        $result.Destination | Should -Be $PathOfAlreadyExpanded
                    }

                    It 'EnsureプロパティがPresentのHashTableを返す (IgnoreRoot指定あり）' {
                        $getParam = @{
                            Path        = $PathOfArchive
                            Destination = $PathOfAlreadyExpanded
                            IgnoreRoot  = $true
                        }

                        $result = Get-TargetResource @getParam

                        Assert-MockCalled -CommandName 'Test-ArchiveExistsAtDestination' -ParameterFilter { $IgnoreRoot } -Times 1 -Scope It

                        $result.Ensure | Should -Be 'Present'
                        $result.Path | Should -Be $PathOfArchive
                        $result.Destination | Should -Be $PathOfAlreadyExpanded
                    }

                    It 'EnsureプロパティがPresentのHashTableを返す (Credential指定あり、アーカイブへアクセス可）' {
                        $getParam = @{
                            Path        = $PathOfArchive
                            Destination = $PathOfAlreadyExpanded
                            Credential  = $script:TestCredential
                        }

                        $result = Get-TargetResource @getParam

                        Assert-MockCalled -CommandName 'Test-ArchiveExistsAtDestination' -Times 1 -Scope It
                        Assert-MockCalled -CommandName 'Mount-PSDriveWithCredential' -Times 1 -Exactly -Scope It
                        Assert-MockCalled -CommandName 'UnMount-PSDrive' -Times 1 -Exactly -Scope It

                        $result.Ensure | Should -Be 'Present'
                        $result.Path | Should -Be $PathOfArchive
                        $result.Destination | Should -Be $PathOfAlreadyExpanded
                    }

                    It '例外発生 (Credential指定あり、アーカイブへアクセス不可）' {
                        $PathNotExist = 'TestDrive:\NotExist\Nothing.zip'
                        $getParam = @{
                            Path        = $PathNotExist
                            Destination = $PathOfAlreadyExpanded
                            Credential  = $script:TestCredential
                        }

                        { Get-TargetResource @getParam } | Should -Throw ('The path {0} does not exist or is not a file' -f $PathNotExist)

                        Assert-MockCalled -CommandName 'Mount-PSDriveWithCredential' -ParameterFilter { $Credential -and ($Credential.UserName -eq $script:TestCredential.UserName) } -Times 1 -Exactly -Scope It
                        Assert-MockCalled -CommandName 'Test-ArchiveExistsAtDestination' -Times 0 -Scope It
                    }
                }

                Context 'Validateが指定されている場合' {

                    It '検証をパスした場合、EnsureプロパティがPresentのHashTableを返す' {
                        $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                        $PathOfAlreadyExpanded = "TestDrive:\$script:TestGuid\AlreadyExpanded"

                        $getParam = @{
                            Path        = $PathOfArchive
                            Destination = $PathOfAlreadyExpanded
                            Validate    = $true
                            Checksum    = 'ModifiedDate'
                        }

                        $result = Get-TargetResource @getParam

                        Assert-MockCalled -CommandName 'Test-ArchiveExistsAtDestination' -Times 1 -Scope It

                        $result.Ensure | Should -Be 'Present'
                        $result.Path | Should -Be $PathOfArchive
                        $result.Destination | Should -Be $PathOfAlreadyExpanded
                    }

                    It '検証をパスしない場合、EnsureプロパティがAbsentのHashTableを返す' {
                        $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                        $PathOfAlreadyExpanded = "TestDrive:\$script:TestGuid\AlreadyExpanded"
                        $getParam = @{
                            Path        = $PathOfArchive
                            Destination = $PathOfAlreadyExpanded
                            Validate    = $true
                            Checksum    = 'Size'
                        }

                        $result = Get-TargetResource @getParam

                        Assert-MockCalled -CommandName 'Test-ArchiveExistsAtDestination' -Times 1 -Scope It

                        $result.Ensure | Should -Be 'Absent'
                        $result.Path | Should -Be $PathOfArchive
                        $result.Destination | Should -Be $PathOfAlreadyExpanded
                    }
                }
            }
        }
    }
    #endregion Tests for Get-TargetResource


    #region Tests for Test-TargetResource
    Describe 'x7ZipArchive/Test-TargetResource' -Tag 'Unit' {

        Context 'Get-TargetResourceの返すHashTableのEnsureプロパティがPresentの場合' {

            Mock Get-TargetResource { return @{Ensure = 'Present' } }

            It 'Trueを返す' {
                $testParam = @{
                    Ensure      = 'Present'
                    Path        = 'PathOfArchive'
                    Destination = 'PathOfDestination'
                }

                Test-TargetResource @testParam | Should -Be $true
                Assert-MockCalled -CommandName 'Get-TargetResource' -Exactly -Times 1 -Scope It
            }
        }


        Context 'Get-TargetResourceの返すHashTableのEnsureプロパティがAbsentの場合' {

            Mock Get-TargetResource { return @{Ensure = 'Absent' } }

            It 'Falseを返す' {
                $testParam = @{
                    Ensure      = 'Present'
                    Path        = 'PathOfArchive'
                    Destination = 'PathOfDestination'
                }

                Test-TargetResource @testParam | Should -Be $false
                Assert-MockCalled -CommandName 'Get-TargetResource' -Exactly -Times 1 -Scope It
            }
        }
    }
    #endregion Tests for Test-TargetResource


    #region Tests for Set-TargetResource
    Describe 'x7ZipArchive/Set-TargetResource' -Tag 'Unit' {

        Mock Expand-7ZipArchive -MockWith { } -ParameterFilter { $IgnoreRoot }
        Mock Expand-7ZipArchive -MockWith { } -ParameterFilter { $Force -eq $false }
        Mock Expand-7ZipArchive -MockWith { }

        BeforeAll {
            Copy-Item -Path $global:TestData -Destination "TestDrive:\$script:TestGuid" -Recurse -Force
            $ErrorActionPreference = 'Stop'
        }

        Context 'エラーパターン' {

            It '指定されたアーカイブパスが存在しない場合は例外発生' {
                $PathNotExist = 'TestDrive:\NotExist\Nothing.zip'
                $PathOfDestination = "TestDrive:\$script:TestGuid\Destination"

                $SetParam = @{
                    Path        = $PathNotExist
                    Destination = $PathOfDestination
                }

                { Set-TargetResource @SetParam } | Should -Throw "The path $PathNotExist does not exist or is not a file"
            }

            It '指定されたアーカイブパスが存在するが、ファイルではなくフォルダの場合は例外発生' {
                $PathOfFolder = "TestDrive:\$script:TestGuid\Folder"
                $PathOfDestination = "TestDrive:\$script:TestGuid\Destination"
                New-Item -Path $PathOfFolder -ItemType Container >$null

                $SetParam = @{
                    Path        = $PathOfFolder
                    Destination = $PathOfDestination
                }

                { Set-TargetResource @SetParam } | Should -Throw "The path $PathOfFolder does not exist or is not a file"
            }

            It 'Checksumが指定されているが、ValidateがFalseの場合は例外発生' {
                $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                $PathOfDestination = "TestDrive:\$script:TestGuid\Destination"

                $SetParam = @{
                    Path        = $PathOfArchive
                    Destination = $PathOfDestination
                    Validate    = $false
                    Checksum    = 'ModifiedDate'
                }

                { Set-TargetResource @SetParam } | Should -Throw "Please specify the Validate parameter as true to use the Checksum parameter."
            }

            Mock Expand-7ZipArchive -MockWith { throw 'Exception' }

            It 'Expand-7ZipArchiveで例外が発生した場合は例外発生' {
                $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                $PathOfDestination = "TestDrive:\$script:TestGuid\Destination"

                $SetParam = @{
                    Path        = $PathOfArchive
                    Destination = $PathOfDestination
                }

                { Set-TargetResource @SetParam } | Should -Throw "Exception"
                Assert-MockCalled -CommandName 'Expand-7ZipArchive' -Times 1 -Exactly -Scope It
            }
        }

        Context 'アーカイブ展開' {

            $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
            $PathOfDestination = "TestDrive:\$script:TestGuid\Destination"

            It '展開先フォルダにアーカイブを展開する' {
                $setParam = @{
                    Path        = $PathOfArchive
                    Destination = $PathOfDestination
                }

                { Set-TargetResource @setParam } | Should -Not -Throw
                Assert-MockCalled -CommandName 'Expand-7ZipArchive' -Times 1 -Scope It
            }

            It '展開先フォルダにアーカイブを展開する (IgnoreRoot指定あり)' {
                $setParam = @{
                    Path        = $PathOfArchive
                    Destination = $PathOfDestination
                    IgnoreRoot  = $true
                }

                { Set-TargetResource @setParam } | Should -Not -Throw
                Assert-MockCalled -CommandName 'Expand-7ZipArchive' -ParameterFilter { $IgnoreRoot } -Times 1 -Scope It
            }
        }
    }
    #endregion Tests for Set-TargetResource


    #region Tests for Get-7ZipArchive
    Describe 'x7ZipArchive/Get-7ZipArchive' -Tag 'Unit' {

        BeforeAll {
            Copy-Item -Path $global:TestData -Destination "TestDrive:\$script:TestGuid" -Recurse -Force
            $ErrorActionPreference = 'Stop'
        }

        Context 'エラーパターン' {

            It 'アーカイブパスが存在しない場合は例外発生' {
                $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'NotExist.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                { Get-7ZipArchive -Path $PathOfArchive } | Should -Throw -ExceptionType ([System.IO.FileNotFoundException])
            }

            It 'アーカイブパスがファイルでない場合は例外発生' {
                $PathOfFolder = (Join-Path "TestDrive:\$script:TestGuid" 'Folder.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                New-Item $PathOfFolder -ItemType Directory -Force >$null

                { Get-7ZipArchive -Path $PathOfFolder } | Should -Throw -ExceptionType ([System.IO.FileNotFoundException])
            }

            It '指定されたファイルがアーカイブファイルでない場合は例外発生' {
                $PathOfInvalidArchive = (Join-Path "TestDrive:\$script:TestGuid" 'InvalidZIP.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                'This is not an Archive' | Out-File -FilePath (Join-Path "TestDrive:\$script:TestGuid" 'InvalidZIP.zip')

                { Get-7ZipArchive -Path $PathOfInvalidArchive } | Should -Throw -ExceptionType ([System.ArgumentException])
            }
        }

        Context 'ZIPファイルリスト取得' {

            Context 'ファイル一つのみを含むアーカイブ' {
                It '出力はPath, Size, ItemType, Modified, CRCプロパティを含むこと' {
                    $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'OnlyOneFile.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)

                    $Result = (Get-7ZipArchive -Path $PathOfArchive).FileList

                    $Result.Path | Should -Be 'Hello Archive.txt'
                    $Result.Size | Should -BeOfType 'int'
                    $Result.Size | Should -Be 14
                    $Result.ItemType | Should -Be 'File'
                    $Result.Modified | Should -BeOfType 'DateTime'
                    $Result.Modified.ToUniversalTime().toString('s') | Should -Be '2018-08-08T15:02:18'
                    $Result.CRC | Should -BeOfType 'string'
                    $Result.CRC | Should -Be '9E5F60BB'
                }
            }

            Context '複数のファイル/フォルダを含むアーカイブ' {

                It 'アーカイブ内のファイルリストを取得' {
                    $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'TestHasRoot.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)

                    $Result = (Get-7ZipArchive -Path $PathOfArchive).FileList

                    $Result | Should -HaveCount 5
                    $Result | Where-Object { $_.ItemType -eq 'File' } | Should -HaveCount 3
                    $Result | Where-Object { $_.ItemType -eq 'Folder' } | Should -HaveCount 2

                    $ContentInResult = $Result | Where-Object { $_.Path -match '002.txt' }
                    $ContentInResult.Path | Should -Be 'root\Folder\002.txt'
                    $ContentInResult.Size | Should -BeOfType 'int'
                    $ContentInResult.Size | Should -Be 6
                    $ContentInResult.ItemType | Should -Be 'File'
                    $ContentInResult.Modified | Should -BeOfType 'DateTime'
                    $ContentInResult.Modified.ToUniversalTime().toString('s') | Should -Be '2018-08-08T15:02:51'
                    $ContentInResult.CRC | Should -BeOfType 'string'
                    $ContentInResult.CRC | Should -Be 'E448FDFB'
                }
            }
        }

        Context '7zファイル' {

            It 'アーカイブ内のファイルリストを取得' {
                $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'TestHasRoot.7z').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)

                $Result = (Get-7ZipArchive -Path $PathOfArchive).FileList

                $Result | Should -HaveCount 5
                $Result | Where-Object { $_.ItemType -eq 'File' } | Should -HaveCount 3
                $Result | Where-Object { $_.ItemType -eq 'Folder' } | Should -HaveCount 2
            }
        }

    }
    #endregion Tests for Get-7ZipArchive


    #region Tests for Test-ArchiveExistsAtDestination
    Describe 'x7ZipArchive/Test-ArchiveExistsAtDestination' -Tag 'Unit' {

        BeforeAll {
            Copy-Item -Path $global:TestData -Destination "TestDrive:\$script:TestGuid" -Recurse -Force
            $ErrorActionPreference = 'Stop'
        }

        Context 'エラーパターン' {

            Mock Get-7ZipArchive -MockWith { throw '7ZipArchive Exception' }

            It 'Get-7ZipArchiveで例外発生した場合は例外発生' {
                $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                New-Item $Destination -ItemType Directory -Force >$null
                'ABC' | Out-File (Join-Path $Destination 'test.txt')

                { Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination } | Should -Throw
                Assert-MockCalled -CommandName 'Get-7ZipArchive' -Times 1 -Scope It
            }
        }

        Context '展開先フォルダが存在しないか空フォルダの場合' {

            It '展開先フォルダが存在しない場合はFalseを返す' {
                $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                $PathOfNotExist = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)

                $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $PathOfNotExist
                $Result | Should -BeOfType 'bool'
                $Result | Should -Be $false
            }

            It '展開先フォルダが空フォルダの場合はFalseを返す' {
                $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                $PathOfEmptyFolder = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                New-Item $PathOfEmptyFolder -ItemType Directory -Force >$null

                $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $PathOfEmptyFolder
                $Result | Should -BeOfType 'bool'
                $Result | Should -Be $false
            }
        }

        Context '展開先フォルダが空ではない場合' {

            Mock Get-7ZipArchive -MockWith {
                @{
                    FileList = @(
                        [PsCustomObject]@{
                            ItemType = 'File'
                            Modified = [Datetime]::Parse('2018-08-09 00:02:36')
                            Size     = 3
                            CRC      = '55B20A4B'
                            Path     = '001.txt'
                        }
                    )
                }
            } -ParameterFilter { $Path -eq ((Join-Path "TestDrive:\$script:TestGuid" 'SingleFile.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)) }

            Mock Get-7ZipArchive -MockWith {
                @{
                    FileList = @(
                        [PsCustomObject]@{
                            ItemType = 'File'
                            Modified = [Datetime]::Parse('2018-08-09 00:02:36')
                            Size     = 3
                            CRC      = '55B20A4B'
                            Path     = '001.txt'
                        },

                        [PsCustomObject]@{
                            ItemType = 'Folder'
                            Modified = [Datetime]::Parse('2018-08-09 09:21:12')
                            Size     = 0
                            CRC      = ''
                            Path     = 'Folder'
                        },

                        [PsCustomObject]@{
                            ItemType = 'File'
                            Modified = [Datetime]::Parse('2018-08-09 10:05:49')
                            Size     = 10
                            CRC      = 'E448FDFB'
                            Path     = 'Folder\002.txt'
                        }
                    )
                }
            } -ParameterFilter { $Path -eq ((Join-Path "TestDrive:\$script:TestGuid" 'MultiFile.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)) }

            Mock Get-7ZipArchive -MockWith { throw 'IgnoreRoot specified' } -ParameterFilter { $IgnoreRoot }

            Context 'Validateなし' {

                It '展開先フォルダにアーカイブ内のファイルとは異なるファイルのみが存在する場合はFalseを返す' {
                    $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'MultiFile.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    New-Item $Destination -ItemType Directory -Force >$null
                    '100' | Out-File (Join-Path $Destination '100.txt')

                    $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination

                    Assert-MockCalled -CommandName 'Get-7ZipArchive' -Times 1 -Scope It
                    $Result | Should -BeOfType 'bool'
                    $Result | Should -Be $false
                }

                It '展開先フォルダにアーカイブ内のファイルの一部しか存在しない場合はFalseを返す' {
                    $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'MultiFile.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    New-Item $Destination -ItemType Directory -Force >$null
                    New-Item (Join-Path $Destination 'Folder') -ItemType Directory -Force >$null
                    '001' | Out-File (Join-Path $Destination '001.txt')

                    $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination

                    Assert-MockCalled -CommandName 'Get-7ZipArchive' -Times 1 -Scope It
                    $Result | Should -BeOfType 'bool'
                    $Result | Should -Be $false
                }

                It '展開先フォルダ内のファイルとアーカイブ内のファイルが一致する場合はTrueを返す' {
                    $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'MultiFile.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    New-Item $Destination -ItemType Directory -Force >$null
                    New-Item (Join-Path $Destination 'Folder') -ItemType Directory -Force >$null
                    '001' | Out-File (Join-Path $Destination '001.txt')
                    '002' | Out-File (Join-Path $Destination '\Folder\002.txt')

                    $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination

                    Assert-MockCalled -CommandName 'Get-7ZipArchive' -Times 1 -Scope It
                    $Result | Should -BeOfType 'bool'
                    $Result | Should -Be $true
                }

                It 'Cleanなしの場合、展開先フォルダにアーカイブ内のファイルが全て存在する場合は他に無関係なファイルが存在していたとしてもTrueを返す' {
                    $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'MultiFile.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    New-Item $Destination -ItemType Directory -Force >$null
                    New-Item (Join-Path $Destination 'Folder') -ItemType Directory -Force >$null
                    '001' | Out-File (Join-Path $Destination '001.txt')
                    '002' | Out-File (Join-Path $Destination '\Folder\002.txt')
                    '003' | Out-File (Join-Path $Destination '003.txt')

                    $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination

                    Assert-MockCalled -CommandName 'Get-7ZipArchive' -Times 1 -Scope It
                    $Result | Should -BeOfType 'bool'
                    $Result | Should -Be $true
                }

                It 'Cleanありの場合、展開先フォルダの既存ファイル数とアーカイブ内のファイル数が一致しないときにFalseを返す' {
                    $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'MultiFile.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    New-Item $Destination -ItemType Directory -Force >$null
                    New-Item (Join-Path $Destination 'Folder') -ItemType Directory -Force >$null
                    '001' | Out-File (Join-Path $Destination '001.txt')
                    '002' | Out-File (Join-Path $Destination '\Folder\002.txt')
                    '003' | Out-File (Join-Path $Destination '003.txt')

                    $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination -Clean

                    Assert-MockCalled -CommandName 'Get-7ZipArchive' -Times 1 -Scope It
                    $Result | Should -BeOfType 'bool'
                    $Result | Should -Be $false
                }

                It 'Cleanありの場合、展開先フォルダにアーカイブ内のファイルが全て存在し、他に無関係なファイルが存在しない場合にのみTrueを返す' {
                    $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'MultiFile.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    New-Item $Destination -ItemType Directory -Force >$null
                    New-Item (Join-Path $Destination 'Folder') -ItemType Directory -Force >$null
                    '001' | Out-File (Join-Path $Destination '001.txt')
                    '002' | Out-File (Join-Path $Destination '\Folder\002.txt')

                    $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination -Clean

                    Assert-MockCalled -CommandName 'Get-7ZipArchive' -Times 1 -Scope It
                    $Result | Should -BeOfType 'bool'
                    $Result | Should -Be $true
                }
            }

            Context 'Validateあり' {

                It 'ChecksumにModifiedDateが指定されている場合で、展開先フォルダ内のファイルとアーカイブ内のファイルの更新日時が一致しない場合はFalseを返す' {
                    $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'SingleFile.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    New-Item $Destination -ItemType Directory -Force >$null
                    '001' | Out-File (Join-Path $Destination '001.txt')
                    Set-ItemProperty (Join-Path $Destination '001.txt') -Name LastWriteTime -Value '2018-08-10 00:02:36'

                    $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination -Checksum 'ModifiedDate'

                    Assert-MockCalled -CommandName 'Get-7ZipArchive' -Times 1 -Scope It
                    $Result | Should -BeOfType 'bool'
                    $Result | Should -Be $false
                }

                It 'ChecksumにModifiedDateが指定されている場合で、展開先フォルダ内のファイルとアーカイブ内のファイルの更新日時が一致する場合はTrueを返す' {
                    $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'SingleFile.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    New-Item $Destination -ItemType Directory -Force >$null
                    '001' | Out-File (Join-Path $Destination '001.txt')
                    Set-ItemProperty (Join-Path $Destination '001.txt') -Name LastWriteTime -Value '2018-08-09 00:02:36.12'

                    $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination -Checksum 'ModifiedDate'

                    Assert-MockCalled -CommandName 'Get-7ZipArchive' -Times 1 -Scope It
                    $Result | Should -BeOfType 'bool'
                    $Result | Should -Be $true
                }

                It 'ChecksumにSizeが指定されている場合で、展開先フォルダ内のファイルとアーカイブ内のファイルのサイズが一致しない場合はFalseを返す' {
                    $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'SingleFile.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    New-Item $Destination -ItemType Directory -Force >$null
                    '0011' | Out-File (Join-Path $Destination '001.txt') -Encoding ascii -NoNewline

                    $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination -Checksum 'Size'

                    Assert-MockCalled -CommandName 'Get-7ZipArchive' -Times 1 -Scope It
                    $Result | Should -BeOfType 'bool'
                    $Result | Should -Be $false
                }

                It 'ChecksumにSizeが指定されている場合で、展開先フォルダ内のファイルとアーカイブ内のファイルのサイズが一致する場合はTrueを返す' {
                    $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'SingleFile.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    New-Item $Destination -ItemType Directory -Force >$null
                    '123' | Out-File (Join-Path $Destination '001.txt') -Encoding ascii -NoNewline

                    $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination -Checksum 'Size'

                    Assert-MockCalled -CommandName 'Get-7ZipArchive' -Times 1 -Scope It
                    $Result | Should -BeOfType 'bool'
                    $Result | Should -Be $true
                }

                It 'ChecksumにCRCが指定されている場合で、展開先フォルダ内のファイルとアーカイブ内のファイルのCRCが一致しない場合はFalseを返す' {
                    $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'SingleFile.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    New-Item $Destination -ItemType Directory -Force >$null
                    '010' | Out-File (Join-Path $Destination '001.txt') -Encoding ascii -NoNewline

                    $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination -Checksum 'CRC'

                    Assert-MockCalled -CommandName 'Get-7ZipArchive' -Times 1 -Scope It
                    $Result | Should -BeOfType 'bool'
                    $Result | Should -Be $false
                }

                It 'ChecksumにCRCが指定されている場合で、展開先フォルダ内のファイルとアーカイブ内のファイルのCRCが一致する場合はTrueを返す' {
                    $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'SingleFile.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    New-Item $Destination -ItemType Directory -Force >$null
                    '001' | Out-File (Join-Path $Destination '001.txt') -Encoding ascii -NoNewline

                    $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination -Checksum 'CRC'

                    Assert-MockCalled -CommandName 'Get-7ZipArchive' -Times 1 -Scope It
                    $Result | Should -BeOfType 'bool'
                    $Result | Should -Be $true
                }

                It 'ChecksumにCRCが指定されている場合で、アーカイブ内に空ファイルが含まれている場合でも正常にTrueを返す (Fixed issue in 2019-12-14)' {
                    $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'HasEmptyFile.7z').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                    New-Item $Destination -ItemType Directory -Force >$null
                    New-Item (Join-Path $Destination 'empty') -ItemType File -Force >$null
                    'ABC' | Out-File (Join-Path $Destination 'text.txt') -Encoding utf8 -NoNewline

                    $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination -Checksum 'CRC'

                    $Result | Should -BeOfType 'bool'
                    $Result | Should -Be $true
                }
            }
        }
    }
    #endregion Tests for Test-ArchiveExistsAtDestination


    #region Tests for Expand-7ZipArchive
    Describe 'x7ZipArchive/Expand-7ZipArchive' -Tag 'Unit' {

        BeforeAll {
            Copy-Item -Path $global:TestData -Destination "TestDrive:\$script:TestGuid" -Recurse -Force
            $ErrorActionPreference = 'Stop'
        }

        Context 'エラーパターン' {

            It 'アーカイブパスが存在しない場合は例外発生' {
                $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'NotExist.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)

                { Expand-7ZipArchive -Path $PathOfArchive -Destination $Destination } | Should -Throw -ExceptionType ([System.IO.FileNotFoundException])
                Test-Path -Path $Destination | Should -Be $false
            }

            It 'アーカイブパスがファイルでない場合は例外発生' {
                $PathOfFolder = (Join-Path "TestDrive:\$script:TestGuid" 'Folder.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                New-Item $PathOfFolder -ItemType Directory -Force >$null
                $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)

                { Expand-7ZipArchive -Path $PathOfFolder -Destination $Destination } | Should -Throw -ExceptionType ([System.IO.FileNotFoundException])
                Test-Path -Path $Destination | Should -Be $false
            }

            It '指定されたファイルがアーカイブファイルでない場合は例外発生' {
                $PathOfInvalidArchive = (Join-Path "TestDrive:\$script:TestGuid" 'InvalidZIP.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                'This is not an Archive' | Out-File -FilePath (Join-Path "TestDrive:\$script:TestGuid" 'InvalidZIP.zip')
                $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)

                { Expand-7ZipArchive -Path $PathOfInvalidArchive -Destination $Destination } | Should -Throw -ExceptionType ([System.ArgumentException])
                Test-Path -Path $Destination | Should -Be $false
            }

            It 'IgnoreRootが指定されている場合で、アーカイブにひとつの"ファイル"のみが含まれる場合は例外発生' {
                $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'OnlyOneFile.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)

                { Expand-7ZipArchive -Path $PathOfArchive -Destination $Destination -IgnoreRoot } | Should -Throw "Archive has no item or only one file in the root. You can't use IgnoreRoot option."
                Test-Path -Path $Destination | Should -Be $false
            }

            It 'IgnoreRootが指定されている場合で、アーカイブのルートに複数のファイル/フォルダが含まれる場合は例外発生' {
                $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)

                { Expand-7ZipArchive -Path $PathOfArchive -Destination $Destination -IgnoreRoot } | Should -Throw "Archive has multiple items in the root. You can't use IgnoreRoot option."
                Test-Path -Path $Destination | Should -Be $false
            }
        }


        Context 'ZIPファイル展開' {

            It '展開先フォルダが存在しない場合、フォルダを作成してその中に展開する' {
                $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'OnlyOneFile.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)

                { Expand-7ZipArchive -Path $PathOfArchive -Destination $Destination } | Should -Not -Throw
                Test-Path -Path $Destination -PathType Container | Should -Be $true
                Get-ChildItem -Path $Destination -Recurse -Force | Should -HaveCount 1
                Test-Path -Path (Join-Path $Destination 'Hello Archive.txt') -PathType Leaf | Should -Be $true
                Get-Content -Path (Join-Path $Destination 'Hello Archive.txt') -Raw | Should -Be 'Hello Archive!'
            }

            It '展開先フォルダにアーカイブ内のファイルと異なるファイルが存在する場合、そのファイルは残したまま展開する (Clean指定なしの場合）' {
                $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'OnlyOneFile.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                New-Item $Destination -ItemType Directory -Force >$null
                '100' | Out-File (Join-Path $Destination '100.txt')

                { Expand-7ZipArchive -Path $PathOfArchive -Destination $Destination } | Should -Not -Throw
                Get-ChildItem -Path $Destination -Recurse -Force | Should -HaveCount 2
                Test-Path -Path (Join-Path $Destination 'Hello Archive.txt') -PathType Leaf | Should -Be $true
                Get-Content -Path (Join-Path $Destination 'Hello Archive.txt') -Raw | Should -Be 'Hello Archive!'
                Test-Path -Path (Join-Path $Destination '100.txt') -PathType Leaf | Should -Be $true
            }

            It 'Clean指定ありの場合、展開前に展開先フォルダ内のファイルを削除する' {
                $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'OnlyOneFile.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                New-Item $Destination -ItemType Directory -Force >$null
                '100' | Out-File (Join-Path $Destination '100.txt')

                { Expand-7ZipArchive -Path $PathOfArchive -Destination $Destination -Clean } | Should -Not -Throw
                Get-ChildItem -Path $Destination -Recurse -Force | Should -HaveCount 1
                Test-Path -Path (Join-Path $Destination 'Hello Archive.txt') -PathType Leaf | Should -Be $true
                Get-Content -Path (Join-Path $Destination 'Hello Archive.txt') -Raw | Should -Be 'Hello Archive!'
                Test-Path -Path (Join-Path $Destination '100.txt') -PathType Leaf | Should -Be $false
            }

            It 'IgnoreRootが指定されている場合、アーカイブのルートフォルダ内のファイルを展開先フォルダ内に展開する' {
                $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'TestHasRoot.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)

                { Expand-7ZipArchive -Path $PathOfArchive -Destination $Destination -IgnoreRoot } | Should -Not -Throw
                Test-Path -Path $Destination -PathType Container | Should -Be $true
                Get-ChildItem -Path $Destination -Recurse -Force | Should -HaveCount 4
                Test-Path -Path (Join-Path $Destination 'Hello Archive.txt') -PathType Leaf | Should -Be $true
                Test-Path -Path (Join-Path $Destination 'Folder') -PathType Container | Should -Be $true
                Test-Path -Path (Join-Path $Destination '\Folder\001.txt') -PathType Leaf | Should -Be $true
                Test-Path -Path (Join-Path $Destination '\Folder\002.txt') -PathType Leaf | Should -Be $true
            }
        }

        Context '7zファイル展開' {
            It '7zファイルも展開できること' {
                $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'TestHasRoot.7z').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)

                { Expand-7ZipArchive -Path $PathOfArchive -Destination $Destination } | Should -Not -Throw
                Test-Path -Path $Destination -PathType Container | Should -Be $true
                Get-ChildItem -Path $Destination -Recurse -Force | Should -HaveCount 5
                Test-Path -Path (Join-Path $Destination 'root') -PathType Container | Should -Be $true
                Test-Path -Path (Join-Path $Destination 'root\Hello Archive.txt') -PathType Leaf | Should -Be $true
                Test-Path -Path (Join-Path $Destination 'root\Folder') -PathType Container | Should -Be $true
                Test-Path -Path (Join-Path $Destination 'root\Folder\001.txt') -PathType Leaf | Should -Be $true
                Test-Path -Path (Join-Path $Destination 'root\Folder\002.txt') -PathType Leaf | Should -Be $true
            }
        }

        Context 'パイプライン入力、複数ファイル入力' {
            It 'パイプライン入力（リテラルパス）' {
                $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'OnlyOneFile.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)

                { $PathOfArchive | Expand-7ZipArchive -Destination $Destination } | Should -Not -Throw
                Test-Path -Path $Destination -PathType Container | Should -Be $true
                Get-ChildItem -Path $Destination -Recurse -Force | Should -HaveCount 1
                Test-Path -Path (Join-Path $Destination 'Hello Archive.txt') -PathType Leaf | Should -Be $true
                Get-Content -Path (Join-Path $Destination 'Hello Archive.txt') -Raw | Should -Be 'Hello Archive!'
            }

            It 'パイプライン入力（FileInfo）' {
                $PathOfArchive = (Join-Path "TestDrive:\$script:TestGuid" 'OnlyOneFile.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)

                { Get-Item -LiteralPath $PathOfArchive | Expand-7ZipArchive -Destination $Destination } | Should -Not -Throw
                Test-Path -Path $Destination -PathType Container | Should -Be $true
                Get-ChildItem -Path $Destination -Recurse -Force | Should -HaveCount 1
                Test-Path -Path (Join-Path $Destination 'Hello Archive.txt') -PathType Leaf | Should -Be $true
                Get-Content -Path (Join-Path $Destination 'Hello Archive.txt') -Raw | Should -Be 'Hello Archive!'
            }

            It '複数入力（パラメータ）' {
                $Items = @()
                $Items += (Join-Path "TestDrive:\$script:TestGuid" 'OnlyOneFile.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                $Items += (Join-Path "TestDrive:\$script:TestGuid" 'TestHasRoot.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)

                { Expand-7ZipArchive -Path $Items -Destination $Destination } | Should -Not -Throw
                Test-Path -Path $Destination -PathType Container | Should -Be $true
                Get-ChildItem -Path $Destination -Recurse -Force | Should -HaveCount 6
                Test-Path -Path (Join-Path $Destination 'Hello Archive.txt') -PathType Leaf | Should -Be $true
                Test-Path -Path (Join-Path $Destination 'root') -PathType Container | Should -Be $true
            }

            It '複数入力（パイプライン）' {
                $Items = @()
                $Items += (Join-Path "TestDrive:\$script:TestGuid" 'OnlyOneFile.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                $Items += (Join-Path "TestDrive:\$script:TestGuid" 'TestHasRoot.zip').Replace('TestDrive:', (Get-PSDrive TestDrive).Root)
                $Destination = (Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())).Replace('TestDrive:', (Get-PSDrive TestDrive).Root)

                { Get-Item -LiteralPath $Items | Expand-7ZipArchive -Destination $Destination } | Should -Not -Throw
                Test-Path -Path $Destination -PathType Container | Should -Be $true
                Get-ChildItem -Path $Destination -Recurse -Force | Should -HaveCount 6
                Test-Path -Path (Join-Path $Destination 'Hello Archive.txt') -PathType Leaf | Should -Be $true
                Test-Path -Path (Join-Path $Destination 'root') -PathType Container | Should -Be $true
            }
        }
    }
    #endregion Tests for Expand-7ZipArchive


    #region Tests for Get-CRC16Hash
    Describe 'x7ZipArchive/Get-CRC16Hash' -Tag 'Unit' {

        BeforeAll {
            $ErrorActionPreference = 'Stop'
        }

        It 'Pathに指定されたファイルが存在しない場合は例外' {
            Mock Test-Path { $false } -ParameterFilter { $LiteralPath -eq 'something' }

            { Get-CRC16Hash -Path 'something' } | Should -Throw -ExceptionType ([System.IO.FileNotFoundException])
            Assert-MockCalled -CommandName Test-Path -Times 1 -Scope It
        }

        It 'ファイルのCRC16を返却' {
            $TestFile = Join-Path $TestDrive 'test.txt'
            '001' | Out-File -FilePath $TestFile -Encoding ascii -NoNewline -Force

            Get-CRC16Hash -Path $TestFile | Should -Be '0000DBD5'
        }
    }
    #endregion Tests for Get-CRC16Hash


    #region Tests for Get-CRC32Hash
    Describe 'x7ZipArchive/Get-CRC32Hash' -Tag 'Unit' {

        BeforeAll {
            $ErrorActionPreference = 'Stop'
        }

        It 'Pathに指定されたファイルが存在しない場合は例外' {
            Mock Test-Path { $false } -ParameterFilter { $LiteralPath -eq 'something' }

            { Get-CRC32Hash -Path 'something' } | Should -Throw -ExceptionType ([System.IO.FileNotFoundException])
            Assert-MockCalled -CommandName Test-Path -Times 1 -Scope It
        }

        It 'ファイルのCRC32を返却' {
            $TestFile = Join-Path $TestDrive 'test.txt'
            '001' | Out-File -FilePath $TestFile -Encoding ascii -NoNewline -Force

            Get-CRC32Hash -Path $TestFile | Should -Be '55B20A4B'
        }
    }
    #endregion Tests for Get-CRC32Hash

    #region Tests for Mount-PSDriveWithCredential
    Describe 'x7ZipArchive/Mount-PSDriveWithCredential' -Tag 'Unit' {

        Mock New-PSDrive { return @{Name = $Name } }
        Mock UnMount-PSDrive { }

        BeforeAll {
            $ErrorActionPreference = 'Stop'
        }

        It 'Nameが指定されていない場合、適当なGuidでPSDriveをマウントする' {
            Mock Test-Path { $true }

            $Ret = Mount-PSDriveWithCredential -Root 'something' -Credential $script:TestCredential
            $Ret.Name | Should -Match '([A-Fa-f0-9]{8})\-([A-Fa-f0-9]{4})\-([A-Fa-f0-9]{4})\-([A-Fa-f0-9]{4})\-([A-Fa-f0-9]{12})'
            Assert-MockCalled -CommandName New-PSDrive -Times 1 -Scope It -Exactly
            Assert-MockCalled -CommandName Test-Path -Times 1 -Scope It -Exactly
            Assert-MockCalled -CommandName UnMount-PSDrive -Times 0 -Scope It -Exactly
        }

        It 'Nameが指定されている場合、その名前でPSDriveをマウントする' {
            Mock Test-Path { $true }

            $Ret = Mount-PSDriveWithCredential -Root 'something' -Name 'drivename' -Credential $script:TestCredential
            $Ret.Name | Should -Be 'drivename'
            Assert-MockCalled -CommandName New-PSDrive -Times 1 -Scope It -Exactly
            Assert-MockCalled -CommandName Test-Path -Times 1 -Scope It -Exactly
            Assert-MockCalled -CommandName UnMount-PSDrive -Times 0 -Scope It -Exactly
        }

        It '処理中に例外が発生した場合、UnMount-PSDriveを呼び出してから終了' {
            Mock Test-Path { throw 'Exception' }

            { Mount-PSDriveWithCredential -Root 'something' -Credential $script:TestCredential } | Should -Throw 'Exception'
            Assert-MockCalled -CommandName New-PSDrive -Times 1 -Scope It -Exactly
            Assert-MockCalled -CommandName Test-Path -Times 1 -Scope It -Exactly
            Assert-MockCalled -CommandName UnMount-PSDrive -Times 1 -Scope It -Exactly
        }
    }
    #endregion Tests for Mount-PSDriveWithCredential

    #region Tests for UnMount-PSDrive
    Describe 'x7ZipArchive/UnMount-PSDrive' -Tag 'Unit' {

        Mock Remove-PSDrive { }

        BeforeAll {
            $ErrorActionPreference = 'Stop'
        }

        It 'Nameが$nullの場合、何もせず終了' {
            { UnMount-PSDrive -Name $null } | Should -Not -Throw
            Assert-MockCalled -CommandName Remove-PSDrive -Times 0 -Scope It -Exactly
        }

        It 'Nameが空文字列の場合、何もせず終了' {
            { UnMount-PSDrive -Name ([string]::Empty) } | Should -Not -Throw
            Assert-MockCalled -CommandName Remove-PSDrive -Times 0 -Scope It -Exactly
        }

        It 'Nameが指定されている場合、Remove-PSDriveを実行' {
            { UnMount-PSDrive -Name 'foo' } | Should -Not -Throw
            Assert-MockCalled -CommandName Remove-PSDrive -Times 1 -Scope It -Exactly
        }
    }
    #endregion Tests for UnMount-PSDrive

}
#endregion End Testing
