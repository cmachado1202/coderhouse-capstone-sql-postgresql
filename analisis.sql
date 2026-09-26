-- CAPSTONE | Carolina Machado | Ejecutar después de estructura.sql.
-- Todas las cifras monetarias están expresadas en ARS ficticios.
-- Cada SELECT es independiente; el prefijo capstone evita depender del search_path.

-- Q1 | ¿Qué cinco clientes aportan más ingresos y cuánto concentran?
-- Se excluyen cancelaciones y se mantiene el ID para no agrupar homónimos.
WITH gasto_cliente AS (
    SELECT c.cliente_id,c.nombre,COUNT(v.pedido_id) AS pedidos,
           SUM(v.ingreso_neto) AS gasto_total
    FROM capstone.clientes AS c
    JOIN capstone.v_ventas AS v ON v.cliente_id=c.cliente_id
    GROUP BY c.cliente_id,c.nombre
)
SELECT cliente_id,nombre,pedidos,gasto_total,
       round(100*gasto_total/NULLIF(SUM(gasto_total) OVER (),0),2) AS porcentaje_ingresos
FROM gasto_cliente
ORDER BY gasto_total DESC,cliente_id
LIMIT 5;

-- Q2 | ¿Cómo evolucionan las ventas mensuales, el ticket y el acumulado?
-- Calendario completo para no confundir un mes sin ventas con un mes inexistente.
-- LAG compara contra el mes calendario previo; NULLIF evita dividir por cero.
WITH meses AS (
    SELECT generate_series(DATE '2026-01-01',DATE '2026-06-01',INTERVAL '1 month')::DATE AS mes
), mensual AS (
    SELECT date_trunc('month',fecha)::DATE AS mes,
           COUNT(*) AS pedidos,SUM(ingreso_neto) AS ingresos
    FROM capstone.v_ventas GROUP BY date_trunc('month',fecha)::DATE
), completo AS (
    SELECT m.mes,COALESCE(v.pedidos,0) AS pedidos,COALESCE(v.ingresos,0) AS ingresos
    FROM meses AS m LEFT JOIN mensual AS v ON v.mes=m.mes
), comparacion AS (
    SELECT *,LAG(ingresos) OVER (ORDER BY mes) AS ingresos_previos FROM completo
)
SELECT mes,pedidos,ingresos,round(ingresos/NULLIF(pedidos,0),2) AS ticket_promedio,
       round(100*(ingresos-ingresos_previos)/NULLIF(ingresos_previos,0),2) AS variacion_pct,
       SUM(ingresos) OVER (ORDER BY mes ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS acumulado
FROM comparacion ORDER BY mes;

-- Q3 | ¿Cuáles son los tres productos menos vendidos, incluidos los de venta cero?
-- LEFT JOIN conserva todo el catálogo. COUNT(v.pedido_id) no cuenta la fila nula.
SELECT p.producto_id,p.nombre,p.categoria,
       COALESCE(SUM(v.cantidad),0) AS unidades,
       COUNT(v.pedido_id) AS pedidos,
       COALESCE(SUM(v.ingreso_neto),0) AS ingresos
FROM capstone.productos AS p
LEFT JOIN capstone.v_ventas AS v ON v.producto_id=p.producto_id
GROUP BY p.producto_id,p.nombre,p.categoria
ORDER BY unidades ASC,p.producto_id
LIMIT 3;

-- Q4 | ¿Qué pedidos lideran cada categoría por importe?
-- El ranking se calcula sobre pedidos individuales, no sobre productos agregados.
-- RANK conserva empates; puede devolver más de tres filas por categoría.
-- El ID solo desempata la presentación: no altera el empate comercial en RANK.
WITH ranking AS (
    SELECT categoria,pedido_id,fecha,producto,ingreso_neto,
           RANK() OVER (PARTITION BY categoria ORDER BY ingreso_neto DESC) AS posicion
    FROM capstone.v_ventas
)
SELECT categoria,posicion,pedido_id,fecha,producto,ingreso_neto
FROM ranking WHERE posicion<=3
ORDER BY categoria,posicion,pedido_id;

-- Q5 | ¿Qué categorías superan ARS 500.000 netos en el semestre?
-- Umbral exploratorio, no objetivo acordado ni prueba de rentabilidad.
SELECT categoria,COUNT(*) AS pedidos,SUM(cantidad) AS unidades,
       SUM(ingreso_neto) AS ingresos
FROM capstone.v_ventas
GROUP BY categoria
HAVING SUM(ingreso_neto)>500000
ORDER BY ingresos DESC,categoria;

-- Q6 | ¿Qué clientes no tienen compras completadas?
-- El universo inicial incluye todos los clientes, aunque tengan cero pedidos.
SELECT c.cliente_id,c.nombre,c.ciudad,COUNT(v.pedido_id) AS compras_completadas
FROM capstone.clientes AS c
LEFT JOIN capstone.v_ventas AS v ON v.cliente_id=c.cliente_id
GROUP BY c.cliente_id,c.nombre,c.ciudad
HAVING COUNT(v.pedido_id)=0
ORDER BY c.cliente_id;

-- Q7 | ¿Cómo cambia cada categoría por mes respecto de su promedio semestral?
-- Misma granularidad mes/categoría para ranking, acumulado y comparación.
-- El promedio incluye los seis meses, incluso si alguno tiene cero ventas.
WITH meses AS (
    SELECT generate_series(DATE '2026-01-01',DATE '2026-06-01',INTERVAL '1 month')::DATE AS mes
), categorias AS (
    SELECT DISTINCT categoria FROM capstone.productos
), totales AS (
    SELECT date_trunc('month',fecha)::DATE AS mes,categoria,SUM(ingreso_neto) AS ingresos
    FROM capstone.v_ventas GROUP BY date_trunc('month',fecha)::DATE,categoria
), completo AS (
    SELECT m.mes,c.categoria,COALESCE(t.ingresos,0) AS ingresos
    FROM meses AS m CROSS JOIN categorias AS c
    LEFT JOIN totales AS t ON t.mes=m.mes AND t.categoria=c.categoria
), ventanas AS (
    SELECT *,RANK() OVER (PARTITION BY mes ORDER BY ingresos DESC) AS ranking_mes,
           SUM(ingresos) OVER (PARTITION BY categoria ORDER BY mes ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS acumulado_categoria,
           AVG(ingresos) OVER (PARTITION BY categoria) AS promedio_semestral
    FROM completo
)
SELECT mes,categoria,ingresos,ranking_mes,acumulado_categoria,
       round(promedio_semestral,2) AS promedio_semestral,
       CASE WHEN ingresos>promedio_semestral THEN 'Por encima'
            WHEN ingresos<promedio_semestral THEN 'Por debajo'
            ELSE 'Igual al promedio' END AS comparacion
FROM ventanas ORDER BY mes,ranking_mes,categoria;

-- Q8 | ¿Qué proporción se cancela y qué importe nominal representa?
-- Importe cancelado NO equivale a pérdida comprobada ni a ingreso reconocido.
SELECT estado,COUNT(*) AS pedidos,
       round(100.0*COUNT(*)/SUM(COUNT(*)) OVER (),2) AS porcentaje_pedidos,
       SUM(round(cantidad*precio_unitario*(1-descuento_pct/100),2)) AS importe_nominal
FROM capstone.pedidos GROUP BY estado ORDER BY estado;

-- Q9 | Control de calidad reproducible: cada excepción tiene una causa visible.
SELECT resultado,COUNT(*) AS filas
FROM capstone.v_pedidos_normalizados GROUP BY resultado ORDER BY resultado;

-- Q10 | Aplicación de JSONB: explorar bebidas por temperatura sin multiplicar filas.
SELECT producto_id,nombre,atributos->>'temperatura' AS temperatura
FROM capstone.productos
WHERE categoria='Bebidas' AND atributos @> '{"temperatura":"fría"}'::JSONB
ORDER BY producto_id;

-- Q11 | Diagnóstico de rendimiento, no promesa de mejora.
-- Con 390 filas el planificador puede preferir Seq Scan, lo cual es válido.
-- EXPLAIN ANALYZE ejecuta realmente este SELECT de solo lectura.
EXPLAIN (ANALYZE, BUFFERS)
SELECT pedido_id,fecha,precio_unitario
FROM capstone.pedidos
WHERE fecha>=DATE '2026-06-01' AND fecha<DATE '2026-07-01'
ORDER BY fecha,pedido_id;
