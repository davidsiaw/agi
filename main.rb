# frozen_string_literal: true

require 'agi'
require 'pry'
require 'tty-cursor'

# random clicker agent
class RandomAgent < Agent
  def initialize
    @state = {}
  end

  def read_state!(state)
    @state = state
  end

  def choose_action(actions)
    x = actions.sample
    puts "move #{x}"
    x
  end

  def notify_result!(state, score)
    @state = state
    puts "my score: #{score}"
  end
end

# the agent that can learn how to play
class QAgent < Agent
  attr_reader :q

  def initialize(q_saved = nil)
    @q = TableQ.new(q_saved)
  end

  def read_state!(state)
    q.last_state = state
  end

  def choose_action(actions)
    q.available_actions += actions
    chosen_action = q.epsilon_greedy(actions)[:action]
    q.last_action = chosen_action
    chosen_action
  end

  def notify_result!(state, score)
    dscore = score - q.last_score
    q.update_policy!(dscore, state)
    q.last_score = score
  end

  def save_state
    q.save_q
  end
end

# table based q
class TableQ
  attr_accessor :last_state, :last_action, :last_score, :available_actions

  EPSILON = 0.99
  LEARNING_RATE = 0.9
  DISCOUNT_RATE = 0.9
  LAMBDA = 0.9

  def initialize(q_saved)
    @last_state = ''
    @last_action = nil
    @last_score = 0
    @q = q_saved || {} # Q-value
    @e = {} # eligibility trace
    @available_actions = Set.new
    @state_action_pairs = []
    @random = Random.new
  end

  def epsilon_greedy(actions)
    if @random.rand > EPSILON
      action = actions.sample
      return {
        action: action,
        score: q(@last_state, action)
      }
    end

    action_values(actions).first
  end

  def action_values(actions)
    action_values = actions.map do |a|
      {
        action: a,
        score: q(@last_state, a)
      }
    end

    action_values.sort_by! { |x| -x[:score] }
  end

  def e(state, action)
    @e["#{state} | #{action}"] || 0
  end

  def q(state, action)
    @q["#{state} | #{action}"] || 0
  end

  def update_policy!(dscore, new_state)
    @state_action_pairs << [@last_state, @last_action]
    # sarsa update algorithm
    new_action = epsilon_greedy(@available_actions.to_a)
    delta = dscore + DISCOUNT_RATE * q(new_state, new_action[:action]) - q(@last_state, @last_action)
    @e["#{@last_state} | #{@last_action}"] = e(@last_state, @last_action) + 1

    @state_action_pairs.each do |s, a|
      @q["#{s} | #{a}"] = q(s, a) + LEARNING_RATE * delta * e(s, a)
      @e["#{s} | #{a}"] = DISCOUNT_RATE * LAMBDA * e(s, a)
    end
  end

  def save_q
    @q
  end
end

# five cell game
class FiveGame < Terminal
  START_INDEX = 2
  CELLS = [-1, -1, -10, -10, 100].freeze

  attr_reader :score

  def initialize
    @cells = CELLS
    @index = START_INDEX
    @score = 0
  end

  def actions
    return [:right] if @index.zero?
    return [] if @index == @cells.length - 1

    %i[left right]
  end

  def state
    @index.to_s
  end

  def ended?
    actions.length.zero?
  end

  def act!(action)
    movement = { left: -1, right: 1 }
    @index += movement[action]
    @score += @cells[@index]
  end
end

# thing that observes a 5-cell game
class FiveGameObserver
  def observe(terminal, agent)
    arr = ['   ', '   ', '   ', '   ', '   ']
    puts "move #{agent.q.last_action} score: #{terminal.score}"
    arr[terminal.state.to_i] = ' o '
    p arr
    show_policy!(agent)
  end

  def show_policy!(agent)
    arr = []
    (0..4).each do |x|
      arr << if agent.q.q(x, :left) > agent.q.q(x, :right)
               ' < '
             elsif agent.q.q(x, :left) < agent.q.q(x, :right)
               ' > '
             else
               ' ? '
             end
    end
    p arr
  end
