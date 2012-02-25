# Automated Jenkins Job Status Comments on GitHub Pull Requests

Configure the post-build hook and launch it on Heroku:

```
$ git clone git://gist.github.com/1911084.git jenkins-pull-request-comments
$ cd jenkins-pull-request-comments
$ heroku create --stack cedar
$ heroku config:add NODE_ENV=production
$ heroku config:add GITHUB_USER_LOGIN=...
$ heroku config:add GITHUB_USER_PASSWORD=...
$ heroku config:add JENKINS_URL=...
$ git push heroku master
$ heroku ps:scale web=1
```

Then configure your Jenkins job to call the post-build hook to report job status:

```
$ curl "http://your.herokuapp.com/jenkins/post_build?\
    user=$GITHUB_USER\
    &repo=$GITHUB_REPO\
    &sha=$GIT_COMMIT\
    &status=$BUILD_STATUS\
    &job=$BUILD_NUMBER"
```

You'll have to specify `GITHUB_USER`, `GITHUB_REPO`, and your build should set `BUILD_STATUS=success` if the build succeeded.