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
// you need a way to resolve a require call on client-side
// for example with webpack
Router = require("holistic-router")
router = new Router(options)

// server-side only
// KOA
koa.use(router.middleware("koa"))
```

### Example
```sh
# Project layout
index.html # base
views/
views/index.html
views/1.html
```
```js
// server-side
Router = require("holistic-router")
router = new Router({
  base: {
    folder: ".",
    file: "index.html"
  },
  folder: "views",
  routes: {
    "/": {},
    "/1": {}
  }
})
```
```html
<!-- index.html -->
<!DOCTYPE html>
<html>
  <head></head>
  <body>
    <div id=view></div>
  </body>
</html>
<!-- views/index.html -->
<p>Hello World</p>
<!-- views/1.html -->
<p>Hello One</p>
```
Will serve the following file under "/":
```html
<!DOCTYPE html>
<html>
  <head></head>
  <body>
    <div id="view" route="/">
      <p>Hello World</p>
    </div>
    <script type="x-template" id="injected-">
      <p>Hello World</p>
    </script>
    <script type="x-template" id="injected-1">
      <p>Hello One</p>
    </script>
  </body>
</html>
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
beforeAll: (path, oldPath) => // throw error to reject route change
afterAll: (path) =>

// server-side only
entry: "index" // add this when a folder is opened
folder: "." // base folder for all files; relative to CWD
cache: true // should cache results. Can be string to folder to use fs cache
watch: true // watch files for changes and invalidate cache
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
    // filename relative to folder, but can also contain a subfolder
    // defaults to route
    // when no basename is given e.g. "someFolder/"
    // the string of the "entry" options will be appended
    file: "someFile" 
    folder: "./someFolder/" // folder relative to CWD, defaults to "."
    ext: ".pug" // defaults to "."+type
    // selector string for template element which contains the view
    // when inject == false
    el: "#templateElement" 
    gen: (url, route) => // generator function for view (only client side)
      // should return html string or array of elements

    // callbacks on route changing
    before: (path, oldPath) => // throw error to reject route change
    after: (path) =>
  }
```
### Routing

You can call `router.open("/")` to route. 

Furthermore all click events will be intercepted and all relative href will be processed by the client side router.

If you want to enforce a server-side routing use a full path instead of a relative as href e.g. `http://localhost/` vs `/`.

### Creating a navigation
Use a template engine of your choice.
The routes object will be injected:
```pug
//- pug
ul
  each route,path in routes
    li(route-active=path)
      a(href=path)= path
```

### Locales

`holistic-router` is compatible to [`getLocale`](https://github.com/paulpflug/getLocale):
```js
GetLocale = require("get-locale")
getLocale = new GetLocale({
  supported: ["de","en"],
  priority: ["query","header"]
})
  
Router = require("holistic-router")
router = new Router({
  base: {
    file: "./index",
    folder: "."
    }, 
  routes:{
    "/": {}
    },
  folder: {
    de: "./de",
    en: "./en"
    }
})
koa.use(getLocale.middleware("koa"))
koa.use(router.middleware("koa"))
```
the `locale` value will also get injected into your templates
```pug
//- pug
html(lang=locale)
```


## License
Copyright (c) 2017 Paul Pflugradt
Licensed under the MIT license.
