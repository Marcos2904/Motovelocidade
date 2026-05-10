-- ============================================================
--  QUERIES PRINCIPAIS — MX CONTROL + PISTA CONTROL
--  Use com psycopg2 / asyncpg / SQLAlchemy (parâmetros: %(nome)s)
-- ============================================================

-- ============================================================
-- [1] DASHBOARD — resumo geral de um evento
-- ============================================================
-- Retorna todos os KPIs do dashboard em uma única query
SELECT
    e.id,
    e.nome,
    e.tipo,
    e.status,
    e.local,
    e.pista,
    e.data_inicio,
    e.data_fim,
    -- Inscrições
    COUNT(DISTINCT i.id)                                        AS total_inscritos,
    COUNT(DISTINCT i.id) FILTER (WHERE i.status = 'confirmada') AS confirmados,
    COUNT(DISTINCT i.id) FILTER (WHERE i.checkin_feito = TRUE)  AS checkins_feitos,
    ROUND(
        COUNT(DISTINCT i.id) FILTER (WHERE i.checkin_feito)::NUMERIC
        / NULLIF(COUNT(DISTINCT i.id) FILTER (WHERE i.status = 'confirmada'), 0) * 100, 1
    )                                                           AS pct_checkin,
    -- Financeiro
    COALESCE(SUM(i.valor_pago) FILTER (WHERE i.status_pagamento = 'pago'), 0) AS receita_total,
    -- Estrutura
    COUNT(DISTINCT cat.id)  AS total_categorias,
    COUNT(DISTINCT b.id)    AS total_baterias,
    COUNT(DISTINCT b.id) FILTER (WHERE b.status = 'concluida')   AS baterias_concluidas,
    COUNT(DISTINCT b.id) FILTER (WHERE b.status = 'em_andamento') AS baterias_em_andamento
FROM eventos e
LEFT JOIN inscricoes i   ON i.evento_id = e.id
LEFT JOIN categorias cat ON cat.evento_id = e.id AND cat.ativa = TRUE
LEFT JOIN baterias b     ON b.evento_id = e.id
WHERE e.id = %(evento_id)s
GROUP BY e.id, e.nome, e.tipo, e.status, e.local, e.pista, e.data_inicio, e.data_fim;


-- ============================================================
-- [2] INSCRIÇÕES — listar por evento com filtros
-- ============================================================
SELECT
    i.id,
    i.numero_largada,
    p.nome                  AS piloto_nome,
    p.numero_piloto,
    p.email,
    p.whatsapp,
    cat.nome_display        AS categoria,
    m.marca || ' ' || m.modelo AS motocicleta,
    m.ano,
    i.status,
    i.status_pagamento,
    i.checkin_feito,
    i.checkin_hora,
    i.valor_pago,
    i.criado_em
FROM inscricoes i
JOIN pilotos p       ON p.id = i.piloto_id
JOIN categorias cat  ON cat.id = i.categoria_id
LEFT JOIN motocicletas m ON m.id = i.motocicleta_id
WHERE i.evento_id = %(evento_id)s
  AND (%(categoria_id)s IS NULL OR i.categoria_id = %(categoria_id)s::UUID)
  AND (%(status)s IS NULL OR i.status = %(status)s::status_inscricao)
  AND (%(checkin)s IS NULL OR i.checkin_feito = %(checkin)s)
  AND (%(busca)s IS NULL OR p.nome ILIKE '%%' || %(busca)s || '%%'
       OR p.email ILIKE '%%' || %(busca)s || '%%'
       OR i.numero_largada::TEXT = %(busca)s)
ORDER BY cat.nome_display, i.numero_largada NULLS LAST
LIMIT %(limit)s OFFSET %(offset)s;

-- Contagem para paginação
SELECT COUNT(*)
FROM inscricoes i
JOIN pilotos p ON p.id = i.piloto_id
WHERE i.evento_id = %(evento_id)s
  AND (%(categoria_id)s IS NULL OR i.categoria_id = %(categoria_id)s::UUID)
  AND (%(status)s IS NULL OR i.status = %(status)s::status_inscricao);


