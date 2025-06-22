# Word Bump 🔥

Ever wondered who else around you is thinking about the same random word? Word Bump is here to help you find out!

## What's this about?

Word Bump is a fun little app that connects people who happen to be thinking about the same word and are close to each other. It's like Tinder, but for words and way less awkward.

Here's how it works:
- You enter a word (any word!)
- The app grabs your location (with your permission, of course)
- It looks for other people nearby who entered the same word
- If there's a match, you can request to connect
- If they accept, you both get to see each other's location

Perfect for finding that person who's also obsessing over "pizza" at 2 AM or wondering about "existentialism" on a Tuesday.

## Tech Stack

Built with Phoenix LiveView because real-time is the only way to live:
- **Phoenix LiveView** - For that sweet real-time magic
- **Phoenix Presence** - Tracks who's around and what they're thinking
- **DaisyUI** - Makes it look pretty without the CSS headache
- **Geolocation API** - Finds where you are (approximately)
- **localStorage** - Remembers your word because nobody wants to retype "supercalifragilisticexpialidocious"

## Getting Started

1. Make sure you have Elixir and Phoenix installed
2. Clone this repo
3. Install dependencies: `mix deps.get`
4. Install JS dependencies: `npm install --prefix assets`
5. Start the server: `mix phx.server`
6. Open `http://localhost:4000` and start bumping words!

## Features

- **Real-time matching** - See potential matches as they appear
- **Location-based** - Only matches people within 5km (configurable)
- **Privacy-first** - No data persistence, everything lives in memory
- **Mobile-friendly** - Works great on your phone
- **Super simple** - Just enter a word and let the magic happen

## How to Use

1. Enter any word that's on your mind
2. Allow location access (we promise we're not tracking you)
3. Toggle "Looking for matches" when you're ready
4. Wait for someone nearby to think the same word
5. Send a match request or accept incoming ones
6. Meet up with your word twin!

## Privacy & Safety

- No data is stored permanently
- Your exact location is only shared with confirmed matches
- You can end matches anytime
- The app only works within a 5km radius for safety

## Contributing

Found a bug? Have an idea? Want to add more word-matching magic? Pull requests are welcome! Just keep it simple and fun.

## License

AGPL-3.0 - Use this code however you want, just don't blame me if it breaks.

---

*Remember: With great word power comes great responsibility. Use your words wisely!*
