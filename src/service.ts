import { loadConfig } from './config';
import { initializeLogger, log } from './core/logger';
import { connectToRabbitMQ, closeRabbitMQConnection } from './core/rabbitmq';
import { connectToSql, closeDbPool } from './core/db';
import { startProducer, getProducerStats } from './components/producer';
import { startCommander } from './components/commander';

async function startApp() {
  initializeLogger();
  log.info('--- [INICIO] Iniciando Avoqado Sync Service ---');
  
  try {
    loadConfig();
    await connectToSql();
    await connectToRabbitMQ();

    startProducer();
    setInterval(async () => {
      const stats = await getProducerStats();
      console.log('Smart Snapshot Stats:', stats);
    }, 5 * 60 * 1000);

    startCommander();

    log.info('✅ Servicio de Sincronización Avoqado corriendo exitosamente.');
  } catch (error) {
    log.error('🚨 Falla crítica durante el arranque del servicio:', error);
    process.exit(1);
  }
}

async function shutdown(signal: string) {
  log.warn(`🚨 Recibido ${signal}. Iniciando apagado limpio...`);
  await closeRabbitMQConnection();
  await closeDbPool();
  log.info('👋 Apagado limpio finalizado.');
  process.exit(0);
}

// Iniciar la aplicación
startApp();

// Manejar señales de apagado del sistema operativo
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));