gm.test('Status', () => gm.expect(gm.response.status).to.equal(200));
gm.test('Header', () => {
  gm.expect(gm.response.header('X-Trace')).to.equal('trace-42');
});
gm.test('Null existe', () => {
  gm.expect(gm.response.lookup('$.nullable').found).to.equal(true);
  gm.expect(gm.response.lookup('$.nullable').value).to.equal(null);
});
gm.test('Falha intencional', () => gm.expect(1).to.equal(2));
gm.test('Continua após falha', async () => {
  gm.expect(await Promise.resolve('ok')).to.equal('ok');
});
console.info('Resposta verificada');
