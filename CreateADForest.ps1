configuration CreateADForest
{
    param
    (
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [Int]$RetryCount = 30,
        [Int]$RetryIntervalSec = 30
    )

    Import-DscResource -ModuleName ActiveDirectoryDsc, ComputerManagementDsc, StorageDsc

    Node localhost
    {
        # ---------- Disks ----------
        # B-series and Dsv3 have a temp disk → AD data disk lands at Disk 2.
        # If you switch to a v5-or-newer SKU without a temp disk, set DiskId = 1.
        WaitForDisk DataDisk
        {
            DiskId           = 2
            RetryIntervalSec = $RetryIntervalSec
            RetryCount       = $RetryCount
        }

        Disk ADDataDisk
        {
            DiskId      = 2
            DriveLetter = 'F'
            FSLabel     = 'AD-Data'
            DependsOn   = '[WaitForDisk]DataDisk'
        }

        # ---------- Roles ----------
        WindowsFeature DNS
        {
            Ensure = 'Present'
            Name   = 'DNS'
        }

        WindowsFeature DnsTools
        {
            Ensure    = 'Present'
            Name      = 'RSAT-DNS-Server'
            DependsOn = '[WindowsFeature]DNS'
        }

        WindowsFeature ADDSInstall
        {
            Ensure    = 'Present'
            Name      = 'AD-Domain-Services'
            DependsOn = '[WindowsFeature]DNS'
        }

        WindowsFeature ADDSTools
        {
            Ensure    = 'Present'
            Name      = 'RSAT-ADDS-Tools'
            DependsOn = '[WindowsFeature]ADDSInstall'
        }

        WindowsFeature ADAdminCenter
        {
            Ensure    = 'Present'
            Name      = 'RSAT-AD-AdminCenter'
            DependsOn = '[WindowsFeature]ADDSInstall'
        }

        PendingReboot BeforeADDomain
        {
            Name      = 'BeforeADDomain'
            DependsOn = '[WindowsFeature]ADDSInstall'
        }

        # ---------- Forest creation ----------
        ADDomain FirstDS
        {
            DomainName                    = $DomainName
            Credential                    = $Admincreds
            SafemodeAdministratorPassword = $Admincreds
            DatabasePath                  = 'F:\NTDS'
            LogPath                       = 'F:\NTDS'
            SysvolPath                    = 'F:\SYSVOL'
            ForestMode                    = 'WinThreshold'
            DomainMode                    = 'WinThreshold'
            DependsOn                     = '[Disk]ADDataDisk', '[PendingReboot]BeforeADDomain'
        }
    }
}
