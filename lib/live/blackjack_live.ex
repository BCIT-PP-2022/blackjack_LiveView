defmodule BlackjackWeb.BlackjackLive do
  use BlackjackWeb, :live_view
  require Logger

  @impl true
  def mount(params, _session, socket) do
    Logger.info("Mounted view")
    # subscribes all users to the game_state topic so that
    # I can handle_info for different events received from broadcast
    if connected?(socket),
    do: BlackjackWeb.Endpoint.subscribe("game_state")

    game_state = GameServer.get_game_state()

    {:ok, assign(socket, playerID: params["name"], playerName: params["name"] , game_state: game_state)}
  end

  @impl true
  def handle_event("hit", %{"seatid" => seat_id}, socket) do
    GameServer.hit(String.to_atom(seat_id))
    BlackjackWeb.Endpoint.broadcast("game_state", "game_state_change", :game_state_change)
    {:noreply, socket}
  end

  @impl true
  def handle_event("stand", %{"seatid" => seat_id}, socket) do
    GameServer.stand(String.to_atom(seat_id))
    BlackjackWeb.Endpoint.broadcast("game_state", "game_state_change", :game_state_change)
    {:noreply, socket}
  end

  @impl true
  def handle_event("seat", %{"seatid" => seat_id}, socket) do
    GameServer.sit(socket.assigns.playerID, String.to_atom(seat_id))
    BlackjackWeb.Endpoint.broadcast("game_state", "game_state_change", :game_state_change)
    {:noreply, assign(socket, seat: String.to_atom(seat_id))}
  end

  @impl true
  def handle_event("leave_seat", _params, socket) do
    GameServer.leave(socket.assigns.seat)
    BlackjackWeb.Endpoint.broadcast("game_state", "user_leaving_game", socket.assigns.seat)
    {:noreply, socket}
  end

  @impl true
  def handle_event("start_round", params, socket) do
    GameServer.start_round()
    BlackjackWeb.Endpoint.broadcast("game_state", "game_state_change", :game_state_change)
    {:noreply, socket}

  end

  @impl true
  def handle_info(%{event: "game_state_change", payload: _}, socket) do
    Logger.info("game state updated")
    game_state_new = GameServer.get_game_state()
    current_turn = Map.get(game_state_new, :turn)
    total_players = Map.get(game_state_new, :total_players)
    Logger.info("Current turn: #{current_turn}, Total players: #{total_players}")

    # Wait till dealer_action is fixed - Each player should keep track of their own result

    # case current_turn > total_players do
    #   true ->
    #     GameServer.dealer_action()
    #     {:noreply, assign(socket, game_state: GameServer.get_game_state())}
    #   false -> {:noreply, assign(socket, game_state: game_state_new)}
    # end

    {:noreply, assign(socket, game_state: game_state_new)}

  end

  # @impl true
  # def handle_info(%{event: "dealer_state_change", payload: _}, socket) do

  # end

  def handle_info(%{event: "user_leaving_game", payload: _}, socket) do
    {:noreply, assign(socket, seat: nil, game_state: GameServer.get_game_state)}
  end

  @impl true
  def terminate({:shutdown, :closed}, socket) do
    Logger.info(socket.assigns.playerID)
    case Map.get(socket.assigns, :seat) do
      nil -> {:noreply, socket}
      seat_id ->
        GameServer.leave(seat_id)
        BlackjackWeb.Endpoint.broadcast("game_state", "user_leaving_game", socket.assigns.seat)
    end
  end

  # helper functions to render to view
  defp rank_to_string(rank) do
    case rank do
      :ace -> "a"
      2 -> "2"
      3 -> "3"
      4 -> "4"
      5 -> "5"
      6 -> "6"
      7 -> "7"
      8 -> "8"
      9 -> "9"
      10 -> "10"
      :jack -> "j"
      :queen -> "q"
      :king -> "k"
    end
  end

  defp suit_to_string(suit) do
    case suit do
      :heart -> "hearts"
      :diamond -> "diams"
      :spade -> "spades"
      :club -> "clubs"
    end
  end

end
