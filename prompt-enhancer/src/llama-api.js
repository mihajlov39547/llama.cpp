(() => {
  'use strict';
  const defaults = Object.freeze({
    baseUrl: 'http://127.0.0.1:8080', temperature: 0.2,
    maxTokens: 2048, timeoutMs: 60000, maxInputLength: 20000
  });
  class ApiError extends Error {
    constructor(code, message) { super(message); this.code = code; }
  }
  function settings(value = {}) {
    const result = { ...defaults, ...value };
    if (result.baseUrl !== defaults.baseUrl) {
      throw new ApiError('SETTINGS', 'This MVP only permits http://127.0.0.1:8080.');
    }
    for (const [key, min, max, integer] of [
      ['temperature', 0, 2, false], ['maxTokens', 1, 4096, true],
      ['timeoutMs', 1000, 60000, true], ['maxInputLength', 1, 20000, true]
    ]) {
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
  async function run(prompt, rawSettings, { signal, fetchImpl = fetch, testOnly = false } = {}) {
    const config = settings(rawSettings);
    if (!testOnly) validatePrompt(prompt, config);
    const controller = new AbortController();
    let timedOut = false;
    const abort = () => controller.abort();
    signal?.addEventListener('abort', abort, { once: true });
    if (signal?.aborted) abort();
    const timer = setTimeout(() => { timedOut = true; abort(); }, config.timeoutMs);
    async function json(path, body) {
      const response = await fetchImpl(config.baseUrl + path, {
        method: body ? 'POST' : 'GET', signal: controller.signal,
        credentials: 'omit', cache: 'no-store', redirect: 'error',
        headers: { Accept: 'application/json', ...(body ? { 'Content-Type': 'application/json' } : {}) },
        ...(body ? { body: JSON.stringify(body) } : {})
      });
      if (!response.ok) {
        throw new ApiError('HTTP', `Local server returned HTTP ${response.status}. ${
          response.status === 503 ? 'The model may still be loading or unavailable.' : 'Check the llama-server console.'
        }`);
      }
      try { return await response.json(); }
      catch (error) {
        if (controller.signal.aborted) throw error;
        throw new ApiError('JSON', 'The local server returned invalid JSON.');
      }
    }
    try {
      const models = await json('/v1/models');
      const model = Array.isArray(models?.data) ?
        models.data.find(item => typeof item?.id === 'string' && item.id.trim())?.id : null;
      if (!model) throw new ApiError('MODEL', 'No model is available. Start llama-server with a loaded GGUF model.');
      if (testOnly) return { model };
      const data = await json('/v1/chat/completions', {
        model, stream: false, temperature: config.temperature, max_tokens: config.maxTokens,
        messages: [
          { role: 'system', content: globalThis.PromptEnhancerInstruction },
          { role: 'user', content: prompt }
        ]
      });
      const choice = data?.choices?.[0];
      if (choice?.finish_reason === 'length') {
        throw new ApiError('TRUNCATED', 'The rewrite hit the output limit. Shorten the prompt or increase max output tokens in options.');
      }
      const text = choice?.message?.content;
      if (typeof text !== 'string' || !text.trim()) {
        throw new ApiError('EMPTY', 'The local model returned no usable text.');
      }
      return { text: text.trim(), model };
    } catch (error) {
      if (timedOut) throw new ApiError('TIMEOUT', 'Local model request timed out. Retry or use a faster model.');
      if (controller.signal.aborted) throw new ApiError('CANCELLED', 'Request cancelled.');
      if (error instanceof ApiError) throw error;
      throw new ApiError('NETWORK', 'Cannot reach the local server. Check that llama-server is running on 127.0.0.1:8080.');
    } finally {
      clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
    }
  }
  globalThis.PromptEnhancerAPI = { defaults, settings, validatePrompt, run, ApiError };
})();
