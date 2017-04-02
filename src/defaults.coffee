module.exports =
  options:
    htmlOptions: inject: true
  global:
    Promise: Promise
    root: ""
    defaultUrl: "/"
    entry: "index"
    type: "html"
    view: "#view"
    active: "active"
    folder: "."
    cache: true
    watch: true
    gzip: true
    inject: false
    mode: if history?.pushState? then "history" else "hash"