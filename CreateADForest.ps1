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
        # Gen 2 / Trusted Launch images on most modern SKUs (including B2s and v5
        # families) don't expose a temp disk to the OS at DSC time, so the AD
        # data disk lands at Disk 1. Older Gen 1 / Dsv3 images had a temp disk
        # and would put it at Disk 2 — change DiskId here if needed.
        WaitForDisk DataDisk
        {
            DiskId           = 1
            RetryIntervalSec = $RetryIntervalSec
            RetryCount       = $RetryCount
        }

        Disk ADDataDisk
        {
            DiskId      = 1
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
