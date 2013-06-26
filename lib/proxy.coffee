#
# This is a proxy based on node-http-proxy which routes requests as specified
# in config/proxy.  It's useful for resolving disparate apps (e.g. etherpad
# and InterTwinkles) running on different domains to their backends.
#
httpProxy = require 'http-proxy'
url       = require 'url'
logger    = require('log4js').getLogger("proxy")

start = (config) ->
  router = {}
  for app in config.routes
    logger.info("#{app.url} => #{app.host}:#{app.port}")
    frontend_parsed = url.parse(app.url)
    router[frontend_parsed.hostname] = "#{app.host}:#{app.port}"

  options = {
    hostnameOnly: true
    router: router
  }
  use_ssl = false
  if config.https?.key and config.https?.cert
    use_ssl = true
    options.https = {
      key: config.https.key
      cert: config.https.cert
      # mitigate BEAST
      honorCipherOrder: true
      # May want to add: ECDHE-RSA-RC4-SHA, ECDHE-RSA-AES128-SHA (https://www.imperialviolet.org/2012/03/02/ieecdhe.html / https://www.imperialviolet.org/2011/11/22/forwardsecret.html) -- consult https://www.openssl.org/docs/apps/ciphers.html#CIPHER_LIST_FORMAT
      ciphers: "ECDHE-RSA-AES128-SHA256:AES128-GCM-SHA256:RC4:HIGH:!MD5:!aNULL:!EDH"
    }

  proxyServer = httpProxy.createServer(options)
  proxyServer.listen(config.listen)
  logger.info(
    "#{if use_ssl then "SSL enabled. " else ""}Listening for " +
    "HTTP#{if use_ssl then "S" else ""} on port #{config.listen}"
  )

module.exports = {start}
