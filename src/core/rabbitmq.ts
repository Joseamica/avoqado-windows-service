import amqp, { connect } from 'amqplib';
import { loadConfig } from '../config';
import { log } from './logger';
import { ChannelModel, Connection, ConfirmChannel } from 'amqplib';
// Declaramos las variables que mantendrán el estado de la conexión
let channelModel: ChannelModel | null = null
let connection: Connection | null = null
let channel: ConfirmChannel | null = null
let isConnecting = false // Una bandera para evitar múltiples intentos de reconexión simultáneos
let hasConnectedOnce = false
let isShuttingDown = false

type ReconnectHandler = () => void | Promise<void>
const reconnectHandlers: ReconnectHandler[] = []

/**
 * Registra un handler que se re-ejecuta después de cada reconexión exitosa.
 * Un canal nuevo NO hereda los consume() del canal muerto: todo consumer
 * (Comandante, errores de configuración) debe registrarse aquí o dejará de
 * recibir mensajes silenciosamente tras un blip de red.
 */
export const onReconnect = (handler: ReconnectHandler): void => {
  reconnectHandlers.push(handler)
}

export const POS_EVENTS_EXCHANGE = 'pos_events_exchange';
export const POS_COMMANDS_EXCHANGE = 'pos_commands_exchange';
export const AVOQADO_EVENTS_QUEUE = 'avoqado_events_queue';
const DEAD_LETTER_EXCHANGE = 'dead_letter_exchange';
const AVOQADO_EVENTS_DLQ = 'avoqado_events_dead_letter_queue';

export const publishMessage = async (
    exchange: string,
    routingKey: string,
    payload: object
  ): Promise<void> => {
    const channel = getRabbitMQChannel();
    const message = Buffer.from(JSON.stringify(payload));
  
    try {
      console.log(`📤 Publicando mensaje en exchange [${exchange}] con routing key [${routingKey}]`);
      
      const published = channel.publish(
        exchange,
        routingKey,
        message,
        { persistent: true }
      );
  
      if (published) {
        await channel.waitForConfirms();
        console.log(`✅ Mensaje [${routingKey}] confirmado por el bróker.`);
      } else {
        throw new Error('El buffer del canal de RabbitMQ está lleno.');
      }
      
    } catch (error) {
      console.error(`🔥 Error al publicar y confirmar mensaje [${routingKey}]:`, error);
      throw error;
    }
  };

const connectWithRetry = async (): Promise<void> => {
  if (isConnecting || isShuttingDown) return;
  isConnecting = true;
  
  try {
    const { rabbitMqUrl } = loadConfig();
    channelModel = await connect(rabbitMqUrl)

    // Get the actual connection from the channel model
    connection = channelModel.connection

    channel = await channelModel.createConfirmChannel()
    if (!channel || !connection) {
      throw new Error("No se pudo crear el canal o la conexión de RabbitMQ.");
    }

    log.info('✅ Conexión con RabbitMQ establecida.');

    await channel.assertExchange(DEAD_LETTER_EXCHANGE, 'direct', { durable: true });
    await channel.assertQueue(AVOQADO_EVENTS_DLQ, { durable: true });
    await channel.bindQueue(AVOQADO_EVENTS_DLQ, DEAD_LETTER_EXCHANGE, 'dead-letter');
    await channel.assertExchange(POS_EVENTS_EXCHANGE, 'topic', { durable: true });
    await channel.assertExchange(POS_COMMANDS_EXCHANGE, 'topic', { durable: true });
    await channel.assertQueue(AVOQADO_EVENTS_QUEUE, {
      durable: true,
      arguments: {
        'x-dead-letter-exchange': DEAD_LETTER_EXCHANGE,
        'x-dead-letter-routing-key': 'dead-letter'
      }
    });
    log.info('✅ Topología de RabbitMQ asegurada.');

    connection.on('error', (err) => log.error('❌ Error de conexión con RabbitMQ:', err.message));
    connection.on('close', () => {
      if (isShuttingDown) {
        log.info('🚪 Conexión RabbitMQ cerrada (apagado del servicio).');
        return;
      }
      log.warn('🚪 Conexión con RabbitMQ cerrada. Reintentando...');
      connection = null;
      channel = null;
      isConnecting = false;
      setTimeout(connectWithRetry, 5000);
    });

    const isReconnect = hasConnectedOnce;
    hasConnectedOnce = true;
    isConnecting = false;

    if (isReconnect && reconnectHandlers.length > 0) {
      log.info(`🔁 Reconexión a RabbitMQ: restableciendo ${reconnectHandlers.length} consumer(s)...`);
      for (const handler of reconnectHandlers) {
        try {
          await handler();
        } catch (err) {
          log.error('❌ Error restableciendo un consumer tras la reconexión:', err);
        }
      }
    }

  } catch (error) {
    log.error('🔥 Falla al conectar con RabbitMQ, reintentando...', error);
    isConnecting = false;
    if (!isShuttingDown) {
      setTimeout(connectWithRetry, 5000);
    }
  }
};

export const connectToRabbitMQ = async () => {
  isShuttingDown = false;
  if (!channel) {
    await connectWithRetry();
  }
};

export const getRabbitMQChannel = (): amqp.ConfirmChannel => {
  if (!channel) {
    throw new Error('El canal de RabbitMQ no ha sido inicializado.');
  }
  return channel;
};

export const closeRabbitMQConnection = async (): Promise<void> => {
  isShuttingDown = true;
  try {
    if (channel) await channel.close();
  } catch (error) {
    log.warn('Error cerrando el canal de RabbitMQ:', error);
  }
  try {
    if (channelModel) await channelModel.close();
  } catch (error) {
    log.warn('Error cerrando la conexión de RabbitMQ:', error);
  }
  channel = null;
  connection = null;
  channelModel = null;
  log.info('🚪 Conexión RabbitMQ cerrada.');
};