end

# maze game
class MazeGame < Terminal
  attr_reader :location

  MAZE = [
    '00000000',
    '0      0',
    'S 00 0 0',
    '0  00  0',
    '00  0 00',
    '0 0 0  0',
    '0    0 G',
    '00000000'
  ].freeze

  def initialize
    MAZE.each_with_index do |row, y|
      row.split('').each_with_index do |cell, x|
        if cell == 'S'
          @location = [x, y]
        elsif cell == 'G'
          @goal = [x, y]
        end
      end
    end
    @score = 0
  end

  def actions
    result = []
    four_sides.map do |dir, loc|
      cell = MAZE[loc[1]][loc[0]]
      next if cell.nil? || cell == '0'

      result << dir
    end
    result
  end

  def state
    "#{@location[0]} #{@location[1]}"
  end

  def ended?
    @location == @goal
  end

  attr_reader :score

  def act!(action)
    return if ended?

    @location = four_sides[action]
    if @location == @goal
      @score += 100
    else
      @score -= 1
    end
  end

  private

  def four_sides
    {
      up: [@location[0], @location[1] - 1],
      down: [@location[0], @location[1] + 1],
      left: [@location[0] - 1, @location[1]],
      right: [@location[0] + 1, @location[1]]
    }
  end
end

class MazeObserver
  def observe(terminal, agent)
    show_pos!(terminal, agent)
  end

  def show_pos!(terminal, agent)
    puts '+----------------+'
    (0..7).each do |y|
      print '|'
      (0..7).each do |x|
        c = MazePolicyObserver::ARROWS.keys.map do |dir|
          [dir, agent.q.q("#{x} #{y}", dir)]
        end
        c.sort_by! { |x| -x[1] }

        if MazeGame::MAZE[y][x] == '0'
          print '..'
        elsif terminal.location == [x, y]
          print '00'
        else
          print '  '
        end
      end
      puts '|'
    end
    puts '+----------------+'
  end
end

class MazePolicyObserver
  ARROWS = {
    up: '↑',
    left: '←',
    right: '→',
    down: '↓'
  }.freeze

  def initialize
    @count = 0
  end

  def observe(_terminal, agent)
    return if @count > 0

    @count = 1
    show_policy!(agent)
  end

  def show_policy!(agent)
    puts '+----------------+'
    (0..7).each do |y|
      print '|'
      (0..7).each do |x|
        c = ARROWS.keys.map do |dir|
          [dir, agent.q.q("#{x} #{y}", dir)]
        end
        c = c.reject { |z| z[1].zero? }.sort_by { |v| -v[1] }

        best = c.first
        if MazeGame::MAZE[y][x] == '0'
          print '..'
        elsif best
          print " #{ARROWS[best[0]]}"
        else
          print '  '
        end
      end
      puts '|'
    end
    puts '+----------------+'
  end
end

# Trains agents
class AgentTrainer
  attr_reader :observers

  # Trainer observer
  class Observer
    attr_reader :count

    def initialize
      @count = 0
    end

    def observe(_terminal, _agent)
      @count += 1
    end
  end

  def initialize(agent_class, game_class, *game_args)
    @agent_class = agent_class
    @game_class = game_class
    @game_args = game_args
    @last_save = nil
    @observers = []
  end

  def step
    curr_agent = agent
    observer = Observer.new
    player = Player.new(@game_class.new(*@game_args), curr_agent)
    event = Event.new([player], [observer, *observers])

    event.run!
    @last_save = curr_agent.save_state
    p observer.count
  end

  def agent
    @agent_class.new(@last_save)
  end
end

t = AgentTrainer.new(QAgent, MazeGame)
10.times { t.step }
t.observers << MazePolicyObserver.new
t.step
t.observers.clear
t.observers << MazeObserver.new
t.step

# puts '---------------------------------------'

# qagent = t.agent

# player = Player.new(FiveGame.new, qagent)
# event = Event.new([player], [FiveGameObserver.new])

# event.run!
