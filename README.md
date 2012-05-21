## Things you'll need

* Jenkins
  * [EnvInject Plugin](https://wiki.jenkins-ci.org/display/JENKINS/EnvInject+Plugin)
* A [Heroku](http://heroku.com) account ([verified](https://devcenter.heroku.com/articles/account-verification))
* A GitHub account (typically a bot account)

We'll pretend the following:

* You have a Jenkins install at http://jenkins.mycompany.com
* You have a GitHub organization called MyCompany
* You have a GitHub account called MyCompany-bot
* You have a repo you'd like pull requests on called FooBar

## Initial setup

### Clone the repo locally

```sh
git clone git@github.com:cramerdev/jenkins-comments.git
cd jenkins-comments 
```

### Create a Heroku application

First we'll need a Heroku app running their Cedar stack, and a Redis
server. We'll also set the url of our Jenkins server. Chose a name
(we'll use "mycompany-jenkins-comments" for the example), and create it:

```sh
heroku create mycompany-jenkins-comments --stack cedar
git push heroku master

heroku addons:add redistogo:nano

heroku config:add JENKINS_URL=http://jenkins.mycompany.com
heroku config:add NODE_ENV=production

heroku ps:dynos 1
```

### Setup your app with permissions for GitHub

Create a new Authorization using the [GitHub Authorizations API](http://developer.github.com/v3/oauth/#create-a-new-authorization):

```sh
curl -u "MyCompany-bot:password" https://api.github.com/authorizations \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{"scopes":["repo"],"note": "mycompany-jenkins-comments.herokuapp.com"}'
```

```json
{
  "scopes": [
    "repo"
  ],
  "updated_at": "2012-05-21T16:33:05Z",
  "note_url": null,
  "app": {
    "url": "http://developer.github.com/v3/oauth/#oauth-authorizations-api",
    "name": "mycompany-jenkins-comments.herokuapp.com (API)"
  },
  "url": "https://api.github.com/authorizations/369874",
  "token": "a55199221f3f66a7d238be5fa32e2cd84735ffc1",
  "note": "mycompany-jenkins-comments.herokuapp.com",
  "created_at": "2012-05-21T16:33:05Z",
  "id": 369874
}
```

In the reponse is the token the app will use to comment on pull
requests. Add that token to Heroku:

```sh
heroku config:add GITHUB_USER_TOKEN=a55199221f3f66a7d238be5fa32e2cd84735ffc1
```

## Per repo

### Configure Jenkins Job

Under **Build > Inject environemnt variables > Properties Content**, set `BUILD_STATUS` to
success. This will only be set if the build succeeds:

```
BUILD_STATUS=success
```

In **Post-build Actions > Post build task > script**, we'll add a curl
statement to post the job status to `mycompany-jenkins-comments.herokuapp.com`:

```sh
curl "http://mycompany-jenkins-comments.herokuapp.com/jenkins/post_build\
?user=MyCompany\
&repo=FooBar\
&sha=$GIT_COMMIT\
&status=$BUILD_STATUS\
&job_name=FooBar%20Tests\
&job_number=$BUILD_NUMBER"
```

### Configure GitHub to notify us of an opened pull request

We'll use the [GitHub PubSubHubBub API](https://github.com/github/github-services/issues/166) to subscribe to pull requests
events:

```sh
curl -u "MyCompany-bot:password" https://api.github.com/hub \
  -Fhub.mode=subscribe \
  -Fhub.topic=https://github.com/MyCompany/FooBar/events/pull_request \
  -Fhub.callback=http://mycompany-jenkins-comments.herokuapp.com/github/MyCompany/FooBar
```
