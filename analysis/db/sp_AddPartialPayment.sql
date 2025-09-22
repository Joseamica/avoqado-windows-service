
                                                                                                                                                                                                                                                             
CREATE PROCEDURE dbo.sp_AddPartialPayment
                                                                                                                                                                                                                    
    @Folio BIGINT,
                                                                                                                                                                                                                                           
    @Amount MONEY,
                                                                                                                                                                                                                                           
    @TipAmount MONEY = 0,
                                                                                                                                                                                                                                    
    @PaymentMethodId VARCHAR(50),
                                                                                                                                                                                                                            
    @Reference VARCHAR(255) = NULL,
                                                                                                                                                                                                                          
    @ExternalPaymentId VARCHAR(255) = NULL,
                                                                                                                                                                                                                  
    @PaymentData NVARCHAR(MAX) = NULL,
                                                                                                                                                                                                                       
    @PartialPaymentId BIGINT OUTPUT
                                                                                                                                                                                                                          
AS
                                                                                                                                                                                                                                                           
BEGIN
                                                                                                                                                                                                                                                        
    INSERT INTO AvoqadoPartialPayments (
                                                                                                                                                                                                                     
        Folio, Amount, TipAmount, PaymentMethodId, Reference,
                                                                                                                                                                                                
        ExternalPaymentId, PaymentData
                                                                                                                                                                                                                       
    )
                                                                                                                                                                                                                                                        
    VALUES (
                                                                                                                                                                                                                                                 
        @Folio, @Amount, @TipAmount, @PaymentMethodId, @Reference,
                                                                                                                                                                                           
        @ExternalPaymentId, @PaymentData
                                                                                                                                                                                                                     
    )
                                                                                                                                                                                                                                                        

                                                                                                                                                                                                                                                             
    SET @PartialPaymentId = SCOPE_IDENTITY()
                                                                                                                                                                                                                 
END                                                                                                                                                                                                                                                            
