path = require("path")
Koa = require("koa")
koaHotDevWebpack = require "koa-hot-dev-webpack"
server = null
router = null
connections = []
startup = (reload) ->
  console.log "startup"
  try
    router = require("./router")(require("../src/server.coffee"))
    koa = new Koa()
    koa.use(require("koa-static")(path.resolve("./static")))
    koa.use koaHotDevWebpack(require("./webpack.config.coffee"))
    koa.use(router.middleware("koa"))
    server = require("http").createServer(koa.callback())
    server.listen(8080)
    koaHotDevWebpack.reload() if reload
    server.on "connection", (con) ->
      connections.push con
  catch e
    console.log e
startup()
restart = ->
  console.log "restart"
  koaHotDevWebpack.close()
  router.close()
  if server
    server.once "close", startup.bind(null, true)
    server.close()
    server = null
    for con in connections
      con?.destroy?()
    connections = []
  else
    startup(true)
chokidar = require "chokidar"
chokidar.watch(["./src","dev"],{ignoreInitial: true, ignored: "**/app/**"})
  .on "all", (ev,filepath) ->
    filepath = path.resolve(filepath)
    if (mod = require.cache[filepath])?
      delete require.cache[filepath]
      console.log "deleted cache for #{filepath}"
      while (id = mod.parent?.id) != "."
        delete require.cache[id]
        console.log "deleted cache for #{id}"
        mod = mod.parent
        
    restart()