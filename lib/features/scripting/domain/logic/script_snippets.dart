// Executable starter scripts shown in the editor. The runtime test executes
// every shipped example, so help content stays aligned with the public API.
import 'package:equatable/equatable.dart';
import 'package:getman/features/scripting/domain/entities/script_phase.dart';

class ScriptSnippet extends Equatable {
  const ScriptSnippet({
    required this.id,
    required this.title,
    required this.phase,
    required this.source,
  });
  final String id;
  final String title;
  final ScriptPhase phase;
  final String source;
  ScriptSnippet copyWith({
    String? id,
    String? title,
    ScriptPhase? phase,
    String? source,
  }) => ScriptSnippet(
    id: id ?? this.id,
    title: title ?? this.title,
    phase: phase ?? this.phase,
    source: source ?? this.source,
  );
  @override
  List<Object> get props => [id, title, phase, source];
}

class ScriptSnippets {
  ScriptSnippets._();
  static const all = <ScriptSnippet>[
    ScriptSnippet(
      id: 'jwt-session',
      title: 'JWT session payload',
      phase: ScriptPhase.preRequest,
      source: '''
// Decodes the payload only; does not verify the signature.
const claims = gm.jwt.decode(gm.variables.get('access_token'));
gm.variables.set('session_id', claims.session.id);
gm.request.headers.set('X-Session', claims.session.id);
gm.request.setBody(JSON.stringify({sessionId: claims.session.id}));''',
    ),
    ScriptSnippet(
      id: 'capture-token',
      title: 'Capture login token',
      phase: ScriptPhase.postResponse,
      source: '''
const body = gm.response.json();
gm.environment.set('access_token', body.token);
gm.test('Login succeeded', () => gm.expect(gm.response.status).to.equal(200));''',
    ),
    ScriptSnippet(
      id: 'response-tests',
      title: 'Check response',
      phase: ScriptPhase.postResponse,
      source: '''
gm.test('Status is 200', () => gm.expect(gm.response.status).to.equal(200));
gm.test('JSON response', () => gm.expect(gm.response.json()).to.be.a('object'));''',
    ),
    ScriptSnippet(
      id: 'capture-header',
      title: 'Capture response header',
      phase: ScriptPhase.postResponse,
      source: '''
const trace = gm.response.header('X-Trace');
if (trace !== undefined) gm.environment.set('trace', trace);''',
    ),
  ];
}
