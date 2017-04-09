path = require "path"
fs = require "fs"
cheerio = require "cheerio"
zlib = require "zlib"
consolidate = require "consolidate"
libs = {}
isString = (str) -> typeof str == "string" || str instanceof String

defaults = require "./defaults"

module.exports = class Router
  getLib: ({route}) ->
    type = @getType(route)
    return libs[type] ?= require type
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

  invalidate: ({url,route}) ->
    console.log "invalidate #{url}"
    if route?
      if route == @getBaseObj()
        for k,v of @routes
          @invalidate(url:k, route:v)
    else
      route = @routes[url] 
    route?.cached = {}
  getCache: ({route,locale,encoding},name) ->
    if (cache = route.cached)?
      if not locale or (cache = cache[locale])?
        str = name || encoding || "doc"
        return cache[str]
    return null
  setCache: ({route,locale,encoding},value, name) ->
    if @getProp(route,"cache")
      cache = route.cached ?= {}
      if locale?
        cache = cache[locale] ?= {}
      str = name || encoding || "doc"
      cache[str] = value
    return value
  getBaseObj: -> @base
  getBase: (o) ->
    o.route = @getBaseObj()
    return Promise.resolve(cache) if (cache = @getCache(o, "doc"))
    return @getHtml(o)
    .then (html) => @setCache(o, cheerio.load(html), "doc")
    .then ($) =>
      injectors = []
      firstScript = $("body>script")
      unless firstScript.length > 0
        body = $("body")
        firstScript = null
      for k,v of @routes
        toInject = @getToInject(obj = route: v, url: k, locale: o.locale)
        if toInject?
          inject = (toInject, html) ->
            if firstScript
              firstScript.before toInject(html)
            else 
              body.append toInject(html)
          injectors.push @getHtml(obj).then inject.bind(@,toInject)
      return Promise.all(injectors).then -> return $
  getType: (route) -> route._type ?= (route.type || @type)
  getOptions: (route) -> @[@getType(route)+"Options"] || {}
  getProp: (route, prop) ->
    return route[prop] if route[prop]?
    if (options = @getOptions(route))? and options[prop]?
      return options[prop] 
    return @[prop]
  getMergedOptions: (route) -> 
    route._mergedOptions ?= Object.assign({}, @getOptions(route), route)
  getHtml: (o) ->
    return Promise.resolve(cache) if (cache = @getCache(o, "html"))
    type = @getType(o.route)
    prop = type+"ToHtml"
    unless @[prop]?
      if consolidate[type]
        getHtml = new Promise (resolve, reject) =>
          consolidate[type] @getFilepath(o), {cache: false, routes: @routes, locale:o.locale}, (err, html) ->
            return reject(err) if err
            resolve(html)
      else
        return Promise.resolve(false)
    else
      getHtml = @[prop](o)
    return getHtml.then (html) => @setCache(o, html, "html")
  getToInject: (o) ->
    return null unless @getProp(o.route,"inject")
    prop = @getType(o.route)+"Inject"
    prop = "htmlInject" unless @[prop]?
    return @[prop].bind(@,@toInjectID(o))
  getFilepath: (o) ->
    filepath = o.route.file
    filepath ?= "."+o.url
    if (basename = path.basename(filepath)) == "" or basename == "."
      filepath += @entry
    ext = @getProp(o.route, "ext")
    unless ext?
      ext ?= ".#{@getType(o.route)}"
    if ext and path.extname(filepath) == ""
      filepath += ext
    folder = @getFolder(o)
    filename = path.resolve(folder, filepath)
    @watchFiles(o, filename)
    return filename
  getFolder: (o) ->
    folder = @getProp(o.route, "folder")
    return (o.locale and folder[o.locale]) or folder

  watchFiles: (o, filenames, add) ->
    if @getProp(o.route,"cache") and @getProp(o.route,"watch")
      watcher = o.route.watcher
      if add
        if watcher
          console.log "watching #{filenames}"
          watcher.add(filenames) 
      else unless watcher
        console.log "watching #{filenames}"
        chokidar = libs.chokidar ?= require "chokidar"
        invalidate = @invalidate.bind(@,o)
        o.route.watcher = chokidar.watch(filenames, ignoreInitial: true)
        .on("add",invalidate).on("change",invalidate)
  toInjectID: (o) -> "injected"+o.url.toLowerCase().replace(/\//g,"-")
  getFile: (filepath) -> new Promise (resolve, reject) ->
    fs.readFile filepath, "utf8", (err, data) ->
      return reject(err) if err
      return resolve(data)
  processUrl: (o) ->
    o.url = o.url.replace(@root, "")
    o.route = @routes[o.url] || @routes[@defaultUrl]
    o.compress = zlib[o.encoding]
    @processRoute(o)
  processRoute: (o) ->
    return Promise.resolve(cache) if (cache = @getCache(o))
    return @getBase(locale: o.locale).then ($) =>
      @getHtml(o)
      .then (html) =>
        if html == false and o.url != @defaultUrl
          return @processUrl(Object.assign({url: @defaultUrl}, o))
        if html != false
          $(@view).html(html).attr("route",o.url)
          toInject = @getToInject(o)
          if toInject?
            $("#"+@toInjectID(o)).replaceWith(toInject(html))
        html = $.html()
        @setCache(o,html,"doc")
        if o.compress?
          return new Promise (resolve,reject) =>
            o.compress new Buffer(html, "utf8"),level:9, (err, result) =>
              return reject(err) if err
              resolve(@setCache(o,html))
        return Promise.resolve(html)
  htmlToHtml: (o) ->
    @getFile(@getFilepath(o))
  pugToHtml: (o) ->
    pug = @getLib(o)
    filename = @getFilepath(o)
    opts = {filename: filename,cache: false}
    @getFile(filename).then (content) =>
      {dependencies} = pug.compileClientWithDependenciesTracked(content,opts)
      @watchFiles(o, dependencies, true)
      fn = pug.compile(content,opts)
      return fn(routes:@routes, locale: o.locale) 
  markedToHtml: (o) ->
    marked = @getLib(o)
    @getFile(@getFilepath(o)).then (content) => new @Promise (resolve, reject) =>
      marked content, @getMergedOptions(o.route), (err, html) ->
        return reject(err) if err
        return resolve(html)
  htmlInject: (id, html) -> """<script type=x-template id=#{id}>#{html}</script>"""