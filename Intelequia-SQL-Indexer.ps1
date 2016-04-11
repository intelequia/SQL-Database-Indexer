<#
.SYNOPSIS 
    Vertically scale an Azure SQL Database and indexes tables in a database if they have a high fragmentation

.DESCRIPTION
  	This runbook enables one to vertically scale an Azure SQL Database and indexes all of the tables 
	in a given database if the fragmentation is above a certain percentage. 
    It highlights how to break up calls into smaller chunks, 
    in this case each table in a database, and use checkpoints. 
    This allows the runbook job to resume for the next chunk of work even if the 
    fairshare feature of Azure Automation puts the job back into the queue every 30 minutes

.PARAMETER SqlServerName  
    Name of the Azure SQL Database server (Ex: bzb98er9bp)  
       
.PARAMETER DatabaseName   
    Target Azure SQL Database name 
    
.PARAMETER SQLCredentialName
    Name of the Automation PowerShell credential setting from the Automation asset store. 
    This setting stores the username and password for the SQL Azure server

.PARAMETER Edition   
    Desired Azure SQL Database edition {Basic, Standard, Premium} 
    For more information on Editions/Performance levels, please  
    see: http://msdn.microsoft.com/en-us/library/azure/dn741336.aspx 
 
.PARAMETER PerfLevel   
    Desired performance level {Basic, S0, S1, S2, P1, P2, P3}  

.PARAMETER FinalEdition   
    Desired final Azure SQL Database edition {Basic, Standard, Premium} 
    For more information on Editions/Performance levels, please  
    see: http://msdn.microsoft.com/en-us/library/azure/dn741336.aspx 
 
.PARAMETER FinalPerfLevel   
    Desired final performance level {Basic, S0, S1, S2, P1, P2, P3}  

.PARAMETER FragPercentage
    Optional parameter for specifying over what percentage fragmentation to index database
    Default is 10 percent

.PARAMETER SqlServerPort
    Optional parameter for specifying the SQL port 
    Default is 1433
 
 .PARAMETER RebuildOffline
    Optional parameter to rebuild indexes offline if online fails 
    Default is false
    
 .PARAMETER Table
    Optional parameter for specifying a specific table to index
    Default is all tables
    
.PARAMETER SMTPServer
    Optional parameter for specifying a specific SMTP Server
    By default doesnt send a notification.

.PARAMETER SMTPCredentials
    Name of the Automation PowerShell credential setting from the Automation asset store. 
    This setting stores the username and password for the SMTP Server

.PARAMETER FromMail
    Sender Email

.PARAMETER ToMail
    Destination Email
  
.NOTES
    AUTHOR: Intelequia Software Solutions
    LASTEDIT: Feb 18th, 2016 
