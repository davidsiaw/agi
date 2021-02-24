# frozen_string_literal: true

require 'agi'
require 'pry'
require 'tty-cursor'
require 'yaml'

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

  EPSILON = 0.9
  LEARNING_RATE = 0.001
  DISCOUNT_RATE = 0.99
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

  def initialize(_num)
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

  def initialize(_num)
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

  def initialize(agent_class, game_class, count, *game_args)
    @count = count.to_i
    @agent_class = agent_class
    @game_class = game_class
    @game_args = game_args
    @last_saves = []
    @observers = []
  end

  def step
    observer = Observer.new
    players = []
    @count.times do |i|
      curr_agent = @agent_class.new(@last_saves[i] || {})
      curr_term = @game_class.new(i, *@game_args)
      players << Player.new(curr_term, curr_agent)
    end

    event = Event.new(players, [observer, *observers])
    event.run!

    players.each_with_index do |player, i|
      @last_saves[i] = player.agent.save_state
    end

    #p observer.count
  end

  def save!(name)
    File.write(name, { result: @last_saves }.to_yaml)
  end

  def load!(name)
    @last_saves = YAML.load(File.read(name))[:result]
  end
end

# t = AgentTrainer.new(QAgent, MazeGame, 1)
# 10.times { t.step }
# t.observers << MazePolicyObserver.new
# t.step
# t.observers.clear
# t.observers << MazeObserver.new
# t.step

class TicTacToeGamestate
  attr_accessor :rows

  def initialize
    reset!
  end

  def reset!
    @rows = [[nil, nil, nil],
             [nil, nil, nil],
             [nil, nil, nil]]
  end

  def paths
    @paths ||= begin
      result = []

      a = []
      b = []
      3.times do |x|
        a << [x, x]
        b << [2 - x, x]
      end
      result << a
      result << b

      3.times do |x|
        a = []
        b = []
        3.times do |y|
          a << [x, y]
          b << [y, x]
        end
        result << a
        result << b
      end

      result
    end
  end

  def victor
    paths.each do |path|
      m = nil
      count = 0
      path.each do |x, y|
        c = @rows[y][x]
        m ||= c
        count += 1 if m == c && !m.nil?
      end
      return m if count == 3
    end
    nil
  end
end

class TicTacToeGame < Terminal
  def initialize(num, gamestate)
    #0 is O and 1 is X
    @num = num
    @gamestate = gamestate
  end

  def actions
    result = []
    3.times do |x|
      3.times do |y|
        result << "#{x}#{y}" if @gamestate.rows[y][x].nil?
      end
    end
    result
  end

  def state
    s = ''
    3.times do |x|
      3.times do |y|
        s += "#{x}#{y}=#{@gamestate.rows[y][x]}"
      end
    end
    s
  end

  def ended?
    !@gamestate.victor.nil? || actions.length.zero?
  end

  def score
    return 1 if @gamestate.victor == @num
    return -1 if @gamestate.victor == 1 - @num

    0
  end

  def act!(action)
    x = action[0].to_i
    y = action[1].to_i

    @gamestate.rows[y][x] = @num
  end

  def rows
    @gamestate.rows
  end

  def victor
    @gamestate.victor
  end
end

class TicTacToeObserver
  def t(x, y)
    return ' X ' if @terminal.rows[y][x] == 1
    return ' O ' if @terminal.rows[y][x] == 0

    '   '
  end

  def victor
    return 'X wins' if @terminal.victor == 1
    return 'O wins' if @terminal.victor == 0

    'no victor'
  end

  def observe(terminal, agent)
    @terminal = terminal
    puts "#{t(0, 0)}|#{t(1, 0)}|#{t(2, 0)}"
    puts '---+---+---'
    puts "#{t(0, 1)}|#{t(1, 1)}|#{t(2, 1)}"
    puts '---+---+---'
    puts "#{t(0, 2)}|#{t(1, 2)}|#{t(2, 2)}"
    puts victor
  end
end

state = TicTacToeGamestate.new
game = TicTacToeGame.new(0, state)
TicTacToeObserver.new.observe(game, nil)

t = AgentTrainer.new(QAgent, TicTacToeGame, 2, state)

# 1000.times do |x|
#   puts "train #{x}"
#   t.load!('tictactoe.yml')
#   10000.times { state.reset!; t.step }
#   t.save!('tictactoe.yml')
# end

#t.load!('tictactoe.yml')
10000.times { state.reset!; t.step }
t.save!('tictactoe.yml')
t.observers << TicTacToeObserver.new
state.reset!
t.step

# puts '---------------------------------------'

# qagent = t.agent

# player = Player.new(FiveGame.new, qagent)
# event = Event.new([player], [FiveGameObserver.new])

# event.run!
