defmodule GameServer do
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  # read apis
  def get_game_state() do
    GenServer.call(__MODULE__, :get_game_state)
  end

  # call vs cast for updates.  could call, reply with game state, and eliminate calls to get_game_state in handle_info except for mount
  # if we have any syncing issues this may be worth looking into

  # update apis
  def sit(player_id, seat_id) do
    GenServer.call(__MODULE__, {:sit, player_id, seat_id})
  end

  def hit(seat_id) do
    GenServer.call(__MODULE__, {:hit, seat_id})
  end

  def stand(seat_id) do
    GenServer.call(__MODULE__, {:stand, seat_id})
  end

  def leave(seat_id) do
    GenServer.call(__MODULE__, {:leave, seat_id})
  end

  def dealer_action() do
    GenServer.call(__MODULE__, :dealer_action)
  end

  def start_round() do
    GenServer.call(__MODULE__, :start_round)
  end

  @impl true
  def init(nil) do
    game_state = %{
      dealer: [],
      seat1: nil,
      seat2: nil,
      seat3: nil,
      cards: CardServer.get_remaining_deck(),
      game_in_progress: false,
      turn: 0,
      completed_games: 0
    }

    {:ok, game_state}
  end

  @impl true
  def handle_call(:get_game_state, _from, state) do
    {:reply, state, state}
  end

  # seat id is an atom e.g. :seat1
  @impl true
  def handle_call({:sit, player_id, seat_id}, _from, state) do
    player = %{
      playerID: player_id,
      hand: [],
      hand_value: 0,
      hand_options: %{},
      result: nil
    }

    Logger.info("player_id: #{player_id}, and seat_id #{seat_id}")

    new_state = Map.put(state, seat_id, player)
    {:reply, new_state, new_state}
  end

  @impl true
  def handle_call(:start_round, _from, state) do
    new_state =
      state
      |> Map.put(:game_in_progress, true)
      # new deck / shuffle deck?
      # consider dealing in order of seat1, seat2, seat3, dealer, one card at at time
      |> Map.put(:dealer, CardServer.deal(2))
      |> Map.put(:turn, 1)
      |> update_seated_player_state(:seat1)
      |> update_seated_player_state(:seat2)
      |> update_seated_player_state(:seat3)
      |> Map.put(:cards, CardServer.get_remaining_deck())

    {:reply, new_state, new_state}
  end

  @impl true
  def handle_call({:hit, seat_id}, _from, state) do
    player = Map.get(state, seat_id)
    new_card = CardServer.deal()
    new_hand = player.hand ++ new_card
    player_state = Map.put(player, :hand, new_hand)

    if get_value_of_hand(new_hand).option_1 > 21 do
      player_state = Map.put(player_state, :result, :bust)

      new_state =
        state
        |> Map.put(seat_id, player_state)
        |> Map.put(:turn, state.turn + 1)

      {:reply, new_state, new_state}
    else
      player_state = Map.put(player_state, :hand_options, get_value_of_hand(new_hand))

      new_state = Map.put(state, seat_id, player_state)

      {:reply, new_state, new_state}
    end
  end

  @impl true
  def handle_call({:stand, _seat_id}, _from, state) do
    new_state =
      state
      |> Map.put(:turn, state.turn + 1)

    {:reply, new_state, new_state}
  end

  ## after player turns, would be called repeatedly until game is over
  ## (maybe every once every second?), rerendering for each card dealt
  @impl true
  def handle_call(:dealer_action, _from, state) do
    dealer_hand_value = state.dealer |> best_hand_option()

    if dealer_hand_value >= 17 do
      new_state =
        state
        |> Map.put(:game_in_progress, false)
        |> Map.put(:completed_games, state.completed_games + 1)
        # update each player results
        ## how to do this dynamically??
        |> Map.put(:seat1, update_player_result(state.seat1, dealer_hand_value))
        |> Map.put(:seat2, update_player_result(state.seat2, dealer_hand_value))
        |> Map.put(:seat3, update_player_result(state.seat3, dealer_hand_value))

      {:reply, new_state, new_state}
    else
      new_state = Map.put(state, :dealer, state.dealer ++ CardServer.deal())

      {:reply, new_state, new_state}
    end
  end

  @impl true
  def handle_call({:leave, seat_id}, _from, state) do
    new_state = Map.put(state, seat_id, nil)

    {:reply, new_state, new_state}
  end

  def update_player_result(player, dealer_hand_value) do
    player_hand_value = player.hand |> best_hand_option()

    cond do
      player_hand_value > 21 ->
        Map.put(player, :result, :bust)

      # player_hand_value == 21 ->
      #   Map.put(player, :result, :blackjack)
      player_hand_value > dealer_hand_value ->
        Map.put(player, :result, :win)

      player_hand_value < dealer_hand_value ->
        Map.put(player, :result, :lose)

      player_hand_value == dealer_hand_value ->
        Map.put(player, :result, :push)

      true ->
        Map.put(player, :result, nil)
    end
  end

  def best_hand_option(hand) do
    hand_value = get_value_of_hand(hand)

    if hand_value.option_2 > 21 do
      hand_value.option_1
    else
      hand_value.option_2
    end
  end

  defp update_seated_player_state(game_state, seatId) do
    cards_dealt = CardServer.deal(2)

    case Map.get(game_state, seatId) do
      nil ->
        game_state

      %{:hand => existing_hand} = player ->
        updated_hand = existing_hand ++ cards_dealt

        p =
          player
          |> Map.put(:hand, updated_hand)
          |> Map.put(:hand_options, get_value_of_hand(updated_hand))

        Map.put(game_state, seatId, p)
    end
  end

  # source this function from:
  # https://github.com/dorilla/live_view_black_jack/blob/master/lib/black_jack_web/game_manager/manager.ex
  # @returns: a map of 2 value options based on card combo: %{option_1: int, option_2: int}
  def get_value_of_hand(hand) do
    Enum.reduce(hand, %{option_1: 0, option_2: 0}, fn card, acc ->
      %{option_1: acc1, option_2: acc2} = acc
      %{option_1: get_value_of_card(card) + acc1, option_2: get_value_of_card(card, true) + acc2}
    end)
  end

  def get_value_of_card({rank, _suit}, ace_2 \\ false) do
    case is_atom(rank) do
      true ->
        case rank do
          :ace -> if ace_2, do: 11, else: 1
          :jack -> 10
          :queen -> 10
          :king -> 10
        end

      false ->
        rank
    end
  end
end
