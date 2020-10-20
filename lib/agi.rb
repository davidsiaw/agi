# frozen_string_literal: true

# base class for a terminal to control the game
class Terminal
  def actions
    []
  end

  def state
    {}
  end

  def ended?
    true
  end

  def score
    0
  end

  def act!(action); end
end

# base class for an agent able to play the game
class Agent
  def read_state!(state); end

  def choose_action(actions); end

  def notify_result!(state, score); end

  def save_state; end
end

# a player with his terminal
class Player
  attr_reader :terminal, :agent

  def initialize(terminal, agent)
    @terminal = terminal
    @agent = agent
  end

  def step!
    @agent.read_state!(@terminal.state)
    action = @agent.choose_action(@terminal.actions)
    @terminal.act!(action)
  end

  def complete!
    @agent.notify_result!(@terminal.state, @terminal.score)
  end
end

# an event
class Event
  def initialize(players = [], observers = [])
    @players = players
    @observers = observers
  end

  def step!
    @players.each(&:step!)
    @players.each(&:complete!)
    @observers.each do |obs|
      @players.each do |player|
        obs.observe(player.terminal, player.agent)
      end
    end
  end

  def ended?
    @players.all? { |player| player.terminal.ended? }
  end

  def run!
    loop do
      step!
      break if ended?
    end
  end
end
