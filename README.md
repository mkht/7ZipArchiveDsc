# 7ZipArchiveDsc

[![7ZipArchiveDsc](https://github.com/mkht/7ZipArchiveDsc/actions/workflows/test.yml/badge.svg)](https://github.com/mkht/7ZipArchiveDsc/actions/workflows/test.yml)

PowerShell DSC Resource to expand an archive file to a specific path. 

## Install
You can install the resource from [PowerShell Gallery](https://www.powershellgallery.com/packages/7ZipArchiveDsc/).
```Powershell
Install-Module -Name 7ZipArchiveDsc
```

## Resources
* **x7ZipArchive**
DSC Resource to expand an archive file to a specific path.  
This resource uses [7-Zip](https://www.7-zip.org/) utility for expand an archive. You can expand all type of the archives that is supported in 7-Zip.  

## Properties

### x7ZipArchive
+ **[string] Path** (key):
    + The path to the archive file that should be expanded.

+ **[string] Destination** (key):
    + The path where the specified archive file should be expanded.

+ **[string] Password** (Write):
    + Specifies the password for archive file.

+ **[bool] Validate** (Write):
    + Specifies whether or not to validate that a file at the destination with the same name as a file in the archive actually matches that corresponding file in the archive by the specified checksum method.
    + The default is `False`

+ **[string] Checksum** (Write):
    + The Checksum method to use to validate whether or not a file at the destination with the same name as a file in the archive actually matches that corresponding file in the archive.
    + An exception will be thrown if Checksum is specified while Validate is specified as false. 
    + The default value is `ModifiedDate`. { ModifiedDate | Size | CRC }
    > * When ModifiedDate is specified, milliseconds in the time information are truncated and compared.

+ **[bool] IgnoreRoot** (Write):
    + When the IgnoreRoot is specified as true, this resource will expand files in the root directory of the archive to the destination.
    + An exception will be thrown if the archive has multiple files or directories in the root. 
    + The default is `False`

+ **[bool] Clean** (Write):
    + When the Clean is specified as true, this resource removes all files in the destination before expand.
    + The default is `False`

+ **[PSCredential] Credential** (Write):
    + The credential for access to the archive on a remote source if needed.


### Usage
See [Examples](/Examples).

----
## Functions

### Compress-7ZipArchive
Creates an archive from specified files and folders.

+ **Syntax**
```PowerShell
Compress-7ZipArchive [-Path] <string[]> [-Destination] <string> [-Password <securestring>] [-Type <string>]
```

+ **Example1**
```PowerShell
PS> $SecurePassword = Read-Host -AsSecureString
PS> Compress-7ZipArchive -Path "C:\Folder1", "C:\Folder2" -Destination "C:\Archive.zip" -Password $SecurePassword
```

+ **Example2**
```PowerShell
PS> Get-Item D:\*.txt | Compress-7ZipArchive -Destination "C:\Archive.zip"
```

+ **Parameters**
  - **[string[]] Path**
    Specifies the path to the files that you want to add to the archive.  
    This parameter is required.

  - **[string] Destination**
    Specifies the path to the archive output file.  
    This parameter is required.

  - **[securestring] Password**
    Specifies the password for archive file.

  - **[string] Type**
    Specifies the type of the archive file.  
    You can choose from `7z`, `zip`, `bzip2`, `gzip`, `tar`, `wim` and `xz`.  
    When the parameter is not specified, the type will be determined from extension of the output file.

### Expand-7ZipArchive
Extracts files from a specified archive file.

+ **Syntax**
```PowerShell
Expand-7ZipArchive [-Path] <string[]> [-Destination] <string> [-Password <securestring>] [-IgnoreRoot] [-Clean]
```

+ **Example**
```PowerShell
PS> Expand-7ZipArchive -Path "C:\Archive.zip" -Destination "C:\Destination"
PS> Get-Item "C:\Archive.zip" | Expand-7ZipArchive -Destination "C:\Destination"
```

+ **Parameters**
  - **[string[]] Path**
    Specifies the path to the archive file.   
    This parameter is required.

  - **[string] Destination**
    Specifies the path to the folder in which you want to extract files.  
    This parameter is required.

  - **[securestring] Password**
    Specifies the password for archive file.

  - **[switch] IgnoreRoot**
    When the switch is specified, this command will extract files in the root directory of the archive to the destination.  
    An exception will be thrown if the archive has multiple files or directories in the root. 
    
  - **[switch] Clean**
    When the switch is specified, this command removes all files in the destination before extract.


## Changelog
### 2.1.0
  - 7-Zip updated to 24.09

### 2.0.0
  - 7-Zip updated to 24.07

### 1.9.1
  - The process of specifying `IgnoreRoot` would fail in environments where certain anti-virus software is installed.

### 1.9.0
  - 7-Zip updated to 23.01

### 1.8.2
  - Fixed an issue where extraction would fail if the archive contained files larger than 2GB. [#7](https://github.com/mkht/7ZipArchiveDsc/issues/7)
  - Improve performance.
  - 7-Zip updated to 22.01

### 1.8.1
  - Fixed an error when specifying a UNC path and credentials.

### 1.8.0
  - 7z.exe updated to 22.00

### 1.7.0
  - Improve long path support

### 1.6.0
  - Add support for paths longer than 260 characters. [#6](https://github.com/mkht/7ZipArchiveDsc/issues/6)
  - Better English messages.

### 1.5.2
  - 7z.exe updated to 21.07

### 1.5.1
  - 7z.exe updated to 21.06

### 1.5.0
  - 7z.exe updated to 21.05

### 1.4.0
 - `Expand-7ZipArchive` accepts input from pipeline [#5](https://github.com/mkht/7ZipArchiveDsc/issues/5)
  ```PowerSHell
  Get-Item "C:\Archive.zip" | Expand-7ZipArchive -Destination "C:\Destination"
  ```
 - Switch CI platform to GitHub Actions

### 1.3.4
  - Fixed issue that an incorrect result is returned if 0-byte files exists in the archive.
    (The fix in v1.3.3 was insufficient)

### ~~1.3.3~~
  ~~- Fixed issue that an incorrect result is returned if 0-byte files exists in the archive.~~

### 1.3.2
  - Fixed minor issues.
  - Improved stabilities.

### 1.3.1
  - Add `Password` property for extracting archives that has protected with password.
  - Export useful functions `Expand-7ZipArchive` and `Compress-7ZipArchive`
  - Improve error handling.
  - Fixed some security issues.

### 1.1.0
  - Acceptable values of `Checksum` has been changed to `ModifiedDate`, `Size` and `CRC` (`CRC32` is remained for backwards compatibility, but will soon deprecated.) 
  - Fixed issue that the CRC hash of LZH archive is not calculated properly.
  - Increased performance.
  - Removed unnecessary files.

### 1.0.0
  - Initial public release

## Licenses
[MIT License](/LICENSE)

## Libraries
This software uses below softwares and libraries.

+ [7-Zip](https://www.7-zip.org/)
    - Copyright (C) Igor Pavlov.
    - Licensed under the **GNU LGPL** and **BSD 3-clause License**.  
      https://www.7-zip.org/license.txt

+ [Crc32.NET](https://github.com/force-net/Crc32.NET)
    - Copyright (c) force
    - Licensed under the **[MIT License](https://github.com/force-net/Crc32.NET/blob/v1.2.0/LICENSE)**.
