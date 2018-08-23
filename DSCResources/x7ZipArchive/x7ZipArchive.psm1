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
        [ValidateSet('ModifiedDate', 'Size', 'CRC32')]
        [string]
        $Checksum
    )

    #TODO: Implement

    <#
    ### 想定する処理の流れ
    1. $Pathが正しいか確認（ファイルが存在するか、正しいアーカイブか）
    2. Destinationが存在しないor空フォルダの場合はFalseを返す
    3. Get-7ZipArchiveFileListを呼び出してアーカイブ内のファイルリストを取得
    4. アーカイブ内のファイル/フォルダ全てがDestination内に存在するか確認
        4-1. Checksumが指定されていない場合はファイル/フォルダ名が一致していればOKとする
        4-2. ChecksumにModifiedDateが指定された場合は4-1に加えてファイルの更新日時が一致しているか確認
        4-3. ChecksumにSizeが指定された場合は4-1に加えてファイルサイズが一致しているか確認
        4-3. ChecksumにCRC32が指定された場合は4-1に加えてCRC32ハッシュが一致しているか確認
    5. アーカイブ内のファイル/フォルダ全てがDestination内に存在していればTrueを、一つでも存在しないファイルがあればFalseを返す
    #>

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
