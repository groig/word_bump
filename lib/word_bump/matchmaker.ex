defmodule WordBump.Matchmaker do
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def report_position(pid, word, {lat, lng}) do
    GenServer.cast(__MODULE__, {:report, pid, word, {lat, lng}})
  end

  def init(_), do: {:ok, %{}}

  def handle_cast({:report, pid, word, location}, state) do
    # Find another user with same word in range
    new_state = maybe_match(pid, word, location, state)
    {:noreply, new_state}
  end

  defp maybe_match(pid, word, location, state) do
    candidates =
      Enum.filter(state, fn
        {other_pid, %{word: ^word}} when other_pid != pid ->
          distance(location, state[other_pid].location) < 0.01

        _ ->
          false
      end)

    case candidates do
      [{other_pid, _}] ->
        send(pid, {:match_found, state[other_pid].location})
        send(other_pid, {:match_found, location})
        Map.put(state, pid, %{word: word, location: location})

      _ ->
        Map.put(state, pid, %{word: word, location: location})
    end
  end

  defp distance({lat1, lon1}, {lat2, lon2}) do
    :math.sqrt(:math.pow(lat1 - lat2, 2) + :math.pow(lon1 - lon2, 2))
  end
end
