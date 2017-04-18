path = require("path")
Koa = require("koa")
GetLocale = require("get-locale")
getLocale = new GetLocale 
  supported: ["de","en"]
  priority: ["query","header"]
Router = require("../src/server.coffee")
router = new Router
  cache: "./dev/localeCache"
  base:
    file: "./index"
    folder: "./dev"
  routes:
    "/": {}
  folder: 
    de: "./dev/app/de"
    en: "./dev/app/en"
module.exports = (server, reload) ->
  koa = new Koa()
  koa.use getLocale.middleware("koa")
  koa.use router.middleware("koa")
  server.on "request", koa.callback()
  server.listen(8080)

