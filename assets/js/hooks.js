let Hooks = {};

Hooks.LocationManager = {
  mounted() {
    // Load word from localStorage on mount
    const savedWord = localStorage.getItem("word_bump_word");
    if (savedWord) {
      this.pushEvent("update_word", { word: savedWord });
    }

    // Save word to localStorage when it changes
    this.handleEvent("word_updated", ({ word }) => {
      localStorage.setItem("word_bump_word", word);
    });

    // Handle location requests
    this.handleEvent("get_location", () => {
      if (navigator.geolocation) {
        navigator.geolocation.getCurrentPosition(
          (position) => {
            this.pushEvent("location_received", {
              lat: position.coords.latitude,
              lng: position.coords.longitude,
            });
          },
          (error) => {
            let errorMessage = "Location access denied";
            switch (error.code) {
              case error.PERMISSION_DENIED:
                errorMessage = "Location access denied by user";
                break;
              case error.POSITION_UNAVAILABLE:
                errorMessage = "Location information unavailable";
                break;
              case error.TIMEOUT:
                errorMessage = "Location request timed out";
                break;
            }
            this.pushEvent("location_error", { error: errorMessage });
          },
          {
            enableHighAccuracy: true,
            timeout: 10000,
            maximumAge: 300000, // 5 minutes
          },
        );
      } else {
        this.pushEvent("location_error", {
          error: "Geolocation is not supported by this browser",
        });
      }
    });
  },
};

export default Hooks;
