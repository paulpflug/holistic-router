defaults = require "./defaults"
isString = (s) -> typeof s == "string" || s instanceof String 
body = document.body
docEl = document.documentElement
module.exports = class Router
  getScrollPos: ->
    top: window.pageYOffset || docEl.scrollTop || body.scrollTop
    left: window.pageXOffset || docEl.scrollLeft || body.scrollLeft
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
    @_currentRoute = @fragToRoute(oldRoute)
    @_currentRoute._el = @createContainer()
    if oldRoute != (current = @getFragment())
      @open(current)
    else
      @_current = current
      setTimeout @setActive.bind(@), 66
    @viewEl.removeAttribute("route")
    listener = (e) ->
      if @_current != (tmp = @getFragment())
        @open(tmp, true)
      return null
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
  loadView: (route) ->
    return false unless route._el?
    if route != @_currentRoute
      viewEl = @viewEl
      @viewParent.replaceChild(@viewComment,viewEl)
      el = @_currentRoute._el
      while child = viewEl.firstChild
        el.appendChild(child)
      routeEl = route._el
      while child = routeEl.firstChild
        viewEl.appendChild(child)
      @_currentRoute = route
      @viewParent.replaceChild(viewEl,@viewComment)
    return true
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
      unless @loadView(route)
        route.el ?= "#"+@urlToInjectID(frag)
        if route.el
          el = document.querySelector(route.el)
          if el?
            route._el = @createContainer(el.innerHTML) if el.children.length == 0
        unless @loadView(route)
          type = @getProp(route,"type")
          if not route._el and (gen = @getProp(route,"gen",type))?
            return @Promise.resolve(gen(frag, route))
              .then (content) =>
                route._el = @createContainer(content)
                @loadView(route)
                return @getProp(route,"cb")?.call(@)
      return @getProp(route,"cb")?.call(@)
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
    if @mode == "history" and @root
      path = path.replace(@root,"")
    start = @Promise.resolve()
    if path != (oldPath = @_current) and (route = @fragToRoute(path))?
      return start
        .then => @beforeAll?.call(@, path, @_current)
        .then => route.before?.call(@, path, @_current)
        .then =>
          @_currentRoute._scroll ?= []
          @_currentRoute._scroll.push @getScrollPos()
          @route(path, route)
        .then =>
          @_lastPath = oldPath
          unless isBack
            if @mode == "history"
              history.pushState(null, null, @root + path)
            else
              window.location.href = window.location.href.replace(/#(.*)$/, '') + '#' + path;
          if (isBack and s = @_currentRoute._scroll?.pop())?
            window.scrollTo(s.left,s.top)
          else
            window.scrollTo(0,0)
          setTimeout (=> @setActive(path, oldPath)), 0
          route.after?.call(@, path)
        .then => @afterAll?.call(@, path)
        .catch (e) =>
          console.log e
          @open @defaultUrl
    return start
  back: ->
    if @_lastPath
      @open(@_lastPath,histMode = @mode == "history")
      .then =>
        if histMode
          history.replaceState(null, null, @root + @_current)