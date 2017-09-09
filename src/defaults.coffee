module.exports =
  options:
    base:
      _isBase: true
    htmlOptions: inject: true
    pugOptions: inject: true
    markedOptions:
      inject: true
      ext: ".md"
  global:
    Promise: Promise
    root: ""
    defaultUrl: "/"
    entry: "index"
    type: "html"
    view: "#view"
    active: "active"
    folder: "."
    cache: "./.holistic-router-cache"
    watch: true
    inject: false
    mode: if history?.pushState? then "history" else "hash"