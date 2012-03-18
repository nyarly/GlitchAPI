require 'sinatra'
require 'oauth2'

require 'glitch-api'

base_options = {:redirect_uri => "http://127.0.0.1:9393/callback"}

get "/" do
  return <<-H
  <p>We're going to try to set up an OAuth2 token for Glitch for the <b>Plato</b> app.</p>
  <p>Click: <a href="#{GlitchAPI::client.web_server.authorize_url(base_options.merge(:scope => "write"))}">here to start the process</a></p>
  H
end

get "/callback" do
  token = GlitchAPI::client.web_server.get_access_token(params[:code], base_options)
  player_data = MultiJson.decode(token.get("/simple/players.info"))
  File::open(player_data["player_name"] + ".oauth2", "w") do |file|
    file.write token.token
  end

  return "Stored token for #{player_data["player_name"]}<br /><img src='#{player_data["avatar_url"]}' />"
end
