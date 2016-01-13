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
        message += " by #{hook.user.name || hook.commit.author_name}"
        message += if hook.build_status == "pending" then " is" else " has"
        message += " [#{hook.build_status.toUpperCase()}]"
        message += if parseInt(hook.build_duration) > 0 then " and took #{hook.build_duration}s" else ""

        link = hook.repository.homepage + '/builds/' + hook.build_id

        robot.send envelope, message
        robot.send envelope, link

        debug && console.log(envelope, query, hook)

        res.end ""
