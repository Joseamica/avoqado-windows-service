// Define los tipos de datos que se usarán en los métodos
// Estos deberían reflejar la estructura de tus modelos de Prisma
export interface OrderPayload { [key: string]: any; }
export interface OrderItemPayload { [key: string]: any; }
export interface PaymentPayload { [key: string]: any; }
export interface ShiftPayload { [key: string]: any; }
export interface ShiftOpenData {
  posStaffId: string;
  startingCash: number;
}

export interface ShiftCloseData {
  cashDeclared: number;
  cardDeclared: number;
  vouchersDeclared: number;
  // ... cualquier otro total que el POS necesite para el cierre.
}


export interface OrderCreateData {
  tableNumber: string;
  waiterPosId: string;
  customerCount: number;
  posAreaId: string;
}

export interface OrderAddItemData {
  productId: string; // El 'idproducto' del POS
  quantity: number;
  price: number; // El precio unitario del producto
  waiterPosId: string; // El mesero que añade el producto
  notes: string; // Notas adicionales
  // ... cualquier otro dato necesario como modificadores
}

export interface PaymentData {
  posPaymentMethodId: string; // ej: 'EF' para efectivo
  amount: number;
  tip: number;
  reference: string;
}

export interface ProductCreateData {
  name: string;
  price: number;
  sku: string;
  // ... otros campos del producto
}
export interface IPOSAdapter {
  // Turnos
  openShift(data: ShiftOpenData): Promise<{ shiftId: number }>;
  closeShift(shiftId: number, data: ShiftCloseData): Promise<void>;

  // Órdenes
  createEmptyOrder(data: OrderCreateData): Promise<{ folio: number }>;
  addItemToOrder(folio: number, item: OrderAddItemData): Promise<void>;
  cancelOrderItem(folio: number, movementId: number, reason: string, user: string): Promise<void>;
  
  // Pagos
  applyPayment(folio: number, payment: PaymentData): Promise<void>;
  closeAndPayOrder(folio: number): Promise<{ finalCheckNumber: number }>;
}

