# Upgrading Paperless-NGX PostgreSQL Database Running In Docker

## Thanks

Thanks to Thomas Bandt for this article https://thomasbandt.com/postgres-docker-major-version-upgrade

## Update 12/11/2025

The method described below was successfully used to upgrade a Postgres 13 database used for Paperless-NGX to Postgres 18.  I have modified the original article to reflect the adaptations I made for this but all credit for figuring it out and documenting goes to Thomas Bandt

## Introduction

This quick guideline shows how to upgrade an existing database running on PostgreSQL major version X to major version Y, given that the database server is hosted in a Docker container.

Published on Wed, June 14, 2023

As it turns out, upgrading to a new major version of PostgreSQL takes work. So I had to google around and converse with ChatGTP4 to complete the puzzle. This quick guide is the result and is meant to be documentation for my future self. Hopefully, it will be helpful for you.

## Assumptions

   1. The database is running in Docker.
   2. Docker Compose is used to orchestrate all containers.
   3. The Docker Compose file contains a service called **paperless-ngx**, which uses an official **postgres** image.
   4. The container name when running will be **paperless_db**.
   5. The postgress database is called **paperless**.

## 1. Export The Existing Data

   - First, ensure not to risk any data loss. Create a backup of your existing database.
   - Connect to your server through SSH. Run `docker-compose down` to ensure no user request interferes with the following actions.
   - Start the database container only: `docker-compose up -d paperless_db`
   - Create a backup of the current database: `docker exec -it paperless_db pg_dumpall -U paperless > $HOME/myapp/upgrade_backup.sql`. Make sure it was created correctly, e.g., by using Nano to look into it.
   - Stop the database container immediately `docker stop paperless_db`.
   - We've now got a complete dump of the whole database. If we imported it, it would fuck up our authentication scheme for some unknown reason to the author. To avoid that, we will extract the specific data for myapp first. Create a script called `pg_extract.sh` and make it executable using `chmod +x pg_extract.sh`:

```
#!/bin/bash
[ $# -lt 2 ] && { echo "Usage: $0 <postgresql dump> <dbname>"; exit 1; }
sed  "/connect.*$2/,\$!d" $1 | sed "/PostgreSQL database dump complete/,\$d"
```

   - Run it: `./pg_extract.sh upgrade_backup.sql paperless >> upgrade_backup_paperless.sql`.

## 2. Upgrade PostgreSQL

Open the Docker Compose file through `nano docker-compose.yml`, comment out the config for the original db and add the config for the new db. Assuming you upgrade to version 18, this would look like the following snippet. Note the new image name and the new local data directory name. That ensures we do not interfere with the old database files, as the new ones are most likely incompatible. Make sure to create that directory as well through `mkdir pgdata2`.

```
  paperless_db_2:
    container_name: paperless_db_2
    image: postgres:18
    restart: ${RESTART_POLICY}
    volumes:
      - ${LOC_CONFIG}/paperless/pgdata2:/var/lib/postgresql/18/data
    environment:
      POSTGRES_DB: ${PAPERLESS_DB}
      POSTGRES_USER: ${PAPERLESS_DB_USER}
      POSTGRES_PASSWORD: ${PAPERLESS_DB_PASSWORD}
```

Note that I keep a lot of configuration items in my `.env` file.  Make sure your `.env` file contains these substitutions or replace them with the required values

   - Now start the database container again: `docker-compose up -d paperless_db_2`. This will download the required image if needed and create the new and empty database named after what is provided with POSTGRES_DB (In my case this is `paperless`).
   - Connect to the database and verify that the database is now running on the latest version: `select version()`.

## 3. Import The Existing Data

   - Import the exported file created earlier: `cat $HOME/myapp/upgrade_backup_paperless.sql | docker exec -i paperless_db_2 psql -U paperless`.
   - Shut down the database container again: `docker stop paperless_db_2.
   - Go through your paperless docker-compose.yml and everywhere that `paperless_db` appears, substitute it with `paperless_db_2`
   - And run everything again: docker-compose up -d.

Done! 🎉
