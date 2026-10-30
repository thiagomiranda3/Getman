const match = /a=(\w+)|b=(\w+)/.exec(gm.response.text());
if (match) gm.environment.set('capture', match[1] ?? match[2] ?? match[0]);
gm.environment.set('trace', gm.response.header('X-Trace'));
