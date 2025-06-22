defmodule WordBumpWeb.WordBumpLive do
  use WordBumpWeb, :live_view
  alias Phoenix.PubSub
  alias WordBumpWeb.Presence

  @topic "word_bump"
  @match_radius_km 5.0

  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.subscribe(WordBump.PubSub, @topic)

      # Track user presence
      {:ok, _} =
        Presence.track(self(), @topic, socket.id, %{
          online_at: inspect(System.system_time(:second)),
          word: nil,
          lat: nil,
          lng: nil,
          looking_for_match: false
        })
    end

    {:ok,
     assign(socket,
       word: "",
       location: nil,
       looking_for_match: false,
       potential_matches: [],
       match_requests: [],
       current_match: nil,
       show_match_modal: false,
       match_requester: nil,
       location_error: nil
     )}
  end

  def handle_event("update_word", %{"value" => word}, socket) do
    # Update presence with new word
    Presence.update(self(), @topic, socket.id, fn meta ->
      %{meta | word: String.trim(word)}
    end)

    {:noreply, assign(socket, word: String.trim(word))}
  end

  def handle_event("get_location", _params, socket) do
    {:noreply, push_event(socket, "get_location", %{})}
  end

  def handle_event("location_received", %{"lat" => lat, "lng" => lng}, socket) do
    # Update presence with location
    Presence.update(self(), @topic, socket.id, fn meta ->
      %{meta | lat: lat, lng: lng}
    end)

    location = %{lat: lat, lng: lng}

    # Check for potential matches
    matches = find_potential_matches(socket.id, socket.assigns.word, location)

    {:noreply,
     assign(socket,
       location: location,
       potential_matches: matches,
       location_error: nil
     )}
  end

  def handle_event("location_error", %{"error" => error}, socket) do
    {:noreply, assign(socket, location_error: error)}
  end

  def handle_event("toggle_looking", _params, socket) do
    new_looking_state = !socket.assigns.looking_for_match

    # Update presence
    Presence.update(self(), @topic, socket.id, fn meta ->
      %{meta | looking_for_match: new_looking_state}
    end)

    matches =
      if new_looking_state and socket.assigns.location do
        find_potential_matches(socket.id, socket.assigns.word, socket.assigns.location)
      else
        []
      end

    {:noreply,
     assign(socket,
       looking_for_match: new_looking_state,
       potential_matches: matches
     )}
  end

  def handle_event("request_match", %{"user_id" => user_id}, socket) do
    # Send match request to specific user
    PubSub.broadcast(WordBump.PubSub, @topic, {
      :match_request,
      %{from: socket.id, to: user_id, word: socket.assigns.word}
    })

    {:noreply, socket}
  end

  def handle_event("accept_match", %{"requester_id" => requester_id}, socket) do
    # Broadcast match acceptance
    PubSub.broadcast(WordBump.PubSub, @topic, {
      :match_accepted,
      %{from: socket.id, to: requester_id}
    })

    # Remove the request and close modal
    updated_requests =
      Enum.reject(socket.assigns.match_requests, fn req ->
        req.from == requester_id
      end)

    {:noreply,
     assign(socket,
       match_requests: updated_requests,
       show_match_modal: false,
       current_match: requester_id
     )}
  end

  def handle_event("decline_match", %{"requester_id" => requester_id}, socket) do
    # Broadcast match decline
    PubSub.broadcast(WordBump.PubSub, @topic, {
      :match_declined,
      %{from: socket.id, to: requester_id}
    })

    # Remove the request and close modal
    updated_requests =
      Enum.reject(socket.assigns.match_requests, fn req ->
        req.from == requester_id
      end)

    {:noreply,
     assign(socket,
       match_requests: updated_requests,
       show_match_modal: false
     )}
  end

  def handle_event("close_match_modal", _params, socket) do
    {:noreply, assign(socket, show_match_modal: false)}
  end

  def handle_event("end_match", _params, socket) do
    {:noreply, assign(socket, current_match: nil)}
  end

  # Handle presence updates
  def handle_info(%{event: "presence_diff"}, socket) do
    if socket.assigns.looking_for_match and socket.assigns.location do
      matches = find_potential_matches(socket.id, socket.assigns.word, socket.assigns.location)
      {:noreply, assign(socket, potential_matches: matches)}
    else
      {:noreply, socket}
    end
  end

  # Handle match requests
  def handle_info({:match_request, %{from: from, to: to, word: word}}, socket) do
    if to == socket.id do
      request = %{from: from, word: word}
      updated_requests = [request | socket.assigns.match_requests]

      {:noreply,
       assign(socket,
         match_requests: updated_requests,
         show_match_modal: true,
         match_requester: from
       )}
    else
      {:noreply, socket}
    end
  end

  # Handle match acceptance
  def handle_info({:match_accepted, %{from: from, to: to}}, socket) do
    if to == socket.id do
      {:noreply, assign(socket, current_match: from)}
    else
      {:noreply, socket}
    end
  end

  # Handle match decline
  def handle_info({:match_declined, %{from: from, to: to}}, socket) do
    if to == socket.id do
      # Could show a notification that match was declined
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # Helper functions
  defp find_potential_matches(current_user_id, word, location) do
    if String.length(word) > 0 do
      @topic
      |> Presence.list()
      |> Enum.filter(fn {user_id, %{metas: [meta | _]}} ->
        user_id != current_user_id and
          meta.word == word and
          meta.looking_for_match and
          meta.lat != nil and
          meta.lng != nil and
          within_radius?(location, %{lat: meta.lat, lng: meta.lng}, @match_radius_km)
      end)
      |> Enum.map(fn {user_id, %{metas: [meta | _]}} ->
        %{
          id: user_id,
          word: meta.word,
          distance: calculate_distance(location, %{lat: meta.lat, lng: meta.lng})
        }
      end)
    else
      []
    end
  end

  defp within_radius?(loc1, loc2, radius_km) do
    calculate_distance(loc1, loc2) <= radius_km
  end

  defp calculate_distance(%{lat: lat1, lng: lng1}, %{lat: lat2, lng: lng2}) do
    # Haversine formula for calculating distance between two points
    # Earth's radius in kilometers
    r = 6371

    dlat = :math.pi() * (lat2 - lat1) / 180
    dlng = :math.pi() * (lng2 - lng1) / 180

    a =
      :math.sin(dlat / 2) * :math.sin(dlat / 2) +
        :math.cos(:math.pi() * lat1 / 180) * :math.cos(:math.pi() * lat2 / 180) *
          :math.sin(dlng / 2) * :math.sin(dlng / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))

    r * c
  end

  defp get_match_location(match_id) do
    case Presence.get_by_key(@topic, match_id) do
      %{metas: [meta | _]} when meta.lat != nil and meta.lng != nil ->
        %{lat: meta.lat, lng: meta.lng}

      _ ->
        nil
    end
  end

  def render(assigns) do
    ~H"""
    <div class="p-4 min-h-screen bg-base-200" phx-hook="LocationManager" id="location-manager">
      <div class="mx-auto max-w-md">
        <div class="shadow-xl card bg-base-100">
          <div class="card-body">
            <h1 class="mb-6 text-2xl font-bold text-center card-title">Word Bump</h1>
            <p class="mb-6 text-center text-base-content/70">
              Find people nearby who are thinking about the same word as you!
              Enter a word, share your location, and see if anyone around you is on the same wavelength.
            </p>

    <!-- Word Input -->
            <div class="mb-4 form-control">
              <input
                type="text"
                placeholder="Enter a word..."
                class="w-full input input-bordered"
                value={@word}
                phx-keyup="update_word"
                phx-debounce="300"
                name="word"
              />
            </div>

    <!-- Location Status -->
            <div class="mb-4">
              <%= if @location do %>
                <div class="alert alert-success">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="w-6 h-6 stroke-current shrink-0"
                    fill="none"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                  <span>Location detected</span>
                </div>
              <% else %>
                <%= if @location_error do %>
                  <div class="mb-2 alert alert-error">
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      class="w-6 h-6 stroke-current shrink-0"
                      fill="none"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"
                      />
                    </svg>
                    <span>{@location_error}</span>
                  </div>
                <% end %>
                <button class="w-full btn btn-primary" phx-click="get_location">
                  Get My Location
                </button>
              <% end %>
            </div>

    <!-- Looking for Match Toggle -->
            <%= if @location != nil and String.length(@word) > 0 do %>
              <div class="mb-4 form-control">
                <label class="cursor-pointer label">
                  <span class="label-text">Looking for matches</span>
                  <input
                    type="checkbox"
                    class="toggle toggle-primary"
                    checked={@looking_for_match}
                    phx-click="toggle_looking"
                  />
                </label>
              </div>
            <% end %>

    <!-- Potential Matches -->
            <%= if @looking_for_match and length(@potential_matches) > 0 do %>
              <div class="mb-4">
                <h3 class="mb-2 font-semibold">Nearby matches for "{@word}":</h3>
                <div class="space-y-2">
                  <%= for match <- @potential_matches do %>
                    <div class="flex justify-between items-center p-3 rounded-lg bg-base-200">
                      <div>
                        <div class="font-medium">Someone with "{match.word}"</div>
                        <div class="text-sm opacity-70">{Float.round(match.distance, 1)} km away</div>
                      </div>
                      <button
                        class="btn btn-sm btn-primary"
                        phx-click="request_match"
                        phx-value-user_id={match.id}
                      >
                        Request Match
                      </button>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

    <!-- Current Match -->
            <%= if @current_match do %>
              <div class="mb-4 alert alert-info">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="w-6 h-6 stroke-current shrink-0"
                  fill="none"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
                <div>
                  <h3 class="font-bold">Matched!</h3>
                  <div class="text-xs">You're matched with someone who also has "{@word}"</div>
                  <%= if get_match_location(@current_match) do %>
                    <% match_loc = get_match_location(@current_match) %>
                    <div class="mt-1 text-xs">
                      Their location: {Float.round(match_loc.lat, 4)}, {Float.round(match_loc.lng, 4)}
                    </div>
                  <% end %>
                </div>
              </div>
              <button class="w-full btn btn-outline btn-sm" phx-click="end_match">
                End Match
              </button>
            <% end %>

    <!-- Status Messages -->
            <%= if @looking_for_match and length(@potential_matches) == 0 and String.length(@word) > 0 do %>
              <div class="alert alert-info">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="w-6 h-6 stroke-current shrink-0"
                  fill="none"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
                <span>Looking for people with "{@word}" nearby...</span>
              </div>
            <% end %>
          </div>
        </div>
      </div>

    <!-- Match Request Modal -->
      <%= if @show_match_modal and length(@match_requests) > 0 do %>
        <div class="modal modal-open">
          <div class="modal-box">
            <h3 class="text-lg font-bold">Match Request!</h3>
            <%= for request <- @match_requests do %>
              <p class="py-4">Someone wants to match with you for the word "{request.word}"</p>
              <div class="modal-action">
                <button
                  class="btn btn-primary"
                  phx-click="accept_match"
                  phx-value-requester_id={request.from}
                >
                  Accept
                </button>
                <button
                  class="btn btn-outline"
                  phx-click="decline_match"
                  phx-value-requester_id={request.from}
                >
                  Decline
                </button>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
