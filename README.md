# CronManager feature proposal

## Configuration files

* Located in ./DSL
* File name is applied as cron group - namespace, that groups jobs defined in that file together. 
For example, file "training-module.yml" contains Training-Module specific cronjobs. 
* One group (file) can define one or more jobs
* Jobs are defined as yaml files, similarily to Ruuter.
* Job order in file is not determined, each one can and is run separately.

Base Job structure:

```yaml
<job_name>:
  trigger: <trigger_expression>
  type: <job_type>
```

Currently only HTTP request job is implemented with structure:

```yaml
<job_name>:
  trigger: <trigger_expression>
  type: http
  method: <http_method (i.e GET, POST, etc.)>
  url: <request_url>
```


Trigger expressions can be set to cron expression or string value "off", in which case this job is not scheduled to run.
It can still be run through API.

An example of a configuration is included in DSL/example.yml


## API calls

#### GET /jobs[/<group_name>]
Returns JSON formatted list of jobs in specified group. 
If group_name is omitted, all jobs from all groups are returned.

Example:
```json
[
    "devops":
      [
        {
          "name": "ruuter-health",
          "schedule": "0 0/10 * * * ?",
          "lastExecution": 1704260826,
          "nextExecution": 1704261426,
          "lastResult": "{\"appName\":\"ruuter\",\"version\":\"PRE-ALPHA-2.3.0\",\"packagingTime\":1703237155,\"appStartTime\":1704055509830,\"serverTime\":1704176520940}"
        }
      ],
    
    "training": 
      [
        {
          "name": "train_intents",
          "schedule": "off",
          "lastExecution": -1,
          "nextExecution": -1
        }
      ]
]
```

Timestamp -1 means that this event has not occurred yet (or is not scheduled to occur).

#### GET /running[/<group_name>] 
Returns list of currently running jobs from specified group.
If group_name is omitted, currently running jobs from all groups are returned.

Example: 
```json
[
  {
    "name": "ruuter-priv-health",
    "started": 1704261426
  },{
    "name": "ruuter-pub-health",
    "started": 1704261326
  }
]
```

#### POST /execute/<group_name>/<job_name> (TODO)
Executes specified job from specifed group out of schedule.

Returns list of currently running jobs in that group at the moment of execution in same format as `GET /running``

#### POST /stop/<group_name>/<job_name>
Stops specified job. 

Returns list of currently running jobs in that group at the moment of execution in same format as `GET /running``


### Administrors' API calls

#### POST /reload[/<group_name>] (TODO)

Reloads specified job group from configuration. If no group is supplied, reloads all files.
This can be used when administrator has changed the configuration in runtime.

#### POST /upload/<group_name> (TODO)