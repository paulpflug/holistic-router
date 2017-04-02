path = require "path"
fs = require "fs"
cheerio = require "cheerio"
zlib = require "zlib"
consolidate = require "consolidate"
libs = {}
isString = (str) -> typeof str == "string" || str instanceof String

if path.extname(__filename) == ".coffee"
  require "coffee-script/register"

defaults = require "./defaults"

module.exports = class Router
  close: ->
    for k,v of @routes
      v.watcher?.close()
  middleware: (name) -> require("./#{name}")(@)
  constructor: (o) ->
    for k,v of defaults.global
      @[k] = v
    for k,v of o
      @[k] = v
    for k,v of defaults.options
      @[k] = Object.assign(v,@[k])
    return @

  invalidate: (url,route) ->
    console.log "invalidate #{url}"
    if route? and route == @getBaseObj()
      for k,v of @routes
        @invalidate(k,v)
    else
      route ?= @routes[url] 
      route.cached = {}
  getBaseObj: -> @base
  getBase: ->
    route = @getBaseObj()
    route.cached ?= {}
    return Promise.resolve(route.cached.doc) if route.cached.doc
    return @getHtml(route)
    .then (html) -> return route.cached.doc = cheerio.load(html)
    .then ($) =>
      injectors = []
      body = $("body")
      for k,v of @routes
        toInject = @getToInject(v,k)
        if toInject?
          inject = (toInject, html) -> body.append toInject(html)
          injectors.push @getHtml(v,k).then inject.bind(@,toInject)
      return Promise.all(injectors).then -> return $
  getProp: (route, prop, options) ->
    return route[prop] if route[prop]?
    if options? and (options = @[options+"Options"])? and options[prop]?
      return options[prop] 
    return @[prop]

  getHtml: (route, url) ->
    route.cached ?= {}
    return Promise.resolve(route.cached.html) if route.cached.html
    type = @getProp(route,"type")
    if consolidate[type]
      getHtml = new Promise (resolve, reject) =>
        consolidate[type] @getFilepath(route,url,type), {cache: false, routes: @routes}, (err, html) ->
          return reject(err) if err
          resolve(html)
    else
      prop = type+"ToHtml"
      return Promise.resolve(false) unless @[prop]?
      getHtml = @[prop](route, url)
    return getHtml.then (html) =>
        if @getProp(route,"cache")
          route.cached.html = html
        return html
  getToInject: (route, url) ->
    type = @getProp(route,"type")
    type = "html" if consolidate[type]
    return null unless @getProp(route,"inject",type)
    prop = type+"Inject"
    return null unless @[prop]?
    return @[prop].bind(@,@urlToInjectID(url))
  getFilepath: (route, url, type) ->
    filepath = route.file
    filepath ?= "."+url
    if (basename = path.basename(filepath)) == "" or basename == "."
      filepath += @entry
    ext = @getProp(route, "ext", type)
    ext ?= ".#{type}"
    if ext and path.extname(filepath) == ""
      filepath += ext
    folder = @getProp(route, "folder", type)
    filename = path.resolve(folder, filepath)
    if not route.watcher and @getProp(route,"cache") and @getProp(route,"watch")
      chokidar = libs.chokidar ?= require "chokidar"
      invalidate = @invalidate.bind(@,url,route)
      console.log "watching #{filename}"
      route.watcher = chokidar.watch(filename, ignoreInitial: true)
      .on("add",invalidate).on("change",invalidate)
    return filename
  urlToInjectID: (url) -> "injected"+url.toLowerCase().replace(/\//g,"-")
  getFile: (filepath) -> new Promise (resolve, reject) ->
    fs.readFile filepath, "utf8", (err, data) ->
      return reject(err) if err
      return resolve(data)
  processUrl: (url, encoding) ->
    url = url.replace(@root, "")
    url = @defaultUrl unless @routes[url]
    @processRoute(@routes[url], url, encoding)
  processRoute: (route, url, encoding) ->
    route.cached ?= {}
    if encoding? and (compress = zlib[encoding])? and (cached = route.cached[encoding])?
      return Promise.resolve(cached)
    else if (cached = route.cached.doc)?
      return Promise.resolve(cached) 
    return Promise.all([@getBase(),@getHtml(route, url)])
    .then ([$,html]) =>
      if html == false and url != @defaultUrl
        return @processUrl(@defaultUrl, encoding)
      if html != false
        $(@view).html(html).attr("route",url)
        toInject = @getToInject(route,url)
        if toInject?
          $("#"+@urlToInjectID(url)).replaceWith(toInject(html))
      html = $.html()
      if @getProp(route,"cache")
        route.cached.doc = html
        if compress?
          return new Promise (resolve,reject) ->
            compress new Buffer(html, "utf8"),level:9, (err, result) ->
              return reject(err) if err
              resolve(route.cached[encoding] = result)
      return Promise.resolve(html)
  htmlToHtml: (route, url) ->
    @getFile(@getFilepath(route,url,"html"))
  htmlInject: (id, html) -> """<script type=x-template id=#{id}>#{html}</script>"""