-- ============================================================
-- [3] INSCRIÇÕES POR CATEGORIA (gráfico donut)
-- ============================================================
SELECT
    cat.nome_display    AS categoria,
    cat.id              AS categoria_id,
    COUNT(i.id)         AS total,
    ROUND(COUNT(i.id)::NUMERIC / SUM(COUNT(i.id)) OVER () * 100, 1) AS pct
FROM inscricoes i
JOIN categorias cat ON cat.id = i.categoria_id
WHERE i.evento_id = %(evento_id)s
  AND i.status IN ('pendente', 'confirmada')
GROUP BY cat.id, cat.nome_display
ORDER BY total DESC;


-- ============================================================
-- [4] CRONOGRAMA DO DIA
-- ============================================================
SELECT
    b.id,
    b.nome                  AS bateria_nome,
    cat.nome_display        AS categoria,
    b.data_hora,
    b.duracao_minutos,
    b.voltas_max,
    b.pista,
    b.status,
    COUNT(DISTINCT i.id)    AS pilotos_inscritos
FROM baterias b
JOIN categorias cat ON cat.id = b.categoria_id
LEFT JOIN inscricoes i ON i.categoria_id = b.categoria_id
    AND i.evento_id = b.evento_id
    AND i.status = 'confirmada'
WHERE b.evento_id = %(evento_id)s
  AND b.data_hora::DATE = %(data)s::DATE
GROUP BY b.id, b.nome, cat.nome_display, b.data_hora, b.duracao_minutos,
         b.voltas_max, b.pista, b.status
ORDER BY b.data_hora;


-- ============================================================
-- [5] RANKING GERAL (TOP 5 e completo)
-- ============================================================
SELECT
    r.posicao_geral,
    p.numero_piloto,
    i.numero_largada,
    p.nome              AS piloto_nome,
    p.foto_url,
    cat.nome_display    AS categoria,
    r.total_pontos,
    r.total_vitorias,
    TO_CHAR(r.melhor_volta, 'MI:SS.MS')  AS melhor_volta_fmt
FROM ranking r
JOIN inscricoes i    ON i.id = r.inscricao_id
JOIN pilotos p       ON p.id = i.piloto_id
JOIN categorias cat  ON cat.id = r.categoria_id
WHERE r.evento_id = %(evento_id)s
  AND (%(categoria_id)s IS NULL OR r.categoria_id = %(categoria_id)s::UUID)
ORDER BY r.categoria_id, r.posicao_geral
LIMIT %(limit)s;  -- passar 5 para top5, NULL para completo


-- ============================================================
-- [6] RESULTADOS DE UMA BATERIA
-- ============================================================
SELECT
    res.posicao,
    p.numero_piloto,
    i.numero_largada,
    p.nome              AS piloto_nome,
    m.marca || ' ' || m.modelo AS motocicleta,
    res.tempo_total,
    TO_CHAR(res.tempo_total, 'MI:SS.MS')   AS tempo_fmt,
    TO_CHAR(res.melhor_volta, 'MI:SS.MS')  AS melhor_volta_fmt,
    res.voltas_completas,
    res.pontos,
    res.dnf,
    res.dns,
    res.dsq
FROM resultados res
JOIN inscricoes i         ON i.id = res.inscricao_id
JOIN pilotos p            ON p.id = i.piloto_id
LEFT JOIN motocicletas m  ON m.id = i.motocicleta_id
WHERE res.bateria_id = %(bateria_id)s
ORDER BY
    res.dsq, res.dnf, res.dns,      -- finalizadores primeiro
    res.posicao NULLS LAST;


-- ============================================================
-- [7] CHECK-IN — realizar check-in
-- ============================================================
UPDATE inscricoes
SET
    checkin_feito = TRUE,
    checkin_hora  = NOW(),
    atualizado_em = NOW()
