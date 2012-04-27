async   = require 'async'
request = require 'request'
express = require 'express'
_       = require 'underscore'
_s      = require 'underscore.string'

class PullRequestCommenter
  BUILDREPORT = "**Build Status**:"

  constructor: (@sha, @job_name, @job_number, @user, @repo, @succeeded) ->
    @job_url = "#{process.env.JENKINS_URL}/job/#{@job_name}/#{@job_number}/console"
    @api = "https://api.github.com/repos/#{@user}/#{@repo}"
    @token = "?access_token=#{process.env.GITHUB_USER_TOKEN}"

  post: (path, obj, cb) =>
    console.log "POST #{@api}#{path}#{@token}"
    console.dir obj
    request.post { uri: "#{@api}#{path}#{@token}", json: obj }, (e, r, body) ->
      console.log body
      cb e, body

  get: (path, cb) =>
    console.log "GET #{@api}#{path}#{@token}"
    request.get { uri: "#{@api}#{path}#{@token}", json: true }, (e, r, body) ->
      console.log body
      cb e, body

  del: (path, cb) =>
    console.log "DELETE #{@api}#{path}#{@token}"
    request.del { uri: "#{@api}#{path}#{@token}" }, (e, r, body) ->
      console.log body
      cb e, body

  getCommentsForIssue: (issue, cb) =>
    @get "/issues/#{issue}/comments", cb

  deleteComment: (id, cb) =>
    @del "/issues/comments/#{id}", cb

  getPulls: (cb) =>
    @get "/pulls", cb

  getPull: (id, cb) =>
    @get "/pulls/#{id}", cb

  commentOnIssue: (issue, comment) =>
    @post "/issues/#{issue}/comments", (body: comment), (e, body) ->
      console.log e if e?

  successComment: ->
    "#{BUILDREPORT} :green_heart: `Succeeded` (#{@sha}, [job info](#{@job_url}))"

  errorComment: ->
    "#{BUILDREPORT} :broken_heart: `Failed` (#{@sha}, [job info](#{@job_url}))"

  # Find the first open pull with a matching HEAD sha
  findMatchingPull: (pulls, cb) =>
    pulls = _.filter pulls, (p) => p.state is 'open'
    async.detect pulls, (pull, detect_if) =>
      @getPull pull.number, (e, { head }) =>
        return cb e if e?
        detect_if head.sha is @sha
    , (match) =>
      return cb "No pull request for #{@sha} found" unless match?
      cb null, match

  removePreviousPullComments: (pull, cb) =>
    @getCommentsForIssue pull.number, (e, comments) =>
      return cb e if e?
      old_comments = _.filter comments, ({ body }) -> _s.include body, BUILDREPORT
      async.forEach old_comments, (comment, done_delete) =>
        @deleteComment comment.id, done_delete
      , () -> cb null, pull

  makePullComment: (pull, cb) =>
    comment = if @succeeded then @successComment() else @errorComment()
    @commentOnIssue pull.number, comment
    cb()

  updateComments: (cb) ->
    async.waterfall [
      @getPulls
      @findMatchingPull
      @removePreviousPullComments
      @makePullComment
    ], cb

app = module.exports = express.createServer()

app.configure 'development', ->
  app.set "port", 3000

app.configure 'production', ->
  app.use express.errorHandler()
  app.set "port", parseInt process.env.PORT

# Jenkins lets us know when a build has failed or succeeded.
app.get '/jenkins/post_build', (req, res) ->
  sha = req.param 'sha'
  job_name = req.param 'job_name'
  job_number = parseInt req.param 'job_number'
  user = req.param 'user'
  repo = req.param 'repo'
  succeeded = req.param('status') is 'success'

  # Look for an open pull request with this SHA and make comments.
  commenter = new PullRequestCommenter sha, job_name, job_number, user, repo, succeeded
  commenter.updateComments (e, r) -> console.log e if e?
  res.send 'Ok', 200

# GitHub lets us know when a pull request has been opened.
app.post '/github/post_receive', (req, res) ->
  console.dir req
  res.send 'Ok', 200

app.listen app.settings.port
