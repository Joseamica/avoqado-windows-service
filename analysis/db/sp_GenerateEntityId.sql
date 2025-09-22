
                                                                                                                                                                                                                                                             
CREATE PROCEDURE dbo.sp_GenerateEntityId
                                                                                                                                                                                                                     
    @EntityType VARCHAR(50),
                                                                                                                                                                                                                                 
    @WorkspaceId UNIQUEIDENTIFIER = NULL,
                                                                                                                                                                                                                    
    @IdTurno BIGINT = NULL,
                                                                                                                                                                                                                                  
    @Folio BIGINT = NULL,
                                                                                                                                                                                                                                    
    @Movimiento INT = NULL,
                                                                                                                                                                                                                                  
    @EntityId VARCHAR(200) OUTPUT
                                                                                                                                                                                                                            
AS
                                                                                                                                                                                                                                                           
BEGIN
                                                                                                                                                                                                                                                        
    DECLARE @version DECIMAL(10,6)
                                                                                                                                                                                                                           
    DECLARE @instanceId VARCHAR(50)
                                                                                                                                                                                                                          

                                                                                                                                                                                                                                                             
    -- Obtener versión y instance ID
                                                                                                                                                                                                                        
    SET @version = dbo.fn_GetSoftRestaurantVersion()
                                                                                                                                                                                                         
    SELECT @instanceId = InstanceId FROM AvoqadoInstanceInfo
                                                                                                                                                                                                 

                                                                                                                                                                                                                                                             
    -- Generar Entity ID según la versión
                                                                                                                                                                                                                  
    IF @version >= 11.0
                                                                                                                                                                                                                                      
    BEGIN
                                                                                                                                                                                                                                                    
        -- Formato v11: Usar WorkspaceId
                                                                                                                                                                                                                     
        IF @EntityType = 'order'
                                                                                                                                                                                                                             
            SET @EntityId = CAST(@WorkspaceId AS VARCHAR(36))
                                                                                                                                                                                                
        ELSE IF @EntityType = 'orderitem'
                                                                                                                                                                                                                    
            SET @EntityId = CAST(@WorkspaceId AS VARCHAR(36)) + ':' + CAST(@Movimiento AS VARCHAR(10))
                                                                                                                                                       
        ELSE IF @EntityType = 'shift'
                                                                                                                                                                                                                        
            SET @EntityId = CAST(@WorkspaceId AS VARCHAR(36))
                                                                                                                                                                                                
    END
                                                                                                                                                                                                                                                      
    ELSE
                                                                                                                                                                                                                                                     
    BEGIN
                                                                                                                                                                                                                                                    
        -- Formato v10: Usar formato tradicional
                                                                                                                                                                                                             
        IF @EntityType = 'order'
                                                                                                                                                                                                                             
            SET @EntityId = @instanceId + ':' + CAST(@IdTurno AS VARCHAR(20)) + ':' + CAST(@Folio AS VARCHAR(20))
                                                                                                                                            
        ELSE IF @EntityType = 'orderitem'
                                                                                                                                                                                                                    
            SET @EntityId = @instanceId + ':' + CAST(@IdTurno AS VARCHAR(20)) + ':' + CAST(@Folio AS VARCHAR(20)) + ':' + CAST(@Movimiento AS VARCHAR(10))
                                                                                                   
        ELSE IF @EntityType = 'shift'
                                                                                                                                                                                                                        
            SET @EntityId = CAST(@IdTurno AS VARCHAR(20))
                                                                                                                                                                                                    
    END
                                                                                                                                                                                                                                                      
END                                                                                                                                                                                                                                                            
