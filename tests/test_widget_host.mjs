import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

// Exercise the QML JavaScript with a scoped bar and injected service catalogue.
function method(file, name, context) {
  const source = readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');
  const start = source.indexOf(`  function ${name}(`);
  assert.ok(start >= 0, `Missing ${name}`);
  const end = source.indexOf('\n  }', start) + 4;
  return vm.runInNewContext(`(${source.slice(start, end)})`, context);
}

test('members resolve from the injected catalogue without a registry on bar', () => {
  const component = {};
  const context = { root: { bar: {} }, folderService: {
    barWidgetRegistry: { widgets: { example: { component } } }
  } };
  const resolve = method('BarWidget.qml', 'memberComponent', context);
  assert.equal(resolve('example'), component);
  assert.equal(resolve('missing'), null);
  context.folderService = null;
  assert.equal(resolve('example'), null);
});

test('hosted member receives a facade for its own identity', () => {
  const scopedBar = {};
  const context = { root: { bar: {} }, nativeBar: {
    pluginBarApiFor(...args) {
      assert.deepEqual(args, ['example', 'example', true]);
      return scopedBar;
    }
  } };
  assert.equal(method('BarWidget.qml', 'memberBar', context)('example'), scopedBar);
});

test('folder IPC uses registered widgets without shell moduleSlots', () => {
  const context = { folderWidgets: [], shell: { bar: {} } };
  const add = method('Service.qml', 'registerFolder', context);
  const remove = method('Service.qml', 'unregisterFolder', context);
  const lookup = method('Service.qml', 'folderWidget', context);
  const first = { folderId: 'first' }, second = { folderId: 'second' };
  add(first); add(first); add(second);
  assert.equal(context.folderWidgets.length, 2);
  assert.equal(lookup('second'), second);
  assert.equal(lookup(''), first);
  remove(first);
  assert.equal(lookup('first'), null);
  assert.equal(lookup('second'), second);
});

test('availability diagnostics catch failed native loaders', () => {
  const context = { folderData: { members: [{ id: 'ok' }, { id: 'failed' }] },
    root: { memberLoader(id) { return id === 'ok' ? { item: {} } : { item: null }; } } };
  assert.equal(JSON.stringify(method('BarWidget.qml', 'unavailableMembers', context)()), '["failed"]');
});
