calculate = require('etag')
isString = (str) -> typeof str == "string" || str instanceof String
module.exports = (router) -> (ctx) ->
    encoding = ctx.acceptsEncodings('gzip', 'deflate', 'identity')
    return router.processUrl(ctx.request.url,encoding).then (html, encoded) =>
        ctx.response.status = 200
        #ctx.response.lastModified = stats.mtime
        if isString(html)
          ctx.response.length = html.length
        else
          ctx.set("Content-Encoding",encoding)
          
        ctx.response.type = "html"
        ctx.response.etag ?= calculate html
        fresh = ctx.request.fresh
        switch ctx.request.method
          when 'HEAD'
            ctx.response.status = fresh ? 304 : 200
            break
          when 'GET'
            if fresh
              ctx.response.status = 304
            else
              ctx.body = html
      .catch (e) => 
        console.log e
        ctx.throw(403)
        