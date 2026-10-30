"""Materialize one benchmark entrypoint in a disposable checkout.

The common template is identical on both revisions. Only script-specific
imports, assertions and measurements are omitted on the pre-script baseline.
"""
import argparse
from pathlib import Path

IMPORTS = '''import 'package:getman/core/domain/entities/request_scripts.dart';
import 'package:getman/features/scripting/domain/repositories/script_trust_repository.dart';
import 'package:getman_quickjs/getman_quickjs.dart' as native;'''
ASSERTION = '''if (tab.config.scripts.hasEnabledScripts &&
          (tab.scriptExecutionResult?.preRequest == null ||
           tab.scriptExecutionResult?.postResponse?.tests.length != 2)) {
        throw StateError('Expected pre hook and two post-response tests');
      }
      if (tab.scriptExecutionResult?.error != null ||
          (tab.scriptExecutionResult?.preRequest?.tests.any((t) => !t.passed) ?? false) ||
          (tab.scriptExecutionResult?.postResponse?.tests.any((t) => !t.passed) ?? false)) {
        throw StateError('Script failed: ${tab.scriptExecutionResult?.error}');
      }'''
MEASUREMENT = '''if (!coldScript) {
    data['native_before'] = {'controls': native.liveControls(), 'runtimes': native.liveRuntimes()};
    if (native.liveControls() != 0 || native.liveRuntimes() != 0) {
      throw StateError('Native allocation occurred before first script');
    }
    }
    if (scriptMode) {
      const scripts = RequestScripts(
        preRequest: 'gm.variables.set("answer", 6 * 7); gm.request.headers.set("X-Answer", gm.variables.get("answer"));',
        postResponse: 'gm.test("status", () => gm.expect(gm.response.status).to.equal(200)); gm.test("JSON", () => gm.expect(gm.response.json().answer).to.equal(42));',
      );
      final scripted = config.copyWith(scripts: scripts);
      await di.sl<ScriptTrustRepository>().trust(config.id, scripts);
      final changed = tabs.stream.firstWhere((s) => s.tabs.byId(tabId)?.config == scripted);
      tabs.add(UpdateTab(tabs.state.tabs.byId(tabId)!.copyWith(config: scripted)));
      await changed;
      data['script_first_us'] = await send();
      data['rss_after_first_script'] = ProcessInfo.currentRss;
      if (!coldScript) {
      for (var i = 0; i < 30; i++) { await send(); }
      data['rss_after_script_warmup'] = ProcessInfo.currentRss;
      final warm = <int>[];
      final ownership = <Map<String, int>>[];
      for (var i = 0; i < 500; i++) {
        warm.add(await send());
        if ((i + 1) % 100 == 0) {
          ownership.add({'send': i + 1, 'rss': ProcessInfo.currentRss,
            'controls': native.liveControls(), 'runtimes': native.liveRuntimes()});
        }
      }
      data['script_warmup_count'] = 30;
      data['script_warm_us'] = warm;
      data['ownership_after_each_100'] = ownership;
      data['rss_after_500'] = ProcessInfo.currentRss;
      }
    }'''
AFTER_CLOSE = "data['native_after'] = {'controls': native.liveControls(), 'runtimes': native.liveRuntimes()};"


def prepare(checkout, current):
    template = Path(__file__).with_name('app.dart.template').read_text()
    substitutions = {'SCRIPT_IMPORTS': IMPORTS, 'SCRIPT_ASSERTION': ASSERTION,
                     'SCRIPT_MEASUREMENT': MEASUREMENT, 'AFTER_CLOSE': AFTER_CLOSE}
    for key, value in substitutions.items():
        template = template.replace('__' + key + '__', value if current else '')
    target = Path(checkout) / 'lib' / 'performance_main_io.dart'
    if target.exists():
        raise FileExistsError(f'Refusing to replace {target}')
    target.write_text(template)
    return target


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('checkout')
    parser.add_argument('--current', action='store_true')
    args = parser.parse_args()
    print(prepare(args.checkout, args.current))
