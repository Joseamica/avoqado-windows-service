import { ConsumeMessage } from 'amqplib';
import { log } from '../core/logger';
import { getRabbitMQChannel } from '../core/rabbitmq';
import { IPOSAdapter, OrderCreateData, OrderAddItemData } from '../adapters/IPosAdapter';
import { SoftRestaurant11Adapter } from '../adapters/SoftRestaurant11Adapter';
import { loadConfig } from '../config';

let adapter: IPOSAdapter;

const handleCommand = async (msg: ConsumeMessage | null) => {
    if (!msg) return;

    const channel = getRabbitMQChannel();
    let routingKey = 'unknown_routing_key';

    try {
      const commandMessage = JSON.parse(msg.content.toString());

      routingKey = msg.fields.routingKey;

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
        // También es útil loguear el payload que causó el error
        payload: JSON.parse(msg.content.toString()) 
      });
      channel.nack(msg, false, false); // Enviar a la Dead-Letter Queue
    }
};

export const startCommander = async () => {
  log.info('▶️  Iniciando Comandante (Avoqado -> POS)');
  
  const config = loadConfig();
  const channel = getRabbitMQChannel();

  if (config.posVersion.startsWith('11')) {
    adapter = new SoftRestaurant11Adapter();
    log.info('✅ Adaptador SoftRestaurant v11 cargado.');
  } else {
    log.error(`FATAL: Versión de POS no soportada: ${config.posVersion}`);
    return;
  }

  const queueName = `commands_queue.venue_${config.venueId}`;
  
  // ✅ CORRECCIÓN: Eliminamos la palabra '.venue' para que coincida con la routing key
  const bindingKey = `command.${config.posType}.${config.venueId}`;
  
  await channel.assertQueue(queueName, { durable: true });
  // Ahora el binding es a 'pos_commands_exchange', como debe ser.
  await channel.bindQueue(queueName, 'pos_commands_exchange', bindingKey);
  
  channel.prefetch(1);
  channel.consume(queueName, handleCommand);

  log.info(`[Comandante] Escuchando en la cola "${queueName}" con el binding key "${bindingKey}"`);
};