WHERE id = %(inscricao_id)s
  AND evento_id = %(evento_id)s
  AND status = 'confirmada'
RETURNING id, numero_largada, checkin_hora;


-- ============================================================
-- [8] COMUNICADOS — listar por evento
-- ============================================================
SELECT
    c.id,
    c.tipo,
    c.titulo,
    c.mensagem,
    c.destinatarios,
    c.enviado_em,
    o.nome AS criado_por,
    -- status de entrega agregado
    COUNT(lc.id)                                        AS total_envios,
    COUNT(lc.id) FILTER (WHERE lc.status_envio = 'enviado') AS enviados_ok,
    COUNT(lc.id) FILTER (WHERE lc.status_envio = 'falha')   AS falhas
FROM comunicados c
LEFT JOIN organizadores o    ON o.id = c.criado_por
LEFT JOIN log_comunicados lc ON lc.comunicado_id = c.id
WHERE c.evento_id = %(evento_id)s
GROUP BY c.id, c.tipo, c.titulo, c.mensagem, c.destinatarios,
         c.enviado_em, o.nome
ORDER BY c.criado_em DESC
LIMIT 20;


-- ============================================================
-- [9] FINANCEIRO — receita por categoria
-- ============================================================
SELECT
    cat.nome_display                    AS categoria,
    COUNT(i.id)                         AS inscritos,
    COUNT(i.id) FILTER (WHERE i.status_pagamento = 'pago') AS pagos,
    COALESCE(SUM(i.valor_pago) FILTER (WHERE i.status_pagamento = 'pago'), 0) AS receita,
    cat.taxa_inscricao                  AS taxa_unitaria,
    cat.taxa_inscricao * COUNT(i.id)    AS receita_potencial
FROM inscricoes i
JOIN categorias cat ON cat.id = i.categoria_id
WHERE i.evento_id = %(evento_id)s
  AND i.status != 'cancelada'
GROUP BY cat.id, cat.nome_display, cat.taxa_inscricao
ORDER BY receita DESC;


-- ============================================================
-- [10] ÁREA DO PILOTO — dados completos para o app
-- ============================================================
SELECT
    p.id,
    p.nome,
    p.numero_piloto,
    p.foto_url,
    p.whatsapp,
    i.id            AS inscricao_id,
    i.numero_largada,
    i.status        AS status_inscricao,
    i.checkin_feito,
    cat.nome_display AS categoria,
    m.marca, m.modelo, m.ano,
    -- próxima bateria
    (
        SELECT json_build_object(
            'id', b.id,
            'nome', b.nome,
            'data_hora', b.data_hora,
            'pista', b.pista,
            'status', b.status
        )
        FROM baterias b
        WHERE b.categoria_id = i.categoria_id
          AND b.evento_id = i.evento_id
          AND b.status IN ('agendada', 'em_andamento')
          AND b.data_hora >= NOW()
        ORDER BY b.data_hora
        LIMIT 1
    )                AS proxima_bateria,
    -- resultados já registrados
    (
        SELECT json_agg(json_build_object(
            'bateria', b2.nome,
            'posicao', res.posicao,
            'pontos', res.pontos,
            'melhor_volta', TO_CHAR(res.melhor_volta, 'MI:SS.MS'),
            'dnf', res.dnf
        ) ORDER BY b2.data_hora)
        FROM resultados res
        JOIN baterias b2 ON b2.id = res.bateria_id
        WHERE res.inscricao_id = i.id
    )                AS meus_resultados,
    -- posição no ranking
    rk.posicao_geral,
    rk.total_pontos
FROM inscricoes i
JOIN pilotos p       ON p.id = i.piloto_id
JOIN categorias cat  ON cat.id = i.categoria_id
LEFT JOIN motocicletas m  ON m.id = i.motocicleta_id
LEFT JOIN ranking rk ON rk.inscricao_id = i.id AND rk.evento_id = i.evento_id
WHERE i.evento_id = %(evento_id)s
  AND p.id = %(piloto_id)s
