# vim: set ft=ruby:
$:.unshift "."
require 'glitch-api'
require 'glitch-www'

class Plato < Thor
  ALL_SKILLS = "all_skills.json"
  argument :char, :type => :string, :desc => "Name of the character to work on"

  desc "all_skills", "Lists all skills"
  def all_skills
    skills = GlitchAPI::Skills.new(char).cached_all

    say skills.values.map{|skill| skill["name"]}.join(", ")
  end

  desc "skill_ids", "Lists the ids for the skills"
  def skill_ids
    skills = GlitchAPI::Skills.new(char).all
    say skills.values.map{|skill| skill["class_tsid"]}.join("\n")
  end

  desc "skill_info", "Info for a skill"
  method_option "skill_id"
  def skill_info
    require 'pp'
    info = GlitchAPI::Skills.new(char).info(options.skill_id)
    pp info
  end

  desc "blocking", "What's keeping me from learning"
  def blocking
    skills = GlitchAPI::Skills.new(char)
    skills.targets.flatten.each do |target|
      say skills.info(target)["name"]

      blockers = skills.blocking_skill(target)
      if blockers.empty?
        say "  <nothing blocking>"
      else
        blockers.each do |blocker|
          say "  #{blocker["type"]}: #{blocker["name"]}"
        end
      end
    end

  end

  desc "next", "Show pick for next skill to learn"
  def next
    say GlitchAPI::Skills.new(char).next_skill["name"]
  end

  desc "start_next", "Beginning learning next skill"
  def start_next
    client = GlitchAPI::Skills.new(char)
    skill = client.next_skill
    result = client.learn(skill["class_tsid"])
    say "Started #{skill["name"]} - estimate finish at #{Time.at(result[skill["class_tsid"]]["end"])}"
  end

  desc "keep_on", "Start next if not learning anything"
  def keep_on
    client = GlitchAPI::Skills.new(char)
    if (learning = client.now_learning).empty?
      invoke :start_next
    else
      say "Already learning: #{learning.values.map{|skill| skill["name"]}.join(", ")}"
    end
  end


  desc "plan", "What skills are we planning forever"
  def plan
    client = GlitchAPI::Skills.new(char)
    skills = client.all
    total = 0
    list = []
    collection = {}
    client.prereqs(client.targets).each do |name|
      skill = skills[name]
      info = client.info(name)
      next if info["got"] == 1
      total += skill["total_time"]
      collection[skill] = true
    end
    list = collection.keys.sort_by do |skill|
      info = client.info(skill["class_tsid"])
      [-info["can_learn"], info["total_time"]]
    end

    list.each do |skill|
      say "  %26s: %3d days %2d hours %2d minutes %2d seconds" %
      ([skill["name"]] + [60,60,24].inject([skill["total_time"]]){|a,u| r = a.shift; [r/u, r%u] + a})
    end
    say "Total time:               %3d days %2d hours %2d minutes %2d seconds (%d)" %
      ([60,60,24].inject([total]){|a,u| r = a.shift; [r/u, r%u] + a} + [total])

  end


  desc "list_queue", "Roughly, what skills are we thinking about?"
  def list_queue
    client = GlitchAPI::Skills.new(char)
    learning = client.now_learning
    total = 0
    say "Currently learning:"
    learning = {} unless Hash === learning
    learning.values.map do |skill|
      total += skill["time_remaining"]
      say "  %20s: %3d days %2d hours %2d minutes %2d seconds" %
      ([skill["name"]] + [60,60,24].inject([skill["time_remaining"]]){|a,u| r = a.shift; [r/u, r%u] + a})
    end
    say "Next up:"
    client.queue.each do |skill|
      total += skill["time_remaining"]
      say "  %20s: %3d days %2d hours %2d minutes %2d seconds" %
      ([skill["name"]] + [60,60,24].inject([skill["time_remaining"]]){|a,u| r = a.shift; [r/u, r%u] + a})
    end
    say "Total time:             %3d days %2d hours %2d minutes %2d seconds (%d)" %
      ([60,60,24].inject([total]){|a,u| r = a.shift; [r/u, r%u] + a} + [total])
  end

  desc "how_long", "How long until we're done learning this?"
  def how_long
    client = GlitchAPI::Skills.new(char)
    if (learning = client.now_learning).empty?
      say "0"
    else
      say learning.values.map{|val| val["time_remaining"]}.max
    end
  end

  desc "when_done", "When will we be done learning this?"
  def when_done
    client = GlitchAPI::Skills.new(char)
    if (learning = client.now_learning).empty?
      say "now"
    else
      time = learning.values.map{|val| val["time_remaining"]}.max
      time = [[60 * 5, time/2].max, time].min
      say (Time.now + time).strftime("%I:%M %p %m/%d/%y")
    end
  end

  desc "about", "About me"
  def about
    require 'pp'
    pp GlitchAPI::Character.new(char).details
  end

  desc "inventory", "What am I carrying?"
  method_option :values, :default => false
  def inventory
    inventory = GlitchAPI::Inventory.new(char).inventory
    auctions = nil
    if options.values?
      auctions = GlitchAPI::Auctions.new(char).best_auctions
    end
    say content_format(inventory, auctions)
  end

  desc "stuff", "How much of everything do I have?"
  method_option :pattern
  method_option :low
  method_option :values, :default => false
  def stuff
    inventory = GlitchAPI::Inventory.new(char).inventory
    stuff = collection_flatten(inventory)
    auctions = nil
    if options.values?
      auctions = GlitchAPI::Auctions.new(char).best_auctions
    end
    if options.pattern or options.low
      regexp = /.*/
      regexp = /#{options.pattern}/i unless options.pattern.nil?
      low = options.low.to_i
      stuff.each_pair do |key, value|
        unless low <= value["count"]
          stuff.delete(key); next
        end
        unless regexp =~ value["label"]
          stuff.delete(key)
        end
      end
    end
    say content_format({"contents" => stuff}, auctions)
  end

  desc "sell", "Put stuff up for auction"
  method_option :pattern
  method_option :number
  method_option :limit
  method_option :amount
  method_option :price
  method_option :force
  def sell
    inventory = GlitchAPI::Inventory.new(char).inventory
    stuff = collection_flatten(inventory)
    if !(options.pattern and options.price)
      puts "Gotta have a pattern, number, stack size and stack price"
      exit 1
    end

    p options
    number = options.number.to_i
    price = options.price.to_f
    pattern = /#{options.pattern}/i

    items = stuff.values.find_all{|item| pattern =~ item["label"]}
    if items.length != 1
      say "Won't sell anything but one kind if thing! (Not #{items.length})"
      exit 1
    end

    limit = items[0]["count"]
    if options.limit
      limit = options.limit.to_i
    elsif !options.force
      exit unless yes?("Sell (almost) all your #{items[0]["label"]}?")
    end

    per_stack = if options.amount
      options.amount.to_i
    else
      [items[0]["item_def"]["max_stack"].to_i, limit].min
    end

    if !options.number
      number = (limit / per_stack).floor
    end

    if items[0]["count"] < (number * per_stack)
      p options, items
      say "You want to sell #{number * per_stack} items, but only have #{items[0]["count"]}"
      exit 1
    end

    stacks = []
    each_item(inventory) do |item, _|
      if pattern =~ item["label"] and !item.has_key?("contents")
        stacks << item
      end
    end

    agent = GlitchAPI::Auctions.new(char)
    stack_price = (price * per_stack).ceil

    p :stacks_of => per_stack, :number => number, :price => stack_price
    while number > 0 and !stacks.empty?
      stacks[0]["count"] -= per_stack
      if stacks[0]["count"] >= 0
        begin
          p agent.create(stacks[0]["tsid"], per_stack, stack_price)
          number -= 1
          say "Auction created"
        rescue Object => ex
          stacks.shift
          p ex
        end
      else
        stacks.shift
      end
    end
    if number > 0
      say "Couldn't sell that many - don't know why"
    end
  end



  desc "auctions", "What's for sale?"
  def auctions
    require 'pp'
    pp GlitchAPI::Auctions.new(char).list
  end

  desc "deals", "What should I buy?"
  method_option :category
  method_option :low
  method_option :high
  method_option :pattern
  def deals
    count = 0
    pattern = options.pattern ? %r{#{options.pattern}} : /.*/
    auctions = GlitchAPI::Auctions.new(char).deals(options.category)
    auctions.delete_if{|auction| auction["markdown"] > 1}
    auctions.sort_by!{|auction| auction["markdown"]}
    if options.low
      low = options.low.to_i
      auctions.delete_if{|auction| auction["cost"].to_i < low}
    end
    if options.high
      high = options.high.to_i
      auctions.delete_if{|auction| auction["cost"].to_i > high}
    end
    if options.pattern
      pattern = %r{#{options.pattern}}i
      auctions.delete_if{|auction| pattern !~ auction["item_def"]["name_single"] and pattern !~ auction["item_def"]["name_plural"] }
    end

    auctions[0..40].each do |deal|
      say "%25s (%2s): %4s = %3.2f%% (%4.2f < %s) http://www.glitch.com%spurchase" % [deal["item_def"]["name_single"], deal["count"], deal["cost"], (deal["markdown"] * 100), deal["cost_each"], deal["item_def"]["base_cost"], deal["url"]]
    end
  end

  desc "arbitrage", "Buy the most items for the best profit that will fit in the fewest slots"
  method_option :budget
  method_option :slots
  method_option :category
  method_option :margin
  method_option :return
  method_option :yes
  method_option :tool
  def arbitrage
    budget = (options.budget ||
      begin
        b = GlitchAPI::Character.new(char).details["stats"]["currants"]
        say "Using current holdings of #{b} as budget"
        b
      end).to_i
    slots = options.slots.to_i
    min_return = options.return.to_i
    vendor = options.tool ? "tool_sale" : "other_sale"

    require 'pp'
    auctions = GlitchAPI::Auctions.new(char).deals(options.category)
    margin = options.margin ? options.margin.to_i : 0
    auctions.delete_if{|lot| lot[vendor]["profit_lot"] < margin}
    auctions = auctions.sort_by{|deal| [-deal[vendor]["profit_lot"], deal["inventory_slots"]]}
    list = []
    cost = 0
    profit = 0
    fills = 0
    blacklist_names = [/hog-tied/i]
    blacklist_categories = %w{powder}
    auctions.each do |deal|
      next if blacklist_names.find{|rx| rx.match deal["item_def"]["name_single"]}
      next if blacklist_categories.include? deal["item_def"]["category"]
      next if budget > 0 and budget < deal["cost"].to_i + cost
      next if slots > 0 and slots < deal["inventory_slots"] + fills

      cst = deal["cost"].to_f
      pft = deal["profit_lot"].to_f

      rtn = (((cst + pft).to_f / cst.to_f) - 1.0) * 100
      next if min_return > rtn

      list << deal
      cost += deal["cost"].to_i
      fills += deal["inventory_slots"]
      profit += deal[vendor]["profit_lot"]
    end

    if list.empty?
      say "No auctions match criteria"
      return
    end

    return_percentage = (((cost + profit).to_f / cost.to_f) - 1.0) * 100

    say "Proposed:"
    list.each do |deal|
      say "Buy: #{deal["count"]} #{deal["item_def"]["name_single"]} for #{deal["cost"]} profit: #{deal[vendor]["profit_lot"].to_i}"
    end
    say "Totals: cost: %d profit: %.2f(%d%%) slots: %d" % [cost, profit, return_percentage, fills.ceil]

    if options.yes or yes? "Proceed?"
      require 'thread'
      agents = []
      list.each do |deal|
        agents << Thread.new do
          begin
            agent = GlitchWWW::Auction.new(char)
            agent.buy(deal["url"])
          rescue Object => ex
            say ex.message
          end
        end
      end
      agents.each do |agent|
        agent.join
      end
    end
  end

  desc "details", "Tell me about myself"
  def details
    require 'pp'
    pp GlitchAPI::Character.new(char).details
  end

  desc "where_am_i", "I'm lost"
  def where_am_i
    require 'pp'
    pp GlitchAPI::Character.new(char).location
  end

  desc "whats_here", "Look around"
  def whats_here
    require 'pp'
    im_at = GlitchAPI::Character.new(char).location
    pp GlitchAPI::Location.new(char).local(im_at["tsid"])
  end

  desc "sweep", "Not useful, just time consuming"
  method_option :pattern
  method_option :range
  def sweep
    require 'pp'
    pattern = /.*/
    pattern = %r{#{options.pattern}}i if options.pattern
    im_at = GlitchAPI::Character.new(char).location
    GlitchAPI::Location.new(char).each_street(im_at["tsid"]) do |far, street|
      break if options.range and options.range.to_i < far
      next if street["features"].nil?
      next if (street["features"].to_a.flatten.grep pattern).empty?
      puts "#{far} #{street["name"]}: #{street["features"].flatten.grep(pattern).join(" ")}"
    end
  end

  desc "closest", "Find the nearest street with a feature that matches"
  method_option :pattern
  method_option :exclude
  def closest
    require 'pp'
    match = %r{#{options.pattern}}i
    but_not = %r{#{options.exclude}}i
    im_at = GlitchAPI::Character.new(char).location
    close = nil
    count = 0

    GlitchAPI::Location.new(char).each_street(im_at["tsid"]) do |far, street, subway|
      next if options.exclude and but_not =~ street["name"]
      count +=1
      if (street["features"]||[]).find{|feature| match =~ feature}
        break if !close.nil? and close < far
        close = far
        pp :hub => street["hub"]["name"], :distance => far, :street => [street["name"], street["features"]], :subway => subway
      end
    end
    say "Searched #{count} streets"
  end

  desc "find_projects", "Where are there street projects?"
  def find_projects
    require 'pp'
    pp GlitchAPI::Location.new(char).has_project
  end


  no_tasks{
    def each_item(container, depth = 0)
      container['contents'].values.compact.map do |item|
        yield(item, depth)
        if item['contents']
          each_item(item, depth + 1) do |item, depth|
            yield(item, depth)
          end
        end
      end
    end

    def collection_flatten(container)
      stuff = {}
      each_item(container) do |item, depth|
        next if item.has_key?("contents")
        if stuff.has_key?(item["class_tsid"])
          stuff[item["class_tsid"]]["count"] += item["count"]
        else
          stuff[item["class_tsid"]] = item
        end
      end
      stuff
    end

    def content_format(container, auction_prices=nil, indent="")
      str = ""
      each_item(container) do |item, depth|
        str += "\n#{" " * depth}#{item["label"]} #{auction_prices ? prices(item, auction_prices) : ""}: #{item["count"]}"
      end
      str
    end

  def prices(item, auction_prices)
    base = item["item_def"]["base_cost"].to_i
    auction = auction_prices[item["item_def"]["class_tsid"]]["price"]
    long_auction = auction_prices[item["item_def"]["class_tsid"]]["long_price"]
    mark = ""
    tool_markdown = base * 0.8
    auction_commission = auction * 0.08
    auction_listing = [auction * 0.015, 3].min
    auction_profit = auction - auction_commission - auction_listing
    if(tool_markdown < auction_profit)
      mark << "*"
    end

    long_auction_commission = long_auction * 0.08
    long_auction_listing = [long_auction * 0.015, 3].min
    long_auction_profit = long_auction - long_auction_commission - long_auction_listing
    if(base < long_auction_profit)
      mark << "+"
    end

    "(%d/%.2f,%.2f)%s" % [base,auction,long_auction,mark]
  rescue
    "base: %.2f tool: %.2f" % [item["item_def"]["base_cost"], item["item_def"]["base_cost"].to_f * 0.8]
  end
  }
end
