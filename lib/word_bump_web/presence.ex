defmodule WordBumpWeb.Presence do
  use Phoenix.Presence,
    otp_app: :word_bump,
    pubsub_server: WordBump.PubSub
end
