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
    # Broadcast that this user ended the match
    if socket.assigns.current_match do
      PubSub.broadcast(WordBump.PubSub, @topic, {
        :match_ended,
        %{from: socket.id, to: socket.assigns.current_match}
      })
    end

    # Update presence to stop looking for matches
    Presence.update(self(), @topic, socket.id, fn meta ->
      %{meta | looking_for_match: false}
    end)

    {:noreply,
     assign(socket,
       current_match: nil,
       looking_for_match: false,
       potential_matches: []
     )}
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
  def handle_info({:match_declined, %{from: _from, to: to}}, socket) do
    if to == socket.id do
      # Could show a notification that match was declined
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:match_ended, %{from: _from, to: to}}, socket) do
    if to == socket.id do
      {:noreply, assign(socket, current_match: nil)}
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
    <div
      class="min-h-screen bg-gradient-to-br from-primary/10 via-secondary/10 to-accent/10"
      phx-hook="LocationManager"
      id="location-manager"
    >
      <div class="container py-8 px-4 mx-auto max-w-md">

    <!-- Header Section with Animation -->
        <div class="mb-8 text-center">
          <div class="inline-flex justify-center items-center mb-4 w-20 h-20 bg-gradient-to-r rounded-full shadow-lg from-primary to-secondary">
            <svg class="w-10 h-10 text-white animate-pulse" fill="currentColor" viewBox="0 0 20 20">
              <path
                fill-rule="evenodd"
                d="M18 10c0 3.866-3.582 7-8 7a8.841 8.841 0 01-4.083-.98L2 17l1.338-3.123C2.493 12.767 2 11.434 2 10c0-3.866 3.582-7 8-7s8 3.134 8 7zM7 9H5v2h2V9zm8 0h-2v2h2V9zM9 9h2v2H9V9z"
                clip-rule="evenodd"
              />
            </svg>
          </div>
          <h1 class="mb-2 text-4xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-primary to-secondary">
            Word Bump
          </h1>
          <p class="mx-auto max-w-sm text-sm leading-relaxed text-base-content/70">
            Find your word twin nearby! 🎯<br />
            Enter a word and discover who's thinking the same thing around you.
          </p>
        </div>

    <!-- Main Card -->
        <div class="border shadow-2xl card bg-base-100 border-base-300/50 backdrop-blur-sm">
          <div class="p-6 space-y-6 card-body">

    <!-- Word Input Section -->
            <div class="form-control">
              <label class="label">
                <span class="font-medium label-text">What's on your mind?</span>
                <%= if String.length(@word) > 0 do %>
                  <span class="label-text-alt text-success">✨ {String.length(@word)} chars</span>
                <% end %>
              </label>
              <div class="relative">
                <input
                  type="text"
                  placeholder="pizza, coffee, adventure..."
                  class="pr-12 w-full transition-all duration-200 input input-bordered input-lg focus:input-primary"
                  value={@word}
                  phx-keyup="update_word"
                  phx-debounce="300"
                  name="word"
                />
                <%= if String.length(@word) > 0 do %>
                  <div class="absolute right-3 top-1/2 transform -translate-y-1/2">
                    <div class="w-3 h-3 rounded-full animate-ping bg-success"></div>
                  </div>
                <% end %>
              </div>
            </div>

    <!-- Location Section -->
            <div class="divider divider-primary">Location</div>

            <%= if @location do %>
              <div class="shadow-lg alert alert-success">
                <div class="flex items-center">
                  <svg
                    class="w-6 h-6 animate-bounce"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"
                    />
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M15 11a3 3 0 11-6 0 3 3 0 016 0z"
                    />
                  </svg>
                  <div class="ml-3">
                    <h3 class="font-bold">Location locked in! 📍</h3>
                    <div class="text-xs opacity-80">Ready to find matches nearby</div>
                  </div>
                </div>
              </div>
            <% else %>
              <%= if @location_error do %>
                <div class="mb-4 shadow-lg alert alert-error">
                  <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.732-.833-2.5 0L4.268 15.5c-.77.833.192 2.5 1.732 2.5z"
                    />
                  </svg>
                  <div>
                    <h3 class="font-bold">Location Error</h3>
                    <div class="text-xs">{@location_error}</div>
                  </div>
                </div>
              <% end %>

              <button
                class="w-full shadow-lg transition-all duration-200 hover:shadow-xl btn btn-primary btn-lg group"
                phx-click="get_location"
              >
                <svg
                  class="w-5 h-5 group-hover:animate-spin"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"
                  />
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M15 11a3 3 0 11-6 0 3 3 0 016 0z"
                  />
                </svg>
                Share My Location
              </button>
            <% end %>

    <!-- Looking for Match Toggle -->
            <%= if @location != nil and String.length(@word) > 0 do %>
              <div class="divider divider-secondary">Matching</div>

              <div class="form-control">
                <label class="p-4 bg-gradient-to-r rounded-xl transition-all duration-200 cursor-pointer label from-base-200/50 to-base-300/30 hover:from-base-200 hover:to-base-300">
                  <div class="flex items-center">
                    <div class="mr-3 w-3 h-3 rounded-full animate-pulse bg-primary"></div>
                    <div>
                      <span class="font-semibold label-text">Start matching for "{@word}"</span>
                      <div class="mt-1 text-xs opacity-70">
                        <%= if @looking_for_match do %>
                          🔍 Actively searching...
                        <% else %>
                          💤 Tap to start looking
                        <% end %>
                      </div>
                    </div>
                  </div>
                  <input
                    type="checkbox"
                    class="toggle toggle-primary toggle-lg"
                    checked={@looking_for_match}
                    phx-click="toggle_looking"
                  />
                </label>
              </div>
            <% end %>
          </div>
        </div>

    <!-- Potential Matches Section -->
        <%= if @looking_for_match and length(@potential_matches) > 0 do %>
          <div class="mt-6">
            <div class="flex justify-between items-center mb-4">
              <h3 class="text-lg font-bold text-primary">Word Twins Found! 🎉</h3>
              <div class="badge badge-primary badge-lg">{length(@potential_matches)}</div>
            </div>

            <div class="space-y-3">
              <%= for {match, index} <- Enum.with_index(@potential_matches) do %>
                <div
                  class="bg-gradient-to-r border shadow-lg transition-all duration-300 hover:shadow-xl card from-primary/5 to-secondary/5 border-primary/20 animate-fade-in"
                  style={"animation-delay: #{index * 100}ms"}
                >
                  <div class="p-4 card-body">
                    <div class="flex justify-between items-center">
                      <div class="flex items-center space-x-3">
                        <div class="avatar placeholder">
                          <div class="w-12 h-12 text-white bg-gradient-to-r rounded-full from-primary to-secondary">
                            <span class="text-xl">🧠</span>
                          </div>
                        </div>
                        <div>
                          <div class="font-bold text-base-content">Anonymous Thinker</div>
                          <div class="flex items-center text-sm opacity-70">
                            <svg class="mr-1 w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                              <path
                                fill-rule="evenodd"
                                d="M5.05 4.05a7 7 0 119.9 9.9L10 18.9l-4.95-4.95a7 7 0 010-9.9zM10 11a2 2 0 100-4 2 2 0 000 4z"
                                clip-rule="evenodd"
                              />
                            </svg>
                            {Float.round(match.distance, 1)} km away
                          </div>
                          <div class="mt-1 text-xs font-medium text-primary">
                            Also thinking: "{match.word}" ✨
                          </div>
                        </div>
                      </div>
                      <button
                        class="shadow-md transition-all duration-200 hover:shadow-lg btn btn-primary btn-sm group"
                        phx-click="request_match"
                        phx-value-user_id={match.id}
                      >
                        <svg
                          class="w-4 h-4 group-hover:animate-pulse"
                          fill="none"
                          stroke="currentColor"
                          viewBox="0 0 24 24"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"
                          />
                        </svg>
                        Connect
                      </button>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

    <!-- Current Match Section -->
        <%= if @current_match do %>
          <div class="mt-6">
            <div class="bg-gradient-to-r border-2 shadow-2xl card from-success/10 to-info/10 border-success/30">
              <div class="p-6 card-body">
                <div class="text-center">
                  <div class="flex justify-center items-center mx-auto mb-4 w-16 h-16 bg-gradient-to-r rounded-full animate-pulse from-success to-info">
                    <span class="text-2xl">🎯</span>
                  </div>
                  <h3 class="mb-2 text-xl font-bold text-success">Perfect Match! 🎉</h3>
                  <p class="mb-4 text-base-content/80">
                    You're connected with someone who's also thinking about "<span class="font-bold text-primary">{@word}</span>"
                  </p>

                  <%= if get_match_location(@current_match) do %>
                    <% match_loc = get_match_location(@current_match) %>
                    <div class="p-3 mb-4 rounded-lg bg-base-200/50">
                      <div class="mb-1 text-xs text-base-content/70">Their approximate location:</div>
                      <div class="font-mono text-sm">
                        📍 {Float.round(match_loc.lat, 4)}, {Float.round(match_loc.lng, 4)}
                      </div>
                    </div>
                  <% end %>

                  <button class="btn btn-outline btn-error btn-sm" phx-click="end_match">
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M6 18L18 6M6 6l12 12"
                      />
                    </svg>
                    End Match
                  </button>
                </div>
              </div>
            </div>
          </div>
        <% end %>

    <!-- Status Messages -->
        <%= if @looking_for_match and length(@potential_matches) == 0 and String.length(@word) > 0 do %>
          <div class="mt-6">
            <div class="shadow-lg alert alert-info">
              <div class="flex items-center">
                <div class="loading loading-spinner loading-md text-info"></div>
                <div class="ml-3">
                  <div class="font-bold">Searching for word twins...</div>
                  <div class="text-xs opacity-80">Looking for people with "{@word}" within 5km</div>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>

    <!-- Match Request Modal -->
      <%= if @show_match_modal and length(@match_requests) > 0 do %>
        <div class="modal modal-open">
          <div class="relative bg-gradient-to-br border modal-box from-base-100 to-base-200 border-primary/20">
            <div class="mb-6 text-center">
              <div class="flex justify-center items-center mx-auto mb-4 w-16 h-16 bg-gradient-to-r rounded-full animate-bounce from-primary to-secondary">
                <span class="text-2xl">💫</span>
              </div>
              <h3 class="text-2xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-primary to-secondary">
                Match Request!
              </h3>
            </div>

            <%= for request <- @match_requests do %>
              <div class="p-6 mb-4 rounded-xl border bg-base-100 border-base-300/50">
                <div class="text-center">
                  <p class="mb-6 text-lg">
                    Someone nearby wants to connect over the word
                    <span class="font-bold text-primary">"{request.word}"</span>
                    ✨
                  </p>

                  <div class="flex flex-col gap-3 justify-center sm:flex-row">
                    <button
                      class="flex-1 shadow-lg transition-all duration-200 hover:shadow-xl btn btn-primary btn-lg"
                      phx-click="accept_match"
                      phx-value-requester_id={request.from}
                    >
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"
                        />
                      </svg>
                      Accept Match
                    </button>
                    <button
                      class="flex-1 btn btn-outline btn-lg"
                      phx-click="decline_match"
                      phx-value-requester_id={request.from}
                    >
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M6 18L18 6M6 6l12 12"
                        />
                      </svg>
                      Decline
                    </button>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
          <div class="modal-backdrop" phx-click="close_match_modal"></div>
        </div>
      <% end %>

      <style>
        @keyframes fade-in {
          from { opacity: 0; transform: translateY(20px); }
          to { opacity: 1; transform: translateY(0); }
        }
        .animate-fade-in {
          animation: fade-in 0.5s ease-out forwards;
          opacity: 0;
        }
      </style>
    </div>
    """
  end
end
