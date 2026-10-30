const body = gm.response.json();
gm.environment.set('access_token', body.token);
gm.test('Login retornou sucesso', () => {
  gm.expect(gm.response.status).to.equal(200);
});
gm.test('Resposta contém token', () => {
  gm.expect(body.token).to.be.a('string');
});
