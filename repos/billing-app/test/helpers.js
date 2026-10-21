// Shared test doubles: no network, no real database.

export const silentLogger = { info() {}, warn() {}, error() {} };

export function fakeDatabase({ up = true, orders = [] } = {}) {
  return {
    ping: async () => up,
    listOrders: async () => {
      if (!up) {
        throw new Error('database down');
      }
      return orders;
    },
  };
}

export const fakeQueue = (connected) => ({ isConnected: () => connected });
