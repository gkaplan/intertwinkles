#
# Configuration for InterTwinkles.  Set domains and ports in `domains.coffee`;
# all other settings below.
#

fs = require 'fs'
SECRET = fs.readFileSync(__dirname + "/secrets/SECRET.txt", 'utf-8').trim()
API_KEY = fs.readFileSync(__dirname + "/secrets/API_KEY.txt", 'utf-8').trim()
try
  ETHERPAD_API_KEY = fs.readFileSync(
    __dirname + "/../vendor/etherpad-lite/APIKEY.txt", 'utf-8').trim()
catch e
  console.error "Etherpad API key not found.  Etherpad will not be available."
  ETHERPAD_API_KEY = ""
domains = require './domains'
email_config = require './email'
base_url = domains.front_end_url

config = {
  # The port on which intertwinkles listens.
  port: domains.base_port
  redirect_port: domains.redirect_port
  # Email configuration
  email: email_config
  from_email: domains.from_email
  # Make this unique, secret, and complex.  It's used for signing session cookies.
  secret: SECRET
  # Mongodb host and port
  dbhost: "localhost"
  dbport: 27017,
  dbname: "intertwinkles"
  # The API key this app uses to make intertwinkles requests.
  api_key: API_KEY
  # Path to a URL shortener that is configured to rewrite to {api_url}/r/.  If
  # you don't have a short URL domain configured, use {api_url}/r/.
  short_url_base: domains.short_url_base
  # Domain to use for cookie suppressing alpha warning
  alpha_cookie_domain: domains.alpha_cookie_domain
  # This is a list of client IP addresses that are allowed to access the API.
  # It should contain a list of IP's of the hosts for each InterTwinkles app.
  api_clients: ["127.0.0.1"]
  # The list of API keys we will accept for connecting clients.  Should include
  # at least our own key.
  authorized_keys: [API_KEY]
  api_url: base_url
  # Installed apps.
  apps: {
    www: {
      name: "Home"
      about: "Recent activity from all your groups"
      url: base_url
      image: "#{base_url}/static/img/groups.png"
    }
    firestarter: {
      name: "Firestarter"
      about: "Go arounds, ice breakers, intros. Get to know each other."
      url: "#{base_url}/firestarter"
      image: "#{base_url}/static/firestarter/img/firestarter_tile.png"
    }
    resolve: {
      name: "Resolve"
      about: "Approve or reject a proposal with a group. Asynchronous voting and revising of proposals."
      url: "#{base_url}/resolve"
      image: "#{base_url}/static/resolve/img/resolve_tile.png"
    }
    dotstorm: {
      name: "Dotstorm"
      about: "Structured brainstorming with sticky notes. Come up with new ideas."
      url: "#{base_url}/dotstorm"
      image: "#{base_url}/static/dotstorm/img/dotstorm_tile.png"
      video: "https://www.youtube-nocookie.com/embed/dj_yW2WfsEw"
    }
    twinklepad: {
      name: "TwinklePad"
      about: "Public or private collaborative document editing with etherpads"
      url: "#{base_url}/twinklepad"
      image: "#{base_url}/static/twinklepad/img/twinklepad_tile.png"
      etherpad: {
        url: domains.etherpad_url
        api_key: ETHERPAD_API_KEY
        cookie_domain: domains.etherpad_cookie_domain
      }
    }
    points: {
      name: "Points of Unity"
      about: "Develop a set of principles or values with your group"
      url: "#{base_url}/points"
      image: "#{base_url}/static/points/img/points_tile.png"
    }
    clock: {
      name: "Progressive Clock"
      about: "Keep time in meetings by identity category"
      url: "#{base_url}/clock"
      image: "#{base_url}/static/clock/img/clock.png"
    }
  }
  testing: {
    selenium_path: __dirname + "/../vendor/selenium-server-standalone.jar"
  }
  hangout_origin_re: "^#{base_url}$" # For local testing
  #hangout_origin_re: "^https://[-a-z0-9]+hangout-opensocial.googleusercontent.com$" # Production
}
module.exports = config
