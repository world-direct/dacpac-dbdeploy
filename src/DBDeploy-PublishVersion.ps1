
param (
    [Parameter(Mandatory=$true)][string] $sqlPackagePath,
    [Parameter(Mandatory=$true)][string] $buildServerName,
    [Parameter(Mandatory=$true)][string] $buildDbName,
    [Parameter(Mandatory=$true)][string] $dacpacFilePath,
    [Parameter(Mandatory=$true)][string] $publishProfileFile,
    [Parameter(Mandatory=$true)][string] $packageName,
    [Parameter(Mandatory=$true)][string] $versionStorePath,
    [Parameter(Mandatory=$true)][string] $version
)


# create some helper vars
$dbConnectionString = "server=$buildServerName;database=$buildDbName;trusted_connection=yes"
$masterConnectionString = "server=$buildServerName;database=master;trusted_connection=yes"
$gVersionStorePath = $versionStorePath

# include helper
. $PSScriptRoot\DBDeploy-Private.ps1


# add sqlPackagePath to the path variable
# because we have just process-scope, we just run a basic test, if we have not set it already before, not a real check
$sqlPackagePath = "C:\Program Files (x86)\Microsoft Visual Studio\2017\Enterprise\Common7\IDE\Extensions\Microsoft\SQLDB\DAC\130"
if(!$env:Path.EndsWith($sqlPackagePath)){
    $env:Path=$env:Path +  ";" + $sqlPackagePath
}


# drops the buildDb if it exists
function drop-build-db {

    $conMaster = open-sql-connection $masterConnectionString

    $dbExists = execute-sql-command $conMaster "SELECT ISNULL(DB_ID('$buildDbName'),0)"
    if($dbExists) {            

        # set to single-user mode to close existing connections
        execute-sql-command $conMaster "ALTER DATABASE [$buildDbName] SET  SINGLE_USER WITH ROLLBACK IMMEDIATE"

        # and drop
        execute-sql-command $conMaster "DROP DATABASE [$buildDbName]"

        Write-Host "Dropped Database '$buildDbName' on '$buildServerName'"
    } else {
        Write-Host "Database '$buildDbName' on '$buildServerName' doesn't exist. Nothing to drop."
    }


    $conMaster.Close()
}

# drops the buildDb and recreates it, so you will always have an empty DB afte this call
function create-build-db {

    drop-build-db    

    $conMaster = open-sql-connection $masterConnectionString
    execute-sql-command $conMaster "CREATE DATABASE [$buildDbName]"

    Write-Host "Creating Database '$buildDbName' on '$buildServerName'"
}

function sqlpackage {

    $cmd = "sqlPackage.exe $args"
    # $cmd
    Invoke-Expression $cmd
}

# this functions removes all DB (name) related stuff from the DB
# we assume the following structure:
#
#  ... anything
#
#  USE [$(DatabaseName)];
#
#   setup script
#
#  PRINT N'Checking existing data against newly created constraints';
#
#  GO
#  USE [$(DatabaseName)];
#
#    rest of the script

function clean-script {
    param($filepath)

    $lines = Get-Content $filepath

    # drop all lines including
    $markerLine = 'USE [$(DatabaseName)];'
       
    $markerLineNr=0
    ForEach ($line in $lines) {
        $markerLineNr = $markerLineNr + 1
        if($line -eq $markerLine){
            Break
        }
    }

    if($markerLineNr -ge $lines.Count) {
        Write-Error "Marker Line not found"
    } else {
        Write-Host "clean-script dropped the first $markerLineNr from $filepath"
        $lines | 
            Select-Object -Skip $markerLineNr | 
            where {$_ -ne $markerLine} | 
            Set-Content $filepath
    }
}


############################################
## Script logic starts here
if ($gVersionStoreIsEmpty) {
    Write-Host "The Version store is currently empty. Only a create script will be created for version $version"

    $vScriptNameCreate = "$version-create.sql"
    $vScriptNameUpdate = $null

} else {
    Write-Host "The last Version in store is $gVersionStoreLastVersion"
    if($gVersionStoreLastVersion -ge $version){
        Write-Error "The specified version $version is below the last verion in store"
    }
    
    Write-Host "For version $version a create and update script will be created"

    $vScriptNameCreate = "$version-create.sql"
    $vScriptNameUpdate = "$version-update.sql"

}

# we always stats with an empty DB
create-build-db

# and script the current version into the create script, useing the empty db
Write-Host "Creating $vScriptNameCreate"
sqlPackage "/a:script /op:'$gVersionStorePath\$vScriptNameCreate' /sf:'$dacpacFilePath' /tsn:'$buildServerName' /tdn:$buildDbName /pr:'$publishProfileFile'"
clean-script "$gVersionStorePath\$vScriptNameCreate"

# add the generation of the extended property
$gExtendedPropertyName = "DBDeploy_$packageName"
$vAddExtendedProperty = "EXEC sys.sp_addextendedproperty @name=N'$gExtendedPropertyName', @value=N'$version'"
Add-Content "$gVersionStorePath\$vScriptNameCreate" -Value "GO", "PRINT 'Update Version to $version'", "GO",$vAddExtendedProperty

if($vScriptNameUpdate) {

    $vScriptNameCreatePrevious = "$gVersionStoreLastVersion-create.sql"
    $con = open-sql-connection $dbConnectionString
    execute-sql-file $con "$gVersionStorePath\$vScriptNameCreatePrevious"
    $con.Close()

    # and script the update from previous to this
    Write-Host "Creating $vScriptNameUpdate"
    sqlPackage "/a:script /op:'$gVersionStorePath\$vScriptNameUpdate' /sf:'$dacpacFilePath' /tsn:'$buildServerName' /tdn:$buildDbName /pr:'$publishProfileFile'"
    clean-script "$gVersionStorePath\$vScriptNameUpdate"

    # add the generation of the extended property
    $vAddExtendedProperty = "EXEC sys.sp_updateextendedproperty @name=N'$gExtendedPropertyName', @value=N'$version'"
    Add-Content "$gVersionStorePath\$vScriptNameUpdate" -Value "GO", "PRINT 'Update Version to $version'", "GO",$vAddExtendedProperty

	# test the update-script
	Write-Host "Testing $vScriptNameUpdate"
    $con = open-sql-connection $dbConnectionString
    execute-sql-file $con "$gVersionStorePath\$vScriptNameUpdate"
    $con.Close()

}

drop-build-db

Write-Host "Operation successfully completed"
