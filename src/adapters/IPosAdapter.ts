// Define los tipos de datos que se usarán en los métodos
// Estos deberían reflejar la estructura de tus modelos de Prisma
export interface OrderPayload {
  [key: string]: any
}
export interface OrderItemPayload {
  [key: string]: any
}
export interface PaymentPayload {
  [key: string]: any
}
export interface ShiftPayload {
  [key: string]: any
}
export interface ShiftOpenData {
  posStaffId: string
  startingCash: number
  stationId?: string
}

export interface ShiftCloseData {
  shiftId?: string // The shift ID to close
  cashDeclared: number
  cardDeclared: number
  vouchersDeclared: number
  otherDeclared?: number
  notes?: string
  // ... cualquier otro total que el POS necesite para el cierre.
}

export interface OrderCreateData {
  tableNumber: string
  waiterPosId: string
  customerCount: number
  posAreaId: string
}

export interface OrderAddItemData {
  productId: string // El 'idproducto' del POS
  quantity: number
  price: number // El precio unitario del producto
  waiterPosId: string // El mesero que añade el producto
  notes: string // Notas adicionales
  // ... cualquier otro dato necesario como modificadores
}

export interface PaymentData {
  posPaymentMethodId: string // ej: 'EF' para efectivo
  amount: number
  tip: number
  reference: string
}

export interface IntelligentPaymentData extends PaymentData {
  isPartial?: boolean // Indica si es un pago parcial
}

export interface PaymentResult {
  closed: boolean // Si la orden fue cerrada
  change?: number // Cambio si hubo sobrepago
  remaining?: number // Cantidad restante por pagar
  totalPaid: number // Total pagado hasta ahora
}

export interface ProductCreateData {
  name: string
  price: number
  sku: string
  // ... otros campos del producto
}

export interface FastPaymentData {
  amount: number // Monto del pago rápido
  posPaymentMethodId: string // Método de pago (EF, CARD, etc.)
  reference?: string // Referencia opcional del pago
  productId?: string // ID del producto a usar (opcional, usa default si no se especifica)
  cashierPosId: string // ID del cajero que registra el pago
  notes?: string // Notas adicionales
}

export interface FastPaymentResult {
  folio: number // Folio de la transacción creada
  checkNumber: number // Número de cheque asignado
  transactionTime: Date // Hora de la transacción
  totalAmount: number // Monto total registrado
  paymentMethod: string // Método de pago usado
  success: boolean // Si la transacción fue exitosa
}

export interface IPOSAdapter {
  // Turnos
  openShift(data: ShiftOpenData): Promise<{ shiftId: number; staffName: string }>
  closeShift(shiftId: string, data: ShiftCloseData): Promise<void>

  // Órdenes
  createEmptyOrder(data: OrderCreateData): Promise<{ folio: number }>
  addItemToOrder(folio: number, item: OrderAddItemData): Promise<void>
  cancelOrderItem(folio: number, movementId: number, reason: string, user: string): Promise<void>
  // Divide una orden: mueve `splitRatio` (0<r<1) de cada línea a una orden hija nueva.
  splitOrder(parentFolio: number, splitRatio: number): Promise<{ parentFolio: number; childFolio: number }>

  // Pagos
  applyPayment(folio: number, payment: PaymentData): Promise<void>
  closeAndPayOrder(folio: number): Promise<{ finalCheckNumber: number }>

  // ✅ NUEVO: Pago inteligente con manejo de pagos parciales
  applyIntelligentPayment(orderExternalId: string, payment: IntelligentPaymentData): Promise<PaymentResult>

  // ✅ NUEVO: Pago rápido (fast payment) para registro de transacciones directas
  createFastPayment(data: FastPaymentData): Promise<FastPaymentResult>
}
