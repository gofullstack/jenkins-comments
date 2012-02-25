async   = require 'async'
request = require 'request'
express = require 'express'
_       = require 'underscore'
_s      = require 'underscore.string'

class BuildResult
  constructor: (@sha, @job, @user_repo, @succeeded) ->

  @fromRequest: (req) ->
    sha = req.param 'sha'
    job = parseInt req.param 'job'
    succeeded = req.param('status') is 'success'
    user_repo = "#{req.param 'user'}/#{req.param 'repo'}"
    new BuildResult sha, job, user_repo, succeeded

class PullRequestCommenter
  BUILDREPORT = "**Build Status**:"

  constructor: (build_result) ->
    {@sha, @succeeded, @job} = build_result
    [@user, @repo] = build_result.user_repo.split '/'
    @job_url = "#{process.env.JENKINS_URL}/job/#{@repo}/#{@job}"
    @api = "https://#{process.env.GITHUB_USER_LOGIN}:#{process.env.GITHUB_USER_PASSWORD}@api.github.com/#{build_result.user_repo}"

  post: (path, obj, cb) =>
    request.post { uri: "#{@api}#{path}", json: obj }, (e, r, body) ->
      cb e, body

  get: (path, cb) =>
    request.get { uri: "#{@api}#{path}", json: true }, (e, r, body) ->
      cb e, body

  del: (path, cb) =>
    request.del { uri: "#{@api}#{path}" }, (e, r, body) ->
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
    @post "/repos/#{@user}/#{@repo}/issues/#{issue}/comments", (body: comment), (e, body) ->
      console.log e if e?

  successComment: ->
    "#{BUILDREPORT} `Succeeded` (#{@sha}, [job info](#{@job_url}))"

  errorComment: ->
    "#{BUILDREPORT} `Failed` (#{@sha}, [job info](#{@job_url}))"

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


# Configuration
app = module.exports = express.createServer()

app.configure 'development', ->
  app.set "port", 3000

app.configure 'production', ->
  app.use express.errorHandler()
  app.set "port", parseInt process.env.PORT

# Jenkins lets us know when a build has failed or succeeded.
app.get '/jenkins/post_build', (req, res) ->
  result = BuildResult.fromRequest req

  # Look for an open pull request with this SHA and make comments.
  commenter = new PullRequestCommenter result
  commenter.updateComments (e, r) -> console.log e if e?
  res.send 'Ok', 200

app.listen app.settings.port