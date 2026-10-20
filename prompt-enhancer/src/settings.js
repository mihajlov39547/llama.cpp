(() => {
  'use strict';
  const limits = Object.freeze({
    temperature: Object.freeze({ min: 0, max: 2, step: 0.1 }),
    maxTokens: Object.freeze({ min: 1, max: 4096, integer: true }),
    timeoutMs: Object.freeze({ min: 1000, max: 60000, integer: true }),
    maxInputLength: Object.freeze({ min: 1, max: 20000, integer: true })
  });
  const defaults = Object.freeze({
    baseUrl: 'http://127.0.0.1:8080', temperature: 0.2,
    maxTokens: 2048, timeoutMs: limits.timeoutMs.max, maxInputLength: limits.maxInputLength.max
  });
  class ApiError extends Error {
    constructor(code, message) { super(message); this.code = code; }
  }
  function settings(value = {}) {
    const result = { ...defaults, ...value };
    if (result.baseUrl !== defaults.baseUrl) {
      throw new ApiError('SETTINGS', `This MVP only permits ${defaults.baseUrl}.`);
    }
    for (const [key, { min, max, integer }] of Object.entries(limits)) {
      if (!Number.isFinite(result[key]) || result[key] < min || result[key] > max ||
          (integer && !Number.isInteger(result[key]))) {
        throw new ApiError('SETTINGS', `Invalid setting: ${key}.`);
      }
    }
    return result;
  }
  function validatePrompt(prompt, config) {
    if (typeof prompt !== 'string' || !prompt.trim()) {
      throw new ApiError('INPUT', 'Enter a prompt first.');
    }
    if (prompt.length > config.maxInputLength) {
      throw new ApiError('INPUT', `Prompt exceeds ${config.maxInputLength.toLocaleString()} characters.`);
    }
  }
  const maxPreviousImprovementLength = limits.maxInputLength.max;
  function validateRefinement(originalPrompt, previousImprovement, config) {
    validatePrompt(originalPrompt, config);
    if (typeof previousImprovement !== 'string' || !previousImprovement.trim()) {
      throw new ApiError('INPUT', 'A previous improvement is required to refine further.');
    }
    if (previousImprovement.length > maxPreviousImprovementLength) {
      throw new ApiError('INPUT', `Previous improvement exceeds ${maxPreviousImprovementLength.toLocaleString()} characters. Copy it or start a new improvement with a shorter draft.`);
    }
  }
  globalThis.PromptEnhancerSettings = {
    defaults, limits, settings, validatePrompt, validateRefinement, maxPreviousImprovementLength, ApiError,
    responseTimeoutMs: limits.timeoutMs.max + 5000
  };
})();
