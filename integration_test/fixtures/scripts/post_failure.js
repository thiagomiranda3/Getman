gm.environment.set('must_not_persist', 'pending');
gm.test('Executado antes do erro', () => gm.expect(1).to.equal(1));
throw new Error('Pós-processamento interrompido');
