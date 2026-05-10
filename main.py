"""
MX Control + Pista Control — FastAPI Backend
Suporta eventos de Motocross e Velocidade/Pista
"""
from __future__ import annotations

import os
import uuid
from contextlib import asynccontextmanager
from datetime import date, datetime, timedelta
from typing import Any, Optional

import asyncpg
from fastapi import Depends, FastAPI, HTTPException, Query, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr, Field


# ──────────────────────────────────────────────────────────────
# CONFIG
# ──────────────────────────────────────────────────────────────
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://user:password@localhost:5432/mxcontrol"
)


# ──────────────────────────────────────────────────────────────
# DATABASE POOL
# ──────────────────────────────────────────────────────────────
class Database:
    pool: asyncpg.Pool | None = None

db = Database()


@asynccontextmanager
async def lifespan(app: FastAPI):
    db.pool = await asyncpg.create_pool(DATABASE_URL, min_size=2, max_size=10)
    yield
    await db.pool.close()


async def get_db() -> asyncpg.Pool:
    return db.pool


# ──────────────────────────────────────────────────────────────
# APP
# ──────────────────────────────────────────────────────────────
app = FastAPI(
    title="MX Control API",
    version="1.0.0",
    description="API para gestão de eventos de Motocross e Velocidade",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ──────────────────────────────────────────────────────────────
# SCHEMAS PYDANTIC
# ──────────────────────────────────────────────────────────────

class EventoCreate(BaseModel):
    organizador_id: uuid.UUID
    nome: str
    tipo: str  # motocross | velocidade | enduro | supermoto
    local: str
    pista: Optional[str] = None
    data_inicio: date
    data_fim: date
    hora_abertura: Optional[str] = None
    descricao: Optional[str] = None
    capacidade: int = 500


class InscricaoCreate(BaseModel):
    evento_id: uuid.UUID
    piloto_id: uuid.UUID
    categoria_id: uuid.UUID
    motocicleta_id: Optional[uuid.UUID] = None
    numero_largada: Optional[int] = None
    valor_pago: Optional[float] = None


class PilotoCreate(BaseModel):
    nome: str
    email: EmailStr
    telefone: Optional[str] = None
    whatsapp: Optional[str] = None
    cpf: Optional[str] = None
    data_nascimento: Optional[date] = None
    numero_piloto: Optional[int] = None


class MotoCreate(BaseModel):
    piloto_id: uuid.UUID
    marca: str
    modelo: str
    ano: Optional[int] = None
    cilindrada: Optional[int] = None
    cor: Optional[str] = None
    placa: Optional[str] = None


class BateriaCreate(BaseModel):
    evento_id: uuid.UUID
    categoria_id: uuid.UUID
    nome: str
    numero_bateria: int = 1
    data_hora: datetime
    duracao_minutos: int = 20
    voltas_max: Optional[int] = None
    pista: Optional[str] = None


class ResultadoCreate(BaseModel):
    bateria_id: uuid.UUID
    inscricao_id: uuid.UUID
    posicao: Optional[int] = None
    tempo_total: Optional[str] = None   # "00:20:35.123"
    melhor_volta: Optional[str] = None  # "00:01:45.670"
    voltas_completas: int = 0
    pontos: int = 0
    dnf: bool = False
    dns: bool = False
    dsq: bool = False


class ComunicadoCreate(BaseModel):
    evento_id: uuid.UUID
    tipo: str  # whatsapp | email | push
    titulo: Optional[str] = None
    mensagem: str
    criado_por: Optional[uuid.UUID] = None


class CheckinRequest(BaseModel):
    evento_id: uuid.UUID


# ──────────────────────────────────────────────────────────────
# HELPERS
# ──────────────────────────────────────────────────────────────

def row_to_dict(record) -> dict:
    if record is None:
        return {}
    return dict(record)


def rows_to_list(records) -> list[dict]:
    return [dict(r) for r in records]


# ──────────────────────────────────────────────────────────────
# ROTAS: SAÚDE
# ──────────────────────────────────────────────────────────────

@app.get("/health", tags=["Sistema"])
async def health():
    return {"status": "ok", "timestamp": datetime.utcnow()}


# ──────────────────────────────────────────────────────────────
# ROTAS: EVENTOS
# ──────────────────────────────────────────────────────────────

@app.get("/eventos", tags=["Eventos"])
async def listar_eventos(
    tipo: Optional[str] = None,
    status: Optional[str] = None,
    pool: asyncpg.Pool = Depends(get_db),
):
    query = """
        SELECT e.*, COUNT(DISTINCT i.id) AS total_inscritos
        FROM eventos e
        LEFT JOIN inscricoes i ON i.evento_id = e.id AND i.status != 'cancelada'
        WHERE ($1::TEXT IS NULL OR e.tipo::TEXT = $1)
          AND ($2::TEXT IS NULL OR e.status::TEXT = $2)
        GROUP BY e.id
        ORDER BY e.data_inicio DESC
    """
    rows = await pool.fetch(query, tipo, status)
    return rows_to_list(rows)


@app.post("/eventos", tags=["Eventos"], status_code=201)
async def criar_evento(body: EventoCreate, pool: asyncpg.Pool = Depends(get_db)):
    query = """
        INSERT INTO eventos (organizador_id, nome, tipo, local, pista,
                             data_inicio, data_fim, hora_abertura, descricao, capacidade)
        VALUES ($1,$2,$3::tipo_evento,$4,$5,$6,$7,$8::TIME,$9,$10)
        RETURNING *
    """
    row = await pool.fetchrow(
        query,
        body.organizador_id, body.nome, body.tipo, body.local, body.pista,
        body.data_inicio, body.data_fim, body.hora_abertura,
        body.descricao, body.capacidade,
    )
    return row_to_dict(row)


@app.get("/eventos/{evento_id}/dashboard", tags=["Eventos"])
async def dashboard_evento(evento_id: uuid.UUID, pool: asyncpg.Pool = Depends(get_db)):
    """KPIs principais do dashboard para um evento."""
    query = """
        SELECT
            e.id, e.nome, e.tipo, e.status, e.local, e.pista,
            e.data_inicio, e.data_fim,
            COUNT(DISTINCT i.id)                                            AS total_inscritos,
            COUNT(DISTINCT i.id) FILTER (WHERE i.status = 'confirmada')     AS confirmados,
            COUNT(DISTINCT i.id) FILTER (WHERE i.checkin_feito = TRUE)      AS checkins_feitos,
            ROUND(
                COUNT(DISTINCT i.id) FILTER (WHERE i.checkin_feito)::NUMERIC
                / NULLIF(COUNT(DISTINCT i.id) FILTER (WHERE i.status='confirmada'), 0) * 100, 1
            )                                                               AS pct_checkin,
            COALESCE(SUM(i.valor_pago) FILTER (WHERE i.status_pagamento='pago'), 0) AS receita_total,
            COUNT(DISTINCT cat.id)                                          AS total_categorias,
            COUNT(DISTINCT b.id)                                            AS total_baterias,
            COUNT(DISTINCT b.id) FILTER (WHERE b.status = 'concluida')     AS baterias_concluidas
        FROM eventos e
        LEFT JOIN inscricoes i   ON i.evento_id = e.id
        LEFT JOIN categorias cat ON cat.evento_id = e.id AND cat.ativa
        LEFT JOIN baterias b     ON b.evento_id = e.id
        WHERE e.id = $1
        GROUP BY e.id, e.nome, e.tipo, e.status, e.local,
                 e.pista, e.data_inicio, e.data_fim
    """
    row = await pool.fetchrow(query, evento_id)
    if not row:
        raise HTTPException(404, "Evento não encontrado")
    return row_to_dict(row)


@app.get("/eventos/{evento_id}/inscritos-por-categoria", tags=["Eventos"])
async def inscritos_por_categoria(evento_id: uuid.UUID, pool: asyncpg.Pool = Depends(get_db)):
    query = """
        SELECT cat.nome_display AS categoria, cat.id AS categoria_id,
               COUNT(i.id) AS total,
               ROUND(COUNT(i.id)::NUMERIC / SUM(COUNT(i.id)) OVER () * 100, 1) AS pct
        FROM inscricoes i
        JOIN categorias cat ON cat.id = i.categoria_id
        WHERE i.evento_id = $1 AND i.status IN ('pendente','confirmada')
        GROUP BY cat.id, cat.nome_display
        ORDER BY total DESC
    """
    return rows_to_list(await pool.fetch(query, evento_id))


# ──────────────────────────────────────────────────────────────
# ROTAS: PILOTOS
# ──────────────────────────────────────────────────────────────

@app.get("/pilotos", tags=["Pilotos"])
async def listar_pilotos(
    busca: Optional[str] = Query(None),
    limit: int = Query(20, le=100),
    pool: asyncpg.Pool = Depends(get_db),
):
    query = """
        SELECT p.*, COUNT(i.id) AS total_inscricoes
        FROM pilotos p
        LEFT JOIN inscricoes i ON i.piloto_id = p.id
        WHERE ($1::TEXT IS NULL
               OR p.nome ILIKE '%%' || $1 || '%%'
               OR p.email ILIKE '%%' || $1 || '%%'
               OR p.numero_piloto::TEXT = $1)
        GROUP BY p.id
        ORDER BY p.nome
        LIMIT $2
    """
    return rows_to_list(await pool.fetch(query, busca, limit))


@app.post("/pilotos", tags=["Pilotos"], status_code=201)
async def criar_piloto(body: PilotoCreate, pool: asyncpg.Pool = Depends(get_db)):
    query = """
        INSERT INTO pilotos (nome, email, telefone, whatsapp, cpf, data_nascimento, numero_piloto)
        VALUES ($1,$2,$3,$4,$5,$6,$7)
        ON CONFLICT (email) DO UPDATE SET
            nome = EXCLUDED.nome, telefone = EXCLUDED.telefone,
            whatsapp = EXCLUDED.whatsapp, atualizado_em = NOW()
        RETURNING *
    """
    row = await pool.fetchrow(
        query,
        body.nome, body.email, body.telefone, body.whatsapp,
        body.cpf, body.data_nascimento, body.numero_piloto,
    )
    return row_to_dict(row)


@app.get("/pilotos/{piloto_id}/area", tags=["Pilotos"])
async def area_piloto(
    piloto_id: uuid.UUID,
    evento_id: uuid.UUID,
    pool: asyncpg.Pool = Depends(get_db),
):
    """Dados completos para o app do piloto."""
    query = """
        SELECT
            p.id, p.nome, p.numero_piloto, p.foto_url, p.whatsapp,
            i.id AS inscricao_id, i.numero_largada,
            i.status AS status_inscricao, i.checkin_feito,
            cat.nome_display AS categoria,
            m.marca, m.modelo, m.ano,
            (
                SELECT json_build_object(
                    'id', b.id, 'nome', b.nome,
                    'data_hora', b.data_hora, 'pista', b.pista, 'status', b.status
                )
                FROM baterias b
                WHERE b.categoria_id = i.categoria_id
                  AND b.evento_id = i.evento_id
                  AND b.status IN ('agendada','em_andamento')
                  AND b.data_hora >= NOW()
                ORDER BY b.data_hora LIMIT 1
            ) AS proxima_bateria,
            (
                SELECT json_agg(json_build_object(
                    'bateria', b2.nome, 'posicao', res.posicao,
                    'pontos', res.pontos,
                    'melhor_volta', TO_CHAR(res.melhor_volta,'MI:SS.MS'),
                    'dnf', res.dnf
                ) ORDER BY b2.data_hora)
                FROM resultados res
                JOIN baterias b2 ON b2.id = res.bateria_id
                WHERE res.inscricao_id = i.id
            ) AS meus_resultados,
            rk.posicao_geral, rk.total_pontos
        FROM inscricoes i
        JOIN pilotos p       ON p.id = i.piloto_id
        JOIN categorias cat  ON cat.id = i.categoria_id
        LEFT JOIN motocicletas m  ON m.id = i.motocicleta_id
        LEFT JOIN ranking rk ON rk.inscricao_id = i.id AND rk.evento_id = i.evento_id
        WHERE i.evento_id = $1 AND p.id = $2
        LIMIT 1
    """
    row = await pool.fetchrow(query, evento_id, piloto_id)
    if not row:
        raise HTTPException(404, "Piloto não encontrado neste evento")
    return row_to_dict(row)


# ──────────────────────────────────────────────────────────────
# ROTAS: INSCRIÇÕES
# ──────────────────────────────────────────────────────────────

@app.get("/eventos/{evento_id}/inscricoes", tags=["Inscrições"])
async def listar_inscricoes(
    evento_id: uuid.UUID,
    categoria_id: Optional[uuid.UUID] = None,
    status_insc: Optional[str] = Query(None, alias="status"),
    checkin: Optional[bool] = None,
    busca: Optional[str] = None,
    limit: int = Query(50, le=200),
    offset: int = 0,
    pool: asyncpg.Pool = Depends(get_db),
):
    query = """
        SELECT i.id, i.numero_largada, p.nome AS piloto_nome, p.numero_piloto,
               p.email, p.whatsapp, cat.nome_display AS categoria,
               m.marca || ' ' || m.modelo AS motocicleta, m.ano,
               i.status, i.status_pagamento, i.checkin_feito,
               i.checkin_hora, i.valor_pago, i.criado_em
        FROM inscricoes i
        JOIN pilotos p       ON p.id = i.piloto_id
        JOIN categorias cat  ON cat.id = i.categoria_id
        LEFT JOIN motocicletas m ON m.id = i.motocicleta_id
        WHERE i.evento_id = $1
          AND ($2::UUID IS NULL OR i.categoria_id = $2)
          AND ($3::TEXT IS NULL OR i.status::TEXT = $3)
          AND ($4::BOOLEAN IS NULL OR i.checkin_feito = $4)
          AND ($5::TEXT IS NULL
               OR p.nome ILIKE '%%' || $5 || '%%'
               OR p.email ILIKE '%%' || $5 || '%%'
               OR i.numero_largada::TEXT = $5)
        ORDER BY cat.nome_display, i.numero_largada NULLS LAST
        LIMIT $6 OFFSET $7
    """
    rows = await pool.fetch(
        query, evento_id, categoria_id, status_insc, checkin, busca, limit, offset
    )
    return rows_to_list(rows)


@app.post("/inscricoes", tags=["Inscrições"], status_code=201)
async def criar_inscricao(body: InscricaoCreate, pool: asyncpg.Pool = Depends(get_db)):
    query = """
        INSERT INTO inscricoes (evento_id, piloto_id, categoria_id,
                                motocicleta_id, numero_largada, valor_pago)
        VALUES ($1,$2,$3,$4,$5,$6)
        RETURNING *
    """
    try:
        row = await pool.fetchrow(
            query,
            body.evento_id, body.piloto_id, body.categoria_id,
            body.motocicleta_id, body.numero_largada, body.valor_pago,
        )
    except asyncpg.UniqueViolationError:
        raise HTTPException(409, "Piloto já inscrito nesta categoria/evento")
    return row_to_dict(row)


@app.patch("/inscricoes/{inscricao_id}/checkin", tags=["Inscrições"])
async def realizar_checkin(
    inscricao_id: uuid.UUID,
    body: CheckinRequest,
    pool: asyncpg.Pool = Depends(get_db),
):
    query = """
        UPDATE inscricoes
        SET checkin_feito = TRUE, checkin_hora = NOW(), atualizado_em = NOW()
        WHERE id = $1 AND evento_id = $2 AND status = 'confirmada'
        RETURNING id, numero_largada, checkin_hora
    """
    row = await pool.fetchrow(query, inscricao_id, body.evento_id)
    if not row:
        raise HTTPException(404, "Inscrição não encontrada ou não confirmada")
    return row_to_dict(row)


@app.patch("/inscricoes/{inscricao_id}/confirmar", tags=["Inscrições"])
async def confirmar_inscricao(inscricao_id: uuid.UUID, pool: asyncpg.Pool = Depends(get_db)):
    row = await pool.fetchrow(
        """UPDATE inscricoes SET status='confirmada', atualizado_em=NOW()
           WHERE id=$1 RETURNING *""",
        inscricao_id,
    )
    if not row:
        raise HTTPException(404, "Inscrição não encontrada")
    return row_to_dict(row)


# ──────────────────────────────────────────────────────────────
# ROTAS: CRONOGRAMA / BATERIAS
# ──────────────────────────────────────────────────────────────

@app.get("/eventos/{evento_id}/cronograma", tags=["Cronograma"])
async def cronograma(
    evento_id: uuid.UUID,
    data: Optional[date] = None,
    pool: asyncpg.Pool = Depends(get_db),
):
    """Cronograma completo ou filtrado por data."""
    data_filtro = data or date.today()
    query = """
        SELECT b.id, b.nome AS bateria_nome, cat.nome_display AS categoria,
               b.data_hora, b.duracao_minutos, b.voltas_max, b.pista, b.status,
               COUNT(DISTINCT i.id) AS pilotos_inscritos
        FROM baterias b
        JOIN categorias cat ON cat.id = b.categoria_id
        LEFT JOIN inscricoes i ON i.categoria_id = b.categoria_id
            AND i.evento_id = b.evento_id AND i.status = 'confirmada'
        WHERE b.evento_id = $1
          AND ($2::DATE IS NULL OR b.data_hora::DATE = $2)
        GROUP BY b.id, b.nome, cat.nome_display,
                 b.data_hora, b.duracao_minutos, b.voltas_max, b.pista, b.status
        ORDER BY b.data_hora
    """
    return rows_to_list(await pool.fetch(query, evento_id, data_filtro))


@app.post("/baterias", tags=["Cronograma"], status_code=201)
async def criar_bateria(body: BateriaCreate, pool: asyncpg.Pool = Depends(get_db)):
    query = """
        INSERT INTO baterias (evento_id, categoria_id, nome, numero_bateria,
                              data_hora, duracao_minutos, voltas_max, pista)
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
        RETURNING *
    """
    row = await pool.fetchrow(
        query,
        body.evento_id, body.categoria_id, body.nome, body.numero_bateria,
        body.data_hora, body.duracao_minutos, body.voltas_max, body.pista,
    )
    return row_to_dict(row)


@app.patch("/baterias/{bateria_id}/status", tags=["Cronograma"])
async def atualizar_status_bateria(
    bateria_id: uuid.UUID,
    novo_status: str = Query(..., description="agendada|em_andamento|concluida|cancelada|adiada"),
    pool: asyncpg.Pool = Depends(get_db),
):
    row = await pool.fetchrow(
        """UPDATE baterias SET status=$2::status_bateria, atualizado_em=NOW()
           WHERE id=$1 RETURNING *""",
        bateria_id, novo_status,
    )
    if not row:
        raise HTTPException(404, "Bateria não encontrada")
    return row_to_dict(row)


# ──────────────────────────────────────────────────────────────
# ROTAS: RESULTADOS
# ──────────────────────────────────────────────────────────────

@app.get("/baterias/{bateria_id}/resultados", tags=["Resultados"])
async def resultados_bateria(bateria_id: uuid.UUID, pool: asyncpg.Pool = Depends(get_db)):
    query = """
        SELECT res.posicao, p.numero_piloto, i.numero_largada, p.nome AS piloto_nome,
               m.marca || ' ' || m.modelo AS motocicleta,
               TO_CHAR(res.tempo_total,'MI:SS.MS')  AS tempo_fmt,
               TO_CHAR(res.melhor_volta,'MI:SS.MS') AS melhor_volta_fmt,
               res.voltas_completas, res.pontos, res.dnf, res.dns, res.dsq
        FROM resultados res
        JOIN inscricoes i        ON i.id = res.inscricao_id
        JOIN pilotos p           ON p.id = i.piloto_id
        LEFT JOIN motocicletas m ON m.id = i.motocicleta_id
        WHERE res.bateria_id = $1
        ORDER BY res.dsq, res.dnf, res.dns, res.posicao NULLS LAST
    """
    return rows_to_list(await pool.fetch(query, bateria_id))


@app.post("/resultados", tags=["Resultados"], status_code=201)
async def registrar_resultado(body: ResultadoCreate, pool: asyncpg.Pool = Depends(get_db)):
    async with pool.acquire() as conn:
        async with conn.transaction():
            # Inserir/atualizar resultado
            row = await conn.fetchrow(
                """
                INSERT INTO resultados (bateria_id, inscricao_id, posicao,
                    tempo_total, melhor_volta, voltas_completas, pontos, dnf, dns, dsq)
                VALUES ($1,$2,$3,
                    $4::INTERVAL, $5::INTERVAL, $6, $7, $8, $9, $10)
                ON CONFLICT (bateria_id, inscricao_id) DO UPDATE SET
                    posicao=EXCLUDED.posicao, tempo_total=EXCLUDED.tempo_total,
                    melhor_volta=EXCLUDED.melhor_volta,
                    voltas_completas=EXCLUDED.voltas_completas,
                    pontos=EXCLUDED.pontos, dnf=EXCLUDED.dnf,
                    dns=EXCLUDED.dns, dsq=EXCLUDED.dsq
                RETURNING *
                """,
                body.bateria_id, body.inscricao_id, body.posicao,
                body.tempo_total, body.melhor_volta, body.voltas_completas,
                body.pontos, body.dnf, body.dns, body.dsq,
            )
            # Buscar evento_id e categoria_id para recalcular ranking
            meta = await conn.fetchrow(
                """SELECT b.evento_id, b.categoria_id
                   FROM baterias b WHERE b.id = $1""",
                body.bateria_id,
            )
            if meta:
                await conn.execute(
                    "SELECT recalcular_ranking($1, $2)",
                    meta["evento_id"], meta["categoria_id"],
                )
    return row_to_dict(row)


# ──────────────────────────────────────────────────────────────
# ROTAS: RANKING
# ──────────────────────────────────────────────────────────────

@app.get("/eventos/{evento_id}/ranking", tags=["Ranking"])
async def ranking_evento(
    evento_id: uuid.UUID,
    categoria_id: Optional[uuid.UUID] = None,
    limit: int = Query(50, le=200),
    pool: asyncpg.Pool = Depends(get_db),
):
    query = """
        SELECT r.posicao_geral, p.numero_piloto, i.numero_largada,
               p.nome AS piloto_nome, p.foto_url, cat.nome_display AS categoria,
               r.total_pontos, r.total_vitorias,
               TO_CHAR(r.melhor_volta,'MI:SS.MS') AS melhor_volta_fmt
        FROM ranking r
        JOIN inscricoes i    ON i.id = r.inscricao_id
        JOIN pilotos p       ON p.id = i.piloto_id
        JOIN categorias cat  ON cat.id = r.categoria_id
        WHERE r.evento_id = $1
          AND ($2::UUID IS NULL OR r.categoria_id = $2)
        ORDER BY r.categoria_id, r.posicao_geral
        LIMIT $3
    """
    return rows_to_list(await pool.fetch(query, evento_id, categoria_id, limit))


# ──────────────────────────────────────────────────────────────
# ROTAS: COMUNICADOS
# ──────────────────────────────────────────────────────────────

@app.get("/eventos/{evento_id}/comunicados", tags=["Comunicação"])
async def listar_comunicados(evento_id: uuid.UUID, pool: asyncpg.Pool = Depends(get_db)):
    query = """
        SELECT c.id, c.tipo, c.titulo, c.mensagem,
               c.destinatarios, c.enviado_em, o.nome AS criado_por,
               COUNT(lc.id) AS total_envios,
               COUNT(lc.id) FILTER (WHERE lc.status_envio='enviado') AS enviados_ok,
               COUNT(lc.id) FILTER (WHERE lc.status_envio='falha') AS falhas
        FROM comunicados c
        LEFT JOIN organizadores o    ON o.id = c.criado_por
        LEFT JOIN log_comunicados lc ON lc.comunicado_id = c.id
        WHERE c.evento_id = $1
        GROUP BY c.id, c.tipo, c.titulo, c.mensagem,
                 c.destinatarios, c.enviado_em, o.nome
        ORDER BY c.criado_em DESC LIMIT 30
    """
    return rows_to_list(await pool.fetch(query, evento_id))


@app.post("/comunicados", tags=["Comunicação"], status_code=201)
async def criar_comunicado(body: ComunicadoCreate, pool: asyncpg.Pool = Depends(get_db)):
    row = await pool.fetchrow(
        """INSERT INTO comunicados (evento_id, tipo, titulo, mensagem, criado_por)
           VALUES ($1,$2::tipo_comunicado,$3,$4,$5)
           RETURNING *""",
        body.evento_id, body.tipo, body.titulo, body.mensagem, body.criado_por,
    )
    return row_to_dict(row)


# ──────────────────────────────────────────────────────────────
# ROTAS: FINANCEIRO
# ──────────────────────────────────────────────────────────────

@app.get("/eventos/{evento_id}/financeiro", tags=["Financeiro"])
async def financeiro_evento(evento_id: uuid.UUID, pool: asyncpg.Pool = Depends(get_db)):
    query = """
        SELECT cat.nome_display AS categoria, COUNT(i.id) AS inscritos,
               COUNT(i.id) FILTER (WHERE i.status_pagamento='pago') AS pagos,
               COALESCE(SUM(i.valor_pago) FILTER (WHERE i.status_pagamento='pago'),0) AS receita,
               cat.taxa_inscricao AS taxa_unitaria,
               cat.taxa_inscricao * COUNT(i.id) AS receita_potencial
        FROM inscricoes i
        JOIN categorias cat ON cat.id = i.categoria_id
        WHERE i.evento_id = $1 AND i.status != 'cancelada'
        GROUP BY cat.id, cat.nome_display, cat.taxa_inscricao
        ORDER BY receita DESC
    """
    return rows_to_list(await pool.fetch(query, evento_id))


# ──────────────────────────────────────────────────────────────
# ROTAS: ALERTAS (para n8n / automação)
# ──────────────────────────────────────────────────────────────

@app.get("/eventos/{evento_id}/alertas/proximas-baterias", tags=["Automação"])
async def alertas_proximas_baterias(
    evento_id: uuid.UUID,
    minutos: int = Query(30, description="Janela de antecedência em minutos"),
    pool: asyncpg.Pool = Depends(get_db),
):
    """Retorna pilotos com bateria nos próximos N minutos — consumido pelo n8n."""
    query = """
        SELECT p.nome AS piloto_nome, p.whatsapp, p.email,
               b.nome AS bateria_nome, b.data_hora, b.pista,
               i.numero_largada, cat.nome_display AS categoria,
               ROUND(EXTRACT(EPOCH FROM (b.data_hora - NOW()))/60) AS minutos_restantes
        FROM baterias b
        JOIN categorias cat ON cat.id = b.categoria_id
        JOIN inscricoes i   ON i.categoria_id = cat.id
            AND i.evento_id = b.evento_id AND i.status = 'confirmada'
        JOIN pilotos p      ON p.id = i.piloto_id
        WHERE b.status = 'agendada'
          AND b.data_hora BETWEEN NOW() AND NOW() + ($2 || ' minutes')::INTERVAL
          AND b.evento_id = $1
        ORDER BY b.data_hora, p.nome
    """
    return rows_to_list(await pool.fetch(query, evento_id, str(minutos)))


# ──────────────────────────────────────────────────────────────
# ENTRYPOINT
# ──────────────────────────────────────────────────────────────
if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
