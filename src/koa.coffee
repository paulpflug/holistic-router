isString = (str) -> typeof str == "string" || str instanceof String
module.exports = (router) -> (ctx) ->
    encoding = ctx.acceptsEncodings('gzip', 'deflate', 'identity')
    return router.processUrl(ctx.request.url,encoding).then (html, encoded) =>
        if isString(html)
          ctx.response.length = html.length
        else
          ctx.set("Content-Encoding",encoding)
        ctx.response.type = "html"
        ctx.body = html
      .catch (e) => 
        console.log e
        ctx.throw(403)
        