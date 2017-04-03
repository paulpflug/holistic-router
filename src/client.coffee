defaults = require "./defaults"
isString = (s) -> typeof s == "string" || s instanceof String 
module.exports = class Router
  constructor: (o) ->
    for k,v of defaults.global
      @[k] = v
    for k,v of o
      @[k] = v
    for k,v of defaults.options
      @[k] = Object.assign(v,@[k])
    @viewEl = document.querySelector(@view)
    @viewComment = document.createComment("#view")
    @viewParent = @viewEl.parentElement
    oldRoute = @viewEl.getAttribute("route")
    @fragToRoute(oldRoute)._el = @_currentEl = @createContainer()
    if oldRoute != (current = @getFragment())
      @open(current)
    else
      @_current = current
      @setActive()
    @viewEl.removeAttribute("route")
    listener = ->
      if @_current != (tmp = @getFragment())
        @open(tmp, true)
    if @mode != "history"
      setInterval(listener.bind(@), 66)
    else
      window.addEventListener "popstate", listener.bind(@)
    document.addEventListener "click", @onClick.bind(@)
    return @
  onClick: (e) ->
    el = e.target
    while el? and not el.pathname?
      el = el.parentElement    
    if (path = el?.pathname) and path == el.getAttribute("href")
      e.preventDefault()
      @open(path)
  getProp: (route, prop, options) ->
    return route[prop] if route[prop]?
    if options? and (options = @[options+"Options"])? and options[prop]?
      return options[prop] 
    return @[prop]

  urlToInjectID: (url) -> "injected"+url.toLowerCase().replace(/\//g,"-")

  getFragment: ->
    if @mode == "history"
      fragment = decodeURI(location.pathname)
      if @root
        fragment = fragment.replace(@root,"")
      return fragment
    else
      match = window.location.href.match(/#(.*)$/)
      if match then return match[1] else return @defaultUrl
  fragToRoute: (frag) -> @routes[frag]
  loadView: (el) ->
    if el != @_currentEl
      @viewParent.replaceChild(@viewComment,@viewEl)
      while child = @viewEl.firstChild
        @_currentEl.appendChild(child)
      while child = el.firstChild
        @viewEl.appendChild(child)
      @_currentEl = el
      @viewParent.replaceChild(@viewEl,@viewComment)
  createContainer: (content) -> 
    el = document.createElement "div"
    if isString(content)
      el.innerHTML = content
    else if Array.isArray(content)
      for ele in content
        el.appendChild(ele)
    return el
  route: (frag, route) ->
    frag ?= @getFragment()
    route ?= @fragToRoute(frag)
    if route
      @_current = frag
      @loadView(route._el) if route._el?
      type = @getProp(route,"type")
      if not route.el?
        route.el = "#"+@urlToInjectID(frag)
      if route.el
        el = document.querySelector(route.el)
        if el?
          el = @createContainer(el.innerHTML) if el.children.length == 0
          @loadView(route._el = el)
      if not route._el and (gen = @getProp(route,"gen",type))?
        @loadView(route._el = @createContainer(gen(frag,route)))
      return @getProp(route,"cb")?()
  setActive: (path = @_current, oldPath) ->
    if @active
      if oldPath
        el = document.querySelector("[route-active='#{oldPath}']")
        if el?
          regex = new RegExp("(?:^|\\s)#{@active}(?!\\S)","g")
          el.className = el.className.replace(regex, "")
      el = document.querySelector("[route-active='#{path}']")
      el?.className += " #{@active}"
  open: (path, isBack) ->
    if path != (oldPath = @_current) and (route = @fragToRoute(path))?
      @Promise.resolve()
      .then => @beforeAll?(path, @_current)
      .then => route.before?(path, @_current)
      .then @route(path, route)
      .then =>
        @_lastPath = oldPath
        unless isBack
          if @mode == "history"
            history.pushState(null, null, @root + path)
          else
            window.location.href = window.location.href.replace(/#(.*)$/, '') + '#' + path;
      .then @setActive.bind(@, path, oldPath)
      .then => route.after?(path)
      .then => @afterAll?(path)
      .catch (e) => 
        console.log e
        @open @defaultUrl
  back: ->
    if @_lastPath
      @open(@_lastPath,histMode = @mode == "history")
      if histMode
        history.replaceState(null, null, @root + @_lastPath)