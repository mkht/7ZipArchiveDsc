#region HEADER
# Requires Pester 4.2.0 or higher
$newestPesterVersion = [System.Version]((Get-Module Pester -ListAvailable).Version | Sort-Object -Descending | Select-Object -First 1)
if ($newestPesterVersion -lt '4.2.0') { throw "Pester 4.2.0 or higher is required." }

$script:moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $script:moduleRoot '\DSCResources\7ZipArchive\7ZipArchive.psm1') -Force
$global:TestData = Join-Path (Split-Path -Parent $PSScriptRoot) '\TestData'
#endregion HEADER

#region Begin Testing
InModuleScope '7ZipArchive' {
    #region Set variables for testing
    $script:TestGuid = [Guid]::NewGuid()
    $testUsername = 'TestUsername'
    $testPassword = 'TestPassword'
    $secureTestPassword = ConvertTo-SecureString -String $testPassword -AsPlainText -Force
    $script:TestCredential = New-Object -TypeName 'System.Management.Automation.PSCredential' -ArgumentList @( $testUsername, $secureTestPassword )
    #endregion Set variables for testing


    #region Tests for Get-TargetResource
    Describe '7ZipArchive/Get-TargetResource' -Tag 'Unit' {

        BeforeAll {
            Copy-Item -Path $global:TestData -Destination "TestDrive:\$script:TestGuid" -Recurse -Force
        }

        Context 'エラーパターン' {

            It '指定されたアーカイブパスが存在しない場合は例外発生' {
                $PathNotExist = 'TestDrive:\NotExist\Nothing.zip'
                $PathOfDestination = "TestDrive:\$script:TestGuid\Destination"

                $getParam = @{
                    Path        = $PathNotExist
                    Destination = $PathOfDestination
                }

                {Get-TargetResource @getParam} | Should -Throw "The path $PathNotExist does not exist or is not a file"
            }

            It '指定されたアーカイブパスが存在するが、ファイルではなくフォルダの場合は例外発生' {
                $PathOfFolder = "TestDrive:\$script:TestGuid\Folder"
                $PathOfDestination = "TestDrive:\$script:TestGuid\Destination"
                New-Item -Path $PathOfFolder -ItemType Container >$null

                $getParam = @{
                    Path        = $PathOfFolder
                    Destination = $PathOfDestination
                }

                {Get-TargetResource @getParam} | Should -Throw "The path $PathOfFolder does not exist or is not a file"
            }

            It 'Checksumが指定されているが、ValidateがFalseの場合は例外発生' {
                $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip'
                $PathOfDestination = "TestDrive:\$script:TestGuid\Destination"

                $getParam = @{
                    Path        = $PathOfArchive
                    Destination = $PathOfDestination
                    Validate    = $false
                    Checksum    = 'ModifiedDate'
                }

                {Get-TargetResource @getParam} | Should -Throw "Please specify the Validate parameter as true to use the Checksum parameter."
            }

            Mock Test-ArchiveExistsAtDestination -MockWith {throw 'Exception'}

            It 'Test-ArchiveExistsAtDestinationで例外発生した場合は例外発生' {
                $PathOfFolder = "TestDrive:\$script:TestGuid\Folder"
                $PathOfDestination = "TestDrive:\$script:TestGuid\Destination"
                New-Item -Path $PathOfFolder -ItemType Container >$null

                $getParam = @{
                    Path        = $PathOfFolder
                    Destination = $PathOfDestination
                }

                {Get-TargetResource @getParam} | Should -Throw "Exception"
                Assert-MockCalled -CommandName 'Test-ArchiveExistsAtDestination' -Times 1 -Exactly -Scope It
            }
        }

        Context '正しいアーカイブパスと展開先が指定されている場合' {

            Context '展開先フォルダが存在しない場合' {
                Mock Test-ArchiveExistsAtDestination {return $true}

                $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip'
                $PathOfNotExist = "TestDrive:\$script:TestGuid\NotExist"
                New-Item $PathOfNotExist -ItemType File -Force >$null

                It 'EnsureプロパティがAbsentのHashTableを返す' {
                    $getParam = @{
                        Path        = $PathOfArchive
                        Destination = $PathOfNotExist
                    }

                    $result = Get-TargetResource @getParam

                    Assert-MockCalled -CommandName 'Test-ArchiveExistsAtDestination' -Times 0 -Exactly -Scope It
                    $result | Should -BeOfType 'HashTable'
                    $result.Ensure | Should -Be 'Absent'
                    $result.Path | Should -Be $PathOfArchive
                    $result.Destination | Should -Be $PathOfNotExist
                }
            }

            Context '展開先にアーカイブが展開されていない場合' {

                Mock Test-ArchiveExistsAtDestination {return $false}

                $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip'
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

                Mock Test-ArchiveExistsAtDestination {return $true} -ParameterFilter {-not $Checksum}
                Mock Test-ArchiveExistsAtDestination {return $true} -ParameterFilter {$IgnoreRoot}
                Mock Test-ArchiveExistsAtDestination {return $true} -ParameterFilter {$Checksum -eq 'ModifiedDate'}
                Mock Test-ArchiveExistsAtDestination {return $false} -ParameterFilter {$Checksum -eq 'Size'}
                Mock Test-ArchiveExistsAtDestination {return $false}

                Mock Mount-PSDriveWithCredential {} -ParameterFilter {$Credential -and ($Credential.UserName -eq $script:TestCredential.UserName)}
                Mock Mount-PSDriveWithCredential {}

                BeforeAll {
                    $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip'
                    $PathOfAlreadyExpanded = "TestDrive:\$script:TestGuid\AlreadyExpanded"
                    New-Item $PathOfAlreadyExpanded -ItemType Container >$null
                    # Expand-Archive -Path $PathOfArchive -DestinationPath $PathOfAlreadyExpanded -Force
                }

                Context 'Validateが指定されていない場合' {
                    $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip'
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

                        Assert-MockCalled -CommandName 'Test-ArchiveExistsAtDestination' -ParameterFilter {$IgnoreRoot} -Times 1 -Scope It

                        $result.Ensure | Should -Be 'Present'
                        $result.Path | Should -Be $PathOfArchive
                        $result.Destination | Should -Be $PathOfAlreadyExpanded
                    }

                    It 'EnsureプロパティがPresentのHashTableを返す (Credential指定あり）' {
                        $getParam = @{
                            Path        = $PathOfArchive
                            Destination = $PathOfAlreadyExpanded
                            Credential  = $script:TestCredential
                        }

                        $result = Get-TargetResource @getParam

                        Assert-MockCalled -CommandName 'Test-ArchiveExistsAtDestination' -Times 1 -Scope It
                        Assert-MockCalled -CommandName 'Mount-PSDriveWithCredential' -ParameterFilter {$Credential -and ($Credential.UserName -eq $TestCredential.UserName)} -Times 1 -Exactly -Scope It

                        $result.Ensure | Should -Be 'Present'
                        $result.Path | Should -Be $PathOfArchive
                        $result.Destination | Should -Be $PathOfAlreadyExpanded
                    }
                }

                Context 'Validateが指定されている場合' {

                    It '検証をパスした場合、EnsureプロパティがPresentのHashTableを返す' {
                        $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip'
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
                        $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip'
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
    Describe '7ZipArchive/Test-TargetResource' -Tag 'Unit' {

        Context 'Get-TargetResourceの返すHashTableのEnsureプロパティがPresentの場合' {

            Mock Get-TargetResource { return @{Ensure = 'Present'} }

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

            Mock Get-TargetResource { return @{Ensure = 'Absent'} }

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
    Describe '7ZipArchive/Set-TargetResource' -Tag 'Unit' {

        Mock Expand-7ZipArchive -MockWith {} -ParameterFilter {$IgnoreRoot}
        Mock Expand-7ZipArchive -MockWith {} -ParameterFilter {$Force -eq $false}
        Mock Expand-7ZipArchive -MockWith {}

        Mock Mount-PSDriveWithCredential {} -ParameterFilter {$Credential -and ($Credential.UserName -eq $script:TestCredential.UserName)}
        Mock Mount-PSDriveWithCredential

        BeforeAll {
            Copy-Item -Path $global:TestData -Destination "TestDrive:\$script:TestGuid" -Recurse -Force
        }

        Context 'エラーパターン' {

            It '指定されたアーカイブパスが存在しない場合は例外発生' {
                $PathNotExist = 'TestDrive:\NotExist\Nothing.zip'
                $PathOfDestination = "TestDrive:\$script:TestGuid\Destination"

                $SetParam = @{
                    Path        = $PathNotExist
                    Destination = $PathOfDestination
                }

                {Set-TargetResource @SetParam} | Should -Throw "The path $PathNotExist does not exist or is not a file"
            }

            It '指定されたアーカイブパスが存在するが、ファイルではなくフォルダの場合は例外発生' {
                $PathOfFolder = "TestDrive:\$script:TestGuid\Folder"
                $PathOfDestination = "TestDrive:\$script:TestGuid\Destination"
                New-Item -Path $PathOfFolder -ItemType Container >$null

                $SetParam = @{
                    Path        = $PathOfFolder
                    Destination = $PathOfDestination
                }

                {Set-TargetResource @SetParam} | Should -Throw "The path $PathOfFolder does not exist or is not a file"
            }

            It 'Checksumが指定されているが、ValidateがFalseの場合は例外発生' {
                $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip'
                $PathOfDestination = "TestDrive:\$script:TestGuid\Destination"

                $SetParam = @{
                    Path        = $PathOfArchive
                    Destination = $PathOfDestination
                    Validate    = $false
                    Checksum    = 'ModifiedDate'
                }

                {Set-TargetResource @SetParam} | Should -Throw "Please specify the Validate parameter as true to use the Checksum parameter."
            }

            Mock Expand-7ZipArchive -MockWith {throw 'Exception'}

            It 'Expand-7ZipArchiveで例外が発生した場合は例外発生' {
                $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip'
                $PathOfDestination = "TestDrive:\$script:TestGuid\Destination"

                $SetParam = @{
                    Path        = $PathOfArchive
                    Destination = $PathOfDestination
                }

                {Set-TargetResource @SetParam} | Should -Throw "Exception"
                Assert-MockCalled -CommandName 'Expand-7ZipArchive' -Times 1 -Exactly -Scope It
            }
        }

        Context 'アーカイブ展開' {

            $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip'
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
                Assert-MockCalled -CommandName 'Expand-7ZipArchive' -ParameterFilter {$IgnoreRoot} -Times 1 -Scope It
            }

            It '展開先フォルダにアーカイブを展開する (Force指定あり)' {
                $setParam = @{
                    Path        = $PathOfArchive
                    Destination = $PathOfDestination
                    Force       = $false
                }

                { Set-TargetResource @setParam } | Should -Not -Throw
                Assert-MockCalled -CommandName 'Expand-7ZipArchive' -ParameterFilter {$Force -eq $false} -Times 1 -Scope It
            }

            It '展開先フォルダにアーカイブを展開する (Credential指定あり)' {
                $setParam = @{
                    Path        = $PathOfArchive
                    Destination = $PathOfDestination
                    Credential  = $script:TestCredential
                }

                { Set-TargetResource @setParam } | Should -Not -Throw
                Assert-MockCalled -CommandName 'Mount-PSDriveWithCredential' -ParameterFilter {$Credential -and ($Credential.UserName -eq $TestCredential.UserName)} -Times 1 -Exactly -Scope It
                Assert-MockCalled -CommandName 'Expand-7ZipArchive' -Times 1 -Scope It
            }
        }
    }
    #endregion Tests for Set-TargetResource


    #region Tests for Mount-PSDriveWithCredential
    Describe '7ZipArchive/Mount-PSDriveWithCredential' -Tag 'Unit' {

        Mock New-PSDrive {}

        Context 'Pathにアクセス可能な場合' {
            Mock Test-Path {return $true}

            It '何もしない' {
                $PathOfFolder = "TestDrive:\$script:TestGuid"
                {$null = Mount-PSDriveWithCredential -Path $PathOfFolder -Credential $script:TestCredential} | Should -Not -Throw
                Assert-MockCalled -CommandName 'Test-Path' -Times 1 -Scope It
                Assert-MockCalled -CommandName 'New-PSDrive' -Times 0 -Exactly -Scope It
            }
        }

        Context 'Pathにアクセスできない場合' {
            Mock Test-Path {return $false}

            It 'PSDriveをマウントする' {
                $PathOfFolder = "TestDrive:\$script:TestGuid"
                {$null = Mount-PSDriveWithCredential -Path $PathOfFolder -Credential $script:TestCredential} | Should -Not -Throw
                Assert-MockCalled -CommandName 'Test-Path' -Times 1 -Scope It
                Assert-MockCalled -CommandName 'New-PSDrive' -Times 1 -Exactly -Scope It
            }
        }
    }
    #endregion Tests for Mount-PSDriveWithCredential


    #region Tests for Get-7ZipArchiveFileList
    Describe '7ZipArchive/Get-7ZipArchiveFileList' -Tag 'Unit' {

        BeforeAll {
            Copy-Item -Path $global:TestData -Destination "TestDrive:\$script:TestGuid" -Recurse -Force
        }

        Context 'エラーパターン' {

            It 'アーカイブパスが存在しない場合は例外発生' {
                $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'NotExist.zip'
                {Get-7ZipArchiveFileList -Path $PathOfArchive} | Should -Throw "The path $PathOfArchive does not exist or is not a file"
            }

            It 'アーカイブパスがファイルでない場合は例外発生' {
                $PathOfFolder = Join-Path "TestDrive:\$script:TestGuid" 'Folder.zip'
                New-Item $PathOfFolder -ItemType Directory -Force >$null

                {Get-7ZipArchiveFileList -Path $PathOfFolder} | Should -Throw "The path $PathOfFolder does not exist or is not a file"
            }

            It '指定されたファイルがアーカイブファイルでない場合は例外発生' {
                $PathOfInvalidArchive = Join-Path "TestDrive:\$script:TestGuid" 'InvalidZIP.zip'
                'This is not an Archive' | Out-File -FilePath (Join-Path "TestDrive:\$script:TestGuid" 'InvalidZIP.zip')

                {Get-7ZipArchiveFileList -Path $PathOfInvalidArchive} | Should -Throw "The file $PathOfInvalidArchive is not a valid archive"
            }

            It 'IgnoreRootが指定されている場合で、アーカイブにひとつの"ファイル"のみが含まれる場合は例外発生' {
                $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'OnlyOneFile.zip'
                {Get-7ZipArchiveFileList -Path $PathOfArchive -IgnoreRoot} | Should -Throw "When the IgnoreRoot parameter is specified, there must be only one folder in the root of the archive."
            }

            It 'IgnoreRootが指定されている場合で、アーカイブのルートに複数のファイル/フォルダが含まれる場合は例外発生' {
                $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip'
                {Get-7ZipArchiveFileList -Path $PathOfArchive -IgnoreRoot} | Should -Throw "When the IgnoreRoot parameter is specified, there must be only one folder in the root of the archive."
            }
        }

        Context 'ZIPファイルリスト取得' {

            Context 'ファイル一つのみを含むアーカイブ' {
                It '出力は[PsCustomObject]で、Name, Size, ItemType, ModifiedDate, CRC32プロパティを含むこと' {
                    $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'OnlyOneFile.zip'

                    $Result = Get-7ZipArchiveFileList -Path $PathOfArchive

                    $Result | Should -BeOfType 'PsCustomObject'
                    $Result.Name | Should -Be 'Hello Archive.txt'
                    $Result.Size | Should -BeOfType 'int'
                    $Result.Size | Should -Be 14
                    $Result.ItemType | Should -Be 'File'
                    $Result.ModifiedDate | Should -BeOfType 'DateTime'
                    $Result.ModifiedDate.toString() | Should -Be '2018/08/09 0:02:49'
                    $Result.CRC32 | Should -BeOfType 'string'
                    $Result.CRC32 | Should -Be '9E5F60BB'
                }
            }

            Context '複数のファイル/フォルダを含むアーカイブ' {

                It 'アーカイブ内のファイルリストを取得（出力は[PsCustomObject]の配列であること）' {
                    $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'TestHasRoot.zip'

                    $Result = Get-7ZipArchiveFileList -Path $PathOfArchive

                    $Result | Should -BeOfType 'Array'
                    $Result | Should -HaveCount 5
                    $Result | Where-Object {$_.ItemType -eq 'File'} | Should -HaveCount 3
                    $Result | Where-Object {$_.ItemType -eq 'Directory'} | Should -HaveCount 2

                    $ContentInResult = $Result | Where-Object {$_.Name -match '002.txt'}
                    $ContentInResult | Should -BeOfType 'PsCustomObject'
                    $ContentInResult.Name | Should -Be 'root\Folder\002.txt'
                    $ContentInResult.Size | Should -BeOfType 'int'
                    $ContentInResult.Size | Should -Be 6
                    $ContentInResult.ItemType | Should -Be 'File'
                    $ContentInResult.ModifiedDate | Should -BeOfType 'DateTime'
                    $ContentInResult.ModifiedDate.toString() | Should -Be '2018/08/09 0:02:51'
                    $Result.CRC32 | Should -BeOfType 'string'
                    $Result.CRC32 | Should -Be 'E448FDFB'
                }

                It 'アーカイブ内のファイルリストを取得 (IgnoreRoot指定ありの場合、ルートフォルダは除外したリストを返すこと)' {
                    $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'TestHasRoot.zip'

                    $Result = Get-7ZipArchiveFileList -Path $PathOfArchive -IgnoreRoot

                    $Result | Should -BeOfType 'Array'
                    $Result | Should -HaveCount 4
                    $Result | Where-Object {$_.ItemType -eq 'File'} | Should -HaveCount 3
                    $Result | Where-Object {$_.ItemType -eq 'Directory'} | Should -HaveCount 1

                    $ContentInResult = $Result | Where-Object {$_.Name -match '002.txt'}
                    $ContentInResult | Should -BeOfType 'PsCustomObject'
                    $ContentInResult.Name | Should -Be 'Folder\002.txt'
                    $ContentInResult.Size | Should -BeOfType 'int'
                    $ContentInResult.Size | Should -Be 6
                    $ContentInResult.ItemType | Should -Be 'File'
                    $ContentInResult.ModifiedDate | Should -BeOfType 'DateTime'
                    $ContentInResult.ModifiedDate.toString() | Should -Be '2018/08/09 0:02:51'
                    $Result.CRC32 | Should -BeOfType 'string'
                    $Result.CRC32 | Should -Be 'E448FDFB'
                }
            }
        }

        Context '7zファイル' {

            It 'アーカイブ内のファイルリストを取得' {
                $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'TestHasRoot.7z'

                $Result = Get-7ZipArchiveFileList -Path $PathOfArchive

                $Result | Should -BeOfType 'Array'
                $Result | Should -HaveCount 5
                $Result | Where-Object {$_.ItemType -eq 'File'} | Should -HaveCount 3
                $Result | Where-Object {$_.ItemType -eq 'Directory'} | Should -HaveCount 2
            }

            It 'アーカイブ内のファイルリストを取得 (IgnoreRoot指定あり)' {
                $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'TestHasRoot.7z'

                $Result = Get-7ZipArchiveFileList -Path $PathOfArchive -IgnoreRoot

                $Result | Should -BeOfType 'Array'
                $Result | Should -HaveCount 4
                $Result | Where-Object {$_.ItemType -eq 'File'} | Should -HaveCount 3
                $Result | Where-Object {$_.ItemType -eq 'Directory'} | Should -HaveCount 1
            }
        }

    }
    #endregion Tests for Get-7ZipArchiveFileList


    #region Tests for Test-ArchiveExistsAtDestination
    Describe '7ZipArchive/Test-ArchiveExistsAtDestination' -Tag 'Unit' {

        Context 'エラーパターン' {

            Mock Get-7ZipArchiveFileList -MockWith {throw '7ZipArchiveFileList Exception'}

            It 'Get-7ZipArchiveFileListが例外発生した場合は例外発生' {
                $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip'
                $Destination = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())
                New-Item $Destination -ItemType Directory -Force >$null
                'ABC' | Out-File (Join-Path $Destination 'test.txt')

                {Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination} | Should -Throw
                Assert-MockCalled -CommandName 'Get-7ZipArchiveFileList' -Times 1 -Scope It
            }
        }

        Context '展開先フォルダが存在しないか空フォルダの場合' {

            It '展開先フォルダが存在しない場合はFalseを返す' {
                $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip'
                $PathOfNotExist = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())

                $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $PathOfNotExist
                $Result | Should -BeOfType 'bool'
                $Result | Should -Be $false
            }

            It '展開先フォルダが空フォルダの場合はFalseを返す' {
                $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip'
                $PathOfEmptyFolder = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())
                New-Item $PathOfEmptyFolder -ItemType Directory -Force >$null

                $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $PathOfEmptyFolder
                $Result | Should -BeOfType 'bool'
                $Result | Should -Be $false
            }
        }

        Context '展開先フォルダが空ではない場合' {

            Mock Get-7ZipArchiveFileList -MockWith {
                @(
                    [PsCustomObject]@{
                        ItemType     = 'File'
                        ModifiedDate = [Datetime]::Parse('2018-08-09 00:02:36')
                        Size         = 3
                        Name         = '001.txt'
                    }
                )
            } -ParameterFilter {$Path -eq (Join-Path "TestDrive:\$script:TestGuid" 'SingleFile.zip')}

            Mock Get-7ZipArchiveFileList -MockWith {
                @(
                    [PsCustomObject]@{
                        ItemType     = 'File'
                        ModifiedDate = [Datetime]::Parse('2018-08-09 00:02:36')
                        Size         = 3
                        CRC32        = '55B20A4B'
                        Name         = '001.txt'
                    },

                    [PsCustomObject]@{
                        ItemType     = 'Folder'
                        ModifiedDate = [Datetime]::Parse('2018-08-09 09:21:12')
                        Size         = 0
                        CRC32        = ''
                        Name         = 'Folder'
                    },

                    [PsCustomObject]@{
                        ItemType     = 'File'
                        ModifiedDate = [Datetime]::Parse('2018-08-09 10:05:49')
                        Size         = 10
                        CRC32        = 'E448FDFB'
                        Name         = 'Folder\002.txt'
                    }
                )
            } -ParameterFilter {$Path -eq (Join-Path "TestDrive:\$script:TestGuid" 'MultiFile.zip')}

            Mock Get-7ZipArchiveFileList -MockWith {throw 'IgnoreRoot specified'} -ParameterFilter {$IgnoreRoot}

            Context 'Validateなし' {

                It '展開先フォルダにアーカイブ内のファイルとは異なるファイルのみが存在する場合はFalseを返す' {
                    $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'MultiFile.zip'
                    $Destination = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())
                    New-Item $Destination -ItemType Directory -Force >$null
                    '100' | Out-File (Join-Path $Destination '100.txt')

                    $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination

                    Assert-MockCalled -CommandName 'Get-7ZipArchiveFileList' -Times 1 -Scope It
                    $Result | Should -BeOfType 'bool'
                    $Result | Should -Be $false
                }

                It '展開先フォルダにアーカイブ内のファイルの一部しか存在しない場合はFalseを返す' {
                    $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'MultiFile.zip'
                    $Destination = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())
                    New-Item $Destination -ItemType Directory -Force >$null
                    New-Item (Join-Path $Destination 'Folder') -ItemType Directory -Force >$null
                    '001' | Out-File (Join-Path $Destination '001.txt')

                    $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination

                    Assert-MockCalled -CommandName 'Get-7ZipArchiveFileList' -Times 1 -Scope It
                    $Result | Should -BeOfType 'bool'
                    $Result | Should -Be $false
                }

                It '展開先フォルダ内のファイルとアーカイブ内のファイルが一致する場合はTrueを返す' {
                    $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'MultiFile.zip'
                    $Destination = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())
                    New-Item $Destination -ItemType Directory -Force >$null
                    New-Item (Join-Path $Destination 'Folder') -ItemType Directory -Force >$null
                    '001' | Out-File (Join-Path $Destination '001.txt')
                    '002' | Out-File (Join-Path $Destination '\Folder\002.txt')

                    $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination

                    Assert-MockCalled -CommandName 'Get-7ZipArchiveFileList' -Times 1 -Scope It
                    $Result | Should -BeOfType 'bool'
                    $Result | Should -Be $true
                }

                It '展開先フォルダにアーカイブ内のファイルが全て存在する場合は他に無関係なファイルが存在していたとしてもTrueを返す' {
                    $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'MultiFile.zip'
                    $Destination = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())
                    New-Item $Destination -ItemType Directory -Force >$null
                    New-Item (Join-Path $Destination 'Folder') -ItemType Directory -Force >$null
                    '001' | Out-File (Join-Path $Destination '001.txt')
                    '002' | Out-File (Join-Path $Destination '\Folder\002.txt')
                    '003' | Out-File (Join-Path $Destination '003.txt')

                    $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination

                    Assert-MockCalled -CommandName 'Get-7ZipArchiveFileList' -Times 1 -Scope It
                    $Result | Should -BeOfType 'bool'
                    $Result | Should -Be $true
                }

                It 'IgnoreRootが指定された場合、Get-7ZipArchiveFileListをIgnoreRoot付きで呼び出すこと' {
                    $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip'
                    $Destination = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())
                    New-Item $Destination -ItemType Directory -Force >$null

                    {Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination} | Should -Throw 'IgnoreRoot specified'
                    Assert-MockCalled -CommandName 'Get-7ZipArchiveFileList' -ParameterFilter {$IgnoreRoot} -Times 1 -Scope It
                }
            }

            Context 'Validateあり' {

                It 'ChecksumにModifiedDateが指定されている場合で、展開先フォルダ内のファイルとアーカイブ内のファイルの更新日時が一致しない場合はFalseを返す' {
                    $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'SingleFile.zip'
                    $Destination = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())
                    New-Item $Destination -ItemType Directory -Force >$null
                    '001' | Out-File (Join-Path $Destination '001.txt')
                    Set-ItemProperty (Join-Path $Destination '001.txt') -Name LastWriteTime -Value '2018-08-10 00:02:36'

                    $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination -Checksum 'ModifiedDate'

                    Assert-MockCalled -CommandName 'Get-7ZipArchiveFileList' -Times 1 -Scope It
                    $Result | Should -BeOfType 'bool'
                    $Result | Should -Be $false
                }

                It 'ChecksumにModifiedDateが指定されている場合で、展開先フォルダ内のファイルとアーカイブ内のファイルの更新日時が一致する場合はTrueを返す' {
                    $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'SingleFile.zip'
                    $Destination = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())
                    New-Item $Destination -ItemType Directory -Force >$null
                    '001' | Out-File (Join-Path $Destination '001.txt')
                    Set-ItemProperty (Join-Path $Destination '001.txt') -Name LastWriteTime -Value '2018-08-09 00:02:36.12'

                    $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination -Checksum 'ModifiedDate'

                    Assert-MockCalled -CommandName 'Get-7ZipArchiveFileList' -Times 1 -Scope It
                    $Result | Should -BeOfType 'bool'
                    $Result | Should -Be $true
                }

                It 'ChecksumにSizeが指定されている場合で、展開先フォルダ内のファイルとアーカイブ内のファイルのサイズが一致しない場合はFalseを返す' {
                    $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'SingleFile.zip'
                    $Destination = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())
                    New-Item $Destination -ItemType Directory -Force >$null
                    '0011' | Out-File (Join-Path $Destination '001.txt') -Encoding ascii -NoNewline

                    $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination -Checksum 'Size'

                    Assert-MockCalled -CommandName 'Get-7ZipArchiveFileList' -Times 1 -Scope It
                    $Result | Should -BeOfType 'bool'
                    $Result | Should -Be $false
                }

                It 'ChecksumにSizeが指定されている場合で、展開先フォルダ内のファイルとアーカイブ内のファイルのサイズが一致する場合はTrueを返す' {
                    $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'SingleFile.zip'
                    $Destination = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())
                    New-Item $Destination -ItemType Directory -Force >$null
                    '123' | Out-File (Join-Path $Destination '001.txt') -Encoding ascii -NoNewline

                    $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination -Checksum 'Size'

                    Assert-MockCalled -CommandName 'Get-7ZipArchiveFileList' -Times 1 -Scope It
                    $Result | Should -BeOfType 'bool'
                    $Result | Should -Be $true
                }

                It 'ChecksumにCRC32が指定されている場合で、展開先フォルダ内のファイルとアーカイブ内のファイルのCRC32が一致しない場合はFalseを返す' {
                    $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'SingleFile.zip'
                    $Destination = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())
                    New-Item $Destination -ItemType Directory -Force >$null
                    '010' | Out-File (Join-Path $Destination '001.txt') -Encoding ascii -NoNewline

                    $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination -Checksum 'CRC32'

                    Assert-MockCalled -CommandName 'Get-7ZipArchiveFileList' -Times 1 -Scope It
                    $Result | Should -BeOfType 'bool'
                    $Result | Should -Be $false
                }

                It 'ChecksumにCRC32が指定されている場合で、展開先フォルダ内のファイルとアーカイブ内のファイルのCRC32が一致する場合はTrueを返す' {
                    $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'SingleFile.zip'
                    $Destination = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())
                    New-Item $Destination -ItemType Directory -Force >$null
                    '001' | Out-File (Join-Path $Destination '001.txt') -Encoding ascii -NoNewline

                    $Result = Test-ArchiveExistsAtDestination -Path $PathOfArchive -Destination $Destination -Checksum 'CRC32'

                    Assert-MockCalled -CommandName 'Get-7ZipArchiveFileList' -Times 1 -Scope It
                    $Result | Should -BeOfType 'bool'
                    $Result | Should -Be $true
                }
            }
        }
    }
    #endregion Tests for Test-ArchiveExistsAtDestination


    #region Tests for Expand-7ZipArchive
    Describe '7ZipArchive/Expand-7ZipArchive' -Tag 'Unit' {

        BeforeAll {
            Copy-Item -Path $global:TestData -Destination "TestDrive:\$script:TestGuid" -Recurse -Force
        }

        Context 'エラーパターン' {

            It 'アーカイブパスが存在しない場合は例外発生' {
                $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'NotExist.zip'
                $Destination = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())

                {Expand-7ZipArchive -Path $PathOfArchive -Destination $Destination} | Should -Throw "The path $PathOfArchive does not exist or is not a file"
                Test-Path -Path $Destination | Should -Be $false
            }

            It 'アーカイブパスがファイルでない場合は例外発生' {
                $PathOfFolder = Join-Path "TestDrive:\$script:TestGuid" 'Folder.zip'
                New-Item $PathOfFolder -ItemType Directory -Force >$null
                $Destination = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())

                {Expand-7ZipArchive -Path $PathOfFolder -Destination $Destination} | Should -Throw "The path $PathOfFolder does not exist or is not a file"
                Test-Path -Path $Destination | Should -Be $false
            }

            It '指定されたファイルがアーカイブファイルでない場合は例外発生' {
                $PathOfInvalidArchive = Join-Path "TestDrive:\$script:TestGuid" 'InvalidZIP.zip'
                'This is not an Archive' | Out-File -FilePath (Join-Path "TestDrive:\$script:TestGuid" 'InvalidZIP.zip')
                $Destination = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())

                {Expand-7ZipArchive -Path $PathOfInvalidArchive -Destination $Destination} | Should -Throw "The file $PathOfInvalidArchive is not a valid archive"
                Test-Path -Path $Destination | Should -Be $false
            }

            It 'IgnoreRootが指定されている場合で、アーカイブにひとつの"ファイル"のみが含まれる場合は例外発生' {
                $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'OnlyOneFile.zip'
                $Destination = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())

                {Expand-7ZipArchive -Path $PathOfArchive -Destination $Destination} | Should -Throw "When the IgnoreRoot parameter is specified, there must be only one folder in the root of the archive."
                Test-Path -Path $Destination | Should -Be $false
            }

            It 'IgnoreRootが指定されている場合で、アーカイブのルートに複数のファイル/フォルダが含まれる場合は例外発生' {
                $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'TestValid.zip'
                $Destination = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())

                {Expand-7ZipArchive -Path $PathOfArchive -Destination $Destination} | Should -Throw "When the IgnoreRoot parameter is specified, there must be only one folder in the root of the archive."
                Test-Path -Path $Destination | Should -Be $false
            }
        }


        Context 'ZIPファイル展開' {

            It '展開先フォルダが存在しない場合、フォルダを作成してその中に展開する' {
                $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'OnlyOneFile.zip'
                $Destination = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())

                {Expand-7ZipArchive -Path $PathOfArchive -Destination $Destination} | Should -Not -Throw
                Test-Path -Path $Destination -PathType Container | Should -Be $true
                Get-ChildItem -Path $Destination -Recurse -Force | Should -HaveCount 1
                Test-Path -Path (Join-Path $Destination 'Hello Archive.txt') -PathType Leaf | Should -Be $true
                Get-Content -Path (Join-Path $Destination 'Hello Archive.txt') -Raw | Should -Be 'Hello Archive!'
            }

            It '展開先フォルダにアーカイブ内のファイルと異なるファイルが存在する場合、そのファイルは残したまま展開する' {
                $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'OnlyOneFile.zip'
                $Destination = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())
                New-Item $Destination -ItemType Directory -Force >$null
                '100' | Out-File (Join-Path $Destination '100.txt')

                {Expand-7ZipArchive -Path $PathOfArchive -Destination $Destination} | Should -Not -Throw
                Get-ChildItem -Path $Destination -Recurse -Force | Should -HaveCount 2
                Test-Path -Path (Join-Path $Destination 'Hello Archive.txt') -PathType Leaf | Should -Be $true
                Get-Content -Path (Join-Path $Destination 'Hello Archive.txt') -Raw | Should -Be 'Hello Archive!'
                Test-Path -Path (Join-Path $Destination '100.txt') -PathType Leaf | Should -Be $true
            }

            It '展開先フォルダにアーカイブ内のファイルと同じファイルが存在し、Forceが指定されていない場合、例外発生' {
                $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'OnlyOneFile.zip'
                $Destination = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())
                New-Item $Destination -ItemType Directory -Force >$null
                '100' | Out-File (Join-Path $Destination 'Hello Archive.txt')

                {Expand-7ZipArchive -Path $PathOfArchive -Destination $Destination} | Should -Throw 'An item with the same name in the archive exists in the destination folder. Please specify the Force parameter as true to overwrite it.'
                Test-Path -Path (Join-Path $Destination 'Hello Archive.txt') -PathType Leaf | Should -Be $true
                Get-Content -Path (Join-Path $Destination 'Hello Archive.txt') -Raw | Should -Be '100'
            }

            It '展開先フォルダにアーカイブ内のファイルと同じファイルが存在し、Forceが指定されている場合、上書きして展開する' {
                $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'OnlyOneFile.zip'
                $Destination = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())
                New-Item $Destination -ItemType Directory -Force >$null
                '100' | Out-File (Join-Path $Destination 'Hello Archive.txt')

                {Expand-7ZipArchive -Path $PathOfArchive -Destination $Destination -Force} | Should -Not -Throw
                Test-Path -Path $Destination -PathType Container | Should -Be $true
                Get-ChildItem -Path $Destination -Recurse -Force | Should -HaveCount 1
                Test-Path -Path (Join-Path $Destination 'Hello Archive.txt') -PathType Leaf | Should -Be $true
                Get-Content -Path (Join-Path $Destination 'Hello Archive.txt') -Raw | Should -Be 'Hello Archive!'
            }

            It 'IgnoreRootが指定されている場合、アーカイブのルートフォルダ内のファイルを展開先フォルダ内に展開する' {
                $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'TestHasRoot.zip'
                $Destination = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())

                {Expand-7ZipArchive -Path $PathOfArchive -Destination $Destination -IgnoreRoot} | Should -Not -Throw
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
                $PathOfArchive = Join-Path "TestDrive:\$script:TestGuid" 'TestHasRoot.7z'
                $Destination = Join-Path "TestDrive:\$script:TestGuid" ([Guid]::NewGuid().toString())

                {Expand-7ZipArchive -Path $PathOfArchive -Destination $Destination} | Should -Not -Throw
                Test-Path -Path $Destination -PathType Container | Should -Be $true
                Get-ChildItem -Path $Destination -Recurse -Force | Should -HaveCount 5
                Test-Path -Path (Join-Path $Destination 'root') -PathType Container | Should -Be $true
                Test-Path -Path (Join-Path $Destination 'root\Hello Archive.txt') -PathType Leaf | Should -Be $true
                Test-Path -Path (Join-Path $Destination 'root\Folder') -PathType Container | Should -Be $true
                Test-Path -Path (Join-Path $Destination 'root\Folder\001.txt') -PathType Leaf | Should -Be $true
                Test-Path -Path (Join-Path $Destination 'root\Folder\002.txt') -PathType Leaf | Should -Be $true
            }
        }
    }
    #endregion Tests for Expand-7ZipArchive

}

#endregion End Testing
