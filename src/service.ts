import { loadConfig } from './config'
import { initializeLogger, log } from './core/logger'
import { connectToRabbitMQ, closeRabbitMQConnection } from './core/rabbitmq'
import { connectToSql, closeDbPool } from './core/db'
import { startProducer, stopProducer } from './components/producer'
import { startCommander } from './components/commander'
import { startConfigurationErrorConsumer, stopConfigurationErrorConsumer } from './components/configurationErrorConsumer'
import { serviceStateManager } from './core/serviceState'
import { managementConsole } from './core/managementConsole'

async function startApp() {
  initializeLogger()
  log.info('--- [INICIO] Iniciando Avoqado Sync Service ---')

  try {
    // Cargar configuración
    loadConfig()
    log.info('✅ Configuración cargada')

    // Conectar a base de datos
    await connectToSql()
    log.info('✅ Conexión a base de datos establecida')

    // Conectar a RabbitMQ
    await connectToRabbitMQ()
    log.info('✅ Conexión a RabbitMQ establecida')

    // Iniciar consumer de errores de configuración
    await startConfigurationErrorConsumer()
    log.info('✅ Consumer de errores de configuración iniciado')

    // Iniciar commander (para comandos regulares)
    await startCommander()
    log.info('✅ Comandante iniciado')

    // Iniciar producer (con heartbeats y polling)
    await startProducer()
    log.info('✅ Producer iniciado')

    // Iniciar consola de administración en modo interactivo
    // DISABLED: Console causes crashes in background mode
    // if (process.env.NODE_ENV !== 'production') {
    //   setTimeout(() => {
    //     managementConsole.start()
    //   }, 2000) // Dar tiempo para que se inicialicen todos los componentes
    // }

    log.info('🎉 Servicio de Sincronización Avoqado corriendo exitosamente.')
    log.info('📊 Estado inicial:', serviceStateManager.getCurrentState())

    // Mensaje informativo sobre la consola
    if (process.env.NODE_ENV !== 'production') {
      console.log('\n💡 La consola de administración estará disponible en unos momentos.')
      console.log('   Escriba "help" para ver comandos disponibles.\n')
    }
  } catch (error) {
    log.error('🚨 Falla crítica durante el arranque del servicio:', error)
    serviceStateManager.stop('Error crítico en arranque')
    process.exit(1)
  }
}

async function shutdown(signal: string) {
  log.warn(`🚨 Recibido ${signal}. Iniciando apagado limpio...`)

  try {
    // Detener consola de administración
    managementConsole.stop()
    log.info('✅ Consola de administración detenida')

    // Detener producer y heartbeats
    stopProducer()
    log.info('✅ Producer detenido')

    // Detener consumer de errores de configuración
    await stopConfigurationErrorConsumer()
    log.info('✅ Consumer de errores de configuración detenido')

    // Actualizar estado del servicio
    serviceStateManager.stop(`Apagado por señal ${signal}`)

    // Cerrar conexiones
    await closeRabbitMQConnection()
    log.info('✅ Conexión RabbitMQ cerrada')

    await closeDbPool()
    log.info('✅ Pool de base de datos cerrado')

    log.info('👋 Apagado limpio finalizado.')
  } catch (error) {
    log.error('❌ Error durante apagado limpio:', error)
  }

  process.exit(0)
}

// Iniciar la aplicación
startApp()

// Manejar señales de apagado del sistema operativo
process.on('SIGINT', () => shutdown('SIGINT'))
process.on('SIGTERM', () => shutdown('SIGTERM'))