#>
workflow Intelequia-Indexer
{
    param(
        # Name of the Azure SQL Database server (Ex: bzb98er9bp) 
        [parameter(Mandatory=$true)]  
        [string] $SqlServerName, 
 
        # Target Azure SQL Database name  
        [parameter(Mandatory=$true)]  
        [string] $DatabaseName, 
		
        [parameter(Mandatory=$True)]
        [string] $SQLCredentialName,
		
        # Desired Azure SQL Database edition {Basic, Standard, Premium} 
        [parameter(Mandatory=$true)]  
        [string] $Edition, 
 
        # Desired performance level {Basic, S0, S1, S2, P1, P2, P3} 
        [parameter(Mandatory=$true)]  
        [string] $PerfLevel, 
 
  		# Desired Azure SQL Database edition {Basic, Standard, Premium} 
        [parameter(Mandatory=$true)]  
        [string] $FinalEdition, 
 
        # Desired performance level {Basic, S0, S1, S2, P1, P2, P3} 
        [parameter(Mandatory=$true)]  
        [string] $FinalPerfLevel,
		
		[parameter(Mandatory=$False)]
        [int] $FragPercentage = 10,

        [parameter(Mandatory=$False)]
        [int] $SqlServerPort = 1433,
        
        [parameter(Mandatory=$False)]
        [boolean] $RebuildOffline = $False,

        [parameter(Mandatory=$False)]
        [string] $Table,

        [parameter(Mandatory=$False)]
        [string] $SMTPSever,

        [parameter(Mandatory=$False)]
        [string] $SMTPCrendetials,

        [parameter(Mandatory=$False)]
        [string] $FromMail,

        [parameter(Mandatory=$False)]
        [string] $ToMail
   
    )

    # Get the stored username and password from the Automation credential
    $SqlCredential = Get-AutomationPSCredential -Name $SQLCredentialName
    if ($SqlCredential -eq $null)
    {
        throw "Could not retrieve '$SQLCredentialName' credential asset. Check that you created this first in the Automation service."
    }
    
    $SqlUsername = $SqlCredential.UserName 
    $SqlPass = $SqlCredential.GetNetworkCredential().Password

	#Email's body 
	$Body = ""
    $output =""
	
	$output = inlinescript 
    { 
		
		Write-Output "Increasing database's tier to $Using:PerfLevel" 
	    
	    # Establish credentials for Azure SQL Database server  
	    $Servercredential = new-object System.Management.Automation.PSCredential(($Using:SqlCredential).UserName, (($Using:SqlCredential).GetNetworkCredential().Password | ConvertTo-SecureString -asPlainText -Force))  
	        
	    # Create connection context for Azure SQL Database server 
	    $CTX = New-AzureSqlDatabaseServerContext -ManageUrl “https://$Using:SqlServerName.database.windows.net” -Credential $Servercredential 
	       
	    # Get Azure SQL Database context 
	    $Db = Get-AzureSqlDatabase $CTX –DatabaseName $Using:DatabaseName 
	       
	    # Specify the specific performance level for the target $DatabaseName 
	    $ServiceObjective = Get-AzureSqlDatabaseServiceObjective $CTX -ServiceObjectiveName "$Using:PerfLevel" 
	   
	    # Set the new edition/performance level 
	    Set-AzureSqlDatabase $CTX –Database $Db –ServiceObjective $ServiceObjective –Edition $Using:Edition -Force 
		
		$PollingInterval = 60
		$KeepGoing = $true
		while ($KeepGoing) {
			Write-Output "Processing..."
			$operation = Get-AzureSqlDatabase -ConnectionContext $CTX -DatabaseName "$Using:DatabaseName"
			if ($operation) {
			    if ($operation.ServiceObjectiveName -eq "$Using:PerfLevel") { $KeepGoing = $false }
			}
		    if ($KeepGoing) { Start-Sleep -Seconds $PollingInterval }
		}
	    
	    # Output final status message 
		Write-Output "Scaled the performance level of $Using:DatabaseName to $Using:Edition - $Using:PerfLevel"
	   	
    }
	
	$Body = $Body + "$output"+"<br>"
	Write-Output "Indexing..."
    
    $TableNames = Inlinescript {
      
        # Define the connection to the SQL Database
        $Conn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$using:SqlServerName.database.windows.net,$using:SqlServerPort;Database=$using:DatabaseName;User ID=$using:SqlUsername;Password=$using:SqlPass;Trusted_Connection=False;Encrypt=True;Connection Timeout=30;")
         
        # Open the SQL connection
        $Conn.Open()
        
        # SQL command to find tables and their average fragmentation
        $SQLCommandString = @"
        SELECT a.object_id, avg_fragmentation_in_percent
        FROM sys.dm_db_index_physical_stats (
               DB_ID(N'$Database')
             , OBJECT_ID(0)
             , NULL
             , NULL
             , NULL) AS a
        JOIN sys.indexes AS b 
        ON a.object_id = b.object_id AND a.index_id = b.index_id;
"@
        # Return the tables with their corresponding average fragmentation
        $Cmd=new-object system.Data.SqlClient.SqlCommand($SQLCommandString, $Conn)
        $Cmd.CommandTimeout=120
        
        # Execute the SQL command
        $FragmentedTable=New-Object system.Data.DataSet
        $Da=New-Object system.Data.SqlClient.SqlDataAdapter($Cmd)
        [void]$Da.fill($FragmentedTable)

 
        # Get the list of tables with their object ids
        $SQLCommandString = @"
        SELECT  t.name AS TableName, t.OBJECT_ID FROM sys.tables t
"@

        $Cmd=new-object system.Data.SqlClient.SqlCommand($SQLCommandString, $Conn)
        $Cmd.CommandTimeout=120

        # Execute the SQL command
        $TableSchema =New-Object system.Data.DataSet
        $Da=New-Object system.Data.SqlClient.SqlDataAdapter($Cmd)
        [void]$Da.fill($TableSchema)


        # Return the table names that have high fragmentation
        ForEach ($FragTable in $FragmentedTable.Tables[0])
        {
            Write-Verbose ("Table Object ID:" + $FragTable.Item("object_id"))
            Write-Verbose ("Fragmentation:" + $FragTable.Item("avg_fragmentation_in_percent"))
            
            If ($FragTable.avg_fragmentation_in_percent -ge $Using:FragPercentage)
            {
                # Table is fragmented. Return this table for indexing by finding its name
                ForEach($Id in $TableSchema.Tables[0])
                {
                    if ($Id.OBJECT_ID -eq $FragTable.object_id.ToString())
                     {
                        # Found the table name for this table object id. Return it
                        Write-Verbose ("Found a table to index! : " +  $Id.Item("TableName"))
                        $Id.TableName
                    }
                }
            }
        }

        $Conn.Close()
    }

    # If a specific table was specified, then find this table if it needs to indexed, otherwise
    # set the TableNames to $null since we shouldn't process any other tables.
    If ($Table)
    {
        Write-Verbose ("Single Table specified: $Table")
        If ($TableNames -contains $Table)
        {
            $TableNames = $Table
        }
        Else
        {
            # Remove other tables since only a specific table was specified.
            Write-Verbose ("Table not found: $Table")
            $TableNames = $Null
        }
    }

    # Interate through tables with high fragmentation and rebuild indexes
    ForEach ($TableName in $TableNames)
    {
      Write-Verbose "Creating checkpoint"
      Checkpoint-Workflow
      Write-Verbose "Indexing Table $TableName..."
      
     $output =  InlineScript {
          $outputT=""
        $SQLCommandString = @"
        EXEC('ALTER INDEX ALL ON $Using:TableName REBUILD with (ONLINE=ON)')
"@

        # Define the connection to the SQL Database
        $Conn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$using:SqlServerName.database.windows.net,$using:SqlServerPort;Database=$using:DatabaseName;User ID=$using:SqlUsername;Password=$using:SqlPass;Trusted_Connection=False;Encrypt=True;Connection Timeout=30;")
        
        # Open the SQL connection
        $Conn.Open()

        # Define the SQL command to run. In this case we are getting the number of rows in the table
        $Cmd=new-object system.Data.SqlClient.SqlCommand($SQLCommandString, $Conn)
        # Set the Timeout to be less than 30 minutes since the job will get queued if > 30
        # Setting to 25 minutes to be safe.
        $Cmd.CommandTimeout=1500

        # Execute the SQL command
        Try 
        {
            $Ds=New-Object system.Data.DataSet
            $Da=New-Object system.Data.SqlClient.SqlDataAdapter($Cmd)
            [void]$Da.fill($Ds)
        }
        Catch
        {
            if (($_.Exception -match "offline") -and ($Using:RebuildOffline) )
            {
                Write-Verbose ("Building table $Using:TableName offline")
                $SQLCommandString = @"
                EXEC('ALTER INDEX ALL ON $Using:TableName REBUILD')
"@              

                # Define the SQL command to run. 
                $Cmd=new-object system.Data.SqlClient.SqlCommand($SQLCommandString, $Conn)
                # Set the Timeout to be less than 30 minutes since the job will get queued if > 30
                # Setting to 25 minutes to be safe.
                $Cmd.CommandTimeout=1500

                # Execute the SQL command
                $Ds=New-Object system.Data.DataSet
                $Da=New-Object system.Data.SqlClient.SqlDataAdapter($Cmd)
                [void]$Da.fill($Ds)
            }
            Else
            {
                # Will catch the exception here so other tables can be processed.
				Write-Error "Table $Using:TableName could not be indexed. Investigate indexing each index instead of the complete table $_"
                $outputT = "$outputT" +"<br>"+ "<font color='red'> Table $Using:TableName could not be indexed. Investigate indexing each index instead of the complete table $_ </font><br>"
             }
        }
        # Close the SQL connection
        $Conn.Close()
		Return $outputT
      }  
	  $Body = $Body + "$output"
    }
	
    Write-Output "Indexed completed"
	
	 $endPerf = ""
	
	$output = inlinescript 
    {  
		$outputFP = ""
		Write-Output "Changing database's tier to $Using:FinalPerfLevel" 
			        
	    # Establish credentials for Azure SQL Database server  
	    $Servercredential = new-object System.Management.Automation.PSCredential(($Using:SqlCredential).UserName, (($Using:SqlCredential).GetNetworkCredential().Password | ConvertTo-SecureString -asPlainText -Force))  
	        
	    # Create connection context for Azure SQL Database server 
	    $CTX = New-AzureSqlDatabaseServerContext -ManageUrl “https://$Using:SqlServerName.database.windows.net” -Credential $Servercredential 
	       
	    # Get Azure SQL Database context 
	    $Db = Get-AzureSqlDatabase $CTX –DatabaseName $Using:DatabaseName 
	       
	    # Specify the specific performance level for the target $DatabaseName 
	    $ServiceObjective = Get-AzureSqlDatabaseServiceObjective $CTX -ServiceObjectiveName "$Using:FinalPerfLevel" 
	        
	    # Set the new edition/performance level 
	    Set-AzureSqlDatabase $CTX –Database $Db –ServiceObjective $ServiceObjective –Edition $Using:FinalEdition -Force 
	    
		$PollingInterval = 60
		
		$KeepGoing = $true
		while ($KeepGoing) {
			Write-Output "Processing..."
			$operation = Get-AzureSqlDatabase -ConnectionContext $CTX -DatabaseName "$Using:DatabaseName"
		    if ($operation) {
			    if ($operation.ServiceObjectiveName -eq "$Using:FinalPerfLevel") { $KeepGoing = $false }
			}
		    if ($KeepGoing) { Start-Sleep -Seconds $PollingInterval }
		} 
		$endPerf= Get-AzureSqlDatabase -ConnectionContext $CTX -DatabaseName "$Using:DatabaseName"
	    # Output final status message 
		Write-Output "Scaled the performance level of $Using:DatabaseName to $Using:FinalEdition - $Using:FinalPerfLevel"
			   
		$outputFP = $outputFP + "<br>"+"Current tier: "+ $endPerf.ServiceObjectiveName;
		Return $outputFP
	}

	$Body = $Body + "<br>"+"$output"

    if($SMTPServer -ne $null){
        inlinescript 
        {  
		           		
		    # Subject
	        $subject = "Intelequia-Indexer '$Using:DatabaseName' completed."
				 
	        # Get the PowerShell credential and prints its properties 
	        $Cred = Get-AutomationPSCredential -Name "$Using:SMTPCredentials"
	        if ($Cred -eq $null) 
	        { 
	            Write-Output "Credential entered: $MyCredential does not exist in the automation service. Please create one..."    
	        } 
	        else 
	        { 
	            $CredUsername = $Cred.UserName 
	            $CredPassword = $Cred.GetNetworkCredential().Password 
	        } 
	    
		    Send-MailMessage -To "$Using:ToMail" -Subject $subject -Body "$Using:Body" -UseSsl -Port 587 -SmtpServer "$Using:SMTPServer" -From "$Using:FromMail" -BodyAsHtml -Credential $Cred   
	    }
    }
	
}