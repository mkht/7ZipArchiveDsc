function Initialize-TestEnvironment {
    param(
        [Parameter(Mandatory)]
        [string] $ModuleRoot,

        [Parameter(Mandatory)]
        [string] $ModuleName
    )

    Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process -Force

    Start-Service WinRM

    if (Test-Path "C:\Program Files\WindowsPowerShell\Modules\$ModuleName") {
        $item = Get-Item "C:\Program Files\WindowsPowerShell\Modules\$ModuleName"
        if ($item.Mode -match 'l') {
            $item.Delete()
        }
        else {
            $item | Remove-Item -Force -Recurse
        }
    }
    New-Item -Path "C:\Program Files\WindowsPowerShell\Modules\$ModuleName" -ItemType SymbolicLink -Value $ModuleRoot -Force
    #endregion Update $env:PSModulePath
}


function Restore-TestEnvironment {
    param(
        [Parameter(Mandatory)]
        [string] $ModuleRoot,

        [Parameter(Mandatory)]
        [string] $ModuleName
    )

    Stop-DscConfiguration -ErrorAction 'SilentlyContinue' -Force -WarningAction SilentlyContinue
    Remove-DscConfigurationDocument -Stage 'Current' -Force
    Remove-DscConfigurationDocument -Stage 'Pending' -Force
    Remove-DscConfigurationDocument -Stage 'Previous' -Force

    if (Test-Path "C:\Program Files\WindowsPowerShell\Modules\$ModuleName") {
        $item = Get-Item "C:\Program Files\WindowsPowerShell\Modules\$ModuleName"
        if ($item.Mode -match 'l') {
            $item.Delete()
        }
        else {
            $item | Remove-Item -Force -Recurse
        }
    }

    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force
}
