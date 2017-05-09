path = require "path"
fs = require "fs-extra"
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
      if v._watcher
        if v._watcher.close
          v._watcher.close()
        else
          for k2,v2 of v._watcher
            v2.close?()
  middleware: (name) -> require("./#{name}")(@)
  constructor: (o) ->
    @cwd = process.cwd()
    for k,v of defaults.global
      @[k] = v
    for k,v of o
      @[k] = v
    for k,v of defaults.options
      @[k] = Object.assign(v,@[k])
    return @
  resolvePath: ->
    path.resolve.apply null, [@cwd].concat(Array.prototype.slice.call(arguments))
  invalidate: ({url,route}) ->
    console.log "invalidate #{url}"
    if route?
      if route == @getBaseObj()
        for k,v of @routes
          @invalidate(url:k, route:v)
    else
      route = @routes[url]
    if route? 
      route.cached = {}
      if url and isString(cachepath = @getProp(route,"cache"))
        fs.remove @resolvePath(cachepath,url.replace(/\//g,"!"))
  getCacheName: ({url, locale}, str) -> [url.replace(/\//g,"!"),locale ?= "default",str].join("/")
  getCache: (o,name, dontRead) ->
    str = name || o.encoding || "doc"
    if (cache = o.route.cached)?
      if not o.locale or (cache = cache[o.locale])?
        return cache[str]
    else if not dontRead and o.url and isString(cachepath = @getProp(o.route,"cache"))
      filename = @resolvePath(cachepath,@getCacheName(o,str))
      if fs.existsSync(filename)
        console.log "reading from cache: #{filename}"
        value = fs.readFileSync(filename)
        @setCache(o, value, name, true)
        if @getProp(o.route,"watch")
          watchedPath = @resolvePath(cachepath,@getCacheName(o,"_watched"))
          if fs.existsSync(watchedPath)
            watchFiles = fs.readJsonSync(watchedPath)
            @watchFiles(o,watchFiles,o.route.watcher?)
        return value
    return null
  setCache: (o, value, name, dontWrite) ->
    if (cachepath = @getProp(o.route,"cache"))
      cache = o.route.cached ?= {}
      if o.locale?
        cache = cache[o.locale] ?= {}
      str = name || o.encoding || "doc"
      cache[str] = value
      if not dontWrite and o.url and isString(cachepath)
        filename = @resolvePath(cachepath,@getCacheName(o,str))
        fs.outputFileSync(filename,value)
        if (watcher = @getWatcher(o))
          watched = watcher.getWatched()
          tmp = []
          for k,v of watched
            for v2 in v
              tmp.push @resolvePath(k,v2)
          fs.outputJsonSync(@resolvePath(cachepath,@getCacheName(o,"_watched")),tmp)
    return value
  getBaseObj: -> @base
  getBase: (o) ->
    o.route = @getBaseObj()
    o.url = "__base"
    return Promise.resolve(cache) if (cache = @getCache(o, "doc", true))
    return @getHtml(o)
    .then (html) => @setCache(o, cheerio.load(html), "doc", true)
    .then ($) =>
      # webpack manifest inject
      if @webpackManifest
        try
          manifest = require(@resolvePath(@webpackManifest))
        catch
          console.log "webpack manifest not found"
        if manifest
          for k,v of manifest
            if k != v
              switch k.slice(-3)
                when ".js"
                  $("script[src='#{k}']").attr "src", v
                when "css"
                  $("link[href='#{k}']").attr "href", v
      if @webpackChunkManifest
        try
          manifest = require(@resolvePath(@webpackChunkManifest))
        catch
          console.log "webpack chunk manifest not found"
          manifest = null
        if manifest
          $("head").append "<script>window.webpackManifest=#{JSON.stringify(manifest)}</script>"

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
    filename = @resolvePath(folder, filepath)
    @watchFiles(o, filename)
    return filename
  getFolder: (o) ->
    folder = @getProp(o.route, "folder")
    return (o.locale and folder[o.locale]) or folder
  getWatcher: (o) ->
    w = o.route?._watcher
    w = w[o.locale] if w and o.locale
    return w
  setWatcher: (o, watcher) ->
    if (route = o.route)?
      if o.locale
        route._watcher ?= {}
        route._watcher[o.locale] = watcher
      else
        route._watcher = watcher
  watchFiles: (o, filenames, add) ->
    if @getProp(o.route,"cache") and @getProp(o.route,"watch")
      watcher = @getWatcher(o)
      if add
        if watcher
          console.log "watching #{filenames}"
          watcher.add(filenames) 
      else unless watcher
        console.log "watching #{filenames}"
        chokidar = libs.chokidar ?= require "chokidar"
        invalidate = @invalidate.bind(@,o)
        @setWatcher o, chokidar.watch(filenames, ignoreInitial: true)
        .on("add",invalidate).on("change",invalidate)
  toInjectID: (o) -> "injected"+o.url.toLowerCase().replace(/\//g,"-")
  getFile: (filepath) -> new Promise (resolve, reject) ->
    fs.readFile filepath, "utf8", (err, data) ->
      return reject(err) if err
      return resolve(data)
  processUrl: (o) ->
    o.url = o.url.replace(@root, "")
    o.route = @routes[o.url] 
    unless o.route
      o.url = @defaultUrl
      o.route = @routes[o.url]
    if o.route
      o.compress = zlib[o.encoding]
      return @processRoute(o)
    else
      return Promise.reject()
  processRoute: (o) ->
    return Promise.resolve(cache) if (cache = @getCache(o))
    return @getBase(locale: o.locale).then ($) =>
      @getHtml(o)
      .then (html) =>
        if html == false and o.url != @defaultUrl
          return @processUrl(Object.assign({}, o, {url: @defaultUrl}))
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
              resolve(@setCache(o,result))
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