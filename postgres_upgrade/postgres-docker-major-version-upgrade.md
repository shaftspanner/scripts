# Upgrading A PostgreSQL Database Running In Docker

## Thanks

Thanks to Thomas Bandt for this article https://thomasbandt.com/postgres-docker-major-version-upgrade

This quick guideline shows how to upgrade an existing database running on PostgreSQL major version X to major version Y, given that the database server is hosted in a Docker container.

Published on Wed, June 14, 2023

As it turns out, upgrading to a new major version of PostgreSQL takes work. So I had to google around and converse with ChatGTP4 to complete the puzzle. This quick guide is the result and is meant to be documentation for my future self. Hopefully, it will be helpful for you.
Assumptions

    The database is running in Docker.
    Docker Compose is used to orchestrate all containers.
    The Docker Compose file contains a service called db, which uses an official postgres image.
    The container name when running will be myapp_db_1.
    The application and database is called myapp.

1. Export The Existing Data

    First, ensure not to risk any data loss. Create a backup of your existing database.
    Connect to your server through SSH. Run docker-compose down to ensure no user request interferes with the following actions.
    Start the database container only: docker-compose up -d db
    Create a backup of the current database: docker exec -it myapp_db_1 pg_dumpall -U postgres > $HOME/myapp/upgrade_backup.sql. Make sure it was created correctly, e.g., by using Vim to look into it.
    Stop the database container immediately docker stop myapp_db_1.
    We now got a complete dump of the whole database. If we imported it, it would fuck up our authentication scheme for some unknown reason to the author. To avoid that, we will extract the specific data for myapp first. Create a script called pg_extract.sh and make it executable using chmod +x pg_extract.sh (source):

#!/bin/bash
[ $# -lt 2 ] && { echo "Usage: $0 <postgresql dump> <dbname>"; exit 1; }
sed  "/connect.*$2/,\$!d" $1 | sed "/PostgreSQL database dump complete/,\$d"

Run it: ./pg_extract.sh upgrade_backup.sql mydb >> upgrade_backup_mydb.sql.
2. Upgrade PostgreSQL

Open the Docker Compose file through vi docker-compose.yml and adjust the config for db. Assuming you upgrade to version 15, this would look like the following snippet. Note the new image name and the new local data directory name. That ensures we do not interfere with the old database files, as the new ones are most likely incompatible. Make sure to create that directory as well through mkdir postgres_15.

db:
  image: postgres:15-alpine
  ports:
    - "5432:5432"
  volumes:
    - $HOME/myapp/postgres_15:/var/lib/postgresql/data
  environment:
    - POSTGRES_PASSWORD
    - POSTGRES_DB
    - POSTGRES_USER
  restart: always

    Now start the database container again: docker-compose up -d db. This will download the required image if needed and create the new and empty database named after what is provided with POSTGRES_DB.
    Connect to the database and verify that the database is now running on the latest version: select version().

3. Import The Existing Data

    Import the exported file created earlier: cat $HOME/myapp/upgrade_backup_myapp.sql | docker exec -i myapp_db_1 psql -U postgres.
    Shut down the database container again: docker docker stop myapp_db_1.
    And run everything again: docker-compose up -d.

Done! 🎉
