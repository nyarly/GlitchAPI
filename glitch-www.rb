require 'mechanize'

module GlitchWWW
  class HTTP
    Host = "http://www.glitch.com"

    def initialize(character)
      @character = character
      @credentials = YAML::load(File::read(@character + ".web_creds"))
      @http = Mechanize.new do |agent|

      end
      load_cookies
      ensure_login
    end

    attr_reader :http

    def ensure_login
      http.get(Host)
      if /Secret Code\?/ =~ http.page.title
        puts "Secret code..."
        form = http.page.form_with(:action => "/beta/")
        form['invite'] = @credentials["beta_secret"]
        http.submit(form)
        store_cookies
      end
      if /Log In/ =~ http.page.title
        puts "Logging in..."
        form = http.page.form_with(:action => "/login/")
        form['e'] = @credentials["email"]
        form['p'] = @credentials["password"]
        http.submit(form)
        store_cookies
      end
      unless /Home/ =~ http.page.title
        raise "Not logged in!"
      end
    end

    def store_cookies
      http.cookie_jar.save_as(@character + ".cookies")
    end

    def load_cookies
      http.cookie_jar.load(@character + ".cookies") rescue nil
    end
  end

  class Auction < HTTP
    def buy(item_path)
      http.get(item_path)
      http.click("Buy")
      form = http.page.forms.first
      if form.nil?
        raise "Missed auction"
      end
      http.page.root.search('input[@type="hidden"]').each do |input|
        form.add_field!(input["name"], input["value"])
      end
      form.click_button
      http.page.root.search('p[@class="alert notice"]').each do |para|
        puts para.text
      end
    end
  end
end
