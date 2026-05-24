-- ═══════════════════════════════════════════════════════════════════
-- FARMACIA WALLET — Supabase SQL Setup
-- Ejecuta este archivo en el SQL Editor de Supabase (en orden)
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. TABLA CUSTOMERS ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS customers (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at  TIMESTAMPTZ DEFAULT now(),
  business_id TEXT NOT NULL,
  nombre      TEXT NOT NULL,
  email       TEXT,
  telefono    TEXT,
  sellos      INTEGER DEFAULT 0,
  nivel       TEXT DEFAULT 'Bronce',
  token       TEXT UNIQUE DEFAULT encode(gen_random_bytes(16), 'hex'),
  activo      BOOLEAN DEFAULT true
);

-- Índices para búsqueda rápida
CREATE INDEX IF NOT EXISTS idx_customers_business_id ON customers(business_id);
CREATE INDEX IF NOT EXISTS idx_customers_token        ON customers(token);
CREATE INDEX IF NOT EXISTS idx_customers_telefono     ON customers(telefono);


-- ─── 2. TABLA STAMP_LOGS ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS stamp_logs (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at  TIMESTAMPTZ DEFAULT now(),
  customer_id UUID REFERENCES customers(id) ON DELETE CASCADE,
  business_id TEXT NOT NULL,
  sellos_delta INTEGER DEFAULT 1,   -- positivo = sello agregado, negativo = canje
  origen      TEXT DEFAULT 'checkin'  -- 'checkin' | 'admin' | 'canje'
);

CREATE INDEX IF NOT EXISTS idx_stamp_logs_customer    ON stamp_logs(customer_id);
CREATE INDEX IF NOT EXISTS idx_stamp_logs_business    ON stamp_logs(business_id, created_at);


-- ─── 3. FUNCIÓN: agregar_sello ───────────────────────────────────────
-- Llamada desde checkin.html vía supabase.rpc('agregar_sello', {...})
CREATE OR REPLACE FUNCTION agregar_sello(p_token TEXT, p_business_id TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_customer        customers%ROWTYPE;
  v_nuevos_sellos   INTEGER;
  v_nivel_nuevo     TEXT;
  v_nivel_viejo     TEXT;
BEGIN
  -- Buscar cliente activo
  SELECT * INTO v_customer
  FROM customers
  WHERE token = p_token
    AND business_id = p_business_id
    AND activo = true;

  IF NOT FOUND THEN
    RETURN json_build_object('ok', false, 'error', 'cliente_no_encontrado');
  END IF;

  v_nivel_viejo   := v_customer.nivel;
  v_nuevos_sellos := v_customer.sellos + 1;

  -- Calcular nuevo nivel
  IF v_nuevos_sellos >= 80 THEN
    v_nivel_nuevo := 'Oro';
  ELSIF v_nuevos_sellos >= 30 THEN
    v_nivel_nuevo := 'Plata';
  ELSE
    v_nivel_nuevo := 'Bronce';
  END IF;

  -- Actualizar cliente
  UPDATE customers
  SET sellos = v_nuevos_sellos, nivel = v_nivel_nuevo
  WHERE id = v_customer.id;

  -- Registrar log
  INSERT INTO stamp_logs(customer_id, business_id, sellos_delta, origen)
  VALUES (v_customer.id, p_business_id, 1, 'checkin');

  RETURN json_build_object(
    'ok',         true,
    'nombre',     v_customer.nombre,
    'sellos',     v_nuevos_sellos,
    'nivel',      v_nivel_nuevo,
    'nivel_subio', v_nivel_nuevo <> v_nivel_viejo
  );
END;
$$;


-- ─── 4. FUNCIÓN: admin_set_sellos ────────────────────────────────────
-- Llamada desde admin.html para editar sellos manualmente
CREATE OR REPLACE FUNCTION admin_set_sellos(p_token TEXT, p_sellos INTEGER)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_nivel TEXT;
BEGIN
  IF p_sellos >= 80 THEN
    v_nivel := 'Oro';
  ELSIF p_sellos >= 30 THEN
    v_nivel := 'Plata';
  ELSE
    v_nivel := 'Bronce';
  END IF;

  UPDATE customers
  SET sellos = p_sellos, nivel = v_nivel
  WHERE token = p_token;
END;
$$;


-- ─── 5. FUNCIÓN: admin_stats_sellos ──────────────────────────────────
-- Devuelve estadísticas de sellos agrupadas para el dashboard
CREATE OR REPLACE FUNCTION admin_stats_sellos(p_business_id TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_hoy        DATE := CURRENT_DATE;
  v_inicio_mes DATE := date_trunc('month', CURRENT_DATE)::DATE;
BEGIN
  RETURN json_build_object(
    'detalle_hoy', (
      SELECT json_agg(json_build_object(
        'id',     customer_id,
        'sellos', SUM(sellos_delta)
      ))
      FROM stamp_logs
      WHERE business_id = p_business_id
        AND created_at::date = v_hoy
        AND sellos_delta > 0
      GROUP BY customer_id
    ),
    'detalle_mes', (
      SELECT json_agg(json_build_object(
        'id',     customer_id,
        'sellos', SUM(sellos_delta)
      ))
      FROM stamp_logs
      WHERE business_id = p_business_id
        AND created_at::date >= v_inicio_mes
        AND sellos_delta > 0
      GROUP BY customer_id
    )
  );
END;
$$;


-- ─── 6. ROW LEVEL SECURITY ───────────────────────────────────────────
-- Habilitar RLS en ambas tablas
ALTER TABLE customers  ENABLE ROW LEVEL SECURITY;
ALTER TABLE stamp_logs ENABLE ROW LEVEL SECURITY;

-- Políticas permisivas para el MVP (clave anon de Supabase)
-- En producción, ajusta estas políticas para mayor seguridad
DROP POLICY IF EXISTS "anon_all_customers"  ON customers;
DROP POLICY IF EXISTS "anon_all_stamp_logs" ON stamp_logs;

CREATE POLICY "anon_all_customers" ON customers
  FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY "anon_all_stamp_logs" ON stamp_logs
  FOR ALL TO anon USING (true) WITH CHECK (true);


-- ─── VERIFICACIÓN ─────────────────────────────────────────────────────
-- Ejecuta esto para confirmar que todo está bien:
-- SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';
-- SELECT routine_name FROM information_schema.routines WHERE routine_schema = 'public';

-- ═══════════════════════════════════════════════════════════════════
-- ✅ Setup completo. Copia ahora Project URL y anon key desde:
--    Settings → API → Project URL / Project API keys (anon public)
-- ═══════════════════════════════════════════════════════════════════
