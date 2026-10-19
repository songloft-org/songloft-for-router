const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const root = process.env.SONGLOFT_TEST_ROOT || path.resolve(__dirname, '..');

for (const variant of ['songloft-koolshare', 'songloft-SWRT']) {
  const base = path.join(root, 'merlin', variant);
  const script = fs.readFileSync(path.join(base, 'scripts/songloft_config.sh'), 'utf8');
  // Execute the production start function with real mkdir/cd. Firmware APIs,
  // process control and nohup are replaced; no router paths or services are touched.
  const startFunction = script.match(/^start_songloft\(\) \{[\s\S]*?^\}/m)[0];

  for (const mode of ['default', 'custom', 'relative', 'root', 'blocked']) {
    test(`${variant}: ${mode} music path reaches the startup environment`, t => {
      const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'songloft-merlin-'));
      t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
      const workDir = path.join(dir, 'work directory');
      let musicPath = '';
      if (mode === 'custom') musicPath = path.join(dir, 'music library; $(echo literal)');
      if (mode === 'relative') musicPath = 'relative';
      if (mode === 'root') musicPath = '/';
      if (mode === 'blocked') {
        musicPath = path.join(dir, 'file');
        fs.writeFileSync(musicPath, 'not a directory');
      }
      const capture = path.join(dir, 'environment');
      const stopped = path.join(dir, 'stopped');
      const result = spawnSync(process.env.BASH_BIN || 'bash', ['-c', `
dbus() { :; }
get_bin_path() { printf '%s\\n' "$TEST_BINARY"; }
echo_date() { printf '%s\\n' "$*"; }
stop_proc() { touch "$TEST_STOPPED"; }
nat_start_link() { :; }
sleep() { :; }
is_running() { return 0; }
mkdir() {
    [ "$1" != -p ] || [ "$2" != /tmp/upload ] || return 0
    command mkdir "$@"
}
nohup() { printf '%s\\n%s\\n' "$MUSIC_DIR" "$PWD" > "$TEST_CAPTURE"; }
${startFunction}
start_songloft
result=$?
wait
exit "$result"
`, 'music-path-test'], {
        encoding: 'utf8',
        env: {
          ...process.env,
          songloft_enable: '1',
          songloft_db_path: workDir,
          songloft_music_path: musicPath,
          LOG_FILE: path.join(dir, 'server.log'),
          PID_FILE: path.join(dir, 'server.pid'),
          TEST_BINARY: process.execPath,
          TEST_CAPTURE: capture,
          TEST_STOPPED: stopped,
        },
      });
      const valid = mode === 'default' || mode === 'custom';
      assert.equal(result.status, valid ? 0 : 1, result.stderr);
      assert.equal(fs.existsSync(stopped), valid, 'invalid paths must preserve the running service');
      assert.equal(fs.existsSync(capture), valid);
      if (valid) {
        const expected = musicPath || path.join(workDir, 'music');
        assert.ok(fs.statSync(expected).isDirectory());
        assert.equal(fs.readFileSync(capture, 'utf8'), `${expected}\n${workDir}\n`);
        if (mode === 'custom') assert.equal(fs.existsSync(path.join(workDir, 'music')), false);
      }
    });
  }

  test(`${variant}: form loads, validates, saves and clears the music path`, () => {
    const html = fs.readFileSync(path.join(base, 'webs/Module_songloft.asp'), 'utf8');
    const nodes = new Map([...html.matchAll(/\bid="([^"]+)"/g)].map(match => [
      match[1], { value: '', checked: false, style: {} },
    ]));
    const requests = [];
    const alerts = [];
    const context = vm.createContext({
      document: { getElementById: id => {
        assert.ok(nodes.has(id), `missing form element ${id}`);
        return nodes.get(id);
      } },
      $: { trim: text => text.trim(), ajax: request => requests.push(JSON.parse(request.data)) },
      alert: text => alerts.push(text),
    });
    vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], context);
    const custom = '/mnt/music library';
    context.dbus = { songloft_enable: '1', songloft_db_path: '/data/songloft', songloft_music_path: custom };
    context.fill_form();
    context.update_visibility();
    assert.equal(nodes.get('songloft_music_path').value, custom);
    assert.equal(nodes.get('tr_music_path').style.display, '');
    context.apply_config();
    assert.equal(requests.pop().fields.songloft_music_path, custom);
    nodes.get('songloft_music_path').value = '';
    context.apply_config();
    assert.equal(requests.pop().fields.songloft_music_path, '');
    for (const invalid of ['relative', '/', '//music', '/music\nfolder']) {
      nodes.get('songloft_music_path').value = invalid;
      context.apply_config();
      assert.equal(requests.length, 0);
    }
    assert.equal(alerts.length, 4);
    nodes.get('songloft_enable').checked = false;
    context.update_visibility();
    assert.equal(nodes.get('tr_music_path').style.display, 'none');
  });
}
