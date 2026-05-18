# CronManager feature proposal

## Job specification files

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
  startDate: <start_timestamp>
  endDate: <end_timestamp>
```

- Trigger expressions can be set to cron expression or `off`/`false` (NB! without quotes 
which would make this a string) in which case this job is not scheduled to run.
  It can still be run through API.
- `startDate` and `endDate` are optional and stored as timestamps in milliseconds since 1970-01-01 ("epoch"). Cronjobs action
is not executed if current time is before `startDate` or after `endDate`. 

### Implemented job types

#### HTTP request job

```yaml
<job_name>:
  trigger: <trigger_expression>
  type: http
  method: <http_method (i.e GET, POST, etc.)>
  url: <request_url>
```

#### Shell execution job
```yaml
<job_name>:
  trigger: <trigger_expression>
  type: http
  command: <path_to_executable_script>
  allowedEnvs: [<array_of_allowed_environment_variables>]
```

- `path_to_executable_script` is resolved from application root 
folder (defined in `application.appRootFolder`)
- if server is started as a standalone and by `startup.sh` script 
or inside a Docker container, the scripts in `scripts` folder under 
application root are automatically change to executable, in other cases
this has to be done manually.
- `allowedEnvs` is (comma separated) array of strings that specify, which
query parameters are passed to script as shell environment variables.


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

#### POST /execute/<group_name>/<job_name>
Executes specified job from specifed group out of sch edule.

It is possible to add query parameters that will be filtered through `allowedEnvs` 
and passed as environment variables to shell execution jobs. 

Returns list of currently running jobs in that group at the moment of execution in same format as `GET /running``

#### POST /stop/<group_name>/<job_name>
Stops specified job. 

Returns list of currently running jobs in that group at the moment of execution in same format as `GET /running``


### Administrors' API calls

#### POST /reload[/<group_name>] (TODO)

Reloads specified job group from configuration. If no group is supplied, reloads all files.
This can be used when administrator has changed the configuration in runtime.

#### POST /upload/<group_name> (TODO)


## Configuration

- `configPath` - location of job specification files, default value `/DSL`
- `allowedOrigins`- YAML list of CORS allowed IP's 
- `shellEnvironment` - YAML list of key-value pairs (key=value) that should be passed 
to executed scripts 
- `appRootPath`- location of `scripts` folder, usually application root, default `/app`

### `constants.ini`
| Key | Example value | Required | Description |
| --- | --- | --- | --- |
| `CHAT_GENERATION_CSA_ID` | `EE30303039914` | Yes | Personal ID / login of the CSA account used by chat generation. The scripts use this value to authenticate the CSA, mark the CSA as online, assign the generated chat to that CSA, and send CSA-authored messages. |
| `CHAT_GENERATION_CSA_PASSWORD` |  | Yes | Password for `CHAT_GENERATION_CSA_ID`. This is intentionally left empty in the template and must be supplied per environment. It is required so the script can log in and receive the backoffice authentication cookie used for private Ruuter requests. |
