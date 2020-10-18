# frozen_string_literal: true

require 'agi'

# five cell game
class FiveGame
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

# random clicker agent
class RandomAgent
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
class QAgent
  attr_reader :q

  def initialize
    @q = TableQ.new
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
end

# table based q
class TableQ
  attr_accessor :last_state, :last_action, :last_score, :available_actions

  def initialize
    @last_state = ''
    @last_action = nil
    @last_score = 0
    @q = {} # Q-value
    @e = {} # eligibility trace
    @epsilon = 0.9
    @learning_rate = 0.9
    @discount_rate = 0.9
    @lambda = 0.5
    @available_actions = Set.new
    @state_action_pairs = []
    @random = Random.new
  end

  def epsilon_greedy(actions)
    if @random.rand > @epsilon
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
    delta = dscore + @discount_rate * q(new_state, new_action[:action]) - q(@last_state, @last_action)
    @e["#{@last_state} | #{@last_action}"] = e(@last_state, @last_action) + 1

    @state_action_pairs.each do |s, a|
      @q["#{s} | #{a}"] = q(s, a) + @learning_rate * delta * e(s, a)
      @e["#{s} | #{a}"] = @discount_rate * @lambda * e(s, a)
    end
  end
end

class Observer
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
      if agent.q.q(x, :left) > agent.q.q(x, :right)
        arr << ' < '
      elsif agent.q.q(x, :left) < agent.q.q(x, :right)
        arr << ' > '
      else
        arr << ' ? '
      end
    end
    p arr
  end
end

player = Player.new(FiveGame.new, QAgent.new)
event = Event.new([player], [Observer.new])

event.run!
