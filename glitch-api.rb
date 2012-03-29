require 'oauth2'
require 'typhoeus'

module GlitchAPI
  class Error < ::Exception; end
  class Basic
    def initialize(character_name)
      @token_string = File::read(character_name + ".oauth2")
      @character = character_name
      #@token = OAuth2::AccessToken.new(client, token_string)

      @hydra = Typhoeus::Hydra.new
      @hydra.cache_setter do |request|
        write_cache(request.cache_key, request.response)
      end

      @hydra.cache_getter do |request|
        begin
          read_cache(request.cache_key, request.cache_timeout)
        rescue Object => ex
          nil
        end
      end
    end

    require 'fileutils'

    def read_cache(path, age)
      path = File::expand_path(path, "cached")
      unless age && age > 0 && (right_now - File::mtime(path)) < age
        raise Errno::ENOENT
      end
      return YAML::load(File::read(path))
    end

    def write_cache(path, data)
      path = File::expand_path(path, "cached")
      FileUtils::mkdir_p(File::dirname(path))
      data.request = nil
      File::open(path, "w") do |file|
        file.write YAML::dump(data)
      end
      data
    end

    #Simpler than a proper refactoring
    def file_cached(path, seconds=0)
      old_cache_life = Thread.current[:cache_life]
      Thread.current[:cache_life] = seconds
      yield
    ensure
      Thread.current[:cache_life] = old_cache_life
    end

    def make_request(path, params={})
      params.merge!('oauth_token' => @token_string)
      headers = { 'Authorization' => "OAuth #{@token_string}" }
      req = Typhoeus::Request.new("http://api.glitch.com/simple/#{path}",
                                  :params => params,
                                    :headers => headers,
                                    :cache_timeout => Thread.current[:cache_life]
                                 )
      req.on_complete do |response|
        begin
          parsed = MultiJson::decode(response.body)
        rescue SystemStackError
          puts "Stack too deep while decoding:"
          puts response.body
          raise
        end
        yield(parsed, response) if block_given?
        parsed
      end
      @hydra.queue req
      return req
    end

    def get(path, params={})
      req = make_request(path, params)
      @hydra.run
      result =  req.handled_response

      unless result["ok"] == 1
        raise Error, "#{result["error"]} for #{path}?#{params.inspect}"
      end
      return result
    end

    def each_page(path, params={}, per_page=200, &block)
      make_request(path, params.merge(:per_page => per_page, :page => 1)) do |parsed, response|
        (2..parsed["pages"]).each do |page_num|
          make_request(path, params.merge(:per_page => per_page, :page => page_num)) do |parsed, response|
            yield(parsed)
          end
        end
        yield(parsed)
      end
      @hydra.run
    end

    def get_all(path, page_data_key="items", params={})
      collection = {}

      each_page(path, params) do |list|
        collection.merge!(list[page_data_key])
      end

      collection
    end

    def right_now
      @right_now ||= Time.now
    end
  end

  class Skills < Basic
    ALL_SKILLS="all_skills.json"

    def all
      @all ||= file_cached(ALL_SKILLS) do
        get_all("skills.listAll")
      end
    end

    def info(skill_id)
      file_cached(File::join("skills", skill_id), 60 * 60 * 3) do
        get("skills.getInfo", "skill_id" => skill_id, "skill_class" => skill_id)
      end
    end

    def blocking_skill(skill_id)
      blocking = []
      skills = [skill_id]

      until skills.empty? do
        skill_info = info(skills.shift)
        skill_info["reqs"].each do |req|
          next unless req["got"] == 0
          case req["type"]
          when "skill"
            skills.push req["class_tsid"]
          when "level"
            req["name"] = req["level"]
            blocking << req
          else
            blocking << req
          end
        end
      end
      blocking
    end

    def learnable
      get("skills.listAvailable")["skills"]
    end

    def targets
      @targets ||=
        begin
          string = File::read(@character + ".targets") rescue ""
          lines = string.split("\n")
          lines.map do |line|
            line.split(/\s/)
          end
        end
    end

    def cached_all
      all
    end

    def prereqs(targets, dummy=nil)
      skills = all
      prereqs = []

      until targets.empty?
        prereqs = targets + prereqs

        targets = (targets.map do |target|
          begin
            skills[target]["required_skills"]
          rescue Object => e
            p [e, target]
            nil
          end
        end.flatten.compact - prereqs)
      end

      return prereqs
    end

    def queue
      skills = all
      learnable_skills = get("skills.listAvailable")["skills"]
      learnable = learnable_skills.keys

      targets.each do |list|
        can_learn = learnable & prereqs(list, skills)

        unless can_learn.empty?
          learnable = can_learn
          break
        end
      end
      learnable.map{|key| learnable_skills[key]}.sort_by{|skill| skill["time_remaining"]}
    end

    def next_skill
      return queue.first
    end

    def learn(tsid)
      return get("skills.learn", "skill_class" => tsid)
    end

    def now_learning
      get("skills.listLearning")["learning"]
    end
  end

  class Inventory < Basic
    def inventory
      get("players.inventory", "defs" => 1)
    end
  end

  class Auctions < Basic
    def list(category=nil)
      path = "all_auctions.json"
      params = { "defs" => "1"}
      if !category.nil?
        path = "#{category}_auctions.json"
        params["category"] = category
      end
      file_cached(path, 5 * 60){ get_all("auctions.list", "items", params) }
    end

    def create(stack_tsid, count, cost)
      get("auctions.create",
          { "stack_tsid" => stack_tsid,
            "count" => count,
            "cost" => cost })
    end

    def detailed_list(category=nil, dont_cache=false)
      path = "detailed_all_auctions.json"
      params = {"defs" => "1"}
      if !category.nil?
        path = "detailed_#{category}_auctions.json"
        params["category"] = category
      end
      if dont_cache
        get_all("auctions.list", "items", params)
      else
        file_cached(path, 60 * 5){ get_all("auctions.list", "items", params) }
      end
    end

    def deals(category=nil)
      all = detailed_list(category, true)
      all.values.each do |auction|
        auction["cost_each"] = auction["cost"].to_f / auction["count"].to_f
        auction["markdown"] = auction["cost_each"].to_f / auction["item_def"]["base_cost"].to_f
        auction["tool_sale"] = vendor_sale(auction, 0.8)
        auction["other_sale"] = vendor_sale(auction, 0.7)
        auction["inventory_slots"] = auction["count"].to_f / auction["item_def"]["max_stack"].to_f
      end
    end

    def vendor_sale(auction, ratio)
        vendor_price =  (auction["item_def"]["base_cost"].to_f * ratio).floor
        profit_each =  vendor_price - auction["cost_each"]
        profit_lot =  profit_each * auction["count"].to_f
        { "profit_each" => profit_each,
          "profit_lot" => profit_lot }

    end

    def best_auctions
      old = Time.now.to_i - 60 * 60 * 2 # two hours
      best_prices = Hash.new{|h,k| h[k] = {"price" => nil, "long_price" => nil, "link" => "no auction"}}
      list.values.each do |auction|
        item_class = auction["class_tsid"]
        price = auction["cost"].to_i / auction["count"].to_f
        best_price = best_prices[item_class]
        if best_price["price"].nil?
          best_price["price"] = price
          best_price["link"] = auction["url"]
          best_price["long_price"] = [
            auction["item_def"]["base_cost"].to_f * 0.8,
            (auction["created"].to_i < old ? price : 0)
          ].max
        else
          if best_price["price"] > price
            best_price["price"] = price
            best_price["link"] = auction["url"]
          end

          if auction["created"].to_i < old and best_price["long_price"] > price
            best_price["long_price"] = price
            best_price["long_url"] = auction["url"]
          end
        end
      end
      return best_prices
    end
  end

  class Character < Basic
    def me
      @me ||= get("players.info")
    end

    def details
      @details ||= get("players.fullInfo",
          "player_tsid" => me["player_tsid"],
          "viewer_tsid" => me["player_tsid"])
    end

    def location
      details["location"]
    end
  end

  class Location < Basic
    def local(tsid)
      @local ||= street(tsid)
    end

    def street(tsid)
      file_cached(File::join("streets", tsid), 12 * 60 * 60) do
        get("locations.streetInfo", "street_tsid" => tsid)
      end
    end

    def cached_street(tsid)
      street(tsid)
    end

    def street_request(tsid)
      make_request("locations.streetInfo", "street_tsid" => tsid) do |street, res|
        yield street
      end
    end

    def all_streets(&block)
      file_cached("") do
        make_request("locations.getHubs") do |hubs, res|
          hubs["hubs"].keys.each do |hub|
            make_request("locations.getStreets", "hub_id" => hub) do |streets, res|
              streets["streets"].keys.each do |tsid|
                street_request(tsid, &block)
              end
            end
          end
        end
      end
      @hydra.run
    end

    def subways
      @subways ||= file_cached("subways.json") do
        subways = {}
        all_streets do |street|
          (street["connections"] || {}).each_pair do |tsid, conn|
            if conn["name"] =~ /Subway Station/
              subways[tsid] = true
            end
          end
        end
        subways.keys
      end
    end

    def has_project
      projects = []
      all_streets do |street|
        if street["active_project"]
          projects << street
        end
      end
      return projects
    end

    def street_search(from, closed, via_subway, distance, &block)
      closed[from] = true
      street_request(from) do |street|
        block.call(distance, street, via_subway)
        if Hash === street["connections"]
          street["connections"].keys.each do |connection|
            next if closed[connection]
            street_search(connection, closed, via_subway, distance + 1, &block)
          end
        end
        unless via_subway
          if subways.include? from
            subways.each do |connection|
              street_search(connection, closed, true, distance + 1, &block)
            end
          end
        end
      end
    end

    def each_street(starting_at, &block)
      closed = {}
      file_cached("", 30 * 60) do
        street_search(starting_at, closed, false, 1, &block)
        @hydra.run
      end
    end
  end
end
