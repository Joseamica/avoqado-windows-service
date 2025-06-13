import { Service } from 'node-windows';
import path from 'path';
import { log, initializeLogger } from './core/logger';

// Primero inicializamos el logger para que capture cualquier mensaje.
initializeLogger();

const svc = new Service({
  name: 'Avoqado POS Sync Service',
  description: 'Sincroniza el POS del restaurante con la plataforma Avoqado.',
  script: path.join(__dirname, 'service.js'), // Apunta al archivo compilado
});

svc.on('install', () => {
  log.info('Servicio instalado correctamente.');
  svc.start();
  log.info('Servicio iniciado.');
});

svc.on('uninstall', () => {
  log.info('Servicio desinstalado.');
});

// Manejo de argumentos de línea de comando
const arg = process.argv[2];
if (arg === 'install') {
  svc.install();
} else if (arg === 'uninstall') {
  svc.uninstall();
} else {
  // Si no hay argumentos, asumimos que es el servicio el que se está ejecutando
  require('./service');
}