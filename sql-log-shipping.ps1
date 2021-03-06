﻿param (
    [Parameter(Mandatory = $true)]
    [string]$SqlServerName,

    [switch]$Discovery,

    [switch]$History,

    [switch]$Errors,

    [Parameter(Mandatory = $false)]
    [int]$EntryCount = 10
)

function Get-ConnectionString {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SqlServerName
    )

    return "data source = $SqlServerName; initial catalog = master; trusted_connection = true; application name = sql-log-shipping;"
}

function RetrieveAndDisplay-LogShippingConfiguration {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SqlServerName
    )

    $PrimaryDatabases = Get-PrimaryDatabases -SqlServerName $SqlServerName
    $SecondaryDatabases = Get-SecondaryDatabases -SqlServerName $SqlServerName

    foreach ($PrimaryDb in $PrimaryDatabases) {
        $BackupCompression = 
            switch ($PrimaryDb.BackupCompression) {
                0 { "DISABLED" }
                1 { "ENABLED" }
                2 { "INHERIT SERVER CONFIG" }
            }

        if ($PrimaryDb.BackupJob.IsEnabled) {
            $BackupJobStatus = "ENABLED"
        }
        else {
            $BackupJobStatus = "DISABLED"
        }

        " ***** PRIMARY DATABASE [local] ($($PrimaryDb.DatabaseName)) *****"
        "Database name:       $($PrimaryDb.DatabaseName)"
        "SQL Server instance: $SqlServerName"
        "Backup share:         $($PrimaryDb.BackupShare)"
        "Backup directory:     $($PrimaryDb.BackupDirectory)"
        "Backup retention:     $($PrimaryDb.BackupRetentionPeriod / 60) HOURS"
        "Backup compression:   $BackupCompression"
        "Last backup date:     $($PrimaryDb.LastBackupDate)"
        "Last backup file:     $($PrimaryDb.LastBackupFile)"
        "Backup job name:      $($PrimaryDb.BackupJob.JobName) ($BackupJobStatus)"
        ""
        foreach ($PrimSecondaryDb in $PrimaryDb.SecondaryDatabases) {
            "   *** SECONDARY DATABASE [remote] ($($PrimSecondaryDb.SecondaryDatabaseName)) ***"
            "  Database name:       $($PrimSecondaryDb.SecondaryDatabaseName)"
            "  SQL Server instance: $($PrimSecondaryDb.SecondaryServerName)"
            try {
                $RemoteDb = Get-SecondaryDatabase -SqlServerName $PrimSecondaryDb.SecondaryServerName -DatabaseName $PrimSecondaryDb.SecondaryDatabaseName
            }
            catch {
                # silently continue but make sure this variable is set to null to indicate 
                # that we weren't able to connect successfully and no data is returned
                #
                $RemoteDb = $null
            }
            if ($RemoteDb -ne $null) {
                if ($RemoteDb.CopyJob.IsEnabled) {
                    $CopyJobStatus = "ENABLED"
                }
                else {
                    $CopyJobStatus = "DISABLED"
                }
                if ($RemoteDb.RestoreJob.IsEnabled) {
                    $RestoreJobStatus = "ENABLED"
                }
                else {
                    $RestoreJobStatus = "DISABLED"
                }

                "  Backup source directory:      $($RemoteDb.BackupSourceDirectory)"
                "  Backup destination directory: $($RemoteDb.BackupDestinationDirectory)"
                "  File retention period:        $($RemoteDb.FileRetentionPeriod / 60) HOURS"
                "  Copy job:                     $($RemoteDb.CopyJob.JobName) ($CopyJobStatus)"
                "  Last copied date:             $($RemoteDb.LastCopiedDate)"
                "  Last copied file:             $($RemoteDb.LastCopiedFile)"
                "  Restore job:                  $($RemoteDb.RestoreJob.JobName) ($RestoreJobStatus)"
                "  Last restored date:           $($RemoteDb.LastRestoredDate)"
                "  Last restored file:           $($RemoteDb.LastRestoredFile)"
                ""
            }
            else {
                "  <UNABLE TO GET DATA FROM SECONDARY>"
                ""
            }
        }
    }

    foreach ($SecondaryDb in $SecondaryDatabases) {
        if ($SecondaryDb.RestoreAll -eq 1) {
            $RestoreAllDesc = "YES"
        }
        else {
            $RestoreAllDesc = "NO"
        }

        $RestoreModeDesc = 
            switch ($SecondaryDb.RestoreMode) {
                0 { "NORECOVERY" }
                1 { "STANDBY" }
            }

        if ($SecondaryDb.DisconnectUsers -eq 1) {
            $DisconnectUsersDesc = "YES"
        }
        else {
            $DisconnectUsersDesc = "NO"
        }

        " ***** SECONDARY DATABASE [local] ($($SecondaryDb.DatabaseName)) *****"
        "Database name:       $($SecondaryDb.DatabaseName)"
        "SQL Server instance: $SqlServerName"
        ""
        "Restore delay:    $($SecondaryDb.RestoreDelay) MINUTE(S)"
        "Restore all:      $RestoreAllDesc"
        "Restore mode:     $RestoreModeDesc"
        "Disconnect users: $DisconnectUsersDesc"
        "Block size:    $($SecondaryDb.BlockSize) BYTES"
        "Buffer count:  $($SecondaryDb.BufferCount)"
        "Max transfer size: $($SecondaryDb.MaxTransferSize) BYTES"
        "Last restored date: $($Secondarydb.LastRestoredDate)"
        "Last restored file: $($SecondaryDb.LastRestoredFile)"
    }
}
function Get-PrimaryDatabases {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SqlServerName
    )

    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection(Get-ConnectionString -SqlServerName $SqlServerName)
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.Connection = $SqlConnection
    $SqlCmd.CommandText = "
        select
	        primary_id, primary_database, backup_directory,
	        backup_share, backup_retention_period,
	        backup_job_id, monitor_server,
	        monitor_server_security_mode, last_backup_file,
	        last_backup_date, backup_compression
        from msdb.dbo.log_shipping_primary_databases;"

    $Output = New-Object System.Data.DataTable
    $sda = New-Object System.Data.SqlClient.SqlDataAdapter($SqlCmd)
    $sda.Fill($Output) | Out-Null

    $PrimaryDatabases = @()

    foreach ($Row in $Output.Rows) {
        $PrimaryDatabase = New-Object System.Object
        $PrimaryDatabase | Add-Member -MemberType NoteProperty -Name "PrimaryId" -Value ([System.Guid]::Parse($Row["primary_id"]))
        $PrimaryDatabase | Add-Member -MemberType NoteProperty -Name "DatabaseName" -Value $Row["primary_database"]
        $PrimaryDatabase | Add-Member -MemberType NoteProperty -Name "BackupDirectory" -Value $Row["backup_directory"]
        $PrimaryDatabase | Add-Member -MemberType NoteProperty -Name "BackupShare" -Value $Row["backup_share"]
        $PrimaryDatabase | Add-Member -MemberType NoteProperty -Name "BackupRetentionPeriod" -Value ([System.Convert]::ToInt32($Row["backup_retention_period"]))
        $PrimaryDatabase | Add-Member -MemberType NoteProperty -Name "MonitorServer" -Value $Row["monitor_server"]
        $PrimaryDatabase | Add-Member -MemberType NoteProperty -Name "MonitorServerSecurityMode" -Value ([System.Convert]::ToInt32($Row["monitor_server_security_mode"]))
        $PrimaryDatabase | Add-Member -MemberType NoteProperty -Name "LastBackupFile" -Value $Row["last_backup_file"]
        $PrimaryDatabase | Add-Member -MemberType NoteProperty -Name "LastBackupDate" -Value $Row["last_backup_date"]
        $PrimaryDatabase | Add-Member -MemberType NoteProperty -Name "BackupCompression" -Value ([System.Convert]::ToInt32($Row["backup_compression"]))
        $PrimaryDatabase | Add-Member -MemberType NoteProperty -Name "BackupJob" -Value (Get-AgentJob -SqlServerName $SqlServerName -JobId ([System.Guid]::Parse($Row["backup_job_id"])))
        $PrimaryDatabase | Add-Member -MemberType NoteProperty -Name "SecondaryDatabases" -Value (Get-PrimarySecondaryDatabases -SqlServerName $SqlServerName -PrimaryId ([System.Guid]::Parse($Row["primary_id"])))

        $PrimaryDatabases += $PrimaryDatabase
    }

    return $PrimaryDatabases
}
function Get-PrimarySecondaryDatabases {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SqlServerName,

        [Parameter(Mandatory = $true)]
        [Guid]$PrimaryId
    )

    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection(Get-ConnectionString -SqlServerName $SqlServerName)
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.Connection = $SqlConnection
    $SqlCmd.CommandText = "
        select secondary_server, secondary_database
        from msdb.dbo.log_shipping_primary_secondaries
        where primary_id = @primary_id;"

    $PrimaryIdParam = New-Object System.Data.SqlClient.SqlParameter("@primary_id", [System.Data.SqlDbType]::UniqueIdentifier)
    $PrimaryIdParam.Value = $PrimaryId
    $SqlCmd.Parameters.Add($PrimaryIdParam) | Out-Null

    $Output = New-Object System.Data.DataTable
    $sda = New-Object System.Data.SqlClient.SqlDataAdapter($SqlCmd)

    $sda.Fill($Output) | Out-Null

    $SecondaryDatabases = @()

    foreach ($Row in $Output.Rows) {
        $SecondaryDb = New-Object System.Object
        $SecondaryDb | Add-Member -MemberType NoteProperty -Name "SecondaryServerName" -Value $Row["secondary_server"]
        $SecondaryDb | Add-Member -MemberType NoteProperty -Name "SecondaryDatabaseName" -Value $Row["secondary_database"]

        $SecondaryDatabases += $SecondaryDb
    }

    return $SecondaryDatabases
}

