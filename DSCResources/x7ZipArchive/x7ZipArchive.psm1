#Requires -Version 5
using namespace System.IO

$script:Crc16 = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '\Libs\CRC16\CRC16.cs'
$script:Crc32NET = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '\Libs\Crc32.NET\Crc32.NET.dll'
$OSArch = (Get-CimInstance Win32_OperatingSystem).OSArchitecture
switch -regex ($OSArch) {
    'ARM 64' {
        $script:7zExe = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '\Libs\7-Zip\ARM64\7z.exe'
        break
    }
    '64' {
        $script:7zExe = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '\Libs\7-Zip\x64\7z.exe'
        break
    }
    Default {
        $script:7zExe = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '\Libs\7-Zip\x86\7z.exe'
    }
}

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
    [long] $Files = 0
    [long] $Folders = 0
    [FileInfo] $FileInfo
    [Object[]] $FileList

    Archive([string]$Path) {
        $this.Init($Path, $null)
    }

    Archive([string]$Path, [securestring]$Password) {
        $this.Init($Path, $Password)
    }

    Hidden [void]Init([string]$Path, [securestring]$Password) {
        $this.Path = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)

        $info = [Archive]::TestArchive($Path, $Password) |`
            ForEach-Object { $_.Replace('\', '\\') } |`
            ForEach-Object { if ($_ -notmatch '=') { $_.Replace(':', ' =') }else { $_ } } |`
            Where-Object { $_ -match '^.+=.+$' } |`
            ConvertFrom-StringData

        $this.Type = [string]$info.Type
        if ([long]::TryParse($info.Files, [ref]$null)) {
            $this.Files = [long]::Parse($info.Files)
        }
        if ([long]::TryParse($info.Folders, [ref]$null)) {
            $this.Folders = [long]::Parse($info.Folders)
        }
        $this.FileInfo = [FileInfo]::new($this.Path)
        $this.FileList = [Archive]::GetFileList($this.Path, $Password)
    }

    [Object[]]GetFileList() {
        return $this.FileList
    }

    static [string[]]TestArchive([string]$Path) {
        return [Archive]::TestArchive($Path, $null)
    }

    static [string[]]TestArchive([string]$Path, [securestring]$Password) {
        $LiteralPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
        $NewLine = [System.Environment]::NewLine
        if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf -ErrorAction Ignore)) {
            throw [FileNotFoundException]::new()
        }

        $pPwd = [string]::Empty
        if ($Password) {
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            $pPwd = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }

        # Test integrity of archive
        $msg = $null
        $currentEA = $global:ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $msg = & $script:7zExe t "$LiteralPath" -ba -p"$pPwd" 2>&1
        }
        catch { }
        finally {
            $global:ErrorActionPreference = $currentEA
        }
        if ($LASTEXITCODE -ne [ExitCode]::Success) {
            throw [System.ArgumentException]::new($msg -join $NewLine)
        }

        return $msg
    }

    static [Object[]]GetFileList([string]$Path) {
        return [Archive]::GetFileList($Path, $null)
    }

    static [Object[]]GetFileList([string]$Path, [securestring]$Password) {
        $LiteralPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
        $NewLine = [System.Environment]::NewLine
        Write-Verbose 'Enumerating files & folders in the archive.'

        $pPwd = [string]::Empty
        if ($Password) {
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            $pPwd = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }

        $ret = $null
        $currentEA = $global:ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $ret = & $script:7zExe l "$LiteralPath" -ba -slt -p"$pPwd" 2>&1
        }
        catch { }
        finally {
            $global:ErrorActionPreference = $currentEA
        }

        if ($LASTEXITCODE -ne [ExitCode]::Success) {
            throw [System.InvalidOperationException]::new($ret -join $NewLine)
        }

        return ($ret -join $NewLine).Replace('\', '\\') -split "$NewLine$NewLine" |`
            ConvertFrom-StringData |`
            ForEach-Object {
            $tmp = $_

            $tmp.Size = [long]$_.Size
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
                $tmp.'Packed Size' = [long]$_.'Packed Size'
            }

            if ($_.Folder) {
                $tmp.Folder = [bool]($_.Folder -eq '+')
                $tmp.ItemType = if ($tmp.Folder) { 'Folder' }else { 'File' }
            }
            elseif ($_.Attributes) {
                $tmp.Folder = [bool]($_.Attributes.Contains('D'))
                $tmp.ItemType = if ($tmp.Folder) { 'Folder' }else { 'File' }
            }
            else {
                # Some type of archive (e.g. VHDX) has no folder flag or attributes
                $tmp.ItemType = 'File'
            }

            if ($_.'Volume Index') {
                $tmp.'Volume Index' = [long]$_.'Volume Index'
            }

            if ($_.Offset) {
                $tmp.Offset = [long]$_.Offset
            }

            [PSCustomObject]$tmp
        }
    }

    [void]Extract([string]$Destination) {
        $this.Extract($Destination, $false)
    }

    [void]Extract([string]$Destination, [securestring]$Password) {
        $this.Extract($Destination, $Password, $false)
    }

    [void]Extract([string]$Destination, [bool]$IgnoreRoot) {
        $this.Extract($Destination, $null, $IgnoreRoot)
    }

    [void]Extract([string]$Destination, [securestring]$Password , [bool]$IgnoreRoot) {
        $Seed = -join ((1..10) | % { Get-Random -input ([char[]]((48..57) + (65..90) + (97..122))) })
        $FinalDestination = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Destination)

        $activityMessage = ('Extracting archive: {0} to {1}' -f $this.Path, $FinalDestination)
        $statusMessage = 'Extracting...'

        Write-Verbose $activityMessage

        $pPwd = [string]::Empty
        if ($Password) {
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            $pPwd = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }

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

            $Destination = $global:ExecutionContext.SessionState.Path.Combine($FinalDestination, "$Seed\$rootDir")
        }

        if ($IgnoreRoot) {
            $currentEA = $global:ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                & $script:7zExe x "$($this.Path)" -ba -o"$Destination" -p"$pPwd" -y -aoa -spe -bsp1 | ForEach-Object -Process {
                    if ($_ -match '(\d+)\%') {
                        $progress = $Matches.1
                        if ([int]::TryParse($progress, [ref]$progress)) {
                            Write-Progress -Activity $activityMessage -Status $statusMessage -PercentComplete $progress -CurrentOperation "$progress % completed."
                        }
                    }
                }
            }
            catch { }
            finally {
                $global:ErrorActionPreference = $currentEA
            }
        }
        else {
            $currentEA = $global:ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                & $script:7zExe x "$($this.Path)" -ba -o"$Destination" -p"$pPwd" -y -aoa -bsp1 | ForEach-Object -Process {
                    if ($_ -match '(\d+)\%') {
                        $progress = $Matches.1
                        if ([int]::TryParse($progress, [ref]$progress)) {
                            Write-Progress -Activity $activityMessage -Status $statusMessage -PercentComplete $progress -CurrentOperation "$progress % completed."
                        }
                    }
                }
            }
            catch { }
            finally {
                $global:ErrorActionPreference = $currentEA
            }
        }

        $ExitCode = $LASTEXITCODE
        if ($ExitCode -ne [ExitCode]::Success) {
            if (Test-Path -LiteralPath ($global:ExecutionContext.SessionState.Path.Combine($FinalDestination, $Seed)) -ErrorAction Ignore) {
                Remove-Item -LiteralPath ($global:ExecutionContext.SessionState.Path.Combine($FinalDestination, $Seed)) -Force -Recurse -ErrorAction SilentlyContinue
            }
            throw [System.InvalidOperationException]::new(('Exit code:{0} ({1})' -f $ExitCode, ([ExitCode]$ExitCode).ToString()))
        }
        else {
            Write-Progress -Activity $activityMessage -Status 'Extraction complete.' -Completed
        }

        if ($IgnoreRoot) {
            try {
                Get-ChildItem -LiteralPath $Destination -Force | Move-Item -Destination $FinalDestination -Force -ErrorAction Stop
            }
            finally {
                Remove-Item -LiteralPath ($global:ExecutionContext.SessionState.Path.Combine($FinalDestination, $Seed)) -Force -Recurse -ErrorAction SilentlyContinue
            }
        }

        Write-Verbose 'Extraction completed successfully.'
    }

    static [void]Extract([string]$Path, [string]$Destination) {
        [Archive]::Extract($Path, $Destination, $false)
    }

    static [void]Extract([string]$Path, [string]$Destination, [securestring]$Password) {
        $archive = [Archive]::new($Path, $Password)
        $archive.Extract($Destination, $Password)
    }

    static [void]Extract([string]$Path, [string]$Destination, [bool]$IgnoreRoot) {
        $archive = [Archive]::new($Path)
        $archive.Extract($Destination, $IgnoreRoot)
    }

    static [void]Extract([string]$Path, [string]$Destination, [securestring]$Password , [bool]$IgnoreRoot) {
        $archive = [Archive]::new($Path, $Password)
        $archive.Extract($Destination, $Password, $IgnoreRoot)
    }

    static [void]Compress([string[]]$Path, [string]$Destination) {
        [Archive]::Compress($Path, $Destination, [string]::Empty, $null)
    }

    static [void]Compress([string[]]$Path, [string]$Destination, [string]$Type) {
        [Archive]::Compress($Path, $Destination, $Type, $null)
    }

    static [void]Compress([string[]]$Path, [string]$Destination, [string]$Type, [securestring]$Password) {
        $Destination = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Destination)
        $activityMessage = ('Compress archive: {0}' -f $Destination)
        $statusMessage = 'Compressing...'

        $oldItem = $null
        if (Test-Path $Destination -PathType Leaf -ErrorAction Ignore) {
            $item = Get-Item -LiteralPath $Destination
            $tmpName = $item.BaseName + ( -join ((1..5) | % { Get-Random -input ([char[]]((48..57) + (65..90) + (97..122))) })) + $item.Extension
            $oldItem = $item | Rename-Item -NewName $tmpName -Force -PassThru
        }

        Write-Verbose $activityMessage
        [string]$TargetFiles = @($Path).ForEach( {
                $LiteralPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($_)
                "`"$LiteralPath`""
            }) -join ' '

        [string[]]$CmdParam = ($script:7zExe, 'a', "`"$Destination`"", $TargetFiles, '-ba', '-y', '-ssw', '-spd', '-bsp1')
        if ($Password) {
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            $pPwd = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            $CmdParam += ('-p"{0}"' -f $pPwd)
        }
        if ($Type) {
            $CmdParam += ('-t"{0}"' -f $Type)
        }
        $CmdParam += '2>&1'

        $msg = $null
        $currentEA = $global:ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $msg = Invoke-Expression ($CmdParam -join ' ') | ForEach-Object -Process {
                if ($_ -match '(\d+)\%') {
                    $progress = $Matches.1
                    if ([int]::TryParse($progress, [ref]$progress)) {
                        Write-Progress -Activity $activityMessage -Status $statusMessage -PercentComplete $progress -CurrentOperation "$progress % completed."
                    }
                }
            }
        }
        catch { }
        finally {
            $global:ErrorActionPreference = $currentEA
        }

        $ExitCode = $LASTEXITCODE
        if ($ExitCode -ne [ExitCode]::Success) {
            if (($null -ne $oldItem) -and (Test-Path $oldItem -ErrorAction Ignore)) {
                Remove-Item $Destination -ErrorAction SilentlyContinue
                Move-Item $oldItem $Destination -Force
            }
            throw [System.ArgumentException]::new($msg -join [System.Environment]::NewLine)
        }
        else {
            if (($null -ne $oldItem) -and (Test-Path $oldItem -ErrorAction Ignore)) {
                Remove-Item $oldItem -Force
            }
            Write-Progress -Activity $activityMessage -Status 'Compression complete.' -Completed
        }

        Write-Verbose 'Compression complete.'
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
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction Ignore)) {
            Write-Error -Exception ([FileNotFoundException]::new('The file does not exist.'))
        }
        else {
            try {
                [FileStream]$stream = [File]::Open($Path, [FileMode]::Open, [FileAccess]::Read, ([FileShare]::ReadWrite + [FileShare]::Delete))
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
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction Ignore)) {
            Write-Error -Exception ([FileNotFoundException]::new('The file does not exist.'))
            return
        }

        $crc32 = [Force.Crc32.Crc32Algorithm]::new()
        try {
            [FileStream]$stream = [File]::Open($Path, [FileMode]::Open, [FileAccess]::Read, ([FileShare]::ReadWrite + [FileShare]::Delete))
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
    [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingPlainTextForPassword', '')]
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
        [string]
        $Password,

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

    # Enable extended long path support (if it does not enabled in current environment)
    if (-not (Test-ExtendedLengthPathSupport)) {
        $local:NeedToRevertExtendedLengthPathSupport = $true
        Set-ExtendedLengthPathSupport -Enable $true
    }

    $local:PsDrive = $null
    $OriginalPath = $Path
    $OriginalDestination = $Destination
    $Path = Convert-RelativePathToAbsolute -Path $Path
    $Destination = Convert-RelativePathToAbsolute -Path $Destination

    # Checksumが指定されているが、ValidateがFalseの場合はエラー
    if ($PSBoundParameters.ContainsKey('Checksum') -and (-not $Validate)) {
        Write-Error -Exception ([System.ArgumentException]::new('Please specify the Validate parameter as true to use the Checksum parameter.'))
        return
    }

    if ($Credential) {
        $local:PsDrive = Mount-PSDriveWithCredential -Root (Split-Path $OriginalPath -Parent) -Credential $Credential -ErrorAction Stop
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction Ignore)) {
        Write-Error "The path $OriginalPath does not exist or is not a file"
        UnMount-PSDrive -Name $local:PsDrive.Name -ErrorAction SilentlyContinue
        return
    }

    $testParam = @{
        Path        = $Path
        Destination = $Destination
        IgnoreRoot  = $IgnoreRoot
        Clean       = $Clean
    }

    if ($Password) {
        $testParam.Password = ConvertTo-SecureString $Password -AsPlainText -Force
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
        if ($local:NeedToRevertExtendedLengthPathSupport) {
            Set-ExtendedLengthPathSupport -Enable $false
        }

    }

    if ($testResult) {
        $Ensure = 'Present'
    }
    else {
        $Ensure = 'Absent'
    }

    return @{
        Ensure      = $Ensure
        Path        = $OriginalPath
        Destination = $OriginalDestination
    }
} # end of Get-TargetResource


function Test-TargetResource {
    [CmdletBinding()]
    [OutputType([bool])]
    [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingPlainTextForPassword', '')]
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
        [string]
        $Password,

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
    [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingPlainTextForPassword', '')]
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
        [string]
        $Password,

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

    # Enable extended long path support (if it does not enabled in current environment)
    if (-not (Test-ExtendedLengthPathSupport)) {
        $local:NeedToRevertExtendedLengthPathSupport = $true
        Set-ExtendedLengthPathSupport -Enable $true
    }

    $local:PsDrive = $null
    $OriginalPath = $Path
    # $OriginalDestination = $Destination
    $Path = Convert-RelativePathToAbsolute -Path $Path
    $Destination = Convert-RelativePathToAbsolute -Path $Destination

    # Checksumが指定されているが、ValidateがFalseの場合はエラー
    if ($PSBoundParameters.ContainsKey('Checksum') -and (-not $Validate)) {
        Write-Error -Exception ([System.ArgumentException]::new('Please specify the Validate parameter as true to use the Checksum parameter.'))
        return
    }

    if ($Credential) {
        $local:PsDrive = Mount-PSDriveWithCredential -Root (Split-Path $OriginalPath -Parent) -Credential $Credential -ErrorAction Stop
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction Ignore)) {
        Write-Error "The path $OriginalPath does not exist or is not a file"
        UnMount-PSDrive -Name $local:PsDrive.Name -ErrorAction SilentlyContinue
        return
    }

    $testParam = @{
        Path        = $Path
        Destination = $Destination
        IgnoreRoot  = $IgnoreRoot
        Clean       = $Clean
    }

    if ($Password) {
        $testParam.Password = ConvertTo-SecureString $Password -AsPlainText -Force
    }

    try {
        Expand-7ZipArchive @testParam -ErrorAction Stop
    }
    catch {
        Write-Error -Exception $_.Exception
    }
    finally {
        UnMount-PSDrive -Name $local:PsDrive.Name -ErrorAction SilentlyContinue
        if ($local:NeedToRevertExtendedLengthPathSupport) {
            Set-ExtendedLengthPathSupport -Enable $false
        }
    }
} # end of Set-TargetResource


<#
.SYNOPSIS
アーカイブファイル内のファイルリストを取得する関数

.PARAMETER Path
アーカイブファイルのパスを指定します
アーカイブは7Zipで扱える形式である必要があります

.PARAMETER Password
アーカイブがパスワード保護されている場合、パスワードを指定する必要があります

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
        $Archive,

        [Parameter(ParameterSetName = 'Path')]
        [AllowNull()]
        [securestring]
        $Password
    )

    (Get-7ZipArchive @PSBoundParameters).FileList
}


<#
.SYNOPSIS
アーカイブファイルの情報を取得する関数

.PARAMETER Path
アーカイブファイルのパスを指定します
アーカイブは7Zipで扱える形式である必要があります

.PARAMETER Password
アーカイブがパスワード保護されている場合、パスワードを指定する必要があります

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
        $Archive,

        [Parameter(ParameterSetName = 'Path')]
        [AllowNull()]
        [securestring]
        $Password
    )

    # $Archiveクラスのインスタンスを返すラッパー関数

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        # Path normalization
        $Path = Convert-RelativePathToAbsolute -Path $Path
        try {
            $Archive = [Archive]::new($Path, $Password)
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

.PARAMETER Password
アーカイブがパスワード保護されている場合、パスワードを指定する必要があります

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
        [AllowNull()]
        [securestring]
        $Password,

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

    if (-not (Test-Path -LiteralPath $Destination -PathType Container -ErrorAction Ignore)) {
        #Destination folder does not exist
        Write-Verbose 'The destination folder does not exist'
        return $false
    }

    if ((Get-ChildItem -LiteralPath $Destination -Force | Measure-Object).Count -eq 0) {
        #Destination folder is empty
        Write-Verbose 'The destination folder is empty'
        return $false
    }

    $archive = Get-7ZipArchive -Path $Path -Password $Password

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
        $AbsolutePath = Convert-RelativePathToAbsolute -Path $global:ExecutionContext.SessionState.Path.Combine($Destination, $RelativePath)

        $tParam = @{
            LiteralPath = $AbsolutePath
            PathType    = $(if ($Item.ItemType -eq 'File') { 'Leaf' }else { 'Container' })
        }
        if (-not (Test-Path @tParam)) {
            # Target file not exist => return false
            Write-Verbose ('The file "{0}" in the archive does not exist in the destination folder' -f $Item.Path)
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

                # Truncate milliseconds of the ModifiedDate property of the file in the archive
                $ArchiveileModifiedDate = [datetime]::new($Item.Modified.Year, $Item.Modified.Month, $Item.Modified.Day, $Item.Modified.Hour, $Item.Modified.Minute, $Item.Modified.Second, $Item.Modified.Kind)

                # Compare datetime
                if ($CurrentFileModifiedDate -ne $ArchiveileModifiedDate) {
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
                    # Some types of an archive does not record CRC value of the 0-byte file.
                    if ([string]::IsNullOrEmpty($Item.CRC)) {
                        $ArchiveFileHash = '00000000'
                    }
                    else {
                        $ArchiveFileHash = $Item.CRC
                    }

                    if ($archive.Type -eq 'lzh') {
                        #LZH has CRC16 checksum
                        $CurrentFileHash = Get-CRC16Hash -Path $CurrentFileInfo.FullName
                    }
                    else {
                        $CurrentFileHash = Get-CRC32Hash -Path $CurrentFileInfo.FullName
                    }

                    # Compare file hash
                    if ($CurrentFileHash -ne $ArchiveFileHash) {
                        Write-Verbose ('The hash of "{0}" is not same.' -f $Item.Path)
                        Write-Verbose ('Exist:{0} / Archive:{1}' -f $CurrentFileHash, $ArchiveFileHash)
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

.PARAMETER Password
アーカイブがパスワード保護されている場合、パスワードを指定する必要があります

.PARAMETER IgnoreRoot
IgnoreRootが指定された場合、アーカイブ内のルートフォルダを除外して展開します

.PARAMETER Clean
Cleanが指定された場合、展開先フォルダの既存ファイルをすべて削除してからアーカイブを展開します
指定しない場合、展開先フォルダの既存ファイルは残したまま展開します

.EXAMPLE
Expand-7ZipArchive -Path C:\Test.zip -Destination C:\Dest -Clean

#>
function Expand-7ZipArchive {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param (
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true ,
            ValueFromPipelineByPropertyName = $true ,
            ParameterSetName = 'Path')]
        [Alias('PSPath', 'LiteralPath', 'LP')]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Path,

        [Parameter(Mandatory = $true, DontShow = $true, ParameterSetName = 'Class')]
        [ValidateNotNullOrEmpty()]
        [Archive]
        $Archive,

        [Parameter(Mandatory = $true, Position = 1, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Destination,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [securestring]
        $Password,

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

    Begin {
        if ($Clean) {
            Write-Verbose ('Clean option is specified. All items in {0} will be removed' -f $Destination)
            if (Test-Path -LiteralPath $Destination -PathType Container) {
                Get-ChildItem -LiteralPath $Destination -Recurse -Force -Verbose:$false -ErrorAction SilentlyContinue |`
                    Remove-Item -Force -Recurse -ErrorAction SilentlyContinue -Verbose:$false
            }
        }
    }

    Process {
        $Destination = Convert-RelativePathToAbsolute -Path $Destination
        if ($PSCmdlet.ParameterSetName -eq 'Class') {
            try {
                $Archive.Extract($Destination, $Password, $IgnoreRoot)
            }
            catch {
                Write-Error -Exception $_.Exception
            }
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'Path') {
            foreach ($item in $Path) {
                try {
                    $item = Convert-RelativePathToAbsolute -Path $item
                    [Archive]::Extract($item, $Destination, $Password, $IgnoreRoot)
                }
                catch {
                    Write-Error -Exception $_.Exception
                }
            }
        }
    }
}


