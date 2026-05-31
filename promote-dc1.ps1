[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DomainName,
    [Parameter(Mandatory)][string]$SafeModePassword
)

# Promotes the local machine as the first DC of a new forest.
# Designed to be invoked once via Azure Custom Script Extension.
# Idempotent: bails early if it has already promoted (marker file).

$ErrorActionPreference = 'Stop'
$logFile = 'C:\dc-promote.log'
Start-Transcript -Path $logFile -Append

try {
    $marker = 'C:\dc-promoted.flag'
    if (Test-Path $marker) {
        Write-Output "Already promoted (marker at $marker). Exiting."
        exit 0
    }

    Write-Output "=== Promoting $env:COMPUTERNAME as forest root for $DomainName ==="

    # ---- 1. Initialize the data disk ----
    Write-Output "Looking for a RAW data disk..."
    $raw = Get-Disk | Where-Object { $_.PartitionStyle -eq 'RAW' -and $_.Number -ne 0 } | Select-Object -First 1
    if ($null -eq $raw) {
        Write-Output "No RAW disk found. Assuming F: already prepared."
    }
    else {
        Write-Output "Initializing disk $($raw.Number) (size $([math]::Round($raw.Size/1GB,1)) GB)..."
        Initialize-Disk -Number $raw.Number -PartitionStyle GPT -PassThru |
            New-Partition -DriveLetter F -UseMaximumSize |
            Format-Volume -FileSystem NTFS -NewFileSystemLabel 'AD-Data' -Confirm:$false -Force | Out-Null
    }

    # ---- 2. Install AD-DS + DNS roles ----
    Write-Output "Installing AD-DS + DNS roles..."
    Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools | Format-Table | Out-String | Write-Output

    # ---- 3. Promote ----
    Write-Output "Running Install-ADDSForest..."
    $safePwd = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force
    Install-ADDSForest `
        -DomainName $DomainName `
        -DomainMode WinThreshold `
        -ForestMode WinThreshold `
        -DatabasePath 'F:\NTDS' `
        -LogPath 'F:\NTDS' `
        -SysvolPath 'F:\SYSVOL' `
        -SafeModeAdministratorPassword $safePwd `
        -InstallDns:$true `
        -CreateDnsDelegation:$false `
        -NoRebootOnCompletion `
        -Force | Out-String | Write-Output

    New-Item -Path $marker -ItemType File -Force | Out-Null
    Write-Output "Forest creation complete. Scheduling reboot in 60s."
    Stop-Transcript

    # Schedule reboot in 60s so the extension returns success first.
    shutdown.exe /r /t 60 /c "Completing forest promotion"
    exit 0
}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    Write-Output $_.ScriptStackTrace
    Stop-Transcript
    exit 1
}
