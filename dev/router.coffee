
module.exports = (Router) -> new Router
  #mode:"hash"
  base:
    file: "./index"
    folder: "./dev"
  routes:
    "/": {}
    "/html": {}
    "/pug": {
      type: "pug"
    }
    "/ceri":
      type: "ceri"
  folder: "./dev/app"
  cache: "./dev/cache"