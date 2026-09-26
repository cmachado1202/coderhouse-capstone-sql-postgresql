-- CAPSTONE | Carolina Machado | Cafetería La Estación (negocio ficticio)
-- PostgreSQL 16 o superior. Dataset sintético, determinista, enero-junio 2026.
-- PRIMERA VEZ: ejecutar aparte en la base postgres, fuera de una transacción:
-- CREATE DATABASE capstone_project;
-- Luego conectarse a capstone_project y ejecutar este archivo completo.
-- El script no borra objetos existentes: si ya existe el esquema, se detiene.
-- Para repetir sin eliminar trabajo, usar otra base vacía.

BEGIN;
CREATE SCHEMA capstone;
SET LOCAL search_path TO capstone, public;
SET LOCAL datestyle TO 'ISO, YMD';

CREATE TABLE clientes (
    cliente_id INTEGER PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    ciudad VARCHAR(60) NOT NULL,
    fecha_registro DATE NOT NULL
);

CREATE TABLE productos (
    producto_id INTEGER PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    categoria VARCHAR(40) NOT NULL,
    precio_catalogo NUMERIC(12,2) NOT NULL,
    atributos JSONB NOT NULL DEFAULT '{}'::JSONB,
    CONSTRAINT chk_producto_precio CHECK (precio_catalogo > 0 AND precio_catalogo < 1000000),
    CONSTRAINT chk_producto_categoria CHECK (categoria IN ('Bebidas','Panadería','Comidas')),
    CONSTRAINT chk_atributos_objeto CHECK (jsonb_typeof(atributos) = 'object')
);

-- Granularidad explícita: cada pedido contiene UN producto y una cantidad.
-- Es la simplificación permitida por la consigna. No representa un ticket mixto.
CREATE TABLE pedidos (
    pedido_id INTEGER PRIMARY KEY,
    cliente_id INTEGER NOT NULL REFERENCES clientes(cliente_id) ON DELETE RESTRICT,
    producto_id INTEGER NOT NULL REFERENCES productos(producto_id) ON DELETE RESTRICT,
    fecha DATE NOT NULL,
    cantidad INTEGER NOT NULL,
    precio_unitario NUMERIC(12,2) NOT NULL,
    descuento_pct NUMERIC(5,2) NOT NULL DEFAULT 0,
    estado VARCHAR(12) NOT NULL,
    precio_recuperado BOOLEAN NOT NULL DEFAULT FALSE,
    fecha_recuperada BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT chk_cantidad CHECK (cantidad BETWEEN 1 AND 1000),
    CONSTRAINT chk_precio_pedido CHECK (precio_unitario > 0 AND precio_unitario < 1000000),
    CONSTRAINT chk_descuento CHECK (descuento_pct BETWEEN 0 AND 100),
    CONSTRAINT chk_estado CHECK (estado IN ('completado','cancelado'))
);

-- Se conservan los datos originales para poder explicar y auditar cada decisión.
CREATE TABLE pedidos_origen (
    registro_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pedido_id INTEGER NOT NULL,
    cliente_id INTEGER,
    producto_id INTEGER,
    fecha_texto TEXT,
    fecha_comprobante TEXT,
    cantidad INTEGER,
    precio_texto TEXT,
    precio_comprobante TEXT,
    descuento_texto TEXT,
    estado_texto TEXT
);

-- Identidades inventadas: los emails usan el dominio reservado example.com.
INSERT INTO clientes (cliente_id,nombre,email,ciudad,fecha_registro)
SELECT n, 'Cliente ' || lpad(n::TEXT,2,'0'),
       'cliente' || n || '@example.com',
       CASE WHEN n % 3 = 0 THEN 'Vicente López' ELSE 'CABA' END,
       DATE '2025-12-01' + (n-1)
FROM generate_series(1,30) AS g(n);

INSERT INTO productos (producto_id,nombre,categoria,precio_catalogo,atributos) VALUES
 (1,'Café espresso','Bebidas',2500,'{"temperatura":"caliente"}'),
 (2,'Café con leche','Bebidas',3200,'{"temperatura":"caliente"}'),
 (3,'Té en hebras','Bebidas',2200,'{"temperatura":"caliente"}'),
 (4,'Limonada','Bebidas',3800,'{"temperatura":"fría"}'),
 (5,'Medialuna','Panadería',1800,'{"presentacion":"unidad"}'),
 (6,'Tostadas','Panadería',3500,'{"presentacion":"porción"}'),
 (7,'Budín','Panadería',4200,'{"presentacion":"porción"}'),
 (8,'Sándwich de pollo','Comidas',8500,'{"servicio":"almuerzo"}'),
 (9,'Ensalada de estación','Comidas',7800,'{"servicio":"almuerzo"}'),
 (10,'Tarta de verduras','Comidas',6500,'{"servicio":"almuerzo"}'),
 (11,'Combo degustación','Comidas',12000,'{"servicio":"especial"}'),
 (12,'Chocolate frío','Bebidas',4500,'{"temperatura":"fría"}');

