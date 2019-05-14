#Requires -Version 5

$script:7zExe = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '\Libs\7-Zip\7z.exe'
$script:Crc16 = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '\Libs\CRC16\CRC16.cs'
$script:Crc32NET = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '\Libs\Crc32.NET\Crc32.NET.dll'

# Class CRC16
$crc16 = Get-Content -LiteralPath $script:Crc16 -Raw
Add-Type -TypeDefinition $crc16 -Language CSharp

Enum ExitCode {
    #https://sevenzip.osdn.jp/chm/cmdline/exit_codes.htm
    Success = 0
    Warning = 1
    FatalError = 2
    CommandLineError = 7
    NotEnoughMemory = 8
    UserStopped = 255
}

class Archive {
    [string] $Path
    [string] $Type
    [int] $Files = 0
    [int] $Folders = 0
    [System.IO.FileInfo] $FileInfo
    [Object[]] $FileList

    Archive([string]$Path) {
        $info = [Archive]::TestArchive($Path) |`
            ForEach-Object { $_.Replace('\', '\\') } |`
            ForEach-Object { if ($_ -notmatch '=') { $_.Replace(':', ' =') }else { $_ } } |`
            Where-Object { $_ -match '^.+=.+$' } |`
            ConvertFrom-StringData

        $this.Path = $Path
        $this.Type = [string]$info.Type
        if ([int]::TryParse($info.Files, [ref]$null)) {
            $this.Files = [int]::Parse($info.Files)
        }
        if ([int]::TryParse($info.Folders, [ref]$null)) {
            $this.Folders = [int]::Parse($info.Folders)
        }
        $this.FileInfo = [System.IO.FileInfo]::new($Path)
        $this.FileList = [Archive]::GetFileList($Path)
    }

    [Object[]]GetFileList() {
        return $this.FileList
    }

    static [string[]]TestArchive([string]$Path) {
        $NewLine = [System.Environment]::NewLine
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw [System.IO.FileNotFoundException]::new()
        }

        # Test integrity of archive
        $msg = $null
        try { $msg = & $script:7zExe t $Path -ba }catch { }
        if ($LASTEXITCODE -ne [ExitCode]::Success) {
            throw [System.ArgumentException]::new($msg -join $NewLine)
        }

