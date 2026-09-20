import { AppController } from './app.controller';

describe('AppController', () => {
  it('returns a minimal health response without configuration details', () => {
    const controller = new AppController();

    expect(controller.health()).toEqual({ status: 'ok' });
    expect(controller.health()).not.toHaveProperty('supabaseConfigured');
  });
});
