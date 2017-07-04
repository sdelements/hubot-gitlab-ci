# Description
#   GitLab CI web hook thing
#
# Usage:
#   http://<ip>:<port>/gitlab-ci?targets=room1,room2
#
# Usage w/ filtered status:
#   http://<ip>:<port>/gitlab-ci?targets=room1&status=failed
#
# Author:
#   Houssam Haidar[houssam@sdelements.com]
#
# Commands:
#   hubot Trigger <x.x> build off <branch> - Trigger a build but do not update Richmond. The format is like "trigger 4.7 build off release/4.7", this affects the new tag that gets created.
#   hubot Trigger richmond <x.x> build off <branch> - Trigger a build and update richmond with it
#   hubot Trigger quick richmond <x.x> build off <branch> - Trigger a build and update richmond with it, but skip tests
#   hubot release_notes {release_number} - Display a list of JIRA ticket numbers
#
#   Requires a few environment variables setup
#
#     GITLABCI_SERVER - gitlab ci hostname
#     TEST_SERVER - test server hostname
#     GITLABCI_PROJECT_NAME - project name of the main project (i.e. 'myorg/myproject')
#     GITLABCI_PROJECT_ID - project id of the main project
#     GITLABCI_TOKEN - access token to gitlab ci
#     JIRA_PROJECT_KEY - project key for jira project

async = require 'async'
url = require 'url'
querystring = require 'querystring'

module.exports = (robot) ->

    debug = process.env.GITLABCI_DEBUG?
    jiraKey = process.env.JIRA_PROJECT_KEY || "JIRA"

    robot.router.post "/gitlab-ci", (req, res) ->

        gitlabCiChannel = process.env.GITLABCI_CHANNEL or "#gitlab"

        query = querystring.parse(url.parse(req.url).query)
        hook = req.body
        status = query.status?

        if !hook || hook.object_kind != "build" || (query.status && query.status != hook.build_status)
            res.end ""
            return

        envelope = {}
        envelope.room = if query.targets then query.targets else gitlabCiChannel
        envelope.type = query.type if query.type

        message = "#{hook.ref}: Build #{hook.build_id} (#{hook.build_name})"
        message += " by #{hook.user.name || hook.commit.author_name}"
        message += if /ing$/i.test(hook.build_status) then " is" else " has"
        message += " [#{hook.build_status.toUpperCase()}]"
        message += if parseInt(hook.build_duration) > 0 then " and took #{Math.round(hook.build_duration * 100) / 100}s" else ""

        link = hook.repository.homepage + '/builds/' + hook.build_id

        robot.send envelope, message
        robot.send envelope, link

        debug && console.log(envelope, query, hook)

        res.end ""

    #
    # Release notes command
    #
    baseURL = "https://#{process.env.GITLABCI_SERVER}/api/v3/projects/#{process.env.GITLABCI_PROJECT_ID}/repository"
    gitlabci_token = process.env.GITLABCI_TOKEN

    getTag = (tag, callback) ->
        robot.http("#{baseURL}/tags/#{tag}?private_token=#{gitlabci_token}")
            .header('Accept', 'application/json')
            .get() (err, res, body) ->
                if err
                    console.log(err)
                    return
                if res.statusCode != 200
                    console.log("Invalid tag name: #{tag}")
                    return

                data = JSON.parse body
                callback(null, data.commit.committed_date)

    getJiraIDs = (current_version, since_date, callback) ->
        robot.http("#{baseURL}/commits?ref_name=#{current_version}&since=#{since_date}&per_page=100&private_token=#{gitlabci_token}")
            .header('Accept', 'application/json')
            .get() (err, res, body) ->
                if (err)
                    console.log(err)
                    return

                data = JSON.parse body
                # The last commit is tied to the previous release
                data.pop()
                pattern = new RegExp("#{jiraKey}-\\d+", "i")
                jira_ids = []

                for commit in data
                    id = pattern.exec(commit.message)
                    if !id || jira_ids.indexOf("##{id[0]}") != -1
                      continue
                    jira_ids.push("##{id[0]}")
                jira_ids.sort()

                callback(jira_ids)

    getJiraTicketsForRelease = (current_version, previous_version, callback) ->
        async.parallel([
            (callback) ->
                getTag(current_version, callback)
            (callback) ->
                getTag(previous_version, callback)
        ]
            (err, results) ->
                getJiraIDs(current_version, results[1], callback)
        )

    getPreviousReleaseVersion = (version) ->
        major = parseInt(version.shift())
        minor = parseInt(version.shift())
        dev = parseInt(version.shift())

        if dev == 0
            dev = 9
            minor--
        else
            dev--
        if minor == -1
            minor = 9
            major--
        if major == -1
            console.log('ERROR')
            return

        return "#{major}.#{minor}.#{dev}"
    triggerBuildPost = (res, updateTestServer, quickly, branch, buildTagPrefix) ->
        triggerURL = "https://#{process.env.GITLABCI_SERVER}/api/v4/projects/#{process.env.GITLABCI_PROJECT_ID}/trigger/pipeline/"
        token = gitlabci_token
        ref = branch
        buildDestination = 'test'
        testServer = process.env.TEST_SERVER
        buildTagPrefix = buildTagPrefix + '.'
        fields = {
            'token': token,
            'ref': ref,
            'variables[BUILD_DESTINATION]': buildDestination,
            'variables[BUILD_TAG_PREFIX]': buildTagPrefix,
        }
        if updateTestServer
            fields['variables[TEST_SERVER]'] = testServer
            fields['variables[SKIP_CHECK_FOR_CHANGES]'] = 'true'
            if quickly
                fields['variables[SKIP_TESTS]'] = 'true'

        data = querystring.stringify(fields)
        console.log data
        robot.http("#{triggerURL}?private_token=#{gitlabci_token}", { rejectUnauthorized: false }).header('Content-Length', data.length).header('Content-Type', 'application/x-www-form-urlencoded').post(data) (err, resp, body) ->
            jbody = JSON.parse(body)
            if err
                res.send "Could not trigger build :("
                res.send "Error: #{err}"
            else
                res.send "Build triggered off #{ref}! Find it at: https://#{process.env.GITLABCI_SERVER}/#{process.env.GITLABCI_PROJECT_NAME}/pipelines/#{jbody.id}"

    triggerBuildRespond = (res) ->
        triggerBuildPost res, false, false, res.match[2], res.match[1]

    triggerRichmondBuildRespond = (res) ->
        triggerBuildPost res, true, false, res.match[2], res.match[1]

    triggerQuickRichmondBuildRespond = (res) ->
        triggerBuildPost res, true, true, res.match[2], res.match[1]

    robot.respond /trigger (\d+\.\d+) build off (.*)/i, triggerBuildRespond
    robot.respond /trigger richmond (\d+\.\d+) build off (.*)/i, triggerRichmondBuildRespond
    robot.respond /trigger quick richmond (\d+\.\d+) build off (.*)/i, triggerQuickRichmondBuildRespond

    robot.respond /release_notes ((\d+(\.\d+)*)(qa)?)(\s+(\d+(\.\d+)*)(qa)?)?$/i, (res) ->
         version = res.match[1]
         previous_version = res.match[5]

         if !previous_version
            tag = res.match[2].trim().split('.')
            previous_version = getPreviousReleaseVersion(tag)
            if res.match[4]
                previous_version = previous_version + "qa"

         previous_version = previous_version.trim()

         getJiraTicketsForRelease(version, previous_version, (jira_ids) ->
              res.reply "#{previous_version} => #{version} : #{jira_ids.length} tickets"
              res.reply jira_ids.join(', ')
         )
