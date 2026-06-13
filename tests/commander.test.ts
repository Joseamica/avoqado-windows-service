import { describe, test, expect, vi, beforeEach } from 'vitest'

const { ackSpy, nackSpy } = vi.hoisted(() => ({ ackSpy: vi.fn(), nackSpy: vi.fn() }))

vi.mock('../src/core/logger', () => ({
  log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  initializeLogger: vi.fn(),
}))

vi.mock('../src/core/rabbitmq', () => ({
  getRabbitMQChannel: () => ({ ack: ackSpy, nack: nackSpy }),
  onReconnect: vi.fn(),
  POS_COMMANDS_EXCHANGE: 'pos_commands_exchange',
}))

vi.mock('../src/config', () => ({
  loadConfig: () => ({ venueId: 'venue-x', posType: 'softrestaurant', posVersion: '11.0.0' }),
}))

vi.mock('../src/adapters/SoftRestaurant11Adapter', () => ({
  SoftRestaurant11Adapter: class {},
}))

import { handleCommand } from '../src/components/commander'

const makeMsg = (content: string, routingKey = 'command.softrestaurant.venue-x'): any => ({
  content: Buffer.from(content),
  fields: { routingKey, deliveryTag: 1, redelivered: false, exchange: 'pos_commands_exchange' },
  properties: {},
})

beforeEach(() => {
  ackSpy.mockClear()
  nackSpy.mockClear()
})

describe('handleCommand', () => {
  test('JSON malformado: nack a DLQ (sin requeue) y NO lanza — la cola no se queda colgada', async () => {
    await expect(handleCommand(makeMsg('esto no es json {{{'))).resolves.toBeUndefined()

    expect(nackSpy).toHaveBeenCalledTimes(1)
    expect(nackSpy).toHaveBeenCalledWith(expect.anything(), false, false)
    expect(ackSpy).not.toHaveBeenCalled()
  })

  test('comando con acción desconocida: se confirma (ack) sin tronar', async () => {
    const msg = makeMsg(JSON.stringify({ entity: 'Foo', action: 'BAR', payload: {} }))

    await expect(handleCommand(msg)).resolves.toBeUndefined()

    expect(ackSpy).toHaveBeenCalledTimes(1)
    expect(nackSpy).not.toHaveBeenCalled()
  })

  test('routing key con formato inesperado: nack a DLQ sin requeue', async () => {
    const msg = makeMsg(JSON.stringify({ entity: 'Order', action: 'CREATE', payload: {} }), 'formato.raro')

    await expect(handleCommand(msg)).resolves.toBeUndefined()

    expect(nackSpy).toHaveBeenCalledTimes(1)
    expect(nackSpy).toHaveBeenCalledWith(expect.anything(), false, false)
  })

  test('mensaje null: no hace nada', async () => {
    await expect(handleCommand(null)).resolves.toBeUndefined()

    expect(ackSpy).not.toHaveBeenCalled()
    expect(nackSpy).not.toHaveBeenCalled()
  })
})
