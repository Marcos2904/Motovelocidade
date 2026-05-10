-- ============================================================
--  MX CONTROL + PISTA CONTROL — Schema PostgreSQL Unificado
--  Suporta: Motocross e Velocidade (Interlagos / Circuit)
-- ============================================================

-- EXTENSÕES
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ============================================================
-- ENUM TYPES
-- ============================================================
CREATE TYPE tipo_evento AS ENUM ('motocross', 'velocidade', 'enduro', 'supermoto');
CREATE TYPE status_evento AS ENUM ('rascunho', 'publicado', 'em_andamento', 'encerrado', 'cancelado');
CREATE TYPE status_inscricao AS ENUM ('pendente', 'confirmada', 'cancelada', 'no_show');
CREATE TYPE status_pagamento AS ENUM ('aguardando', 'pago', 'estornado', 'isento');
CREATE TYPE status_bateria AS ENUM ('agendada', 'em_andamento', 'concluida', 'cancelada', 'adiada');
CREATE TYPE tipo_comunicado AS ENUM ('whatsapp', 'email', 'push', 'sms');
CREATE TYPE tipo_categoria_moto AS ENUM (
    -- Motocross
    'MX1_PRO', 'MX2_INTERMEDIARIA', 'MX3_NACIONAL', 'MX4_INICIANTE',
    'MX5_2T', 'MXF_FEMININA', 'MXJR_85CC',
    -- Velocidade / Pista
    'SUPERBIKE', 'SUPERSPORT', 'NAKED', 'SCOOTER',
    'NINJA_636', 'R6', 'CBR600', 'S1000RR',
    'MOTO3', 'MOTO_LIVRE'
);

