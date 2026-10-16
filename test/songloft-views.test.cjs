'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(process.env.SONGLOFT_TEST_ROOT || process.argv[2] || path.join(__dirname, '..'));
const packageRoot = path.join(root, 'openwrt/luci-app-songloft');
const read = (file) => fs.readFileSync(path.join(packageRoot, file), 'utf8');
const templates = {
  log: read('luasrc/view/songloft/songloft_log.htm'),
  status: read('luasrc/view/songloft/songloft_status.htm')
};
const controller = read('luasrc/controller/songloft.lua');
const cbi = read('luasrc/model/cbi/songloft.lua');
const css = read('htdocs/luci-static/resources/view/songloft.css');
const endpoint = (name) => '/cgi-bin/luci/admin/services/songloft/' + name;
const section = 'cfg &/?#=+汉字';
const token = 'token &/?#=+汉字';
const logFailure = 'Unable to read the latest log file. Please refresh and try again.';
const actionFailure = 'Service operation failed. Check the executable, configuration and system log.';
const logReply = {
  directory: '/mnt/music/data/logs', file: 'latest.any-name',
  modified: 1700000000, content: 'line one\nline two\n', truncated: false
};

// Execute the actual template JS, not a reimplementation of its behavior.
// Only known Lua expressions are substituted; unexpected expressions fail closed.
function renderScript(kind, currentSection = section) {
  const source = templates[kind].match(/<script\b[^>]*>([\s\S]*?)<\/script>/);
  assert.ok(source, 'Template must contain an inline script');
  const ids = {
    section: currentSection,
    status_id: `cbid.songloft.${currentSection}._status`,
    control_id: `cbid.songloft.${currentSection}._actions`,
    'self:cbid(section)': `cbid.songloft.${currentSection}._logs`
  };
  const rendered = source[1].replace(/<%=([\s\S]*?)%>/g, (_, expression) => {
    const value = expression.trim();
    if (value === 'resource') return '/luci-static/resources';
    if (value === 'token') return token;
    const route = value.match(/^url\(\[\[admin\]\], \[\[services\]\], \[\[songloft\]\], \[\[(log|status|action)\]\]\)$/);
    if (route) return endpoint(route[1]);
    const translation = value.match(/^json\.stringify\(translate\(("(?:[^"\\]|\\.)*")\)\)$/);
    if (translation) return JSON.stringify(JSON.parse(translation[1]));
    const identifier = value.match(/^json\.stringify\((.*)\)$/);
    if (identifier && Object.hasOwn(ids, identifier[1])) {
      return JSON.stringify(ids[identifier[1]]);
    }
    throw new Error(`Unsupported template expression: ${value}`);
  });
  assert.ok(!rendered.includes('<%'), 'All template expressions must be replaced');
  return new vm.Script(rendered, { filename: `songloft_${kind}.htm.rendered.js` });
}

class Element {
  constructor(tagName = 'div', attributes = {}) {
    this.tagName = tagName;
    this.attributes = attributes;
    this.children = [];
    this.listeners = new Map();
    this.selectors = new Map();
    this.disabled = false;
    this.hidden = false;
    this.value = '';
    this.className = '';
    this.scrollTop = 0;
    this.scrollHeight = 456;
    this._text = '';
  }
  set textContent(value) {
    this._text = String(value);
    this.children = [];
  }
  get textContent() {
    return this._text + this.children.map((child) => child.textContent).join('');
  }
  set innerHTML(_) { throw new Error('Unsafe HTML sink'); }
  set outerHTML(_) { throw new Error('Unsafe HTML sink'); }
  insertAdjacentHTML() { throw new Error('Unsafe HTML sink'); }
  getAttribute(name) { return this.attributes[name] ?? null; }
  appendChild(child) { this.children.push(child); return child; }
  querySelector(selector) {
    assert.ok(this.selectors.has(selector), `Unexpected selector: ${selector}`);
    return this.selectors.get(selector);
  }
  querySelectorAll(selector) { return this.querySelector(selector); }
  addEventListener(name, callback) { this.listeners.set(name, callback); }
  // Deliberately dispatch even when disabled to exercise handler-level guards.
  click() { this.listeners.get('click').call(this); }
}

class FixedDate extends Date {
  toLocaleString() { return this.toISOString(); }
}

// No real DOM, network, timers, services, process or filesystem in the VM.
function environment({ readonly = false, hostname = 'router.example' } = {}) {
  const elements = new Map();
  const head = new Element('head');
  const document = {
    head,
    getElementById(id) {
      return elements.get(id) || head.children.find((child) => child.id === id) || null;
    },
    createElement(tag) {
      assert.ok(['span', 'link'].includes(tag), `Unexpected element: ${tag}`);
      return new Element(tag);
    }
  };
  const requests = [];
  class XMLHttpRequest {
    constructor() { this.headers = {}; requests.push(this); }
    open(method, url, async) { Object.assign(this, { method, url, async }); }
    setRequestHeader(name, value) { this.headers[name] = value; }
    send(body) { this.body = body; this.sent = true; }
    load(reply, status = 200, raw = false) {
      this.status = status;
      this.responseText = raw ? reply : JSON.stringify(reply);
      this.onload();
    }
    finish(reply, status = 200, raw = false) {
      this.load(reply, status, raw);
      this.onloadend();
    }
    fail(type) {
      assert.ok(['error', 'timeout'].includes(type));
      this.status = 0;
      this.responseText = '';
      if (this['on' + type]) this['on' + type]();
      this.onloadend();
    }
  }
  const polls = [];
  const opened = [];
  let now = 0, nextTimer = 0;
  const timers = new Map();
  const context = vm.createContext({
    document, XMLHttpRequest, Date: FixedDate, JSON, URL, encodeURIComponent,
    setTimeout(callback, delay) {
      const id = ++nextTimer;
      timers.set(id, { callback, at: now + delay });
      return id;
    },
    clearTimeout(id) { timers.delete(id); },
    L: { hasViewPermission: () => !readonly },
    XHR: { poll(interval, url, body, callback) { polls.push({ interval, url, body, callback }); } },
    window: {
      location: { hostname },
      open(...args) { opened.push(args); }
    }
  });
  return {
    elements, head, requests, polls, opened,
    advance(milliseconds) {
      now += milliseconds;
      for (const [id, timer] of timers) {
        if (timer.at <= now) {
          timers.delete(id);
          timer.callback();
        }
      }
    },
    run(kind, currentSection) { renderScript(kind, currentSection).runInContext(context, { timeout: 1000 }); }
  };
}

function logWidget(env = environment(), currentSection = section) {
  const view = new Element();
  const nodes = {};
  for (const name of ['refresh', 'info', 'path', 'notice', 'content']) {
    nodes[name] = new Element(name === 'content' ? 'textarea' : 'div');
    view.selectors.set(`[data-${name}]`, nodes[name]);
  }
  nodes.notice.hidden = true;
  const textareaTag = templates.log.match(/<textarea\b(?:[^"'>]|"[^"]*"|'[^']*')*>/)[0];
  nodes.content.readOnly = /\breadonly\b/.test(textareaTag);
  env.elements.set(`cbid.songloft.${currentSection}._logs`, view);
  env.run('log', currentSection);
  return {
    env, nodes,
    click() { nodes.refresh.click(); },
    finish(reply = logReply, status = 200, raw = false) { env.requests.at(-1).finish(reply, status, raw); }
  };
}

function statusWidget(options = {}, env = environment(options), currentSection = section) {
  const status = new Element();
  const controls = new Element();
  const error = new Element();
  error.hidden = true;
  const buttons = {};
  for (const action of ['start', 'stop', 'restart', 'open']) {
    buttons[action] = new Element('button', { 'data-action': action });
    buttons[action].disabled = true;
  }
  controls.selectors.set('button[data-action]', Object.values(buttons));
  controls.selectors.set('[data-error]', error);
  env.elements.set(`cbid.songloft.${currentSection}._status`, status);
  env.elements.set(`cbid.songloft.${currentSection}._actions`, controls);
  env.run('status', currentSection);
  const poll = env.polls.at(-1);
  return {
    env, status, error, buttons,
    poll(reply) { poll.callback({}, reply); },
    update(data = {}) { poll.callback({}, { sections: { [currentSection]: data } }); },
    click(action) { buttons[action].click(); }
  };
}

function assertButtons(widget, enabled) {
  for (const [name, button] of Object.entries(widget.buttons)) {
    assert.equal(button.disabled, !enabled.includes(name), name);
  }
}

// The original 27 log checks, retained as isolated cases.
test('log: rendered JavaScript syntax', () => { renderScript('log'); });

test('log: initial asynchronous GET encodes section, no body, 15 second timeout', () => {
  const { env } = logWidget();
  assert.equal(env.requests.length, 1);
  const request = env.requests[0];
  assert.equal(request.method, 'GET');
  assert.equal(request.url, endpoint('log') + '?section=' + encodeURIComponent(section));
  assert.equal(request.async, true);
  assert.equal(request.body, null);
  assert.equal(request.timeout, 15000);
});

test('log: no client file selection or secondary request', () => {
  assert.doesNotMatch(templates.log, /FileReader|fetch\(|\.sort\(|\.filter\(|type\s*=\s*["']file|localStorage/);
  assert.doesNotMatch(templates.log, /<select\b|data-action=.*file/);
  const widget = logWidget();
  widget.finish();
  assert.equal(widget.env.requests.length, 1);
  assert.equal(new URL(widget.env.requests[0].url, 'https://stub.invalid').searchParams.size, 1);
});

test('log: initial busy disables refresh and displays loading', () => {
  const { nodes } = logWidget();
  assert.equal(nodes.refresh.disabled, true);
  assert.equal(nodes.info.textContent, 'Collecting data...');
  assert.equal(nodes.notice.hidden, true);
});

test('log: busy handler calls deduplicate', () => {
  const widget = logWidget();
  widget.click(); widget.click(); widget.click();
  assert.equal(widget.env.requests.length, 1);
});

test('log: load alone stays busy until loadend', () => {
  const widget = logWidget();
  widget.env.requests[0].load(logReply);
  widget.click();
  assert.equal(widget.nodes.refresh.disabled, true);
  assert.equal(widget.env.requests.length, 1);
  widget.env.requests[0].onloadend();
  assert.equal(widget.nodes.refresh.disabled, false);
  widget.click();
  assert.equal(widget.env.requests.length, 2);
});

test('log: Refresh repeats GET and reads new response', () => {
  const widget = logWidget();
  widget.finish(); widget.click();
  assert.equal(widget.env.requests.length, 2);
  assert.equal(widget.env.requests[1].url, widget.env.requests[0].url);
  assert.equal(widget.env.requests[1].method, 'GET');
  assert.equal(widget.nodes.refresh.disabled, true);
  widget.finish({ ...logReply, content: 'read again' });
  assert.equal(widget.nodes.content.value, 'read again');
  widget.click();
  assert.equal(widget.env.requests.length, 3);
});

for (const mode of ['malformed JSON', 'network error', 'timeout', 'HTTP 500']) {
  test(`log: ${mode} clears stale data, enables retry`, () => {
    const widget = logWidget();
    widget.finish({ ...logReply, truncated: true }); widget.click();
    if (mode === 'malformed JSON') widget.finish('{bad', 200, true);
    else if (mode === 'HTTP 500') widget.finish(logReply, 500);
    else widget.env.requests.at(-1).fail(mode === 'timeout' ? 'timeout' : 'error');
    assert.equal(widget.nodes.info.textContent, logFailure);
    assert.equal(widget.nodes.content.value, '');
    assert.equal(widget.nodes.path.textContent, '');
    assert.equal(widget.nodes.notice.hidden, true);
    assert.equal(widget.nodes.refresh.disabled, false);
    widget.click();
    assert.equal(widget.env.requests.length, 3);
    widget.finish();
    assert.equal(widget.nodes.content.value, logReply.content);
  });
}

test('log: populated path, deterministic modified time, exact text and bottom scroll', () => {
  const widget = logWidget(); widget.finish();
  assert.equal(widget.nodes.path.textContent, logReply.directory + '/' + logReply.file);
  assert.equal(widget.nodes.info.textContent, 'Last modified: 2023-11-14T22:13:20.000Z');
  assert.equal(widget.nodes.content.value, logReply.content);
  assert.equal(widget.nodes.content.scrollTop, widget.nodes.content.scrollHeight);
  assert.equal(widget.nodes.notice.hidden, true);
});

test('log: textarea readonly, wrap off, no spellcheck or form submission', () => {
  const tag = templates.log.match(/<textarea\b(?:[^"'>]|"[^"]*"|'[^']*')*>/)[0];
  assert.match(tag, /\breadonly\b/);
  assert.match(tag, /wrap="off"/);
  assert.match(tag, /spellcheck="false"/);
  assert.doesNotMatch(tag, /\bname=/);
  assert.doesNotMatch(templates.log, /\.readOnly\s*=|removeAttribute/);
  const widget = logWidget(); widget.finish();
  assert.equal(widget.nodes.content.readOnly, true);
});

test('log: HTML and closing textarea/script payloads remain inert text', () => {
  const widget = logWidget();
  const payload = '<img src=x onerror=alert(1)></textarea><script>globalThis.pwned=1</script>&"';
  widget.finish({ ...logReply, directory: '/' + payload, file: payload, content: payload });
  assert.equal(widget.nodes.path.textContent, '/' + payload + '/' + payload);
  assert.equal(widget.nodes.content.value, payload);
  assert.doesNotMatch(templates.log, /innerHTML|outerHTML|insertAdjacentHTML|document\.write/);
  assert.equal((templates.log.match(/<script\b/g) || []).length, 1);
  assert.equal((templates.log.match(/<\/textarea>/g) || []).length, 1);
});

for (const [name, content, truncated, message] of [
  ['empty', '', false, 'The latest log file is empty.'],
  ['truncated', 'abc', true, 'Showing only the last 128 KiB of this file.'],
  ['truncated empty', '', true, 'Showing only the last 128 KiB of this file.']
]) {
  test(`log: ${name} hint`, () => {
    const widget = logWidget(); widget.finish({ ...logReply, content, truncated });
    assert.equal(widget.nodes.notice.hidden, false);
    assert.equal(widget.nodes.notice.textContent, message);
    assert.equal(widget.nodes.content.value, content);
  });
}

test('log: latest opaque filename changes after Refresh, previous hint stays hidden', () => {
  const widget = logWidget(); widget.finish({ ...logReply, truncated: true }); widget.click();
  assert.equal(widget.nodes.notice.hidden, true);
  const next = { ...logReply, file: 'older-looking-1999.no-extension', modified: 1700000100, content: 'new latest' };
  widget.finish(next);
  assert.equal(widget.nodes.path.textContent, next.directory + '/' + next.file);
  assert.equal(widget.nodes.content.value, next.content);
  assert.equal(widget.nodes.info.textContent, 'Last modified: 2023-11-14T22:15:00.000Z');
  assert.equal(widget.nodes.notice.hidden, true);
});

for (const [error, message] of Object.entries({
  data_directory_missing: 'Configure and save the data directory first.',
  log_directory_missing: 'The log directory does not exist yet.',
  log_directory_unreadable: 'Unable to read the log directory.',
  no_logs: 'No log files found.',
  invalid_section: logFailure,
  log_read_failed: logFailure
})) {
  test(`log: error mapping ${error}, safe directory and retry`, () => {
    const widget = logWidget(); widget.finish(); widget.click();
    const directory = ['data_directory_missing', 'invalid_section'].includes(error) ? undefined : '/<img onerror=x>/data/logs';
    widget.finish({ error, directory });
    assert.equal(widget.nodes.info.textContent, message);
    assert.equal(widget.nodes.path.textContent, directory || '');
    assert.equal(widget.nodes.content.value, '');
    assert.equal(widget.nodes.notice.hidden, true);
    assert.equal(widget.nodes.refresh.disabled, false);
    widget.click();
    assert.equal(widget.env.requests.length, 3);
  });
}

test('log: null JSON reports generic failure and allows retry', () => {
  const widget = logWidget(); widget.finish(null);
  assert.equal(widget.nodes.info.textContent, logFailure);
  assert.equal(widget.nodes.refresh.disabled, false);
  widget.click();
  assert.equal(widget.env.requests.length, 2);
});

test('log: stylesheet deduplicates repeated template execution', () => {
  const widget = logWidget(); widget.env.run('log', section); widget.env.run('log', section);
  assert.equal(widget.env.head.children.length, 1);
  const link = widget.env.head.children[0];
  assert.equal(link.id, 'songloft-view-stylesheet');
  assert.equal(link.rel, 'stylesheet');
  assert.equal(link.href, '/luci-static/resources/view/songloft.css');
});

test('log: CBI logs tab maps DummyValue to template and saved latest-file description', () => {
  assert.match(cbi, /s:tab\("logs",\s*translate\("Logs"\)\)/);
  assert.match(cbi, /logs\s*=\s*s:taboption\("logs",\s*DummyValue,\s*"_logs"\)/);
  assert.match(cbi, /logs\.template\s*=\s*"songloft\/songloft_log"/);
  assert.match(cbi, /most recently modified regular file.*saved data directory/);
  assert.match(cbi, /last 128 KiB/);
});

test('log: route and no-store support repeated latest reads (source contract only)', () => {
  assert.match(controller, /entry\(\{"admin", "services", "songloft", "log"\}, call\("act_log"\)\)/);
  assert.match(controller, /luci\.http\.header\("Cache-Control", "no-store"\)/);
  assert.match(controller, /latest_log\(luci\.http\.formvalue\("section"\)\)/);
});

test('log: native full-width 18-row textarea inherits LuCI theme styling', () => {
  const tag = templates.log.match(/<textarea\b(?:[^"'>]|"[^"]*"|'[^']*')*>/)[0];
  assert.match(tag, /class="cbi-input-textarea songloft-log-content"/);
  assert.match(tag, /rows="18"/);
  assert.match(tag, /aria-label="<%:Runtime log%>"/);
  const contentStyle = css.match(/\.songloft-log-content\s*\{([^}]*)\}/)[1];
  assert.match(contentStyle, /width:\s*100%/);
  assert.match(contentStyle, /font-family:\s*monospace/);
  assert.doesNotMatch(contentStyle, /(?:height|font-size|line-height|background|color)\s*:/);
});

test('log: full-width field has no left title or flex-row description', () => {
  assert.match(cbi, /logs\s*=\s*s:taboption\("logs",\s*DummyValue,\s*"_logs"\)/);
  assert.match(css, /\.cbi-value\[id\^="cbi-songloft-"\]\[id\$="-_logs"\]\s*\{\s*display:\s*block;/);
  assert.match(css, /\.songloft-log-view\s*\{\s*width:\s*100%;\s*min-width:\s*0;/);
  assert.match(css, /\.songloft-log-path\s*\{/);
  assert.match(css, /overflow-wrap:\s*anywhere/);
});

// Additional backend source contract, not execution of the Lua file selection.
test('log: backend selects regular files by mtime with opaque names (source contract only)', () => {
  const selection = controller.match(/for name in entries do([\s\S]*?)\n\tend/)[1];
  assert.match(selection, /fs\.lstat\(directory \.\. "\/" \.\. name\)/);
  assert.match(selection, /stat\.type == "reg"/);
  assert.match(selection, /stat\.mtime > metadata\.mtime/);
  assert.doesNotMatch(selection, /name:(?:match|find)|tonumber|os\.date/);
});

test('status: rendered JavaScript syntax and initial polling contract', () => {
  renderScript('status');
  const widget = statusWidget();
  assertButtons(widget, []);
  assert.equal(widget.env.requests.length, 0);
  assert.equal(widget.env.polls.length, 1);
  assert.equal(widget.env.polls[0].interval, 3);
  assert.equal(widget.env.polls[0].url, endpoint('status'));
  assert.equal(widget.env.polls[0].body, null);
});

for (const [name, data, texts, labelClass, enabled] of [
  ['disabled', { enabled: false, running: false }, ['Not enabled', 'The service is not running'], 'label warning', ['start']],
  ['running', { enabled: true, running: true, pids: [12, 34] }, ['Running', 'PID: 12, 34'], 'label success', ['stop', 'restart', 'open']],
  ['temporary', { enabled: false, running: true, pids: [56] }, ['Running (not enabled)', 'PID: 56'], 'label success', ['stop', 'restart', 'open']],
  ['stopped', { enabled: true, running: false, pids: [] }, ['Stopped', 'PID: -'], 'label', ['start']]
]) {
  test(`status: ${name} text, PID, label style and buttons`, () => {
    const widget = statusWidget(); widget.update(data);
    assert.deepEqual(widget.status.children.map((child) => child.textContent), texts);
    assert.equal(widget.status.children[0].className, labelClass);
    assert.equal(widget.status.children[1].className, 'songloft-status-meta');
    assertButtons(widget, enabled);
    for (const [action, style] of Object.entries({ start: 'apply', stop: 'reset', restart: 'reload', open: 'action' })) {
      assert.equal(widget.buttons[action].className, 'cbi-button cbi-button-' + style);
    }
  });
}

for (const [name, reply] of [
  ['null', null], ['service error', { error: 'service_unavailable' }],
  ['missing section', { sections: {} }]
]) {
  test(`status: unavailable ${name} clears previous status and disables controls`, () => {
    const widget = statusWidget(); widget.update({ enabled: true, running: true }); widget.poll(reply);
    assert.equal(widget.status.children.length, 1);
    assert.equal(widget.status.textContent, 'Unable to read service status.');
    assert.equal(widget.status.children[0].className, 'label warning');
    assertButtons(widget, []);
  });
}

test('status: PID HTML payload is text, missing PIDs show dash', () => {
  const widget = statusWidget();
  const payload = '</textarea><script>globalThis.pwned=1</script>';
  widget.update({ enabled: true, running: true, pids: [payload] });
  assert.equal(widget.status.children[1].textContent, 'PID: ' + payload);
  assert.equal(widget.status.children[1].children.length, 0);
  widget.update({ enabled: true, running: true });
  assert.equal(widget.status.children[1].textContent, 'PID: -');
});

for (const running of [false, true]) {
  test(`status: read-only permissions with running=${running}`, () => {
    const widget = statusWidget({ readonly: true }); widget.update({ enabled: true, running });
    assertButtons(widget, running ? ['open'] : []);
    widget.click('start'); widget.click('stop'); widget.click('restart');
    assert.equal(widget.env.requests.length, 0);
    if (running) {
      widget.click('open');
      assert.equal(widget.env.opened.length, 1);
    }
  });
}

for (const action of ['start', 'stop', 'restart']) {
  test(`status: ${action} POST encodes token and section, busy dedup until finish`, () => {
    const widget = statusWidget(); widget.update({ enabled: false, running: action !== 'start' });
    widget.click(action);
    const request = widget.env.requests[0];
    assert.equal(request.method, 'POST');
    assert.equal(request.url, endpoint('action'));
    assert.equal(request.async, true);
    assert.equal(request.timeout, action === 'restart' ? 45000 : 30000);
    assert.equal(widget.status.textContent, { start: 'Starting...', stop: 'Stopping...', restart: 'Restarting...' }[action]);
    assert.equal(request.headers['Content-Type'], 'application/x-www-form-urlencoded');
    assert.equal(request.body, 'token=' + encodeURIComponent(token) + '&action=' + action + '&section=' + encodeURIComponent(section));
    assert.deepEqual([...new URLSearchParams(request.body)], [['token', token], ['action', action], ['section', section]]);
    assertButtons(widget, []);
    widget.click(action); widget.click('open');
    assert.equal(widget.env.requests.length, 1);
    assert.equal(widget.env.opened.length, 0);
    widget.update({ enabled: true, running: true });
    assertButtons(widget, []);
    const status = { sections: { [section]: { enabled: false, running: action !== 'stop', pids: [99] } } };
    request.load({ success: true, status });
    assertButtons(widget, []);
    request.onloadend();
    assert.equal(widget.error.hidden, true);
    widget.env.advance(30000);
    assert.equal(widget.error.hidden, true, 'successful operation cancels its timeout');
    assertButtons(widget, action === 'stop' ? ['start'] : ['stop', 'restart', 'open']);
    widget.update({ enabled: true, running: false });
    assertButtons(widget, ['start']);
    assert.match(widget.status.textContent, /Stopped/);
  });
}

for (const mode of ['service error', 'network error', 'timeout', 'HTTP 500', 'malformed JSON', 'pending request']) {
  test(`status: stop ${mode} stays pending until 30 seconds and clears on eventual exit`, () => {
    const widget = statusWidget();
    widget.update({ enabled: true, running: true, active: true });
    widget.click('stop');
    const request = widget.env.requests[0];
    if (mode === 'service error') request.finish({ success: false });
    else if (mode === 'network error') request.fail('error');
    else if (mode === 'timeout') request.fail('timeout');
    else if (mode === 'HTTP 500') request.finish({}, 500);
    else if (mode === 'malformed JSON') request.finish('{bad', 200, true);
    widget.env.advance(29999);
    widget.poll({ error: 'service_unavailable' });
    widget.update({ enabled: true, running: true, active: true });
    assert.equal(widget.status.textContent, 'Stopping...');
    assert.equal(widget.error.hidden, true);
    assertButtons(widget, []);
    widget.env.advance(1);
    assert.equal(widget.error.hidden, false);
    assert.match(widget.error.textContent, /30 seconds/);
    widget.update({ enabled: true, running: false, active: false });
    assert.equal(widget.error.hidden, true);
    assert.match(widget.status.textContent, /Stopped/);
    assertButtons(widget, ['start']);
  });
}

test('status: slow stop recovers through polling and ignores a late action response', () => {
  const widget = statusWidget();
  widget.update({ enabled: true, running: true, active: true });
  widget.click('stop');
  const stopRequest = widget.env.requests[0];
  widget.env.advance(12000);
  widget.update({ enabled: true, running: false, active: true });
  assert.equal(widget.status.textContent, 'Stopping...', 'registered instance is not fully stopped');
  widget.update({ enabled: true, running: false });
  assert.equal(widget.status.textContent, 'Stopping...', 'missing active status cannot confirm exit');
  widget.update({ enabled: true, running: false, active: false });
  assert.equal(widget.error.hidden, true);
  assertButtons(widget, ['start']);
  widget.click('start');
  stopRequest.finish({ success: true, status: { sections: { [section]: { running: false, active: false } } } });
  widget.env.advance(18000);
  assert.equal(widget.status.textContent, 'Starting...');
  assert.equal(widget.error.hidden, true);
  assertButtons(widget, []);
});

test('status: early stop request failure can recover before the deadline', () => {
  const widget = statusWidget();
  widget.update({ enabled: true, running: true, active: true });
  widget.click('stop');
  widget.env.requests[0].fail('error');
  widget.env.advance(20000);
  widget.update({ enabled: true, running: false, active: false });
  widget.env.advance(10000);
  assert.equal(widget.error.hidden, true);
  assertButtons(widget, ['start']);
});

for (const mode of ['service error', 'malformed JSON', 'HTTP 500', 'network error', 'timeout']) {
  test(`status: action ${mode} reports failure and polling restores controls`, () => {
    const widget = statusWidget(); widget.update({ enabled: true, running: false }); widget.click('start');
    const request = widget.env.requests[0];
    if (mode === 'service error') request.finish({ success: false, status: { error: 'service_unavailable' } });
    else if (mode === 'malformed JSON') request.finish('{bad', 200, true);
    else if (mode === 'HTTP 500') request.finish({ success: true }, 500);
    else request.fail(mode === 'timeout' ? 'timeout' : 'error');
    assert.equal(widget.error.hidden, false);
    assert.equal(widget.error.textContent, actionFailure);
    assert.equal(widget.status.textContent, 'Unable to read service status.');
    assertButtons(widget, []);
    widget.update({ enabled: true, running: false });
    assertButtons(widget, ['start']);
    widget.click('start');
    assert.equal(widget.env.requests.length, 2);
    assert.equal(widget.error.hidden, true);
    widget.env.requests[1].finish({ success: true, status: { sections: { [section]: { enabled: true, running: true } } } });
    assertButtons(widget, ['stop', 'restart', 'open']);
    assert.equal(widget.error.hidden, true);
  });
}

test('status: service failure with usable status immediately restores allowed controls', () => {
  const widget = statusWidget(); widget.update({ enabled: true, running: false }); widget.click('start');
  widget.env.requests[0].finish({ success: false, status: { sections: { [section]: { enabled: true, running: false } } } });
  assert.equal(widget.error.hidden, false);
  assertButtons(widget, ['start']);
});

for (const [hostname, port, basePath, expected] of [
  ['router.example', '12345', '/music space/汉字/#?%/', 'http://router.example:12345/music%20space/%E6%B1%89%E5%AD%97/%23%3F%25/'],
  ['2001:db8::1', '58092', '/music', 'http://[2001:db8::1]:58092/music/'],
  ['[2001:db8::1]', '58092', '/music///', 'http://[2001:db8::1]:58092/music/'],
  ['router.example', undefined, undefined, 'http://router.example:58091/']
]) {
  test(`status: Open saved URL ${hostname} ${basePath || '(default)'}`, () => {
    const widget = statusWidget({ hostname, readonly: true });
    widget.update({ enabled: false, running: true, port, base_path: basePath });
    widget.click('open');
    assert.deepEqual(widget.env.opened, [[expected, '_blank', 'noopener,noreferrer']]);
    assert.equal(widget.env.requests.length, 0);
  });
}

test('views: stylesheet deduplicates multiple status and log widgets with isolated sections', () => {
  const env = environment();
  const firstStatus = statusWidget({}, env, 'first');
  const secondStatus = statusWidget({}, env, 'second');
  const firstLog = logWidget(env, 'first');
  const secondLog = logWidget(env, 'second');
  assert.equal(env.head.children.length, 1);
  firstStatus.update({ enabled: true, running: true });
  secondStatus.update({ enabled: false, running: false });
  assertButtons(firstStatus, ['stop', 'restart', 'open']);
  assertButtons(secondStatus, ['start']);
  env.requests[0].finish({ ...logReply, content: 'first log' });
  env.requests[1].finish({ ...logReply, content: 'second log' });
  assert.equal(firstLog.nodes.content.value, 'first log');
  assert.equal(secondLog.nodes.content.value, 'second log');
  assert.equal(env.requests[0].url, endpoint('log') + '?section=first');
  assert.equal(env.requests[1].url, endpoint('log') + '?section=second');
});
