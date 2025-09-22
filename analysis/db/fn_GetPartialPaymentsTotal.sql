
                                                                                                                                                                                                                                                             
CREATE FUNCTION dbo.fn_GetPartialPaymentsTotal(@Folio BIGINT)
                                                                                                                                                                                                
RETURNS MONEY
                                                                                                                                                                                                                                                
AS
                                                                                                                                                                                                                                                           
BEGIN
                                                                                                                                                                                                                                                        
    DECLARE @total MONEY
                                                                                                                                                                                                                                     
    SELECT @total = ISNULL(SUM(Amount), 0)
                                                                                                                                                                                                                   
    FROM AvoqadoPartialPayments
                                                                                                                                                                                                                              
    WHERE Folio = @Folio AND IsProcessed = 0
                                                                                                                                                                                                                 
    RETURN @total
                                                                                                                                                                                                                                            
END                                                                                                                                                                                                                                                            
