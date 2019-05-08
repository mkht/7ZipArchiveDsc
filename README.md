# 7ZipArchiveDsc

[![Build Status](https://mkht.visualstudio.com/7ZipArchiveDsc/_apis/build/status/mkht.7ZipArchiveDsc?branchName=master)](https://mkht.visualstudio.com/7ZipArchiveDsc/_build/latest?definitionId=6&branchName=master)

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

+ **[bool] Validate** (Write):
    + Specifies whether or not to validate that a file at the destination with the same name as a file in the archive actually matches that corresponding file in the archive by the specified checksum method.
    + The default is `False`

+ **[string] Checksum** (Write):
    + The Checksum method to use to validate whether or not a file at the destination with the same name as a file in the archive actually matches that corresponding file in the archive.
    + An exception will be thrown if Checksum is specified while Validate is specified as false. 
    + The default value is `ModifiedDate`. { ModifiedDate | Size | CRC32 }

+ **[bool] IgnoreRoot** (Write):
    + When the IgnoreRoot is specified as true, this resource will expand files in the root directory of the archive to the destination.
    + An exception will be thrown if the archive has multiple files or directories in the root. 
    + The default is `False`

+ **[bool] Clean** (Write):
    + When the Clean is specified as true, this resource removes all files in the destination before expand.
    + The default is `False`

+ **[PSCredential] Credential** (Write):
    + The credential for access to the archive on a remote source if needed.


## Usage
See [Examples](/Examples).

## Changelog
### Not Released Yet


## Licenses
The license of this software is not specified yet.

## Libraries
This software uses below softwares and libraries.

+ [7-Zip](https://www.7-zip.org/)
    - Copyright (C) Igor Pavlov.
    - Licensed under the **GNU LGPL** and **BSD 3-clause License**.  
      https://www.7-zip.org/license.txt

+ [Crc32.NET](https://github.com/force-net/Crc32.NET)
    - Copyright (c) force
    - Licensed under the **[MIT License](https://github.com/force-net/Crc32.NET/blob/v1.2.0/LICENSE)**.
