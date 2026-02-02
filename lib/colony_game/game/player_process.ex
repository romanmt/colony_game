defmodule ColonyGame.Game.PlayerProcess do
  use GenServer
  require Logger

  alias ColonyGame.Game.Rules
  alias ColonyGame.Game.PlayerPresence
  alias ColonyGame.Game.Schemas.Player
  alias ColonyGame.Repo

  defmodule PlayerState do
    defstruct [
      :player_id,
      :db_player_id,  # UUID from database, nil if not persisted
      :rules  # This will hold the Rules struct
    ]
  end

  ## Public API

  def start_link(player_id) do
    GenServer.start_link(__MODULE__, player_id, name: via_tuple(player_id))
  end

  def get_state(player_id) do
    GenServer.call(via_tuple(player_id), :get_state)
  end

  def update_resources(player_id, new_resources) do
    GenServer.cast(via_tuple(player_id), {:update_resources, new_resources})
  end

  def forage(player_id) do
    GenServer.call(via_tuple(player_id), {:start_foraging, :forest})
  end

  def forage(player_id, location) when location in [:forest, :river, :cave] do
    GenServer.call(via_tuple(player_id), {:start_foraging, location})
  end

  def add_item(player_id, item, amount) do
    GenServer.cast(via_tuple(player_id), {:add_item, item, amount})
  end

  def add_items(player_id, items) when is_map(items) do
    GenServer.cast(via_tuple(player_id), {:add_items, items})
  end

  def remove_item(player_id, item, amount) do
    GenServer.call(via_tuple(player_id), {:remove_item, item, amount})
  end

  def get_inventory(player_id) do
    GenServer.call(via_tuple(player_id), :get_inventory)
  end

  ## GenServer Callbacks

  def init(player_id) do
    # Try to load player from database or create new
    {db_player_id, rules} = load_or_create_player(player_id)

    state = %PlayerState{
      player_id: player_id,
      db_player_id: db_player_id,
      rules: rules
    }

    {:ok, state}
  end

  def handle_call({:start_foraging, location}, _from, state) do
    case Rules.check(state.rules, {:begin_foraging, location}) do
      {:ok, new_rules} ->
        new_state = %{state | rules: new_rules}

        # Persist state to database
        new_state = persist_state(new_state)

        # Notify presence system of activity change
        PlayerPresence.update_activity(state.player_id, :foraging)

        # Return flattened state in the response
        flattened_state = %{
          player_id: new_state.player_id,
          resources: new_rules.resources,
          status: new_rules.state,
          tick_counter: new_rules.tick_counter,
          foraging_ticks: new_rules.current_state_counter,
          foraging_location: new_rules.foraging_location
        }
        {:reply, {:ok, flattened_state}, new_state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_cast({:update_resources, new_resources}, state) do
    new_rules = Rules.update_resources(state.rules, new_resources)
    new_state = %{state | rules: new_rules}

    # Persist state to database
    new_state = persist_state(new_state)

    {:noreply, new_state}
  end

  def handle_cast({:add_item, item, amount}, state) do
    new_rules = Rules.add_item(state.rules, item, amount)
    new_state = %{state | rules: new_rules}

    # Persist state to database
    new_state = persist_state(new_state)

    broadcast_inventory_update(state.player_id, new_rules.inventory)
    {:noreply, new_state}
  end

  def handle_cast({:add_items, items}, state) do
    new_rules = Rules.add_items(state.rules, items)
    new_state = %{state | rules: new_rules}

    # Persist state to database
    new_state = persist_state(new_state)

    broadcast_inventory_update(state.player_id, new_rules.inventory)
    {:noreply, new_state}
  end

  def handle_call(:get_state, _from, state) do
    # Return a flattened version of the state that matches the expected structure
    flattened_state = %{
      player_id: state.player_id,
      resources: state.rules.resources,
      inventory: state.rules.inventory,
      status: state.rules.state,
      tick_counter: state.rules.tick_counter,
      foraging_location: state.rules.foraging_location
    }
    {:reply, flattened_state, state}
  end

  def handle_call(:get_inventory, _from, state) do
    {:reply, state.rules.inventory, state}
  end

  def handle_call({:remove_item, item, amount}, _from, state) do
    case Rules.remove_item(state.rules, item, amount) do
      {:ok, new_rules} ->
        new_state = %{state | rules: new_rules}

        # Persist state to database
        new_state = persist_state(new_state)

        broadcast_inventory_update(state.player_id, new_rules.inventory)
        {:reply, {:ok, new_rules.inventory}, new_state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_cast(:tick, state) do
    old_status = state.rules.state
    foraging_location = state.rules.foraging_location
    new_rules = Rules.process_tick(state.rules)

    # Handle foraging completion if state changed from foraging to idle
    new_rules =
      if old_status == :foraging and new_rules.state == :idle do
        # Notify presence system of activity change back to idle
        PlayerPresence.update_activity(state.player_id, :idle)
        # Use the location that was being foraged (defaulting to :forest for backwards compat)
        location = foraging_location || :forest
        case ColonyGame.Game.ForagingServer.forage(location) do
          {:ok, resource_type, amount} ->
            Rules.update_resources(new_rules, %{resource_type => amount})
          :empty ->
            new_rules
        end
      else
        new_rules
      end

    new_state = %{state | rules: new_rules}

    # Persist state to database
    new_state = persist_state(new_state)

    # Broadcast state update to LiveView
    ColonyGameWeb.Endpoint.broadcast("player:#{state.player_id}", "tick_update", %{
      resources: new_rules.resources,
      inventory: new_rules.inventory,
      status: new_rules.state,
      tick_counter: new_rules.tick_counter,
      foraging_location: new_rules.foraging_location
    })

    {:noreply, new_state}
  end

  ## Internal Helpers

  defp via_tuple(player_id), do: {:via, Registry, {ColonyGame.Game.Registry, player_id}}

  defp broadcast_inventory_update(player_id, inventory) do
    ColonyGameWeb.Endpoint.broadcast("player:#{player_id}", "inventory_update", %{
      inventory: inventory
    })
  end

  @doc """
  Loads existing player from database or creates a new one.
  Returns {db_player_id, rules} tuple.
  Falls back to in-memory only if database is unavailable.
  """
  defp load_or_create_player(player_id) do
    try do
      case Repo.get_by(Player, session_id: player_id) do
        nil ->
          # Player doesn't exist, create new
          create_new_player(player_id)

        player ->
          # Player exists, load their state
          Logger.info("Loaded player #{player_id} from database")
          rules = rules_from_player(player)
          {player.id, rules}
      end
    rescue
      error ->
        Logger.warning("Database unavailable for player #{player_id}, using in-memory state: #{inspect(error)}")
        {nil, Rules.new()}
    end
  end

  defp create_new_player(player_id) do
    attrs = %{
      session_id: player_id,
      food: 100,
      water: 100,
      energy: 100,
      state: "idle"
    }

    changeset = Player.create_changeset(%Player{}, attrs)

    case Repo.insert(changeset) do
      {:ok, player} ->
        Logger.info("Created new player #{player_id} in database")
        {player.id, Rules.new()}

      {:error, changeset} ->
        Logger.warning("Failed to create player #{player_id} in database: #{inspect(changeset.errors)}")
        {nil, Rules.new()}
    end
  end

  defp rules_from_player(%Player{} = player) do
    %Rules{
      state: String.to_existing_atom(player.state),
      current_state_counter: 0,  # Reset on reconnect (foraging progress lost)
      resources: %{
        food: player.food,
        water: player.water,
        energy: player.energy
      },
      last_updated: System.system_time(:second),
      tick_counter: 0,  # Reset tick counter on reconnect
      inventory: %{},  # Inventory not persisted yet
      foraging_location: nil  # Reset on reconnect
    }
  end

  @doc """
  Persists the current player state to the database.
  Returns updated state with db_player_id if insert was needed.
  Gracefully handles database errors by logging and continuing.
  """
  defp persist_state(%PlayerState{db_player_id: nil} = state) do
    # Player not in database yet, try to insert
    try do
      attrs = player_attrs_from_state(state)
      changeset = Player.create_changeset(%Player{}, Map.put(attrs, :session_id, state.player_id))

      case Repo.insert(changeset) do
        {:ok, player} ->
          Logger.debug("Persisted new player #{state.player_id} to database")
          %{state | db_player_id: player.id}

        {:error, changeset} ->
          Logger.warning("Failed to persist new player #{state.player_id}: #{inspect(changeset.errors)}")
          state
      end
    rescue
      error ->
        Logger.warning("Database unavailable for persist (insert) #{state.player_id}: #{inspect(error)}")
        state
    end
  end

  defp persist_state(%PlayerState{db_player_id: db_id} = state) when not is_nil(db_id) do
    # Player exists in database, update
    try do
      case Repo.get(Player, db_id) do
        nil ->
          Logger.warning("Player #{state.player_id} not found in database for update, reinserting")
          persist_state(%{state | db_player_id: nil})

        player ->
          attrs = player_attrs_from_state(state)
          changeset = Player.update_changeset(player, attrs)

          case Repo.update(changeset) do
            {:ok, _player} ->
              Logger.debug("Updated player #{state.player_id} in database")
              state

            {:error, changeset} ->
              Logger.warning("Failed to update player #{state.player_id}: #{inspect(changeset.errors)}")
              state
          end
      end
    rescue
      error ->
        Logger.warning("Database unavailable for persist (update) #{state.player_id}: #{inspect(error)}")
        state
    end
  end

  defp player_attrs_from_state(%PlayerState{rules: rules}) do
    %{
      food: rules.resources.food,
      water: rules.resources.water,
      energy: rules.resources.energy,
      state: Atom.to_string(rules.state)
    }
  end
end
