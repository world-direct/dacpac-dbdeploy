# Welcome to DBDeploy

DBDeploy uses the existing .sqlproj / sqlpackage.exe infrastructure to create and update databases
to an on-premeses deployment.

It has the following features:

* Generates a pair of .sql scripts for each version (create and update)
* Has no runtime dependencies, so sqlpackage.exe is not needed for deployment.
* Supports direct creation of a Database for any published version
* Supports updates from any version to the next version
* Automatisation is done with powershell

## Principles of operation

### Creating a new Version

To deploy a Database, you need to have a .dacpac file representing the current version.
This may reference other files.

At one time, that you want to create a version of the database for production deployment,
you execute:

```powershell
# This will create an create and an update script in the VersionStore folder.
DBDeploy-CreateVersion.ps1 -src <dbfolder> -version 1.5
```

IMPORTANT: The VersionStore need to be commited to Source-Control, or archived in another way, before the deployment to any external system.

Notes:
* sqlpackage.exe is currently not able to create script without a real SQL-Server,
so you have to specifiy one in the configuration.

### VersionStore organization

There is a root-folder for the VersionStore. The VersionStore contains only .sql scripts, that are organized in the following way:

file-name := version-spec "-" {"create"|"update"} ".sql"
version-spec := major "." minor [ "." build ] [ "." revision ]

1.0-create.sql	// the first version only has a create script
1.1-create.sql	// all following versions have a create and a update script
1.1-update.sql


### Deploying to the customer

DBDeploy remembers the version of a deployed database in an extended property named "DBDeploy_<DBNAME>".
If there is no such propery, DBDeploy executes the current create script.
If there is one, DBDeploy executes all script > current version to the most recent one.

DBDeploy-UpdateDatabase.ps1 -src <VersionStoreFolder> -targetServer <servername> -targetDatabase <dbname>.

VersionStoreFolder defaults to the directory of DBDeploy-UpdateDatabase.ps1, so on the customer side, you should have the following structure:


## Motivation

* Snapshots of an .sqlproj don't include referenced databases
* Deploying sqlpackage.exe to the customer has unclear dependencies
* SQL Scripts from DBDeploy can be tested very well
