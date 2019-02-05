#	DBDeploy-UpdateDatabase.ps is normally called by a customer individual ps-script,
#		DBDeploy_Update.ps1
#
#	This reads customer specific configuration format, and calls itself the real update script:
#	 -> DBDeploy-UpdateDatabase.ps1 -VersionStore "AtlasDatabase\VersionStore" -TargetServerName "dbserver" -TargetDbName "dbname"


# Step 1: Read current version
# Step 2: If there is a current version, apply all update-script > current version
# Step 3: If there is no current version, apply the lateste create-script

param(
    [string]$PackageName,
    [string]$VersionStorePath,
    [string]$TargetServerName,
    [string]$TargetDbName
)

$gVersionStorePath = $VersionStorePath

# include helper
. $PSScriptRoot\DBDeploy-Private.ps1

$dbConnectionString = "server=$targetServerName;database=$targetDbName;trusted_connection=yes"
$con = open-sql-connection $dbConnectionString

$currentInstalledVersionString = execute-sql-command $con "SELECT value FROM fn_listextendedproperty(default, default, default, default, default, default, default) WHERE name='DBDeploy_$PackageName' AND objtype IS NULL"

if($currentInstalledVersionString) {
    $currentInstalledVersion = parse-version $currentInstalledVersionString
    Write-Host "The current version of Package '$PackageName' on '$TargetDbName@$TargetServerName' is $currentInstalledVersion"
    if($currentInstalledVersionString -lt $gVersionStoreLastVersion){

        Write-Host "It will be updated to the most recent version '$gVersionStoreLastVersion'"
        ForEach($vVerionStoreFile in $gVersionStoreFiles) {
            if($vVerionStoreFile.Operation -eq "update" -and $vVerionStoreFile.Version -gt $currentInstalledVersionString){
                $vUpdateVersion = $vVerionStoreFile.Version
                Write-Host "Updateing to version $vUpdateVersion"
                $vUpdateScriptName = "$gVersionStorePath\$vUpdateVersion-update.sql"
                execute-sql-file $con $vUpdateScriptName
            }
        }


    } else {
        Write-Host "This is the most recent version. No further actions needed."        
    }

} else {
    Write-Host "Package '$PackageName' is not installed on '$TargetDbName@$TargetServerName'"
    Write-Host "It will be installed in the most recent version '$gVersionStoreLastVersion'"

    $createScriptName = "$gVersionStorePath\$gVersionStoreLastVersion-create.sql"
    execute-sql-file $con $createScriptName
}

$con.Close()