-- ============================================================
-- TABELA: organizadores
-- ============================================================
CREATE TABLE organizadores (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nome          VARCHAR(120) NOT NULL,
    email         VARCHAR(180) UNIQUE NOT NULL,
    telefone      VARCHAR(20),
    senha_hash    TEXT NOT NULL,
    avatar_url    TEXT,
    criado_em     TIMESTAMPTZ DEFAULT NOW(),
    atualizado_em TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- TABELA: eventos
-- ============================================================
CREATE TABLE eventos (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organizador_id  UUID NOT NULL REFERENCES organizadores(id) ON DELETE CASCADE,
    nome            VARCHAR(200) NOT NULL,
    tipo            tipo_evento NOT NULL,
    status          status_evento NOT NULL DEFAULT 'rascunho',
    descricao       TEXT,
    local           VARCHAR(300),          -- Ex: "Autódromo de Interlagos, SP"
    pista           VARCHAR(150),          -- Ex: "Pista do Sertão", "Circuito Principal"
    data_inicio     DATE NOT NULL,
    data_fim        DATE NOT NULL,
    hora_abertura   TIME,
    capacidade      INT DEFAULT 500,
    banner_url      TEXT,
    regulamento_url TEXT,
    criado_em       TIMESTAMPTZ DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_eventos_tipo    ON eventos(tipo);
CREATE INDEX idx_eventos_status  ON eventos(status);
CREATE INDEX idx_eventos_data    ON eventos(data_inicio);

-- ============================================================
-- TABELA: categorias (por evento)
-- ============================================================
CREATE TABLE categorias (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    evento_id       UUID NOT NULL REFERENCES eventos(id) ON DELETE CASCADE,
    tipo_categoria  tipo_categoria_moto NOT NULL,
    nome_display    VARCHAR(80) NOT NULL,   -- "MX1 Pró", "Ninja 636", etc.
    cilindrada_min  INT,
    cilindrada_max  INT,
    ano_min         INT,
    descricao       TEXT,
    taxa_inscricao  NUMERIC(10,2) DEFAULT 0,
    max_pilotos     INT DEFAULT 30,
    ativa           BOOLEAN DEFAULT TRUE,
    criado_em       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_categorias_evento ON categorias(evento_id);

-- ============================================================
-- TABELA: pilotos
-- ============================================================
CREATE TABLE pilotos (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nome          VARCHAR(120) NOT NULL,
    cpf           VARCHAR(14) UNIQUE,
    email         VARCHAR(180) UNIQUE NOT NULL,
    telefone      VARCHAR(20),
    whatsapp      VARCHAR(20),
    data_nascimento DATE,
    numero_piloto INT,                      -- número fixo do piloto
    foto_url      TEXT,
    cnh           VARCHAR(30),
    ficha_medica  BOOLEAN DEFAULT FALSE,
    criado_em     TIMESTAMPTZ DEFAULT NOW(),
    atualizado_em TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_pilotos_email  ON pilotos(email);
CREATE INDEX idx_pilotos_numero ON pilotos(numero_piloto);

-- ============================================================
-- TABELA: motocicletas
-- ============================================================
CREATE TABLE motocicletas (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    piloto_id     UUID NOT NULL REFERENCES pilotos(id) ON DELETE CASCADE,
    marca         VARCHAR(60),             -- Kawasaki, Honda, Yamaha…
    modelo        VARCHAR(80),             -- Ninja ZX-6R 636, CRF450…
    ano           INT,
    cilindrada    INT,
    cor           VARCHAR(40),
    placa         VARCHAR(10),
    chassi        VARCHAR(30),
    criado_em     TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- TABELA: inscricoes
-- ============================================================
CREATE TABLE inscricoes (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    evento_id       UUID NOT NULL REFERENCES eventos(id) ON DELETE CASCADE,
    piloto_id       UUID NOT NULL REFERENCES pilotos(id) ON DELETE CASCADE,
    categoria_id    UUID NOT NULL REFERENCES categorias(id),
    motocicleta_id  UUID REFERENCES motocicletas(id),
    numero_largada  INT,
    status          status_inscricao NOT NULL DEFAULT 'pendente',
    status_pagamento status_pagamento NOT NULL DEFAULT 'aguardando',
    checkin_feito   BOOLEAN DEFAULT FALSE,
    checkin_hora    TIMESTAMPTZ,
    valor_pago      NUMERIC(10,2),
    observacoes     TEXT,
    criado_em       TIMESTAMPTZ DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(evento_id, piloto_id, categoria_id),
    UNIQUE(evento_id, numero_largada)
);

CREATE INDEX idx_inscricoes_evento    ON inscricoes(evento_id);
CREATE INDEX idx_inscricoes_piloto    ON inscricoes(piloto_id);
CREATE INDEX idx_inscricoes_status    ON inscricoes(status);
CREATE INDEX idx_inscricoes_checkin   ON inscricoes(checkin_feito);

-- ============================================================
-- TABELA: pagamentos
-- ============================================================
CREATE TABLE pagamentos (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    inscricao_id    UUID NOT NULL REFERENCES inscricoes(id) ON DELETE CASCADE,
    valor           NUMERIC(10,2) NOT NULL,
    metodo          VARCHAR(40),           -- pix, cartao, boleto, dinheiro
    gateway_id      VARCHAR(120),          -- ID externo (Mercado Pago, PagSeguro…)
    gateway_status  VARCHAR(60),
    pago_em         TIMESTAMPTZ,
    criado_em       TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- TABELA: baterias (heats / sessions)
-- ============================================================
CREATE TABLE baterias (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    evento_id       UUID NOT NULL REFERENCES eventos(id) ON DELETE CASCADE,
    categoria_id    UUID NOT NULL REFERENCES categorias(id),
    nome            VARCHAR(100) NOT NULL,  -- "MX1 Pró – Bateria 1", "Ninja 636 – Q1"
    numero_bateria  INT NOT NULL DEFAULT 1,
    data_hora       TIMESTAMPTZ NOT NULL,
    duracao_minutos INT DEFAULT 20,
    voltas_max      INT,
    pista           VARCHAR(150),
    status          status_bateria NOT NULL DEFAULT 'agendada',
    notas           TEXT,
    criado_em       TIMESTAMPTZ DEFAULT NOW(),
    atualizado_em   TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_baterias_evento    ON baterias(evento_id);
CREATE INDEX idx_baterias_categoria ON baterias(categoria_id);
CREATE INDEX idx_baterias_datahora  ON baterias(data_hora);

-- ============================================================
-- TABELA: resultados
-- ============================================================
CREATE TABLE resultados (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bateria_id      UUID NOT NULL REFERENCES baterias(id) ON DELETE CASCADE,
    inscricao_id    UUID NOT NULL REFERENCES inscricoes(id) ON DELETE CASCADE,
    posicao         INT,
    tempo_total     INTERVAL,              -- tempo total da bateria
    melhor_volta    INTERVAL,             -- volta mais rápida
    voltas_completas INT DEFAULT 0,
    pontos          INT DEFAULT 0,
    dnf             BOOLEAN DEFAULT FALSE, -- Did Not Finish
    dns             BOOLEAN DEFAULT FALSE, -- Did Not Start
    dsq             BOOLEAN DEFAULT FALSE, -- Desqualificado
    observacoes     TEXT,
    registrado_em   TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(bateria_id, inscricao_id)
);

CREATE INDEX idx_resultados_bateria   ON resultados(bateria_id);
CREATE INDEX idx_resultados_inscricao ON resultados(inscricao_id);

-- ============================================================
-- TABELA: ranking (materializado por evento + categoria)
-- ============================================================
CREATE TABLE ranking (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    evento_id       UUID NOT NULL REFERENCES eventos(id) ON DELETE CASCADE,
    categoria_id    UUID NOT NULL REFERENCES categorias(id),
    inscricao_id    UUID NOT NULL REFERENCES inscricoes(id),
    posicao_geral   INT,
    total_pontos    INT DEFAULT 0,
    total_vitorias  INT DEFAULT 0,
    melhor_volta    INTERVAL,
    atualizado_em   TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(evento_id, categoria_id, inscricao_id)
);

CREATE INDEX idx_ranking_evento    ON ranking(evento_id, categoria_id);
CREATE INDEX idx_ranking_pontos    ON ranking(total_pontos DESC);

-- ============================================================
-- TABELA: comunicados
-- ============================================================
CREATE TABLE comunicados (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    evento_id       UUID NOT NULL REFERENCES eventos(id) ON DELETE CASCADE,
    tipo            tipo_comunicado NOT NULL DEFAULT 'whatsapp',
    titulo          VARCHAR(200),
    mensagem        TEXT NOT NULL,
    destinatarios   INT DEFAULT 0,         -- contagem de envios
    enviado_em      TIMESTAMPTZ,
    criado_em       TIMESTAMPTZ DEFAULT NOW(),
    criado_por      UUID REFERENCES organizadores(id)
);

CREATE INDEX idx_comunicados_evento ON comunicados(evento_id);

-- ============================================================
-- TABELA: log_comunicados (rastreio individual)
-- ============================================================
CREATE TABLE log_comunicados (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    comunicado_id   UUID NOT NULL REFERENCES comunicados(id) ON DELETE CASCADE,
    piloto_id       UUID NOT NULL REFERENCES pilotos(id),
    canal           tipo_comunicado NOT NULL,
    status_envio    VARCHAR(40) DEFAULT 'pendente', -- pendente, enviado, falha
    enviado_em      TIMESTAMPTZ,
    erro            TEXT
);

-- ============================================================
-- VIEW: dashboard_evento (resumo rápido)
-- ============================================================
CREATE OR REPLACE VIEW vw_dashboard_evento AS
SELECT
    e.id                                            AS evento_id,
    e.nome                                          AS evento_nome,
    e.tipo,
    e.status,
    e.data_inicio,
    e.local,
    COUNT(DISTINCT i.id)                            AS total_inscritos,
    COUNT(DISTINCT i.id) FILTER (WHERE i.checkin_feito) AS checkins_feitos,
    ROUND(
        COUNT(DISTINCT i.id) FILTER (WHERE i.checkin_feito)::NUMERIC
        / NULLIF(COUNT(DISTINCT i.id), 0) * 100, 1
    )                                               AS pct_checkin,
    COUNT(DISTINCT cat.id)                          AS total_categorias,
    COUNT(DISTINCT b.id)                            AS total_baterias,
    COALESCE(SUM(i.valor_pago), 0)                  AS receita_total
FROM eventos e
LEFT JOIN inscricoes i      ON i.evento_id = e.id AND i.status = 'confirmada'
LEFT JOIN categorias cat    ON cat.evento_id = e.id AND cat.ativa
LEFT JOIN baterias b        ON b.evento_id = e.id
GROUP BY e.id, e.nome, e.tipo, e.status, e.data_inicio, e.local;

-- ============================================================
-- VIEW: vw_ranking_geral (top pilotos por evento+categoria)
-- ============================================================
CREATE OR REPLACE VIEW vw_ranking_geral AS
SELECT
    r.evento_id,
    e.nome          AS evento_nome,
    cat.nome_display AS categoria,
    r.posicao_geral,
    p.nome          AS piloto_nome,
    p.numero_piloto,
    i.numero_largada,
    r.total_pontos,
    r.total_vitorias,
    r.melhor_volta
FROM ranking r
JOIN inscricoes i    ON i.id = r.inscricao_id
JOIN pilotos p       ON p.id = i.piloto_id
JOIN eventos e       ON e.id = r.evento_id
JOIN categorias cat  ON cat.id = r.categoria_id
ORDER BY r.evento_id, r.categoria_id, r.posicao_geral;

-- ============================================================
-- FUNÇÃO: recalcular_ranking (chamada após cada bateria)
-- ============================================================
CREATE OR REPLACE FUNCTION recalcular_ranking(p_evento_id UUID, p_categoria_id UUID)
RETURNS VOID AS $$
BEGIN
    INSERT INTO ranking (evento_id, categoria_id, inscricao_id, total_pontos, total_vitorias, melhor_volta, posicao_geral)
    SELECT
        p_evento_id,
        p_categoria_id,
        r.inscricao_id,
        SUM(r.pontos)                           AS total_pontos,
        COUNT(*) FILTER (WHERE r.posicao = 1)   AS total_vitorias,
        MIN(r.melhor_volta)                     AS melhor_volta,
        ROW_NUMBER() OVER (ORDER BY SUM(r.pontos) DESC, MIN(r.melhor_volta) ASC) AS posicao_geral
    FROM resultados r
    JOIN baterias b ON b.id = r.bateria_id
    WHERE b.evento_id = p_evento_id
      AND b.categoria_id = p_categoria_id
      AND b.status = 'concluida'
      AND NOT r.dsq
    GROUP BY r.inscricao_id
    ON CONFLICT (evento_id, categoria_id, inscricao_id)
    DO UPDATE SET
        total_pontos   = EXCLUDED.total_pontos,
        total_vitorias = EXCLUDED.total_vitorias,
        melhor_volta   = EXCLUDED.melhor_volta,
        posicao_geral  = EXCLUDED.posicao_geral,
        atualizado_em  = NOW();
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- DADOS INICIAIS DE EXEMPLO
-- ============================================================
INSERT INTO organizadores (nome, email, senha_hash) VALUES
    ('Marcos Admin', 'marcos@mxcontrol.com.br', '$2b$12$placeholder_hash');

-- Evento Motocross
WITH org AS (SELECT id FROM organizadores LIMIT 1)
INSERT INTO eventos (organizador_id, nome, tipo, status, local, pista, data_inicio, data_fim)
SELECT id, 'Copa MX Verão 2025', 'motocross', 'publicado',
       'Centro Esportivo Parque do Trabalhador, SP',
       'Pista Principal',
       '2025-06-15', '2025-06-16'
FROM org;

-- Evento Velocidade
WITH org AS (SELECT id FROM organizadores LIMIT 1)
INSERT INTO eventos (organizador_id, nome, tipo, status, local, pista, data_inicio, data_fim)
SELECT id, 'Interlagos Speed Festival 2025', 'velocidade', 'publicado',
       'Autódromo José Carlos Pace – Interlagos, SP',
       'Circuito Completo (4.309 km)',
       '2025-09-20', '2025-09-21'
FROM org;
