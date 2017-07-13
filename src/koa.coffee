isString = (str) => typeof str == "string" || str instanceof String
module.exports = (router) => (ctx, next) =>
  encoding = ctx.acceptsEncodings('gzip', 'deflate', 'identity')
  router.processUrl 
    url: ctx.path
    encoding: encoding
    locale: ctx.getLocale?()
  .then (html, encoded) =>
    if isString(html)
      ctx.response.length = html.length
    else
      ctx.set("Content-Encoding",encoding)
    ctx.response.type = "html"
    ctx.body = html
  .catch (e) => 
    console.log e
    ctx.throw(403)
        