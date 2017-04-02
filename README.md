# holistic-router

versatile server and client router for small single page sites.

- client side routing (history and hash mode)
- fallback to server side routing for all html/template content
- supports [consolidate](https://github.com/tj/consolidate.js/)
- simple caching / watching of files
- injects views into base html

### Install

```sh
npm install --save holistic-router
```

### Usage

```js
// server AND client-side
Router = require("holistic-router")
router = new Router(options)

// server-side only
// KOA
koa.use(router.middleware("koa"))
```

### Options
```js
// both
defaultUrl: "/" // fallback on 404
type: "html" // default type
view: "#view" // query to get view container
inject: false // inject view into base html

// client-side only
Promise: Promise // Promise lib to use
root: "" // in history mode: string will be removed from path
mode: if history?.pushState? then "history" else "hash" 
active: "active" // class for 'route-active' element if route is active
// callbacks on route changing
beforeAll: (path, oldPath) => // must return Promise
afterAll: (path) =>

// server-side only
entry: "index" // add this when a folder is opened
folder: "." // base folder for all files relative to CWD
cache: true // should cache results
watch: true // watch files for changes
gzip: true // only with cache

// type-specific options
// will overwrite global options
htmlOptions:
  inject: true

// like a normal route object
// html to inject views, should have the view element
base: {
  type: "html"
  folder: "."
  file: "base.html"
}

routes:
  "/": {
    // route-specific options
    // will overwrite type-specific and global ones
    type: "pug"
    // filename relative to folder
    // would default to index as route points to a folder
    file: "someFile" 
    folder: "./someFolder/" // folder relative to CWD, defaults to "."
    ext: ".pug" // defaults to "."+type
    // selector string for template element which contains the view
    // when inject == false
    el: "#templateElement" 
    gen: (url, route) => // generator function for view

    // callbacks on route changing
    before: (path, oldPath) => // throw error or reject to abort changing
    after: (path, oldPath) =>
  }
```
### Routing

You can call `router.open("/")` to route. Furthermore all click events will be intercepted and when a local href is found e.g. `/`, processed by the router.
If you want to enforce a server-side routing use a full path as href instead e.g. `http://localhost/".

### Creating a navigation
Use a template engine of your choice.
The routes object will be injected into locals:
```pug
//pug
ul
  each route,path in routes
    li(route-active=path)
      a(href=path)= path
```


## License
Copyright (c) 2017 Paul Pflugradt
Licensed under the MIT license.
