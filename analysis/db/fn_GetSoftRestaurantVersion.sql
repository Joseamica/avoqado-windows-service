
                                                                                                                                                                                                                                                             
CREATE FUNCTION dbo.fn_GetSoftRestaurantVersion()
                                                                                                                                                                                                            
RETURNS DECIMAL(10,6)
                                                                                                                                                                                                                                        
AS
                                                                                                                                                                                                                                                           
BEGIN
                                                                                                                                                                                                                                                        
    DECLARE @version DECIMAL(10,6)
                                                                                                                                                                                                                           
    SELECT @version = ISNULL(versiondb, 10.0) FROM parametros2
                                                                                                                                                                                               
    RETURN @version
                                                                                                                                                                                                                                          
END                                                                                                                                                                                                                                                            
