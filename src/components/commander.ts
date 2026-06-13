import { ConsumeMessage } from 'amqplib';
import { log } from '../core/logger';
import { getRabbitMQChannel, onReconnect, POS_COMMANDS_EXCHANGE } from '../core/rabbitmq';
import { IPOSAdapter, OrderCreateData, OrderAddItemData } from '../adapters/IPosAdapter';
import { SoftRestaurant11Adapter } from '../adapters/SoftRestaurant11Adapter';
import { loadConfig } from '../config';

let adapter: IPOSAdapter;
let reconnectHandlerRegistered = false;

export const handleCommand = async (msg: ConsumeMessage | null) => {
    if (!msg) return;

    const channel = getRabbitMQChannel();
    const routingKey = msg.fields.routingKey;

    // Parseamos UNA sola vez, en su propio try: un mensaje con JSON inválido
    // se va directo a la DLQ. (Antes, el catch principal re-parseaba el mismo
    // contenido para loguearlo, explotaba, y el mensaje quedaba sin ack ni
    // nack — con prefetch(1) eso congelaba la cola entera hasta reiniciar.)
    let commandMessage: any;
    try {
      commandMessage = JSON.parse(msg.content.toString());
    } catch (parseError: any) {
      log.error({
        message: '[Comandante] Mensaje con JSON inválido. Enviando a la Dead-Letter Queue.',
        routingKey,
        errorMessage: parseError.message,
        rawContent: msg.content.toString().slice(0, 500),
      });
      channel.nack(msg, false, false);
      return;
    }

    try {
      log.info(`[Comandante] Comando recibido: ${routingKey}`);
      const { entity, action, payload } = commandMessage;
      log.info(`[Comandante] Despachando acción: ${entity}.${action}`);

      const keyParts = routingKey.split('.');
      if (keyParts[0] !== 'command' || keyParts.length !== 3) {
        throw new Error(`Routing key de comando no tiene el formato esperado (command.pos_type.venueId): ${routingKey}`);
      }

      switch (`${entity}.${action}`) {
        case 'Order.CREATE':
          await adapter.createEmptyOrder(payload as OrderCreateData);
          log.info(`[Comandante] Acción 'createEmptyOrder' completada.`);
          break;

        case 'OrderItem.CREATE':
            // El payload ya contiene todo lo que necesitamos
            const { orderFolio, ...itemData } = payload;
            if (!orderFolio) {
              throw new Error("El payload para 'OrderItem.CREATE' debe incluir 'orderFolio'.");
            }
            await adapter.addItemToOrder(orderFolio, itemData as OrderAddItemData);
            log.info(`[Comandante] Acción 'addItemToOrder' completada para el folio ${orderFolio}.`);
            break;
        
        default:
          log.warn(`[Comandante] No hay un manejador para el comando: ${entity}.${action}`);
      }
      
      
      channel.ack(msg);
      log.info(`[Comandante] Comando ${routingKey} procesado con éxito.`);

    } catch (error: any) {
      log.error({
        message: `[Comandante] Error al procesar comando`,
        routingKey: routingKey,
        // Aquí imprimimos explícitamente el mensaje y el stack del error
        errorMessage: error.message,
        errorStack: error.stack,
        // Logueamos el payload YA parseado (nunca re-parsear aquí: si el JSON
        // fuera inválido, el throw dentro del catch dejaría el mensaje colgado)
        payload: commandMessage
      });
      channel.nack(msg, false, false); // Enviar a la Dead-Letter Queue
    }
};

const setupConsumer = async (): Promise<void> => {
  const config = loadConfig();
  const channel = getRabbitMQChannel();

  const queueName = `commands_queue.venue_${config.venueId}`;

  // ✅ CORRECCIÓN: Eliminamos la palabra '.venue' para que coincida con la routing key
  const bindingKey = `command.${config.posType}.${config.venueId}`;

  await channel.assertQueue(queueName, { durable: true });
  await channel.bindQueue(queueName, POS_COMMANDS_EXCHANGE, bindingKey);

  channel.prefetch(1);
  await channel.consume(queueName, handleCommand);

  log.info(`[Comandante] Escuchando en la cola "${queueName}" con el binding key "${bindingKey}"`);
};

export const startCommander = async () => {
  log.info('▶️  Iniciando Comandante (Avoqado -> POS)');

  const config = loadConfig();

  if (config.posVersion.startsWith('11')) {
    adapter = new SoftRestaurant11Adapter();
    log.info('✅ Adaptador SoftRestaurant v11 cargado.');
  } else {
    log.error(`FATAL: Versión de POS no soportada: ${config.posVersion}`);
    return;
  }

  await setupConsumer();

  // Un canal nuevo (tras una reconexión) no hereda los consume() del canal
  // anterior: sin este registro, después de un blip de red el servicio
  // seguía publicando eventos pero dejaba de recibir comandos hasta reiniciar.
  if (!reconnectHandlerRegistered) {
    onReconnect(async () => {
      log.info('[Comandante] Restableciendo consumer tras reconexión...');
      await setupConsumer();
    });
    reconnectHandlerRegistered = true;
  }
};