LIMIT 1;


-- ============================================================
-- [11] INSERIR RESULTADO DE BATERIA + RECALCULAR RANKING
-- ============================================================
-- Passo 1: inserir/atualizar resultado
INSERT INTO resultados (
    bateria_id, inscricao_id, posicao, tempo_total,
    melhor_volta, voltas_completas, pontos, dnf, dns, dsq
)
VALUES (
    %(bateria_id)s, %(inscricao_id)s, %(posicao)s,
    %(tempo_total)s::INTERVAL, %(melhor_volta)s::INTERVAL,
    %(voltas)s, %(pontos)s, %(dnf)s, %(dns)s, %(dsq)s
)
ON CONFLICT (bateria_id, inscricao_id)
DO UPDATE SET
    posicao          = EXCLUDED.posicao,
    tempo_total      = EXCLUDED.tempo_total,
    melhor_volta     = EXCLUDED.melhor_volta,
    voltas_completas = EXCLUDED.voltas_completas,
    pontos           = EXCLUDED.pontos,
    dnf              = EXCLUDED.dnf,
    dns              = EXCLUDED.dns,
    dsq              = EXCLUDED.dsq
RETURNING id;

-- Passo 2 (chamar função de recálculo):
SELECT recalcular_ranking(%(evento_id)s::UUID, %(categoria_id)s::UUID);


-- ============================================================
-- [12] RELATÓRIO EXPORTÁVEL (PDF/Excel) — resultados completos
-- ============================================================
SELECT
    cat.nome_display        AS categoria,
    r.posicao_geral         AS posicao,
    p.numero_piloto,
    i.numero_largada,
    p.nome                  AS piloto,
    m.marca || ' ' || m.modelo AS moto,
    m.ano,
    r.total_pontos,
    r.total_vitorias,
    TO_CHAR(r.melhor_volta, 'MI:SS.MS') AS melhor_volta
FROM ranking r
JOIN inscricoes i    ON i.id = r.inscricao_id
JOIN pilotos p       ON p.id = i.piloto_id
JOIN categorias cat  ON cat.id = r.categoria_id
LEFT JOIN motocicletas m ON m.id = i.motocicleta_id
WHERE r.evento_id = %(evento_id)s
ORDER BY cat.nome_display, r.posicao_geral;


-- ============================================================
-- [13] AUTOCOMPLETE — busca de piloto por nome/CPF/número
-- ============================================================
SELECT
    p.id,
    p.nome,
    p.numero_piloto,
    p.email,
    p.whatsapp,
    p.cpf
FROM pilotos p
WHERE p.nome % %(termo)s              -- pg_trgm similarity
   OR p.cpf ILIKE %(termo)s || '%%'
   OR p.numero_piloto::TEXT = %(termo)s
ORDER BY similarity(p.nome, %(termo)s) DESC
LIMIT 10;


-- ============================================================
-- [14] PRÓXIMAS BATERIAS — alertas automáticos (n8n trigger)
-- Pilotos com bateria em até 30 min
-- ============================================================
SELECT
    p.nome                  AS piloto_nome,
    p.whatsapp,
    p.email,
    b.nome                  AS bateria_nome,
    b.data_hora,
    b.pista,
    i.numero_largada,
    cat.nome_display        AS categoria,
    EXTRACT(EPOCH FROM (b.data_hora - NOW()))/60 AS minutos_restantes
FROM baterias b
JOIN categorias cat  ON cat.id = b.categoria_id
JOIN inscricoes i    ON i.categoria_id = cat.id
    AND i.evento_id = b.evento_id
    AND i.status = 'confirmada'
JOIN pilotos p       ON p.id = i.piloto_id
WHERE b.status = 'agendada'
  AND b.data_hora BETWEEN NOW() AND NOW() + INTERVAL '30 minutes'
  AND b.evento_id = %(evento_id)s
ORDER BY b.data_hora, p.nome;
