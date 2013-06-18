async   = require 'async'
request = require 'request'
express = require 'express'
_       = require 'underscore'
_s      = require 'underscore.string'

if process.env.REDISTOGO_URL
  rtg   = require("url").parse process.env.REDISTOGO_URL
  redis = require("redis").createClient rtg.port, rtg.hostname
  redis.auth rtg.auth.split(":")[1]
else
  redis = require("redis").createClient()

class PullRequestCommenter
  BUILDREPORT = "**Build Status**:"

  constructor: (@sha, @job_name, @job_number, @user, @repo, @succeeded) ->
    @job_url = "#{process.env.JENKINS_URL}/job/#{@job_name}/#{@job_number}/console"
    @api = "https://api.github.com/repos/#{@user}/#{@repo}"
    @token = "?access_token=#{process.env.GITHUB_USER_TOKEN}"

  post: (path, obj, cb) =>
    console.log "POST #{@api}#{path}#{@token}"
    console.dir obj
    request.post { uri: "#{@api}#{path}#{@token}", json: obj, headers: 'User-Agent': 'Skyscrpr Status Commenter' }, (e, r, body) ->
      console.log body if process.env.DEBUG
      cb e, body

  get: (path, cb) =>
    console.log "GET #{@api}#{path}#{@token}"
    request.get { uri: "#{@api}#{path}#{@token}", json: true, headers: 'User-Agent': 'Skyscrpr Status Commenter' }, (e, r, body) ->
      console.log body if process.env.DEBUG
      cb e, body

  del: (path, cb) =>
    console.log "DELETE #{@api}#{path}#{@token}"
    request.del { uri: "#{@api}#{path}#{@token}", headers: 'User-Agent': 'Skyscrpr Status Commenter' }, (e, r, body) ->
      console.log body if process.env.DEBUG
      cb e, body

  getCommentsForIssue: (issue, cb) =>
    @get "/issues/#{issue}/comments", cb

  deleteComment: (id, cb) =>
    @del "/issues/comments/#{id}", cb

  commentOnIssue: (issue, comment) =>
    @post "/issues/#{issue}/comments", (body: comment), (e, body) ->
      console.log e if e?

  setCommitStatus: (state) =>
    @post "/statuses/#{@sha}", (state:state, target_url:@job_url, description:'job info'), (e, body) ->
      console.log e if e?

  makePullComment: (cb) =>
    state = if @succeeded then 'success' else 'failure'
    @setCommitStatus state
    cb()

  updateComments: (cb) ->
    async.waterfall [
      @makePullComment
    ], cb

app = module.exports = express.createServer()

app.configure ->
  app.use express.bodyParser()

app.configure 'development', ->
  app.set "port", 3000

app.configure 'production', ->
  app.use express.errorHandler()
  app.set "port", parseInt process.env.PORT

# Route for uptime pings and general curiosity
app.get '/', (req, res) ->
  res.send '
    <a href="https://github.com/cramerdev/jenkins-comments">
      jenkins-comments
    </a>
  ', 200

# Jenkins lets us know when a build has failed or succeeded.
app.get '/jenkins/post_build', (req, res) ->
  sha = req.param 'sha'

  if sha
    job_name = req.param 'job_name'
    job_number = parseInt req.param 'job_number'
    user = req.param 'user'
    repo = req.param 'repo'
    succeeded = req.param('status') is 'success'

    # Store the status of this sha for later
    redis.hmset sha, {
      "job_name": job_name,
      "job_number": job_number,
      "user": user,
      "repo": repo,
      "succeeded": succeeded
    }

    # Look for an open pull request with this SHA and make comments.
    commenter = new PullRequestCommenter sha, job_name, job_number, user, repo, succeeded
    commenter.updateComments (e, r) -> console.log e if e?
    res.send 200
  else
    res.send 400

# GitHub lets us know when a pull request has been opened.
app.post '/github/post_receive', (req, res) ->
  payload = JSON.parse req.body.payload
  if payload.pull_request
    sha = payload.pull_request.head.sha

    # Get the sha status from earlier and insta-comment the status
    redis.hgetall sha, (err, obj) ->
      # Convert stored string to boolean
      obj.succeeded = (obj.succeeded == "true" ? true : false)

      commenter = new PullRequestCommenter sha, obj.job_name, obj.job_number, obj.user, obj.repo, obj.succeeded
      commenter.updateComments (e, r) -> console.log e if e?

    res.send 201
  else
    res.send 404

app.listen app.settings.port
