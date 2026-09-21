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

  "pre-mortem": {
    name: "Pre-Mortem",
    vars: {
      bg: "#0e1114",
      card: "#171b20",
      card2: "#20262c",
      line: "#3a4046",
      text: "#e8e1d1",
      textSoft: "#c9c2b3",
      muted: "#9aa4ae",
      accent: "#d9453f",
      accentSoft: "rgba(217, 69, 63, 0.14)",
      accentFaint: "rgba(217, 69, 63, 0.08)",
      accentEdge: "rgba(217, 69, 63, 0.42)",
      accentContrast: "#ffffff",
      good: "#7fb069",
      danger: "#f08c3c",
    },
    ramp: ["#d9453f", "#c9973b", "#e8e1d1", "#8fa3c8", "#a3c47a", "#9aa4ae", "#d98cb0", "#7fb3a8"],
    font: {
      family: "'Archivo', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
      googleFonts: "https://fonts.googleapis.com/css2?family=Archivo:wght@400;600;800;900&display=swap",
    },
    qr: { dark: "#0e1114", light: "#ffffff" },
  },
};