-- 40, 50, 60, 70, 80 y 90 pedidos por mes: 390 pedidos únicos.
-- El patrón de crecimiento es parte del diseño sintético, no un descubrimiento real.
-- Precios históricos: los de cada comprobante; nunca se recuperan del catálogo actual.
WITH calendario AS (
    SELECT m, n,
           row_number() OVER (ORDER BY m,n)::INTEGER AS id,
           (DATE '2026-01-01' + (m-1)*INTERVAL '1 month')::DATE + ((n*7+m)%28) AS fecha
    FROM generate_series(1,6) AS meses(m)
    CROSS JOIN LATERAL generate_series(1,30+10*m) AS pedidos_mes(n)
), base AS (
    SELECT id, fecha, 1+((id*7+id/5)%28) AS cliente_id,
           CASE WHEN id IN (19,101,223,359) THEN 11 ELSE 1+((id*3+id/7)%10) END AS producto_id,
           1+(id%3) AS cantidad
    FROM calendario
), importes AS (
    SELECT b.*, p.precio_catalogo AS precio,
           CASE WHEN id%5=0 THEN 10 ELSE 0 END AS descuento
    FROM base AS b JOIN productos AS p USING (producto_id)
)
INSERT INTO pedidos_origen
 (pedido_id,cliente_id,producto_id,fecha_texto,fecha_comprobante,cantidad,
  precio_texto,precio_comprobante,descuento_texto,estado_texto)
SELECT id,cliente_id,producto_id,
       CASE WHEN id IN (8,88,188) THEN NULL ELSE fecha::TEXT END,
       fecha::TEXT,cantidad,
       CASE WHEN id IN (5,45,105,205,305) THEN NULL
            WHEN id IN (6,66,166) THEN replace(precio::TEXT,'.',',')
            ELSE precio::TEXT END,
       precio::TEXT,
       CASE WHEN descuento=0 AND id%4=0 THEN NULL ELSE descuento::TEXT END,
       CASE WHEN id%17=0 THEN ' CANCELADO ' ELSE ' Completado ' END
FROM importes ORDER BY id;

-- Dos reintentos idénticos de carga: conservar primera aparición por pedido_id.
INSERT INTO pedidos_origen
 (pedido_id,cliente_id,producto_id,fecha_texto,fecha_comprobante,cantidad,
  precio_texto,precio_comprobante,descuento_texto,estado_texto)
SELECT pedido_id,cliente_id,producto_id,fecha_texto,fecha_comprobante,cantidad,
       precio_texto,precio_comprobante,descuento_texto,estado_texto
FROM pedidos_origen WHERE pedido_id IN (10,20);

-- Seis errores adicionales. No se corrigen inventando datos; van a cuarentena.
INSERT INTO pedidos_origen
 (pedido_id,cliente_id,producto_id,fecha_texto,fecha_comprobante,cantidad,
  precio_texto,precio_comprobante,descuento_texto,estado_texto) VALUES
 (9001,999,1,'2026-02-10',NULL,1,'2500',NULL,'0','completado'),
 (9002,1,1,NULL,NULL,1,'2500',NULL,'0','completado'),
 (9003,1,1,'2026-02-10',NULL,1,'-2500',NULL,'0','completado'),
 (9004,1,1,'2026-02-10',NULL,0,'2500',NULL,'0','completado'),
 (9005,1,999,'2026-02-10',NULL,1,'2500',NULL,'0','completado'),
 (9006,1,1,'2026-02-30',NULL,1,'2500',NULL,'0','completado');

-- PERFIL INICIAL. Diagnosticar antes de transformar para conservar evidencia.
SELECT COUNT(*) AS filas_origen,
       COUNT(*) FILTER (WHERE precio_texto IS NULL) AS precios_nulos,
       COUNT(*) FILTER (WHERE fecha_texto IS NULL) AS fechas_nulas,
       COUNT(*) FILTER (WHERE descuento_texto IS NULL) AS descuentos_nulos,
       COUNT(*) - COUNT(DISTINCT pedido_id) AS duplicados
FROM pedidos_origen;