<#
.SYNOPSIS
アーカイブを作成する関数

.PARAMETER Path
圧縮したいファイルのリスト

.PARAMETER Destination
アーカイブファイルの出力先
出力先に同名のファイルが存在する場合は、確認なしで上書きされることに注意してください

.PARAMETER Password
アーカイブのパスワード

.PARAMETER Type
アーカイブの形式
サポートされている値：'7z', 'zip', 'bzip2', 'gzip', 'tar', 'wim', 'xz'
指定しない場合、出力先ファイルの拡張子から自動判別します。

.EXAMPLE
$pwd = Read-Host -AsSecureString
Get-Item * | Compress-7ZipArchive -Destination C:\Archive.7z -Password $pwd

#>
function Compress-7ZipArchive {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param (
        [Parameter(Mandatory = $true, Position = 0 , ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Path,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'Literal')]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $LiteralPath,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Destination,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [securestring]
        $Password,

        [Parameter(Mandatory = $false)]
        [ValidateSet('7z', 'zip', 'bzip2', 'gzip', 'tar', 'wim', 'xz')]
        [string]
        $Type
    )

    Begin {
        $FileList = New-Object 'System.Collections.Generic.HashSet[string]'
    }

    Process {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $Object = $Path
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'Literal') {
            $Object = $LiteralPath
        }

        foreach ($o in $Object) {
            $o = Convert-RelativePathToAbsolute -Path $o
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $Items = Get-Item -Path $o -ErrorAction SilentlyContinue
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'Literal') {
                $Items = Get-Item -LiteralPath $o -ErrorAction SilentlyContinue
            }

            foreach ($item in $Items) {
                $null = $FileList.Add($item.FullName)
            }
        }
    }

    End {
        if ($FileList.Count -le 0) {
            Write-Error -Exception [FileNotFoundException]::new('No item found.')
            return
        }

        try {
            $AllItems = New-Object System.String[]($FileList.Count)
            $FileList.CopyTo($AllItems, 0)
            $null = [Archive]::Compress($AllItems, $Destination, $Type, $Password)
        }
        catch {
            Write-Error -Exception $_.Exception
            return
        }
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
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

function Convert-RelativePathToAbsolute {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateLength(1, 32000)]
        [string]
        $Path
    )

    $EXTENDED_PATH_PREFIX = '\\?\'

    # Convert relative path to absolute path
    $ResolvedPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)

    # Add "\\?\" prefix for too long paths. (only when the system supports that)
    # https://docs.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation
    # However, in PowerShell 6 and later, the prefix is not required.
    # Rather, in PowerShell 7.1 and later, it should not be added, because it will cause inconsistent behavior.
    # https://github.com/PowerShell/PowerShell/issues/10805
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        if (Test-ExtendedLengthPathSupport) {
            if (-not $ResolvedPath.StartsWith($EXTENDED_PATH_PREFIX)) {
                if (([uri]$ResolvedPath).IsUnc) {
                    $ResolvedPath = $EXTENDED_PATH_PREFIX + 'UNC\' + $ResolvedPath.Substring(2)
                }
                else {
                    $ResolvedPath = $EXTENDED_PATH_PREFIX + $ResolvedPath
                }
            }
        }
    }

    $ResolvedPath
}