function Get-AgentJob {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SqlServerName,

        [Parameter(Mandatory = $true)]
        [Guid]$JobId
    )

    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection(Get-ConnectionString -SqlServerName $SqlServerName)
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.Connection = $SqlConnection
    $SqlCmd.CommandText = "
        select job_id, name, enabled
        from msdb.dbo.sysjobs
        where job_id = @job_id;"

    $JobIdParam = New-Object System.Data.SqlClient.SqlParameter("@job_id", [System.Data.SqlDbType]::UniqueIdentifier)
    $JobIdParam.Value = $JobId

    $SqlCmd.Parameters.Add($JobIdParam) | Out-Null

    $Output = New-Object System.Data.DataTable
    $sda = New-Object System.Data.SqlClient.SqlDataAdapter($SqlCmd)

    $sda.Fill($Output) | Out-Null

    if ($Output.Rows.Count -eq 0) {
        return $null
    }

    $Job = New-Object System.Object
    $Job | Add-Member -MemberType NoteProperty -Name "JobId" -Value ([System.Guid]::Parse($Output.Rows[0]["job_id"]))
    $Job | Add-Member -MemberType NoteProperty -Name "JobName" -Value $Output.Rows[0]["name"]
    $Job | Add-Member -MemberType NoteProperty -Name "IsEnabled" -Value ([System.Convert]::ToBoolean($Output.Rows[0]["enabled"]))

    return $Job
}

