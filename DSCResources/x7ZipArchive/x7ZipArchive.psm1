#Requires -Version 5

$script:7zExe = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '\Libs\7-Zip\7z.exe'
$script:Crc32NET = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '\Libs\Crc32.NET\Crc32.NET.dll'

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
        $msg = & $script:7zExe t $Path -ba
        if ($LASTEXITCODE -ne [ExitCode]::Success) {
            throw [System.ArgumentException]::new($msg -join $NewLine)
        }

        return $msg
    }

    static [Object[]]GetFileList([string]$Path) {
        $NewLine = [System.Environment]::NewLine
        [Archive]::TestArchive($Path) | Write-Debug
        $ret = & $script:7zExe l $Path -ba -slt
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

        Write-Verbose ('Extracting archive: {0} to {1}' -f $this.Path, $FinalDestination)

        # Test the archive has multiple root or not
        if ($IgnoreRoot) {
            $rootDir = $this.FileList | Where-Object { $_.Path.Contains('\') } | ForEach-Object { ($_.Path -split '\\')[0] } | Select-Object -First 1
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
            $ret = & $script:7zExe x $this.Path -ba -o"$Destination" -y -aoa -spe
        }
        else {
            $ret = & $script:7zExe x $this.Path -ba -o"$Destination" -y -aoa
        }

        $ExitCode = $LASTEXITCODE
        if ($ExitCode -ne [ExitCode]::Success) {
            throw [System.InvalidOperationException]::new(('Exit code:{0} ({1})' -f $ExitCode, ([ExitCode]$ExitCode).ToString()))
        }

        if ($IgnoreRoot) {
            try {
                Get-ChildItem -LiteralPath $Destination -Recurse | Move-Item -Destination $FinalDestination -Force -ErrorAction Stop
            }
            finally {
                Remove-Item -LiteralPath (Join-Path $FinalDestination $Guid) -Force -Recurse
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
        $Validate,

        [Parameter()]
        [ValidateSet('ModifiedDate', 'Size', 'CRC32')]
        [string]
        $Checksum,

        [Parameter()]
        [bool]
        $IgnoreRoot = $false,

        [Parameter()]
        [bool]
        $Force = $true,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    #TODO: Implement

    <#
    ### 想定する処理の流れ
    1. $Pathの正当性を確認
    2. $Pathにアクセスできず、Credentialが指定されている場合はMount-PSDriveWithCredentialを呼び出してマウントする
        2-1. 終了時にはかならずRemove-PSDriveでアンマウントすること
    3. Test-ArchiveExistsAtDestinationを呼び出してアーカイブがDestinationに展開済みかどうかチェック
    4. 展開済みであればEnsureにPresentをセットしたHashTableを、未展開であればEnsureにAbsentをセットしたHashTableを返す
    #>

    return @{
        Ensure      = 'Present'
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
        $Validate,

        [Parameter()]
        [ValidateSet('ModifiedDate', 'Size', 'CRC32')]
        [string]
        $Checksum,

        [Parameter()]
        [bool]
        $IgnoreRoot = $false,

        [Parameter()]
        [bool]
        $Force = $true,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    #TODO: Implement

    <#
    ### 想定する処理の流れ
    1. Get-TargetResourceを呼び出す
    2. 1の返り値のEnsureプロパティがPresentならTrueを、AbsentならFalseを返す
    #>

    return $false
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
        $Validate,

        [Parameter()]
        [ValidateSet('ModifiedDate', 'Size', 'CRC32')]
        [string]
        $Checksum,

        [Parameter()]
        [bool]
        $IgnoreRoot = $false,

        [Parameter()]
        [bool]
        $Force = $true,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    #TODO: Implement

    <#
    ### 想定する処理の流れ
    1. $Pathの正当性を確認
    2. $Pathにアクセスできず、Credentialが指定されている場合はMount-PSDriveWithCredentialを呼び出してマウントする
        2-1. 終了時にはかならずRemove-PSDriveでアンマウントすること
    3. Expand-7ZipArchiveを呼び出してアーカイブをDestinationに展開する
    #>

} # end of Set-TargetResource


<#
.SYNOPSIS
共有フォルダなどアクセスするのに別の資格情報が必要なパスをマウントする関数

.PARAMETER Path
マウントするパスを指定します

.PARAMETER Credential
使用する資格情報を指定します

.EXAMPLE
Mount-PSDriveWithCredential -Path '\\server\sharedFolder' -Credential (Get-Credential)

#>
function Mount-PSDriveWithCredential {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSDriveInfo])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    #TODO: Implement

    <#
    ### 想定する処理の流れ
    1. $Pathにアクセスできるか確認、アクセスできる場合は何も処理せず終了
    2. New-PSDriveコマンドレットを使用してパスを資格情報指定でマウントする
    #>



}


<#
.SYNOPSIS
アーカイブファイル内のファイルリストを取得する関数

.PARAMETER Path
アーカイブファイルのパスを指定します
アーカイブは7Zipで扱える形式である必要があります

.PARAMETER IgnoreRoot
IgnoreRootが指定された場合、アーカイブ内のルートフォルダを除外し、その中のファイルをリストアップします
ルートに複数のファイル/フォルダが含まれるアーカイブを指定した場合、エラーになります

.EXAMPLE
PS> Get-7ZipArchiveFileList -Path C:\Test.zip
ItemType ModifiedDate       Size CRC32    Name
-------- ------------       ---- -----    ----
Folder   2018/08/09 0:02:30    0          Folder
File     2018/08/09 0:02:36  243 DAEF1A68 Folder\001.txt

#>
function Get-7ZipArchiveFileList {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path,

        [Parameter()]
        [switch]
        $IgnoreRoot
    )

    #TODO: Implement

    <#
    ### 想定する処理の流れ
    1. $Pathが正しいか確認（ファイルが存在するか、正しいアーカイブか）
    2. 7Zipを使ってアーカイブ内のファイルリストを取得
    3. PowerShellで扱いやすいようファイルリストをパースしたうえで出力
    出力は[PsCustomObject]で、Name, Size, ItemType, ModifiedDate, CRC32プロパティを含むこと'
    #>

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
Checksumに"CRC32"を指定した場合、ファイル名に加えてCRC32ハッシュが一致するかチェックします

.EXAMPLE
PS> Test-ArchiveExistsAtDestination -Path C:\Test.zip -Destination C:\Dest
True

#>
function Test-ArchiveExistsAtDestination {
    [CmdletBinding()]
    [OutputType([bool])]
    param
    (
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path,

        [Parameter(Mandatory = $true, ParameterSetName = 'Class')]
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
        [ValidateSet('ModifiedDate', 'Size', 'CRC32')]
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
        3-3. ChecksumにCRC32が指定された場合は3-1に加えてCRC32ハッシュが一致しているか確認
    4. アーカイブ内のファイル/フォルダ全てがDestination内に存在していればTrueを、一つでも存在しないファイルがあればFalseを返す
    #>

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        try {
            $Archive = [Archive]::new($Path)
        }
        catch {
            Write-Error -Exception $_.Exception
        }
    }

    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
        #Destination folder is not exist
        Write-Verbose 'The destination folder is not exist'
        return $false
    }

    $ExistItems = Get-ChildItem -LiteralPath $Destination -Recurse -Force
    if (0 -eq @($ExistItems).Length) {
        #Destination folder is empty
        Write-Verbose 'The destination folder is empty'
        return $false
    }

    $fileList = $Archive.GetFileList()
    $rootDir = $fileList | Where-Object { $_.Path.Contains('\') } | ForEach-Object { ($_.Path -split '\\')[0] } | Select-Object -First 1

    # Test the archive has multiple root or not
    if ($IgnoreRoot) {
        [bool]$HasMultipleRoot = $false
        foreach ($Item in $fileList) {
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
    }

    foreach ($Item in $fileList) {
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
                # Truncate milliseconds
                [datetime]$s = $CurrentFileInfo.LastWriteTimeUtc
                $CurrentFileModifiedDate = [datetime]::new($s.Year, $s.Month, $s.Day, $s.Hour, $s.Minute, $s.Second, $s.Kind)
                # Compare datetime
                if ($CurrentFileModifiedDate -ne $Item.Modified.ToUniversalTime()) {
                    Write-Verbose ('The modified date of "{0}" is not same.' -f $Item.Path)
                    return $false
                }
            }
            elseif ($Checksum -eq 'Size') {
                # Compare file size
                if ($CurrentFileInfo.Length -ne $Item.Size) {
                    Write-Verbose ('The size of "{0}" is not same.' -f $Item.Path)
                    return $false
                }
            }
            elseif ($Checksum -eq 'CRC32') {
                # Compare file hash
                $CurrentFileHash = Get-CRC32Hash -Path $CurrentFileInfo.FullName
                if ($CurrentFileHash -ne $Item.CRC) {
                    Write-Verbose ('The hash of "{0}" is not same.' -f $Item.Path)
                    return $false
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

.PARAMETER IgnoreRoot
IgnoreRootが指定された場合、アーカイブ内のルートフォルダを除外して展開します

.PARAMETER Force
Forceが指定された場合、展開先フォルダの既存ファイルをアーカイブ内のファイルで上書きします
指定しない場合、展開先フォルダとアーカイブ内に同名のファイルが存在する場合、上書きせずエラーを出力します

.EXAMPLE
Expand-7ZipArchive -Path C:\Test.zip -Destination C:\Dest -Force

#>
function Expand-7ZipArchive {
    [CmdletBinding()]
    param (
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
        $Force
    )

    #TODO: Implement

    <#
    ### 想定する処理の流れ
    1. $Pathが正しいか確認（ファイルが存在するか、正しいアーカイブか）
    2. Destinationフォルダが存在しない場合はDestinationフォルダを作る
    3. 7Zipを使ってアーカイブをDestinationに展開
        3-1. アーカイブ内のファイルと同名のファイルがDestinationに存在する場合は処理停止して例外終了
        3-2. ただしForceスイッチが指定されている場合は上書き
    #>

}


Export-ModuleMember -Function *-TargetResource
