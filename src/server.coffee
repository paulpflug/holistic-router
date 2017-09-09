path = require "path"
fs = require "fs-extra"
cheerio = require "cheerio"
zlib = require "zlib"
consolidate = require "consolidate"

libs = {}
isString = (str) => typeof str == "string" || str instanceof String
isFunction = (fn) => typeof fn == "function"


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
    if isString(@cache)
      @_watchedPath = @resolvePath(@cache, "_watched")
      try
        @_watched = fs.readJsonSync @_watchedPath
        for k,v of @_watched
          if k == "__base"
            route = @getBaseObj()
          else
            route = @routes[k]
          @watchFiles({url: k, route:route, locale:v.locale},v.files)
      catch 
        @_watched = {}
    return @
  resolvePath: ->
    path.resolve.apply null, [@cwd].concat(Array.prototype.slice.call(arguments))
  invalidate: (o, _docOnly) ->
    url = o.url
    route = o.route || @routes[url]
    if (cache = route?.cached)? 
      if o.locale
        cache = cache[o.locale]
        return unless cache?
      unless _docOnly
        console.log "invalidate #{url}"
        @invalidate({url:"__base", route:@getBaseObj(), locale:o.locale}, true)
        for k,v of @routes
          if k != url
            @invalidate({url:k, route:v, locale:o.locale}, true)
 
      for k,v of cache
        if not _docOnly or k != "html"
          delete cache[k]
      if isString(cachepath = @getProp(route,"cache"))
        files = await fs.readdir(abspath = @resolvePath(cachepath, @getCacheName(o,"")))
        for file in files
          if not _docOnly or (file != "html")
            fs.remove path.resolve(abspath, file)

  getCacheName: ({url, locale}, str) -> [url.replace(/\//g,"!"),locale ?= "default",str].join("/")
  getCache: (o,name, dontRead) ->
    str = name || o.encoding || "doc"
    if (cache = o.route.cached)?
      if not o.locale or (cache = cache[o.locale])?
        return cache[str]
    else if not dontRead and o.url and isString(cachepath = @getProp(o.route,"cache"))
      filename = @resolvePath(cachepath,@getCacheName(o,str))
      if await fs.exists(filename)
        console.log "reading from cache: #{filename}"
        value = await fs.readFile(filename)
        await @setCache(o, value, name, true)
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
        await fs.outputFile(filename,value)
        if (watcher = @getWatcher(o))
          watched = watcher.getWatched()
          tmp = []
          for k,v of watched
            for v2 in v
              tmp.push @resolvePath(k,v2)
          @_watched[o.url] = 
            files: tmp
            locale: o.locale
          await fs.outputJson(@_watchedPath,@_watched)

    return value
  getBaseObj: -> @base
  getBase: (o) ->
    o.route = @getBaseObj()
    o.url = "__base"
    return cache if (cache = await @getCache(o, "doc", true))
    html = await @getHtml(o)
    $ = await @setCache(o, cheerio.load(html), "doc", true)
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
    if (ccss = @criticalcss)
      try
        critical = await fs.readFile path.resolve(ccss.save, "_critical.css"), "utf8"
      catch e
        console.log e
      if critical?
        $(ccss.stylesheets).remove()
        unless ccss.hash? and ccss.hash == false
          hashed = await fs.readFile path.resolve(ccss.save, "_uncritical"), "utf8"
        else
          hashed = "_uncritical.css"
        uncritical = path.join(ccss.path or "",hashed)
        $("head").append "<style type='text/css'>#{critical}</style><link rel='stylesheet' href='#{uncritical}'></style>"
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
    return Promise.all(injectors).then => return $
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
    return cache if (cache = await @getCache(o, "html"))
    type = @getType(o.route)
    prop = type+"ToHtml"
    unless @[prop]?
      if consolidate[type]
        html = await consolidate[type] @getFilepath(o), {cache: false, routes: @routes, locale:o.locale}
      else
        return false
    else
      html = await @[prop](o)
    if (minifyOpts = @getProp(o.route, "minify"))?
      if isFunction(minifyOpts)
        html = await minifyOpts(html)
      else
        {minify} = require "html-minifier"
        html = minify html, minifyOpts
    @setCache(o, html, "html")
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
        invalidate = @invalidate.bind(@,o,false)
        @setWatcher o, chokidar.watch(filenames, ignoreInitial: true)
        .on("add",invalidate).on("change",invalidate)
  toInjectID: (o) -> "injected"+o.url.toLowerCase().replace(/\//g,"-")
  getFile: (filepath) -> fs.readFile filepath, "utf8"
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
    return cache if (cache = await @getCache(o))
    $ = await @getBase(locale: o.locale)
    html = await @getHtml(o)
    if html == false and o.url != @defaultUrl
      return @processUrl(Object.assign({}, o, {url: @defaultUrl}))
    if html != false
      $(@view).html(html).attr("route",o.url)
      toInject = @getToInject(o)
      if toInject?
        $("#"+@toInjectID(o)).replaceWith(toInject(html))
    html = $.html()
    await @setCache(o,html,"doc")
    if o.compress?
      return new Promise (resolve,reject) =>
        o.compress new Buffer(html, "utf8"),level:9, (err, result) =>
          return reject(err) if err
          resolve(await @setCache(o,result))
    return html
  htmlToHtml: (o) -> @getFile(@getFilepath(o))
  pugToHtml: (o) ->
    pug = @getLib(o)
    filename = @getFilepath(o)
    opts = {filename: filename,cache: false}
    content = await @getFile(filename)
    {dependencies} = pug.compileClientWithDependenciesTracked(content,opts)
    @watchFiles(o, dependencies, true)
    fn = pug.compile(content,opts)
    fn(routes:@routes, locale: o.locale) 
  markedToHtml: (o) ->
    marked = @getLib(o)
    content = await @getFile(@getFilepath(o))
    return new @Promise (resolve, reject) =>
      marked content, @getMergedOptions(o.route), (err, html) =>
        return reject(err) if err
        return resolve(html)
  htmlInject: (id, html) -> """<script type=x-template id=#{id}>#{html}</script>"""