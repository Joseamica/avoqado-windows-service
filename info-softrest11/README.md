# SoftRestaurant Database Reference

Esta carpeta contiene información de referencia sobre la base de datos de SoftRestaurant v11 para proporcionar contexto técnico al desarrollo del servicio de sincronización Avoqado.

## Estructura del Directorio

### 📊 `database-schema/`
Información estructural de la base de datos SQL Server 2014:

- **`table-definitions.csv`** - Lista completa de las 366 tablas del sistema
- **`table-relationships.csv`** - Todas las columnas y tipos de datos de las tablas
- **`core-relationships.csv`** - Relaciones principales entre tablas críticas
- **`table-create-statements.sql`** - Scripts CREATE TABLE para recrear la estructura

#### `constraints/`
- **`foreign-keys.csv`** - Las 189 relaciones de foreign key del sistema
- **`indexes.csv`** - Índices clustered y non-clustered para performance
- **`primary-keys.csv`** - Claves primarias de todas las tablas
- **`objects-db.csv`** - Objetos de base de datos (tablas, vistas, procedures)

### 🔍 `sql-traces/`
Trazas reales del SQL Server Profiler que documentan flujos de negocio:

- **`shift-close-flow.sql`** - Trace completo del proceso de cierre de turno
  - Operaciones de archivo (temp* → permanent tables)
  - Secuencia crítica: UPDATE turnos SET cierre=... 
  - Performance metrics reales (203ms para finalización)

- **`order-lifecycle-flow.sql`** - Trace del ciclo completo de una orden
  - Abrir turno → Crear orden → Agregar items → Imprimir → Pagar
  - Patrones de transacción y timing real del POS

### 🔬 `table-analysis/`
Análisis específicos de tablas críticas:

- **`turnos-table-details.sql`** - Query para analizar estructura de tabla turnos
  - Documenta la arquitectura dual-key (idturnointerno vs idturno)
  - Crítica para entender Entity ID format del servicio

## Propósito

Esta información permite:

1. **Resolver confusiones** sobre estructura de datos durante desarrollo
2. **Consultar relaciones** entre tablas sin acceso directo a la BD
3. **Entender flujos de negocio** reales a través de traces del profiler
4. **Validar operaciones** del servicio contra comportamiento real del POS

## Notas Importantes

- Todos los traces son de **SQL Server 2014 Express Edition (32-bit)**
- Los flujos documentan **comportamiento real en producción**
- La información es **read-only** y solo para referencia técnica
- Los CREATE statements pueden usarse para **recrear esquema en desarrollo**

## Uso Durante Desarrollo

```bash
# Buscar definición de tabla específica
grep -i "tempcheques" database-schema/table-definitions.csv

# Verificar relaciones de foreign key
grep -i "tempcheques\|turnos" database-schema/constraints/foreign-keys.csv

# Analizar timing de operaciones
grep -i "UPDATE turnos" sql-traces/shift-close-flow.sql
```

Esta estructura facilita la consulta rápida de información durante el desarrollo sin necesidad de conectarse a la base de datos de producción.