-- Separar limpieza de validación evita que un texto inválido aborte toda la carga.
-- pg_input_is_valid está disponible desde PostgreSQL 16.
CREATE VIEW v_pedidos_normalizados AS
WITH textos AS (
    SELECT o.*,
           NULLIF(btrim(fecha_texto),'') AS fecha_limpia,
           NULLIF(btrim(fecha_comprobante),'') AS fecha_respaldo,
           replace(NULLIF(btrim(precio_texto),''),',','.') AS precio_limpio,
           replace(NULLIF(btrim(precio_comprobante),''),',','.') AS precio_respaldo,
           replace(NULLIF(btrim(descuento_texto),''),',','.') AS descuento_limpio,
           lower(btrim(estado_texto)) AS estado_limpio,
           row_number() OVER (PARTITION BY pedido_id ORDER BY registro_id) AS orden_copia
    FROM pedidos_origen AS o
), tipados AS (
    SELECT t.*,
           COALESCE(
             CASE WHEN fecha_limpia ~ '^\d{4}-\d{2}-\d{2}$' AND pg_input_is_valid(fecha_limpia,'date') THEN fecha_limpia::DATE END,
             CASE WHEN fecha_respaldo ~ '^\d{4}-\d{2}-\d{2}$' AND pg_input_is_valid(fecha_respaldo,'date') THEN fecha_respaldo::DATE END
           ) AS fecha,
           COALESCE(
             CASE WHEN precio_limpio ~ '^-?[0-9]+([.][0-9]{1,2})?$' AND pg_input_is_valid(precio_limpio,'numeric(12,2)') THEN precio_limpio::NUMERIC(12,2) END,
             CASE WHEN precio_respaldo ~ '^-?[0-9]+([.][0-9]{1,2})?$' AND pg_input_is_valid(precio_respaldo,'numeric(12,2)') THEN precio_respaldo::NUMERIC(12,2) END
           ) AS precio_unitario,
           CASE WHEN descuento_limpio IS NULL THEN COALESCE(descuento_limpio::NUMERIC,0)
                WHEN descuento_limpio ~ '^[0-9]+([.][0-9]{1,2})?$'
                     AND pg_input_is_valid(descuento_limpio,'numeric(5,2)')
                THEN descuento_limpio::NUMERIC(5,2) END AS descuento_pct
    FROM textos AS t
)
SELECT t.*,
       CASE WHEN orden_copia>1 THEN 'duplicado'
            WHEN c.cliente_id IS NULL THEN 'cliente_inexistente'
            WHEN p.producto_id IS NULL THEN 'producto_inexistente'
            WHEN fecha IS NULL THEN 'fecha_no_recuperable'
            WHEN fecha < DATE '2026-01-01' OR fecha >= DATE '2026-07-01' THEN 'fecha_fuera_periodo'
            WHEN cantidad IS NULL OR cantidad NOT BETWEEN 1 AND 1000 THEN 'cantidad_invalida'
            WHEN precio_unitario IS NULL OR precio_unitario<=0 OR precio_unitario>=1000000 THEN 'precio_invalido'
            WHEN descuento_pct IS NULL OR descuento_pct NOT BETWEEN 0 AND 100 THEN 'descuento_invalido'
            WHEN estado_limpio IS NULL OR estado_limpio NOT IN ('completado','cancelado') THEN 'estado_invalido'
            ELSE 'aceptado' END AS resultado
FROM tipados AS t
LEFT JOIN clientes AS c ON c.cliente_id=t.cliente_id
LEFT JOIN productos AS p ON p.producto_id=t.producto_id;

CREATE TABLE pedidos_rechazados AS
SELECT registro_id,pedido_id,resultado AS motivo
FROM v_pedidos_normalizados WHERE resultado <> 'aceptado';
ALTER TABLE pedidos_rechazados ADD PRIMARY KEY (registro_id);
ALTER TABLE pedidos_rechazados ADD FOREIGN KEY (registro_id) REFERENCES pedidos_origen(registro_id);

INSERT INTO pedidos
 (pedido_id,cliente_id,producto_id,fecha,cantidad,precio_unitario,descuento_pct,
  estado,precio_recuperado,fecha_recuperada)
SELECT pedido_id,cliente_id,producto_id,fecha,cantidad,precio_unitario,descuento_pct,
       estado_limpio,precio_limpio IS NULL,fecha_limpia IS NULL
FROM v_pedidos_normalizados WHERE resultado='aceptado';

-- Una única definición de ingresos para evitar discrepancias entre reportes.
-- Importe neto de descuentos; no es utilidad, y no se modelan impuestos ni costos.
CREATE VIEW v_ventas AS
SELECT pe.pedido_id,pe.cliente_id,pe.producto_id,pe.fecha,
       pe.cantidad,pe.precio_unitario,pe.descuento_pct,
       pr.nombre AS producto,pr.categoria,
       round(pe.cantidad*pe.precio_unitario*(1-pe.descuento_pct/100),2) AS ingreso_neto
FROM pedidos AS pe
JOIN productos AS pr ON pr.producto_id=pe.producto_id
WHERE pe.estado='completado';

-- B-Tree de fecha para consultas temporales; las PK ya crean sus propios índices.
CREATE INDEX idx_pedidos_fecha ON pedidos(fecha);
ANALYZE clientes;
ANALYZE productos;
ANALYZE pedidos;

-- Conciliación: cada fila original debe quedar aceptada o rechazada, una sola vez.
DO $$
BEGIN
    IF (SELECT COUNT(*) FROM pedidos_origen) <>
       (SELECT COUNT(*) FROM pedidos)+(SELECT COUNT(*) FROM pedidos_rechazados) THEN
       RAISE EXCEPTION 'La conciliación de carga no cierra';
    END IF;
    IF (SELECT COUNT(*) FROM pedidos) <> 390 THEN
       RAISE EXCEPTION 'El dataset no contiene los 390 pedidos esperados';
    END IF;
END $$;
COMMIT;

SELECT resultado,COUNT(*) AS filas
FROM capstone.v_pedidos_normalizados GROUP BY resultado ORDER BY resultado;