function Get-SecondaryDatabases {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SqlServerName
    )

    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection(Get-ConnectionString -SqlServerName $SqlServerName)
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.Connection = $SqlConnection
    $SqlCmd.CommandText = "
        select sd.secondary_id, sd.secondary_database,
            sd.restore_delay, sd.restore_all, sd.restore_mode,
            sd.disconnect_users, sd.block_size, sd.buffer_count, sd.max_transfer_size,
            sd.last_restored_file, sd.last_restored_date,
	        s.backup_source_directory, s.backup_destination_directory,
	        s.file_retention_period, s.copy_job_id, s.restore_job_id,
	        s.last_copied_date, s.last_copied_file
        from msdb.dbo.log_shipping_secondary_databases sd
        inner join msdb.dbo.log_shipping_secondary s
        on sd.secondary_id = s.secondary_id;"

    $Output = New-Object System.Data.DataTable
    $sda = New-Object System.Data.SqlClient.SqlDataAdapter($SqlCmd)

    $sda.Fill($Output) | Out-Null

    $SecondaryDatabases = @()

    foreach ($Row in $Output.Rows) {
        $SecondaryDb = New-Object System.Object
        $SecondaryDb | Add-Member -MemberType NoteProperty -Name "DatabaseName" -Value $Row["secondary_database"]
        $SecondaryDb | Add-Member -MemberType NoteProperty -Name "SecondaryId" -Value ([System.Guid]::Parse($Row["secondary_id"]))
        $SecondaryDb | Add-Member -MemberType NoteProperty -Name "RestoreDelay" -Value ([System.Convert]::ToInt32($Row["restore_delay"]))
        $SecondaryDb | Add-Member -MemberType NoteProperty -Name "RestoreAll" -Value ([System.Convert]::ToInt32($Row["restore_all"]))
        $SecondaryDb | Add-Member -MemberType NoteProperty -Name "RestoreMode" -Value ([System.Convert]::ToInt32($Row["restore_mode"]))
        $SecondaryDb | Add-Member -MemberType NoteProperty -Name "DisconnectUsers" -Value ([System.Convert]::ToInt32($Row["disconnect_users"]))
        $SecondaryDb | Add-Member -MemberType NoteProperty -Name "BlockSize" -Value ([System.Convert]::ToInt32($Row["BlockSize"]))
        $SecondaryDb | Add-Member -MemberType NoteProperty -Name "BufferCount" -Value ([System.Convert]::ToInt32($Row["buffer_count"]))
        $SecondaryDb | Add-Member -MemberType NoteProperty -Name "MaxTransferSize" -Value ([System.Convert]::ToInt32($Row["max_transfer_size"]))
        $SecondaryDb | Add-Member -MemberType NoteProperty -Name "LastRestoredFile" -Value $Row["last_restored_file"]
        $SecondaryDb | Add-Member -MemberType NoteProperty -Name "LastRestoredDate" -Value $Row["last_restored_date"]
        $SecondaryDb | Add-Member -MemberType NoteProperty -Name "BackupSourceDirectory" -Value $Row["backup_source_directory"]
        $SecondaryDb | Add-Member -MemberType NoteProperty -Name "BackupDestinationDirectory" -Value $Row["backup_destination_directory"]
        $SecondaryDb | Add-Member -MemberType NoteProperty -Name "FileRetentionPeriod" -Value ([System.Convert]::ToInt32($Row["file_retention_period"]))
        $SecondaryDb | Add-Member -MemberType NoteProperty -Name "CopyJob" -Value (Get-AgentJob -SqlServerName $SqlServerName -JobId ([System.Guid]::Parse($Row["copy_job_id"])))
        $SecondaryDb | Add-Member -MemberType NoteProperty -Name "RestoreJob" -Value (Get-AgentJob -SqlServerName $SqlServerName -JobId ([System.Guid]::Parse($Row["restore_job_id"])))
        $SecondaryDb | Add-Member -MemberType NoteProperty -Name "LastCopiedDate" -Value $Row["last_copied_date"]
        $SecondaryDb | Add-Member -MemberType NoteProperty -Name "LastCopiedFile" -Value $Row["last_copied_file"]

        $SecondaryDatabases += $SecondaryDb
    }

    return $SecondaryDatabases
}
function Get-SecondaryDatabase {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SqlServerName,

        [Parameter(Mandatory = $true)]
        [string]$DatabaseName
    )

    return Get-SecondaryDatabases -SqlServerName $SqlServerName | Where-Object {$_.DatabaseName -eq $DatabaseName}
}

