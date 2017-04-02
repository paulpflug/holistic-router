calculate = require('etag')
isString = (str) -> typeof str == "string" || str instanceof String
module.exports = (router) ->
  return (next) ->
    encoding = @acceptsEncodings('gzip', 'deflate', 'identity')
    yield router.processUrl(@request.url,encoding).then (html, encoded) =>
        @response.status = 200
        #@response.lastModified = stats.mtime
        if isString(html)
          @response.length = html.length
        else
          @set("Content-Encoding",encoding)
          
        @response.type = "html"
        @response.etag ?= calculate html
        fresh = @request.fresh
        switch @request.method
          when 'HEAD'
            @response.status = fresh ? 304 : 200
            break
          when 'GET'
            if fresh
              @response.status = 304
            else
              @body = html
        return next
      .catch (e) => 
        console.log e
        @throw(403)
        