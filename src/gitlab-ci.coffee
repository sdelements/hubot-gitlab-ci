# Description
#   GitLab CI web hook thing
#
# Usage:
#   http://<ip>:<port>/gitlab-ci?targets=room1,room2
#
# Author:
#   Houssam Haidar[houssam@sdelements.com]

url = require 'url'
querystring = require 'querystring'

module.exports = (robot) ->

    debug = process.env.GITLABCI_DEBUG?

    robot.router.post "/gitlab-ci", (req, res) ->

        gitlabCiChannel = process.env.GITLABCI_CHANNEL or "#gitlab"

        query = querystring.parse(url.parse(req.url).query)
        hook = req.body

        if !hook || hook.object_kind != "build"
            res.end ""
            return

        envelope = {}
        envelope.room = if query.targets then query.targets else gitlabCiChannel
        envelope.type = query.type if query.type

        message = "#{hook.ref}: Build #{hook.build_id} (#{hook.build_name})"
        message += " by #{hook.user.name} is [#{hook.build_status.toUpperCase()}]"
        message += if hook.build_duration then " and took #{Math.round(hook.build_duration / 1000)}s" else ""

        robot.send envelope, message

        debug && console.log(envelope, query, hook)

        res.end ""