        return $msg
    }

    static [Object[]]GetFileList([string]$Path) {
        $NewLine = [System.Environment]::NewLine
        # [Archive]::TestArchive($Path) | Write-Debug

        Write-Verbose 'Enumerating files & folders in the archive.'
        $ret = $null
        try { $ret = & $script:7zExe l $Path -ba -slt }catch { }
        if ($LASTEXITCODE -ne [ExitCode]::Success) {
            throw [System.InvalidOperationException]::new($ret -join $NewLine)
        }
        return ($ret -join $NewLine).Replace('\', '\\') -split "$NewLine$NewLine" |`
            ConvertFrom-StringData |`
            ForEach-Object {
            $tmp = $_

            $tmp.Size = [int]$_.Size
            $tmp.Encrypted = [bool]($_.Encrypted -eq '+')

            if ($_.Modified) {
                $tmp.Modified = [datetime]$_.Modified
            }

            if ($_.Created) {
                $tmp.Created = [datetime]$_.Created
            }

            if ($_.Accessed) {
                $tmp.Accessed = [datetime]$_.Accessed
            }

            if ($_.'Packed Size') {
                $tmp.'Packed Size' = [int]$_.'Packed Size'
            }

            if ($_.Folder) {
                $tmp.Folder = [bool]($_.Folder -eq '+')
                $tmp.ItemType = if ($tmp.Folder) { 'Folder' }else { 'File' }
            }
            else {
                $tmp.Folder = [bool]($_.Attributes.Contains('D'))
                $tmp.ItemType = if ($tmp.Folder) { 'Folder' }else { 'File' }
            }

            if ($_.'Volume Index') {
                $tmp.'Volume Index' = [int]$_.'Volume Index'
            }

            if ($_.Offset) {
                $tmp.Offset = [int]$_.Offset
            }

            [PSCustomObject]$tmp
        }
    }

    [void]Extract([string]$Destination) {
        $this.Extract($Destination, $false)
    }

    [void]Extract([string]$Destination, [bool]$IgnoreRoot) {
        $Guid = [System.Guid]::NewGuid().toString()
        $FinalDestination = $Destination

        $activityMessage = ('Extracting archive: {0} to {1}' -f $this.Path, $FinalDestination)
        $statusMessage = "Extracting..."

        Write-Verbose $activityMessage

        # Test the archive has multiple root or not
        if ($IgnoreRoot) {
            $rootDir = $this.FileList | Where-Object { $_.Path.Contains('\') } | ForEach-Object { ($_.Path -split '\\')[0] } | Select-Object -First 1
            if (-not $rootDir) {
                throw [System.InvalidOperationException]::new("Archive has no item or only one file in the root. You can't use IgnoreRoot option.")
            }

            [bool]$HasMultipleRoot = $false
            foreach ($Item in $this.FileList) {
                if (($Item.ItemType -eq 'Folder') -and ($Item.Path -ceq $rootDir)) {
                    # The item is Root dir
                    continue
                }
                elseif ($Item.Path.StartsWith(($rootDir + '\'), [System.StringComparison]::Ordinal)) {
                    # The item in the root dir
                    continue
                }
                else {
                    # The item out of the root dir
                    $HasMultipleRoot = $true
                    break
                }
            }

            if ($HasMultipleRoot) {
                throw [System.InvalidOperationException]::new("Archive has multiple items in the root. You can't use IgnoreRoot option.")
            }

            $Destination = Join-Path $FinalDestination "$Guid\$rootDir"
        }

        if ($IgnoreRoot) {
            try {
                & $script:7zExe x $this.Path -ba -o"$Destination" -y -aoa -spe -bsp1 | ForEach-Object -Process {
                    if ($_ -match '(\d+)\%') {
                        $progress = $Matches.1
                        if ([int]::TryParse($progress, [ref]$progress)) {
                            Write-Progress -Activity $activityMessage -Status $statusMessage -PercentComplete $progress -CurrentOperation "$progress % completed."
                        }
                    }
                }
            }
            catch { }
        }
        else {
            try {
                & $script:7zExe x $this.Path -ba -o"$Destination" -y -aoa -bsp1 | ForEach-Object -Process {
                    if ($_ -match '(\d+)\%') {
                        $progress = $Matches.1
                        if ([int]::TryParse($progress, [ref]$progress)) {
                            Write-Progress -Activity $activityMessage -Status $statusMessage -PercentComplete $progress -CurrentOperation "$progress % completed."
                        }
                    }
                }
            }
            catch { }
        }

        $ExitCode = $LASTEXITCODE
        if ($ExitCode -ne [ExitCode]::Success) {
            if (Test-Path -LiteralPath (Join-Path $FinalDestination $Guid)) {
                Remove-Item -LiteralPath (Join-Path $FinalDestination $Guid) -Force -Recurse -ErrorAction SilentlyContinue
            }
            throw [System.InvalidOperationException]::new(('Exit code:{0} ({1})' -f $ExitCode, ([ExitCode]$ExitCode).ToString()))
        }
        else {
            Write-Progress -Activity $activityMessage -Status 'Extraction complete.' -Completed
        }

        if ($IgnoreRoot) {
            try {
                Get-ChildItem -LiteralPath $Destination -Recurse -Force | Move-Item -Destination $FinalDestination -Force -ErrorAction Stop
            }
            finally {
                Remove-Item -LiteralPath (Join-Path $FinalDestination $Guid) -Force -Recurse -ErrorAction SilentlyContinue
            }
        }

        Write-Verbose 'Extraction completed successfully.'
    }

    static [void]Extract([string]$Path, [string]$Destination) {
        [Archive]::Extract($Path, $Destination, $false)
    }

    static [void]Extract([string]$Path, [string]$Destination, [bool]$IgnoreRoot) {
        $archive = [Archive]::new($Path)
        $archive.Extract($Destination, $IgnoreRoot)
    }
}


<#
.SYNOPSIS
ファイルのCRC16ハッシュを計算する関数

.PARAMETER Path
ハッシュを計算するファイルのパスを指定します

.EXAMPLE
Get-CRC16Hash -Path C:\file.txt
#>
function Get-CRC16Hash {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        [string]$Path
    )

    Begin {
        $crc16 = [CRC16]::new()
    }

    Process {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            Write-Error -Exception ([System.IO.FileNotFoundException]::new('The file is not exist.'))
        }
        else {
            try {
                [System.IO.FileStream]$stream = [System.IO.File]::OpenRead($Path)
                [byte[]]$hash = $crc16.ComputeHash($stream);
                [System.BitConverter]::ToString($hash).Replace('-', [string]::Empty)
            }
            catch {
                Write-Error -Exception $_.Exception
            }
            finally {
                if ($null -ne $stream) {
                    $stream.Dispose()
                }
            }
        }
    }
}


<#
.SYNOPSIS
ファイルのCRC32ハッシュを計算する関数

.PARAMETER Path
ハッシュを計算するファイルのパスを指定します

.EXAMPLE
Get-CRC32Hash -Path C:\file.txt
#>
function Get-CRC32Hash {
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]
        $Path
    )

    Begin {
        if (-not ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.Location -eq $script:Crc32NET })) {
            $null = [reflection.assembly]::LoadFrom($script:Crc32NET)
        }
    }

    Process {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            Write-Error -Exception ([System.IO.FileNotFoundException]::new('The file is not exist.'))
            return
        }

        $crc32 = [Force.Crc32.Crc32Algorithm]::new()
        try {
            [System.IO.FileStream]$stream = [System.IO.File]::OpenRead($Path)
            [byte[]]$hash = $crc32.ComputeHash($stream)
            [System.BitConverter]::ToString($hash).Replace('-', [string]::Empty)
        }
        catch {
            Write-Error -Exception $_.Exception
        }
        finally {
            if ($null -ne $stream) {
                $stream.Dispose()
            }
        }
    }
}

function Get-TargetResource {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter()]
        [ValidateSet('Present', 'Absent')]
        [string]
        $Ensure = 'Present',

        [Parameter(Mandatory)]
        [string]
        $Path,

        [Parameter(Mandatory)]
        [string]
        $Destination,

        [Parameter()]
        [bool]
        $Validate = $false,

        [Parameter()]
        [string]
        $Checksum = 'ModifiedDate',

        [Parameter()]
        [bool]
        $IgnoreRoot = $false,

        [Parameter()]
        [bool]
        $Clean = $false,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    <#
    ### 処理の流れ
    1. $Pathの正当性を確認
    2. $Pathにアクセスできず、Credentialが指定されている場合はNew-PSDriveでマウントする
        2-1. 終了時にはかならずRemove-PSDriveでアンマウントする
    3. Test-ArchiveExistsAtDestinationを呼び出してアーカイブがDestinationに展開済みかどうかチェック
    4. 展開済みであればEnsureにPresentをセットしたHashTableを、未展開であればEnsureにAbsentをセットしたHashTableを返す
    #>

    $local:PsDrive = $null

    # Checksumが指定されているが、ValidateがFalseの場合はエラー
    if ($PSBoundParameters.ContainsKey('Checksum') -and (-not $Validate)) {
        Write-Error -Exception ([System.ArgumentException]::new('Please specify the Validate parameter as true to use the Checksum parameter.'))
        return
    }

    if ($Credential) {
        $local:PsDrive = Mount-PSDriveWithCredential -Root (Split-Path $Path -Parent) -Credential $Credential -ErrorAction Stop
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction SilentlyContinue)) {
        Write-Error "The path $Path does not exist or is not a file"
        UnMount-PSDrive -Name $local:PsDrive.Name -ErrorAction SilentlyContinue
        return
    }

    $testParam = @{
        Path        = $Path
        Destination = $Destination
        IgnoreRoot  = $IgnoreRoot
        Clean       = $Clean
    }

    if ($Validate) {
        if ($Checksum -eq 'CRC32') { $Checksum = 'CRC' }
        $testParam.Checksum = $Checksum
    }

    try {
        $testResult = Test-ArchiveExistsAtDestination @testParam -ErrorAction Stop
    }
    catch {
        Write-Error -Exception $_.Exception
        return
    }
    finally {
        UnMount-PSDrive -Name $local:PsDrive.Name -ErrorAction SilentlyContinue
    }

    if ($testResult) {
        $Ensure = 'Present'
    }
    else {
        $Ensure = 'Absent'
    }

    return @{
        Ensure      = $Ensure
        Path        = $Path
        Destination = $Destination
    }
} # end of Get-TargetResource


function Test-TargetResource {
    [CmdletBinding()]
    [OutputType([bool])]
    param
    (
        [Parameter()]
        [ValidateSet('Present', 'Absent')]
        [string]
        $Ensure = 'Present',

        [Parameter(Mandatory)]
        [string]
        $Path,

        [Parameter(Mandatory)]
        [string]
        $Destination,

        [Parameter()]
        [bool]
        $Validate = $false,

        [Parameter()]
        [ValidateSet('ModifiedDate', 'Size', 'CRC', 'CRC32')]
        [string]
        $Checksum = 'ModifiedDate',

        [Parameter()]
        [bool]
        $IgnoreRoot = $false,

        [Parameter()]
        [bool]
        $Clean = $false,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )
    <#
    ### 処理の流れ
    1. Get-TargetResourceを呼び出す
    2. 1の返り値のEnsureプロパティがPresentならTrueを、AbsentならFalseを返す
    #>

    $ret = (Get-TargetResource @PSBoundParameters -ErrorAction Stop).Ensure
    return ($ret -eq 'Present')
} # end of Test-TargetResource


function Set-TargetResource {
    param
    (
        [Parameter()]
        [ValidateSet('Present', 'Absent')]
        [string]
        $Ensure = 'Present',

        [Parameter(Mandatory)]
        [string]
        $Path,

        [Parameter(Mandatory)]
        [string]
        $Destination,

        [Parameter()]
        [bool]
        $Validate = $false,

        [Parameter()]
        [ValidateSet('ModifiedDate', 'Size', 'CRC', 'CRC32')]
        [string]
        $Checksum = 'ModifiedDate',

        [Parameter()]
        [bool]
        $IgnoreRoot = $false,

        [Parameter()]
        [bool]
        $Clean = $false,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )
    <#
    ### 処理の流れ
    1. $Pathの正当性を確認
    2. $Pathにアクセスできず、Credentialが指定されている場合はNew-PSDriveでマウントする
        2-1. 終了時にはかならずRemove-PSDriveでアンマウント
    3. Expand-7ZipArchiveを呼び出してアーカイブをDestinationに展開する
    #>

    $local:PsDrive = $null

    # Checksumが指定されているが、ValidateがFalseの場合はエラー
    if ($PSBoundParameters.ContainsKey('Checksum') -and (-not $Validate)) {
        Write-Error -Exception ([System.ArgumentException]::new('Please specify the Validate parameter as true to use the Checksum parameter.'))
        return
    }

    if ($Credential) {
        $local:PsDrive = Mount-PSDriveWithCredential -Root (Split-Path $Path -Parent) -Credential $Credential -ErrorAction Stop
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction SilentlyContinue)) {
        Write-Error "The path $Path does not exist or is not a file"
        UnMount-PSDrive -Name $local:PsDrive.Name -ErrorAction SilentlyContinue
        return
    }

    $testParam = @{
        Path        = $Path
        Destination = $Destination
        IgnoreRoot  = $IgnoreRoot
        Clean       = $Clean
    }

    try {
        Expand-7ZipArchive @testParam -ErrorAction Stop
    }
    catch {
        Write-Error -Exception $_.Exception
    }
    finally {
        UnMount-PSDrive -Name $local:PsDrive.Name -ErrorAction SilentlyContinue
    }

} # end of Set-TargetResource


<#
.SYNOPSIS
アーカイブファイル内のファイルリストを取得する関数

.PARAMETER Path
アーカイブファイルのパスを指定します
アーカイブは7Zipで扱える形式である必要があります

.EXAMPLE
PS> Get-7ZipArchiveFileList -Path C:\Test.zip

#>
function Get-7ZipArchiveFileList {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path,

        [Parameter(Mandatory = $true, DontShow = $true, ParameterSetName = 'Class')]
        [ValidateNotNullOrEmpty()]
        [Archive]
        $Archive
    )

    (Get-7ZipArchive @PSBoundParameters).FileList
}


<#
.SYNOPSIS
アーカイブファイルの情報を取得する関数

.PARAMETER Path
アーカイブファイルのパスを指定します
アーカイブは7Zipで扱える形式である必要があります

.EXAMPLE
PS> Get-7ZipArchive -Path C:\Test.zip

#>
function Get-7ZipArchive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path,

        [Parameter(Mandatory = $true, DontShow = $true, ParameterSetName = 'Class')]
        [ValidateNotNullOrEmpty()]
        [Archive]
        $Archive
    )

    # $Archiveクラスのインスタンスを返すラッパー関数

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        try {
            $Archive = [Archive]::new($Path)
        }
        catch {
            Write-Error -Exception $_.Exception
            return
        }
    }

    $Archive
}


<#
.SYNOPSIS
アーカイブファイルが展開先フォルダに既に展開済みかどうかをチェックする関数

.PARAMETER Path
アーカイブファイルのパスを指定します

.PARAMETER Destination
アーカイブファイルの展開先フォルダを指定します

.PARAMETER IgnoreRoot
IgnoreRootが指定された場合、アーカイブ内のルートフォルダを除外します

.PARAMETER Checksum
Checksumを指定しない場合、ファイル名のみをチェックします
Checksumに"ModifiedDate"を指定した場合、ファイル名に加えてファイルの更新日時が一致するかチェックします
Checksumに"Size"を指定した場合、ファイル名に加えてファイルサイズが一致するかチェックします
Checksumに"CRC"を指定した場合、ファイル名に加えてCRCハッシュが一致するかチェックします

.EXAMPLE
PS> Test-ArchiveExistsAtDestination -Path C:\Test.zip -Destination C:\Dest
True

#>
function Test-ArchiveExistsAtDestination {
    [CmdletBinding()]
    [OutputType([bool])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Destination,

        [Parameter()]
        [switch]
        $IgnoreRoot,

        [Parameter()]
        [switch]
        $Clean,

        [Parameter()]
        [ValidateSet('ModifiedDate', 'Size', 'CRC')]
        [string]
        $Checksum
    )
    <#
    ### 処理の流れ
    1. $Pathが正しいか確認（ファイルが存在するか、正しいアーカイブか）
    2. Destinationが存在しないor空フォルダの場合はFalseを返す
    3. アーカイブ内のファイル/フォルダ全てがDestination内に存在するか確認
        3-1. Checksumが指定されていない場合はファイル/フォルダ名が一致していればOKとする
        3-2. ChecksumにModifiedDateが指定された場合は3-1に加えてファイルの更新日時が一致しているか確認
        3-3. ChecksumにSizeが指定された場合は3-1に加えてファイルサイズが一致しているか確認
        3-3. ChecksumにCRCが指定された場合は3-1に加えてCRCハッシュが一致しているか確認
    4. アーカイブ内のファイル/フォルダ全てがDestination内に存在していればTrueを、一つでも存在しないファイルがあればFalseを返す
    #>

    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
        #Destination folder is not exist
        Write-Verbose 'The destination folder is not exist'
        return $false
    }

    if ($null -eq (Get-ChildItem -LiteralPath $Destination -Force | Select-Object -First 1)) {
        #Destination folder is empty
        Write-Verbose 'The destination folder is empty'
        return $false
    }

    $archive = Get-7ZipArchive -Path $Path

    if ($Clean) {
        $ExistFileCount = @(Get-ChildItem -LiteralPath $Destination -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PsIsContainer }).Count
        $ArchiveFileCount = @($archive.FileList | Where-Object { $_.ItemType -ne 'Folder' }).Count
        if ($ArchiveFileCount -ne $ExistFileCount) {
            Write-Verbose 'The number of destination files does not match the number of files in the archive'
            return $false
        }
    }

    $rootDir = $archive.FileList | Where-Object { $_.Path.Contains('\') } | ForEach-Object { ($_.Path -split '\\')[0] } | Select-Object -First 1
    if ($IgnoreRoot -and (-not $rootDir)) {
        Write-Error -Exception ([System.InvalidOperationException]::new("Archive has no item or only one file in the root. You can't use IgnoreRoot option."))
        return
    }

    # Test the archive has multiple root or not
    if ($IgnoreRoot) {
        [bool]$HasMultipleRoot = $false
        foreach ($Item in $archive.FileList) {
            if (($Item.ItemType -eq 'Folder') -and ($Item.Path -ceq $rootDir)) {
                # The item is Root dir
                continue
            }
            elseif ($Item.Path.StartsWith(($rootDir + '\'), [System.StringComparison]::Ordinal)) {
                # The item in the root dir
                continue
            }
            else {
                # The item out of the root dir
                $HasMultipleRoot = $true
                break
            }
        }

        if ($HasMultipleRoot) {
            Write-Error -Exception ([System.InvalidOperationException]::new("Archive has multiple items in the root. You can't use IgnoreRoot option."))
            return
        }
    }

    foreach ($Item in $archive.FileList) {
        if ($IgnoreRoot) {
            $RelativePath = $Item.Path.Substring($rootDir.Length)
            if ($RelativePath.Length -eq '0') {
                Write-Verbose ('Skip root folder: "{0}"' -f $Item.Path)
                continue
            }
        }
        else {
            $RelativePath = $Item.Path
        }
        $AbsolutePath = Join-Path -Path $Destination -ChildPath $RelativePath

        $tParam = @{
            LiteralPath = $AbsolutePath
            PathType    = $(if ($Item.ItemType -eq 'File') { 'Leaf' }else { 'Container' })
        }
        if (-not (Test-Path @tParam)) {
            # Target file not exist => return false
            Write-Verbose ('The file "{0}" in the archive is not exist in the destination folder' -f $Item.Path)
            return $false
        }

        if ($Checksum) {
            $CurrentFileInfo = Get-Item -LiteralPath $AbsolutePath -Force
            if ($Checksum -eq 'ModifiedDate') {
                # Truncate milliseconds of the LastWriteTimeUtc property of the file at the destination
                [datetime]$s = $CurrentFileInfo.LastWriteTimeUtc
                $CurrentFileModifiedDateUtc = [datetime]::new($s.Year, $s.Month, $s.Day, $s.Hour, $s.Minute, $s.Second, $s.Kind)

                # Convert UTC time to Local time by using only the current time zone information and the DST information. (Emulate FileTimeToLocalFileTime() of Win32API)
                # See http://support.microsoft.com/kb/932955 and https://devblogs.microsoft.com/oldnewthing/?p=42053
                $CurrentFileModifiedDate = $CurrentFileModifiedDateUtc.Add([System.TimeZone]::CurrentTimeZone.GetUtcOffset([datetime]::Now))

                # Compare datetime
                if ($CurrentFileModifiedDate -ne $Item.Modified) {
                    Write-Verbose ('The modified date of "{0}" is not same.' -f $Item.Path)
                    Write-Verbose ('Exist:{0} / Archive:{1}' -f $CurrentFileModifiedDate, $Item.Modified)
                    return $false
                }
            }
            elseif ($Checksum -eq 'Size') {
                if (-not $CurrentFileInfo.PsIsContainer) {
                    # Compare file size
                    if ($CurrentFileInfo.Length -ne $Item.Size) {
                        Write-Verbose ('The size of "{0}" is not same.' -f $Item.Path)
                        Write-Verbose ('Exist:{0} / Archive:{1}' -f $CurrentFileInfo.Length, $Item.Size)
                        return $false
                    }
                }
            }
            elseif ($Checksum -eq 'CRC') {
                if (-not $CurrentFileInfo.PsIsContainer) {
                    # Compare file hash
                    if ($archive.Type -eq 'lzh') {
                        #LZH has CRC16 checksum
                        $CurrentFileHash = Get-CRC16Hash -Path $CurrentFileInfo.FullName
                    }
                    else {
                        $CurrentFileHash = Get-CRC32Hash -Path $CurrentFileInfo.FullName
                    }
                    if ($CurrentFileHash -ne $Item.CRC) {
                        Write-Verbose ('The hash of "{0}" is not same.' -f $Item.Path)
                        Write-Verbose ('Exist:{0} / Archive:{1}' -f $CurrentFileHash, $Item.CRC)
                        return $false
                    }
                }
            }
        }
    }

    Write-Verbose ('All items in the archive exists in the destination folder')
    return $true
}


<#
.SYNOPSIS
アーカイブを展開する関数

.PARAMETER Path
アーカイブファイルのパスを指定します

.PARAMETER Destination
アーカイブファイルの展開先フォルダを指定します
展開先フォルダ内にアーカイブ内のファイルと同名のファイルが存在する場合は、確認なしで上書きされることに注意してください

.PARAMETER IgnoreRoot
IgnoreRootが指定された場合、アーカイブ内のルートフォルダを除外して展開します

.PARAMETER Clean
Cleanが指定された場合、展開先フォルダの既存ファイルをすべて削除してからアーカイブを展開します
指定しない場合、展開先フォルダの既存ファイルは残したまま展開します

.EXAMPLE
Expand-7ZipArchive -Path C:\Test.zip -Destination C:\Dest -Clean

#>
function Expand-7ZipArchive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path,

        [Parameter(Mandatory = $true, DontShow = $true, ParameterSetName = 'Class')]
        [ValidateNotNullOrEmpty()]
        [Archive]
        $Archive,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Destination,

        [Parameter()]
        [switch]
        $IgnoreRoot,

        [Parameter()]
        [switch]
        $Clean
    )

    <#
    ### 処理の流れ
    1. $Pathが正しいか確認（ファイルが存在するか、正しいアーカイブか）
    2. Cleanスイッチが指定されている場合はDestinationフォルダ内の全ファイルを削除
    3. 7Zipを使ってアーカイブをDestinationに展開
    #>

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        try {
            $Archive = [Archive]::new($Path)
        }
        catch {
            Write-Error -Exception $_.Exception
            return
        }
    }

    if ($Clean) {
        Write-Verbose ('Clean option is specified. Remove all items in {0}' -f $Destination)
        if (Test-Path -LiteralPath $Destination -PathType Container) {
            Get-ChildItem -LiteralPath $Destination -Recurse -Force -Verbose:$false -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue -Verbose:$false
        }
    }

    try {
        $Archive.Extract($Destination, $IgnoreRoot)
    }
    catch {
        Write-Error -Exception $_.Exception
        return
    }
}

function Mount-PSDriveWithCredential {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSDriveInfo])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Root,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name
    )

    if (-not $Name) {
        $Name = [guid]::NewGuid().toString()
    }

    try {
        New-PSDrive -Name $Name -Root $Root -PSProvider FileSystem -Credential $Credential -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $Root -ErrorAction SilentlyContinue)) {
            throw ('Could not access to "{0}"' -f $Root)
        }
    }
    catch {
        UnMount-PSDrive -Name $Name -ErrorAction SilentlyContinue
        Write-Error -Exception $_.Exception
        return
    }
}


function UnMount-PSDrive {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [AllowEmptyString()]
        [string]
        $Name
    )

    if (![string]::IsNullOrWhiteSpace($Name)) {
        Remove-PSDrive -Name $Name
    }
}


Export-ModuleMember -Function *-TargetResource
