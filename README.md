# What this is 

This script leverages and extends the integration code from a provider called Airbyte to ingest data from Github (a source) and write that data into Google’s data warehouse service, BigQuery (a destination). It allows you to run this integration locally through a Docker container. 

You can find the integration code for the source Github [here](https://github.com/XIDProject/airbyte/tree/master/airbyte-integrations/connectors/source-github/source_github). You can find the integration code for our destination, BigQuery [here](https://github.com/XIDProject/airbyte/tree/master/airbyte-integrations/connectors/destination-bigquery). 

## Precursors

A Github instance and a Personal Access Token. You can find more details about how to set up the Github connector [here](https://docs.airbyte.com/integrations/sources/github/), including the required scopes for the Personal Access Token. 
A Google BigQuery instance with a specific project and dataset for this sync and a GoogleCloud service account. You can find more details about how to set up the BigQuery integration [here](https://docs.airbyte.com/integrations/destinations/bigquery/). 


## How to run
- If running on EC2, use `Amazon Linux 2 AMI (HVM) - Kernel 5.10, SSD Volume Type` image with t2.medium instance type and 30GB of disk space.
  This instance type and disk space is what Airbyte recommends. The scripts will probably run on other image types as well, but you need to make sure that bash and `envsubst` are available.
- Install Docker and docker-compose. See [this](https://docs.airbyte.com/deploying-airbyte/on-aws-ec2#install-environment) as an example.
- Download this repo
- Create config.yml to configure Github org/repository and BigQuery project and dataset ids (you can use sample_config.yml as an example)
- In one shell:
```shell
cd airbyte_sync
docker-compose up
```
- Wait until the server is started on port 8000 (there will be some fancy ascii art)
- Login to Airbyte
- Make sure following scopes are selected for provided Github Personal Access Token:
```shell
repo, read:org, read:repo_hook, read:user, read:discussion, workflow
```
For further information about scopes and permissions: https://docs.airbyte.com/integrations/sources/github#permissions-and-scopes
- In the other shell:
```shell
export GITHUB_PERSONAL_ACCESS_TOKEN=<your Github PAK>
export GCP_CREDENTIALS_JSON='<json auth file for GCP system account>'
cd airbyte_sync
bash ./configure_connection.sh config.yml
```
Once it finishes, run
```shell
bash ./sync_data.sh
```
It'll kick off the data sync. The data sync may take a while - watch the logs in the docker-compose to see the progress. By default, this sync is configured to run manually (it's not configured to run on a schedule). 
