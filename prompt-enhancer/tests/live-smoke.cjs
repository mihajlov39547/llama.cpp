// Optional: sends only this synthetic prompt to the locally running server.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
for (const file of ['settings.js', 'prompt-template.js', 'llama-api.js']) {
  vm.runInThisContext(fs.readFileSync(path.join(__dirname, '../src', file), 'utf8'), { filename: file });
}
PromptEnhancerAPI.run('please explain how a javascript array works. keep it short and use one example.')
  .then(result => {
    console.log(JSON.stringify({ ok: true, model: result.model, text: result.text }, null, 2));
  })
  .catch(error => {
    console.error(JSON.stringify({ ok: false, code: error.code, message: error.message }));
    process.exitCode = 1;
  });
