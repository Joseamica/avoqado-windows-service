
                                                                                                                                                                                                                                                             
CREATE PROCEDURE dbo.sp_ProcessPartialPayments
                                                                                                                                                                                                               
    @Folio BIGINT,
                                                                                                                                                                                                                                           
    @TotalProcessed MONEY OUTPUT,
                                                                                                                                                                                                                            
    @PaymentsCount INT OUTPUT
                                                                                                                                                                                                                                
AS
                                                                                                                                                                                                                                                           
BEGIN
                                                                                                                                                                                                                                                        
    DECLARE @paymentMethodId VARCHAR(50)
                                                                                                                                                                                                                     
    DECLARE @amount MONEY
                                                                                                                                                                                                                                    
    DECLARE @tipAmount MONEY
                                                                                                                                                                                                                                 
    DECLARE @reference VARCHAR(255)
                                                                                                                                                                                                                          

                                                                                                                                                                                                                                                             
    SET @TotalProcessed = 0
                                                                                                                                                                                                                                  
    SET @PaymentsCount = 0
                                                                                                                                                                                                                                   

                                                                                                                                                                                                                                                             
    -- Cursor para procesar todos los pagos parciales pendientes
                                                                                                                                                                                             
    DECLARE payment_cursor CURSOR LOCAL FAST_FORWARD FOR
                                                                                                                                                                                                     
        SELECT PaymentMethodId, Amount, TipAmount, Reference
                                                                                                                                                                                                 
        FROM AvoqadoPartialPayments
                                                                                                                                                                                                                          
        WHERE Folio = @Folio AND IsProcessed = 0
                                                                                                                                                                                                             
        ORDER BY CreatedAt
                                                                                                                                                                                                                                   

                                                                                                                                                                                                                                                             
    OPEN payment_cursor
                                                                                                                                                                                                                                      
    FETCH NEXT FROM payment_cursor INTO @paymentMethodId, @amount, @tipAmount, @reference
                                                                                                                                                                    

                                                                                                                                                                                                                                                             
    WHILE @@FETCH_STATUS = 0
                                                                                                                                                                                                                                 
    BEGIN
                                                                                                                                                                                                                                                    
        -- Insertar en tempchequespagos
                                                                                                                                                                                                                      
        INSERT INTO tempchequespagos (folio, idformadepago, importe, propina, referencia)
                                                                                                                                                                    
        VALUES (@Folio, @paymentMethodId, @amount, @tipAmount, @reference)
                                                                                                                                                                                   

                                                                                                                                                                                                                                                             
        SET @TotalProcessed = @TotalProcessed + @amount
                                                                                                                                                                                                      
        SET @PaymentsCount = @PaymentsCount + 1
                                                                                                                                                                                                              

                                                                                                                                                                                                                                                             
        FETCH NEXT FROM payment_cursor INTO @paymentMethodId, @amount, @tipAmount, @reference
                                                                                                                                                                
    END
                                                                                                                                                                                                                                                      

                                                                                                                                                                                                                                                             
    CLOSE payment_cursor
                                                                                                                                                                                                                                     
    DEALLOCATE payment_cursor
                                                                                                                                                                                                                                

                                                                                                                                                                                                                                                             
    -- Marcar todos los pagos parciales como procesados
                                                                                                                                                                                                      
    UPDATE AvoqadoPartialPayments
                                                                                                                                                                                                                            
    SET IsProcessed = 1, ProcessedAt = GETDATE()
                                                                                                                                                                                                             
    WHERE Folio = @Folio AND IsProcessed = 0
                                                                                                                                                                                                                 
END                                                                                                                                                                                                                                                            