function Get-History {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SqlServerName,

        [Parameter(Mandatory = $true)]
        [int]$Top
    )

    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection(Get-ConnectionString -SqlServerName $SqlServerName)
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.Connection = $SqlConnection
    $SqlCmd.CommandText = "
        select top (@top_count)
	        session_id,
	        session_status_desc = 
		        case session_status
			        when 0 then 'STARTING'
			        when 1 then 'RUNNING'
			        when 2 then 'SUCCESS'
			        when 3 then 'ERROR'
			        when 4 then 'WARNING'
                    else 'UNKNOWN'
		        end,
	        agent_type_desc = 
		        case agent_type
			        when 0 then 'BACKUP'
			        when 1 then 'COPY'
			        when 2 then 'RESTORE'
			        else 'UNKNOWN'
		        end,
	        message,
	        log_time
        from msdb.dbo.log_shipping_monitor_history_detail
        order by log_time desc;"

    $TopCountParam = New-Object System.Data.SqlClient.SqlParameter("@top_count", [System.Data.SqlDbType]::Int)
    $TopCountParam.Value = $Top
    $SqlCmd.Parameters.Add($TopCountParam) | Out-Null

    $Output = New-Object System.Data.DataTable
    $sda = New-Object System.Data.SqlClient.SqlDataAdapter($SqlCmd)

    try {
        $sda.Fill($Output) | Out-Null

        return $Output
    }
    catch {
        Write-Error $_.Exception
    }
    finally {
        $sda.Dispose()
        $SqlCmd.Dispose()
        $SqlConnection.Dispose()
    }
}

function Get-Errors {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SqlServerName,

        [Parameter(Mandatory = $true)]
        [int]$Top
    )

    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection(Get-ConnectionString -SqlServerName $SqlServerName)
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.Connection = $SqlConnection
    $SqlCmd.CommandText = "
        select top (@top_count)
	        log_time,
	        agent_type_desc = 
		        case agent_type
			        when 0 then 'backup'
			        when 1 then 'copy'
			        when 2 then 'restore'
			        else 'unknown'
		        end,
	        database_name,
	        session_id,
	        message,
	        source
        from msdb.dbo.log_shipping_monitor_error_detail
        order by log_time desc;"

    $TopCountParam = New-Object System.Data.SqlClient.SqlParameter("@top_count", [System.Data.SqlDbType]::Int)
    $TopCountParam.Value = $Top
    $SqlCmd.Parameters.Add($TopCountParam) | Out-Null

    $Output = New-Object System.Data.DataTable
    $sda = New-Object System.Data.SqlClient.SqlDataAdapter($SqlCmd)

    try {
        $sda.Fill($Output) | Out-Null

        return $Output
    }
    catch {
        Write-Error $_.Exception
    }
    finally {
        $sda.Dispose()
        $SqlCmd.Dispose()
        $SqlConnection.Dispose()
    }
}

if ($Discovery) {
    RetrieveAndDisplay-LogShippingConfiguration -SqlServerName $SqlServerName
}
elseif ($History) {
    Get-History -SqlServerName $SqlServerName -Top $EntryCount
}
elseif ($Errors) {
    Get-Errors -SqlServerName $SqlServerName -Top $EntryCount
}