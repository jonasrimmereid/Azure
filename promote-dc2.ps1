[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DomainName,
    [Parameter(Mandatory)][string]$DomainAdminUser,
    [Parameter(Mandatory)][string]$DomainAdminPassword,
    [Parameter(Mandatory)][string]$SafeModePassword
)

# Joins the local machine to an existing forest and promotes it to a DC.
# Designed to be invoked once via Azure Custom Script Extension.
# Waits up to 30 minutes for the forest to be reachable via DNS before promoting.

$ErrorActionPreference = 'Stop'
$logFile = 'C:\dc-promote.log'
Start-Transcript -Path $logFile -Append

try {
    $marker = 'C:\dc-promoted.flag'
    if (Test-Path $marker) {
        Write-Output "Already promoted (marker at $marker). Exiting."
        exit 0
    }

    Write-Output "=== Joining $env:COMPUTERNAME to $DomainName as additional DC ==="

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

    # ---- 3. Wait for the forest to be reachable ----
    Write-Output "Waiting for $DomainName to be reachable via DNS..."
    $reachable = $false
    for ($i = 1; $i -le 60; $i++) {
        try {
            $r = Resolve-DnsName -Type SRV -Name "_ldap._tcp.dc._msdcs.$DomainName" -ErrorAction Stop
            if ($r -and $r.Count -gt 0) {
                Write-Output "  Reachable after $i attempt(s)."
                $reachable = $true
                break
            }
        }
        catch {
            Write-Output "  [$i/60] Not yet: $($_.Exception.Message)"
        }
        Start-Sleep -Seconds 30
    }
    if (-not $reachable) {
        throw "Forest $DomainName not reachable after 30 minutes."
    }

    # ---- 4. Promote as additional DC ----
    Write-Output "Running Install-ADDSDomainController..."
    $domainPwd = ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential("$DomainName\$DomainAdminUser", $domainPwd)
    $safePwd = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force

    Install-ADDSDomainController `
        -DomainName $DomainName `
        -InstallDns:$true `
        -DatabasePath 'F:\NTDS' `
        -LogPath 'F:\NTDS' `
        -SysvolPath 'F:\SYSVOL' `
        -Credential $cred `
        -SafeModeAdministratorPassword $safePwd `
        -NoRebootOnCompletion `
        -Force | Out-String | Write-Output

    New-Item -Path $marker -ItemType File -Force | Out-Null
    Write-Output "Promotion complete. Scheduling reboot in 60s."
    Stop-Transcript

    shutdown.exe /r /t 60 /c "Completing additional DC promotion"
    exit 0
}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    Write-Output $_.ScriptStackTrace
    Stop-Transcript
    exit 1
}
