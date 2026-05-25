configuration ConfigureADBDC
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
        WindowsFeature ADDSInstall
        {
            Ensure = 'Present'
            Name   = 'AD-Domain-Services'
        }

        WindowsFeature ADDSTools
        {
            Ensure    = 'Present'
            Name      = 'RSAT-ADDS-Tools'
            DependsOn = '[WindowsFeature]ADDSInstall'
        }

        # ---------- Wait for the forest to be reachable ----------
        # WaitForADDomain queries the domain via DC1. The VNet DNS must already
        # point to DC1 by the time this DSC runs (handled by the orchestrator).
        WaitForADDomain WaitForestAvailability
        {
            DomainName  = $DomainName
            Credential  = $Admincreds
            WaitTimeout = 1200
            DependsOn   = '[WindowsFeature]ADDSInstall'
        }

        # ---------- Promote to DC ----------
        ADDomainController SecondDC
        {
            DomainName                    = $DomainName
            Credential                    = $Admincreds
            SafemodeAdministratorPassword = $Admincreds
            DatabasePath                  = 'F:\NTDS'
            LogPath                       = 'F:\NTDS'
            SysvolPath                    = 'F:\SYSVOL'
            DependsOn                     = '[Disk]ADDataDisk', '[WaitForADDomain]WaitForestAvailability'
        }
    }
}
