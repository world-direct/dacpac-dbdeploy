## this contains helper methods used by CreateVersion and UpdateDatabase
## you should NOT call this directly

$ErrorActionPreference = "Stop"

function open-sql-connection {
    param($connectionstring)

    $con = New-Object System.Data.SqlClient.SqlConnection
    $con.ConnectionString = $connectionstring
    $con.Open()

    return $con
}

function execute-sql-command {
    param($con, $sql)

    $vCmd = $con.CreateCommand()
    $vCmd.CommandText = $sql
    $vRetVal = $vCmd.ExecuteScalar()
    $vCmd.Dispose()

    return $vRetVal
}

function execute-sql-file {
    param($con, $filepath)

    Write-Host "Executing file '$filepath' in an SQL-Transaction"

    $tx = $con.BeginTransaction()

    $con.Add_InfoMessage({
        Write-Host $_.Message
    })


    $vCmd = $con.CreateCommand()
    $vCmd.Transaction = $tx
    $lines = Get-Content $filepath

    Function exec-cmd {
        if($vCmd -and $vCmd.CommandText.Length) { 
            Try {
                $vCmd.ExecuteNonQuery() | Out-Null 
                $vCmd.CommandText = ""
            } Catch {
                $vErrorMessage = $_.Exception.InnerException.Message
                $tx.Rollback()
                Write-Error $vErrorMessage
            }
        }   
    }

    ForEach($line in $lines){
        if($line -eq "GO"){
            exec-cmd
        } else {
            $vCmd.CommandText += [System.Environment]::NewLine
            $vCmd.CommandText += $line
        }
    }

    exec-cmd
    $vCmd.Dispose()

    Write-Host "Committing Transaction"
    $tx.Commit()

}

##############################
## This block contains the initialization of the Version-Store
## 
##   the $gVersionStorePath must be set before running this code
##   after execution, the following globals are set:
##
##   $gVersionStoreIsEmpty: A bool if there are any versions in store, if false, no other global can be ignored
##   $gVersionStoreVersions: An sorted array of distinct System.Version objects for all existing versions
##   $gVersionStoreFiles: A sorted array of all files, with FileName, Operation and Version
##   $gVersionStoreLastVersion: A System.Version representing the last version in store
if(!$gVersionStorePath){
    Write-Error "VersionStore initialization error"
}


function parse-version {
    param($versionString)
    return [System.Version]::Parse($versionString)
}

# validates and parses a given filename
# returns an object with the following properties:
#  FileName (1.1-create.sql)
#  Operation (create)
#  Version (1.1, already parsed into System.Version)
function parse-filename {
    param($filename)

    $vMatches = [regex]::Match($filename, "(.+)-(\w+).sql")
    if(!$vMatches.Success){
        Write-Error "The filename '$filename' is invalid. Cannot continue!"
    }

    $vVersionPart = $vMatches.Groups[1].Value
    $vOperationPart = $vMatches.Groups[2].Value
    
    $ret = @{
        FileName = $filename
        Operation = $vOperationPart
        Version = parse-version $vVersionPart
    }

    return $ret
}



$vScripts = Get-ChildItem $gVersionStorePath -Filter "*.sql"       

if(!$vScripts.Count){

    $gVersionStoreIsEmpty = $true

} else {

    $gVersionStoreIsEmpty = $false
    $gVersionStoreFiles = $vScripts | %{parse-filename $_.Name} | Sort-Object -Property "Version"

    $gVersionStoreVersions = $gVersionStoreFiles | %{$_.Version} | Select-Object -Unique
    $gVersionStoreLastVersion = $gVersionStoreFiles | %{$_.Version} | Sort-Object | Select-Object -Last 1 
}