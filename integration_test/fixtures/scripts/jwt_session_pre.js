const claims = gm.jwt.decode(gm.variables.get('access_token'));
gm.variables.set('session_id', claims.session.id);
gm.request.headers.set('X-Session', claims.session.id);
gm.request.setBody(JSON.stringify({
  sessionId: claims.session.id,
  description: 'texto com "aspas" e acentuação'
}));
