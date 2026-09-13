-- NhaCarro - schema inicial (PostgreSQL + PostGIS)

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

DO $$
BEGIN
  CREATE TYPE tipo_perfil_enum AS ENUM ('PASSAGEIRO', 'MOTORISTA', 'ADMIN');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE status_conta_enum AS ENUM ('PENDENTE', 'ATIVO', 'BLOQUEADO');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE categoria_veiculo_enum AS ENUM ('TAXI_TRADICIONAL', 'CONFORT', 'MOTO');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE status_corrida_enum AS ENUM (
    'SOLICITADA',
    'ACEITA',
    'EM_ANDAMENTO',
    'CONCLUIDA',
    'CANCELADA'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE forma_pagamento_enum AS ENUM (
    'DINHEIRO',
    'ORANGE_MONEY',
    'MTN_MONEY'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE tipo_transacao_enum AS ENUM (
    'RECARGA_ORANGE',
    'RECARGA_MTN',
    'DEDUCAO_COMISSAO'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS usuarios (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  nome VARCHAR(100) NOT NULL,
  telefone VARCHAR(20) UNIQUE NOT NULL,
  tipo_perfil tipo_perfil_enum NOT NULL,
  saldo_carteira NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
  status_conta status_conta_enum NOT NULL DEFAULT 'PENDENTE',
  criado_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS veiculos_motoristas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  motorista_id UUID NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  placa VARCHAR(20) NOT NULL,
  marca_modelo VARCHAR(50) NOT NULL,
  cor VARCHAR(30) NOT NULL,
  categoria categoria_veiculo_enum NOT NULL DEFAULT 'TAXI_TRADICIONAL',
  documentos_validados BOOLEAN NOT NULL DEFAULT FALSE,
  criado_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (motorista_id)
);

CREATE TABLE IF NOT EXISTS localizacao_motoristas (
  motorista_id UUID PRIMARY KEY REFERENCES usuarios(id) ON DELETE CASCADE,
  coordenadas geometry(Point, 4326) NOT NULL,
  em_corrida BOOLEAN NOT NULL DEFAULT FALSE,
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_localizacao_motoristas_coordenadas
  ON localizacao_motoristas USING GIST (coordenadas);

CREATE TABLE IF NOT EXISTS corridas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  passageiro_id UUID NOT NULL REFERENCES usuarios(id),
  motorista_id UUID REFERENCES usuarios(id),
  origem_coords geometry(Point, 4326) NOT NULL,
  destino_coords geometry(Point, 4326) NOT NULL,
  valor_total NUMERIC(10, 2) NOT NULL CHECK (valor_total >= 0),
  valor_comissao NUMERIC(10, 2) NOT NULL CHECK (valor_comissao >= 0),
  forma_pagamento forma_pagamento_enum NOT NULL,
  status status_corrida_enum NOT NULL DEFAULT 'SOLICITADA',
  criado_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_corridas_passageiro_criado_em
  ON corridas (passageiro_id, criado_em DESC);

CREATE INDEX IF NOT EXISTS idx_corridas_motorista_status
  ON corridas (motorista_id, status);

CREATE TABLE IF NOT EXISTS transacoes_carteira (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  usuario_id UUID NOT NULL REFERENCES usuarios(id),
  valor NUMERIC(10, 2) NOT NULL CHECK (valor > 0),
  tipo tipo_transacao_enum NOT NULL,
  referencia_provedor VARCHAR(100),
  criado_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_transacoes_carteira_usuario_criado_em
  ON transacoes_carteira (usuario_id, criado_em DESC);

CREATE OR REPLACE FUNCTION buscar_motoristas_proximos(
  lat_passageiro DOUBLE PRECISION,
  lng_passageiro DOUBLE PRECISION,
  raio_metros DOUBLE PRECISION,
  comissao_requerida NUMERIC(10, 2)
)
RETURNS TABLE (
  motorista_id UUID,
  distancia_metros DOUBLE PRECISION
)
LANGUAGE SQL
STABLE
AS $function$
  SELECT
    lm.motorista_id,
    ST_Distance(
      lm.coordenadas::geography,
      ST_SetSRID(
        ST_MakePoint(lng_passageiro, lat_passageiro),
        4326
      )::geography
    ) AS distancia_metros
  FROM localizacao_motoristas lm
  INNER JOIN usuarios u ON u.id = lm.motorista_id
  WHERE lm.em_corrida = FALSE
    AND u.tipo_perfil = 'MOTORISTA'
    AND u.status_conta = 'ATIVO'
    AND u.saldo_carteira >= comissao_requerida
    AND ST_DWithin(
      lm.coordenadas::geography,
      ST_SetSRID(
        ST_MakePoint(lng_passageiro, lat_passageiro),
        4326
      )::geography,
      raio_metros
    )
  ORDER BY distancia_metros;
$function$;
