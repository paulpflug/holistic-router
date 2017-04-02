module.exports =
  entry: "./dev/client.coffee"
  devtool: "sourcemap"
  output:
    publicPath: ""
    filename: "[name].js"
  module:
    rules: [
      { test: /\.coffee$/, use: "coffee-loader"}
    ]
  resolve:
    extensions: [".js", ".json", ".coffee"]
