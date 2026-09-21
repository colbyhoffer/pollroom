/* PollRoom themes.
   Each entry restyles every surface: audience phones, the presenter
   console, and the presentation screen. Add new themes by copying an
   entry (see THEME-TEMPLATE.md for a fill-in template you can hand to
   Claude), then pick the theme in the presenter console.
   The "default" entry must always exist. */
window.POLLROOM_THEMES = {
  "default": {
    name: "PollRoom Dark",
    vars: {
      bg: "#10141b",
      card: "#1a212c",
      card2: "#212a37",
      line: "#2c3646",
      text: "#edf1f7",
      textSoft: "#b9c2ce",
      muted: "#8b96a5",
      accent: "#ff7a2e",
      accentSoft: "rgba(255, 122, 46, 0.14)",
      accentFaint: "rgba(255, 122, 46, 0.10)",
      accentEdge: "rgba(255, 122, 46, 0.4)",
      accentContrast: "#17110c",
      good: "#43c6ac",
      danger: "#e05b5b",
    },
    ramp: ["#ff7a2e", "#43c6ac", "#f2c94c", "#6c9bf2", "#e86aa6", "#9b7bf2", "#57b75e", "#e05b5b"],
    font: {
      family: "'Archivo', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
      googleFonts: "https://fonts.googleapis.com/css2?family=Archivo:wght@400;600;800;900&display=swap",
    },
    qr: { dark: "#10141b", light: "#ffffff" },
  },

  "longhorn-light": {
    name: "Longhorn Light",
    vars: {
      bg: "#f5f2ec",
      card: "#ffffff",
      card2: "#efece4",
      line: "#dcd6c8",
      text: "#221f1a",
      textSoft: "#4c463c",
      muted: "#6d675c",
      accent: "#bf5700",
      accentSoft: "rgba(191, 87, 0, 0.12)",
      accentFaint: "rgba(191, 87, 0, 0.07)",
      accentEdge: "rgba(191, 87, 0, 0.45)",
      accentContrast: "#ffffff",
      good: "#1d7a68",
      danger: "#c23b2e",
    },
    ramp: ["#bf5700", "#1d7a68", "#a8790f", "#3b6fc4", "#b0447e", "#6d4fc0", "#3f7d3a", "#c23b2e"],
    font: {
      family: "'Archivo', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
      googleFonts: "https://fonts.googleapis.com/css2?family=Archivo:wght@400;600;800;900&display=swap",
    },
    qr: { dark: "#221f1a", light: "#ffffff" },
  },
};
