# hubot-gitlab-ci

See [`src/gitlab-ci.coffee`](src/gitlab-ci.coffee) for full documentation.

## Installation

In hubot project repo, run:

`npm install hubot-gitlab-ci --save`

Then add **hubot-gitlab-ci** to your `external-scripts.json`:

```json
["hubot-gitlab-ci"]
```

## Sample Usage

Add the following URL as a build web hook in GitLab:

```
http://<ip>:<port>/gitlab-ci?targets=room1,room2
```

or to filter for a specific status:

```
http://<ip>:<port>/gitlab-ci?targets=room1&status=failed
```
