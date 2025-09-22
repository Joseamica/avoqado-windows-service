
                                                                                                                                                                                                                                                             
CREATE FUNCTION dbo.fn_CanCompleteOrderPayment(@Folio BIGINT, @NewPaymentAmount MONEY)
                                                                                                                                                                       
RETURNS BIT
                                                                                                                                                                                                                                                  
AS
                                                                                                                                                                                                                                                           
BEGIN
                                                                                                                                                                                                                                                        
    DECLARE @orderTotal MONEY
                                                                                                                                                                                                                                
    DECLARE @partialTotal MONEY
                                                                                                                                                                                                                              
    DECLARE @existingPayments MONEY
                                                                                                                                                                                                                          

                                                                                                                                                                                                                                                             
    -- Obtener total de la orden
                                                                                                                                                                                                                             
    SELECT @orderTotal = ISNULL(total, 0) FROM tempcheques WHERE folio = @Folio
                                                                                                                                                                              

                                                                                                                                                                                                                                                             
    -- Obtener pagos parciales pendientes
                                                                                                                                                                                                                    
    SET @partialTotal = dbo.fn_GetPartialPaymentsTotal(@Folio)
                                                                                                                                                                                               

                                                                                                                                                                                                                                                             
    -- Obtener pagos ya aplicados en tempchequespagos
                                                                                                                                                                                                        
    SELECT @existingPayments = ISNULL(SUM(importe), 0) FROM tempchequespagos WHERE folio = @Folio
                                                                                                                                                            

                                                                                                                                                                                                                                                             
    -- Verificar si el total de pagos cubre la orden
                                                                                                                                                                                                         
    IF (@partialTotal + @existingPayments + @NewPaymentAmount) >= @orderTotal
                                                                                                                                                                                
        RETURN 1
                                                                                                                                                                                                                                             

                                                                                                                                                                                                                                                             
    RETURN 0
                                                                                                                                                                                                                                                 
END                                                                                                                                                                                                                                                            