function Test-ExtendedLengthPathSupport {
    try {
        $null = [System.IO.Path]::GetFullPath('\\?\C:\extended_length_path_support_test.txt')
        return $true
    }
    catch {
        return $false
    }
}

function Set-ExtendedLengthPathSupport {
    param (
        [Parameter(Mandatory, Position = 0)]
        [bool]$Enable
    )

    $Disable = -not $Enable
    [int32]$IntFlag = if ($Disable) { 1 }else { -1 }

    $CurrentStatus = Test-ExtendedLengthPathSupport
    if ($CurrentStatus -eq $Enable) {
        return
    }

    $AppContextSwitches = [type]::GetType('System.AppContextSwitches')
    if (-not $AppContextSwitches) {
        Write-Error 'Could not find type System.AppContextSwitches'
        return
    }

    [System.AppContext]::SetSwitch('Switch.System.IO.UseLegacyPathHandling', $Disable)
    $InternalField = $AppContextSwitches.GetField('_useLegacyPathHandling', ([System.Reflection.BindingFlags]::Static -bor [System.Reflection.BindingFlags]::NonPublic))
    $InternalField.SetValue($null, $IntFlag)
    # Write-Verbose ('Set Extended Length Path feature as {0}.' -f $(if ($Enable) { 'Enabled' } else { 'Disabled' }))
}


Export-ModuleMember -Function @(
    'Get-TargetResource',
    'Test-TargetResource',
    'Set-TargetResource',
    'Expand-7ZipArchive',
    'Compress-7ZipArchive'
)
