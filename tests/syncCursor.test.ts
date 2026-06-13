import { describe, test, expect, vi, beforeEach, afterEach } from 'vitest'
import fs from 'fs'
import os from 'os'
import path from 'path'

vi.mock('../src/core/logger', () => ({
  log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  initializeLogger: vi.fn(),
}))

import { loadSyncCursor, saveSyncCursor } from '../src/core/syncCursor'

const FIVE_MINUTES_MS = 5 * 60 * 1000

let tmpDir: string
let cursorFile: string

beforeEach(() => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'avoqado-cursor-'))
  cursorFile = path.join(tmpDir, 'sync-cursor.json')
})

afterEach(() => {
  fs.rmSync(tmpDir, { recursive: true, force: true })
})

describe('saveSyncCursor + loadSyncCursor', () => {
  test('roundtrip: lo que se guarda es lo que se carga', () => {
    const cursor = { lastModifiedAt: new Date('2026-06-12T18:30:45.123Z'), lastId: 9876 }

    saveSyncCursor(cursor, cursorFile)
    const loaded = loadSyncCursor(cursorFile)

    expect(loaded.lastModifiedAt.toISOString()).toBe('2026-06-12T18:30:45.123Z')
    expect(loaded.lastId).toBe(9876)
  })

  test('archivo inexistente: fallback a ahora menos 5 minutos con lastId 0', () => {
    const before = Date.now()
    const loaded = loadSyncCursor(path.join(tmpDir, 'no-existe.json'))
    const after = Date.now()

    expect(loaded.lastId).toBe(0)
    expect(loaded.lastModifiedAt.getTime()).toBeGreaterThanOrEqual(before - FIVE_MINUTES_MS)
    expect(loaded.lastModifiedAt.getTime()).toBeLessThanOrEqual(after - FIVE_MINUTES_MS)
  })

  test('JSON corrupto: fallback sin lanzar excepción', () => {
    fs.writeFileSync(cursorFile, '{esto no es json valido')

    const loaded = loadSyncCursor(cursorFile)

    expect(loaded.lastId).toBe(0)
    expect(loaded.lastModifiedAt).toBeInstanceOf(Date)
  })

  test('fecha inválida o tipos incorrectos: fallback', () => {
    fs.writeFileSync(cursorFile, JSON.stringify({ lastModifiedAt: 'no-es-fecha', lastId: 5 }))
    expect(loadSyncCursor(cursorFile).lastId).toBe(0)

    fs.writeFileSync(cursorFile, JSON.stringify({ lastModifiedAt: '2026-06-12T18:30:45.123Z', lastId: 'cinco' }))
    expect(loadSyncCursor(cursorFile).lastId).toBe(0)
  })

  test('escritura atómica: no deja archivo temporal residual', () => {
    saveSyncCursor({ lastModifiedAt: new Date(), lastId: 1 }, cursorFile)

    const leftovers = fs.readdirSync(tmpDir).filter(f => f.endsWith('.tmp'))
    expect(leftovers).toEqual([])
    expect(fs.existsSync(cursorFile)).toBe(true)
  })

  test('save crea el directorio padre si no existe', () => {
    const nested = path.join(tmpDir, 'sub', 'dir', 'sync-cursor.json')

    saveSyncCursor({ lastModifiedAt: new Date('2026-01-01T00:00:00.000Z'), lastId: 42 }, nested)
    const loaded = loadSyncCursor(nested)

    expect(loaded.lastId).toBe(42)
  })

  test('save sobreescribe un cursor previo', () => {
    saveSyncCursor({ lastModifiedAt: new Date('2026-01-01T00:00:00.000Z'), lastId: 1 }, cursorFile)
    saveSyncCursor({ lastModifiedAt: new Date('2026-02-02T00:00:00.000Z'), lastId: 2 }, cursorFile)

    const loaded = loadSyncCursor(cursorFile)
    expect(loaded.lastModifiedAt.toISOString()).toBe('2026-02-02T00:00:00.000Z')
    expect(loaded.lastId).toBe(2)
  })
})
