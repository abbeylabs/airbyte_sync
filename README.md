# airbyte_sync
A combination of Docker and scripts to fully automate Airbyte pre-configured data sync

## How to run
- Install Docker and docker-compose
- Download this repo
- In one shell:
```shell
cd airbyte_sync
docker-compose up
```
  wait until the server is started on port 8000 (there will be fancy ascii art)

- In the other shell:
```shell
cd airbyte_sync
bash ./configure_connection.sh
```
