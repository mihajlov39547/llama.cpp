(() => {
  'use strict';
  const { defaults, settings, validatePrompt, validateRefinement, ApiError } = globalThis.PromptEnhancerSettings;
  async function run(prompt, rawSettings, {
    signal, fetchImpl = fetch, testOnly = false, mode = 'improve', previousImprovement
  } = {}) {
    const config = settings(rawSettings);
    if (!['improve', 'refine'].includes(mode)) throw new ApiError('INPUT', 'Unknown request mode.');
    const refining = mode === 'refine';
    if (!testOnly) {
      if (refining) validateRefinement(prompt, previousImprovement, config);
      else validatePrompt(prompt, config);
    }
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
        model, stream: false,
        temperature: refining ? Math.min(config.temperature + 0.1, 2.0) : config.temperature,
        max_tokens: config.maxTokens,
        messages: [
          { role: 'system', content: refining ? globalThis.PromptEnhancerRefinementInstruction : globalThis.PromptEnhancerInstruction },
          { role: 'user', content: refining ? globalThis.buildPromptEnhancerRefinement(prompt, previousImprovement) : prompt }
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
      // Validate emptiness above without stripping indentation or trailing
      // blank lines from a code-containing rewrite.
      return { text: text.replace(/\r\n?/g, '\n'), model };
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
