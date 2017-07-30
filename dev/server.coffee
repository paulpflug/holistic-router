path = require("path")
Koa = require("koa")
module.exports = (server, reload) =>
  koaHotDevWebpack = require "koa-hot-dev-webpack"
  router = require("./router")(require("../src/server.coffee"))
  koa = new Koa()
  koa.use(require("koa-static")(path.resolve("./static")))
  koa.use koaHotDevWebpack(require("./webpack.config.coffee"))
  koa.use(router.middleware("koa"))
  server.on "request", koa.callback()
  server.listen(8080)
  koaHotDevWebpack.reload() if reload
  return =>
    koaHotDevWebpack.close()
    router.close()
