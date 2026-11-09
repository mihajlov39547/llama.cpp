globalThis.BetterFacebook = Object.freeze({
  defaults: Object.freeze({ enabled: true, focus: false, textSize: "default" }),
  normalize(value = {}) {
    if (!value || typeof value !== "object") value = {};
    return {
      enabled: typeof value.enabled === "boolean" ? value.enabled : true,
      focus: typeof value.focus === "boolean" ? value.focus : false,
      textSize: ["default", "comfortable", "large"].includes(value.textSize)
        ? value.textSize : "default"
    };
  }
});
