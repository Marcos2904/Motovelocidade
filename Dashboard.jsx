import { useState, useEffect } from "react";

const API_BASE = "http://localhost:8000";

// ── Mock data (substitua pelas chamadas reais à API) ──────────────
const MOCK_DASHBOARD = {
  evento_nome: "Interlagos Speed Festival 2025",
  tipo: "velocidade",
  status: "em_andamento",
  local: "Autódromo José Carlos Pace – Interlagos, SP",
  pista: "Circuito Completo (4.309 km)",
  data_inicio: "2025-09-20",
  data_fim: "2025-09-21",
  total_inscritos: 148,
  confirmados: 132,
  checkins_feitos: 98,
  pct_checkin: 74.2,
  receita_total: 22400.0,
  total_categorias: 6,
  total_baterias: 18,
  baterias_concluidas: 6,
};

const MOCK_CATEGORIAS = [
  { categoria: "Ninja 636", total: 32, pct: 24 },
  { categoria: "Supersport", total: 28, pct: 21 },
  { categoria: "Superbike", total: 24, pct: 18 },
  { categoria: "Naked", total: 22, pct: 17 },
  { categoria: "Moto Livre", total: 14, pct: 11 },
  { categoria: "Scooter", total: 10, pct: 8 },
];

const MOCK_CRONOGRAMA = [
  { data_hora: "08:00", bateria_nome: "Treino Livre – Todas Categorias", categoria: "Geral", status: "concluida", pilotos_inscritos: 132 },
  { data_hora: "09:30", bateria_nome: "Ninja 636 – Q1", categoria: "Ninja 636", status: "concluida", pilotos_inscritos: 32 },
  { data_hora: "10:30", bateria_nome: "Supersport – Q1", categoria: "Supersport", status: "concluida", pilotos_inscritos: 28 },
  { data_hora: "11:30", bateria_nome: "Superbike – Corrida 1", categoria: "Superbike", status: "em_andamento", pilotos_inscritos: 24 },
  { data_hora: "13:00", bateria_nome: "Naked – Corrida 1", categoria: "Naked", status: "agendada", pilotos_inscritos: 22 },
  { data_hora: "14:30", bateria_nome: "Ninja 636 – Corrida 1", categoria: "Ninja 636", status: "agendada", pilotos_inscritos: 32 },
  { data_hora: "16:00", bateria_nome: "Supersport – Corrida Final", categoria: "Supersport", status: "agendada", pilotos_inscritos: 28 },
];

const MOCK_RANKING = [
  { posicao_geral: 1, numero_largada: 21, piloto_nome: "Pedro Henrique", categoria: "Ninja 636", total_pontos: 98, melhor_volta_fmt: "01:23.456" },
  { posicao_geral: 2, numero_largada: 77, piloto_nome: "Lucas Oliveira", categoria: "Ninja 636", total_pontos: 92, melhor_volta_fmt: "01:24.102" },
  { posicao_geral: 3, numero_largada: 3, piloto_nome: "Gabriel Souza", categoria: "Superbike", total_pontos: 85, melhor_volta_fmt: "01:22.880" },
  { posicao_geral: 4, numero_largada: 26, piloto_nome: "Matheus Lima", categoria: "Superbike", total_pontos: 78, melhor_volta_fmt: "01:23.001" },
  { posicao_geral: 5, numero_largada: 101, piloto_nome: "Rafael Almeida", categoria: "Supersport", total_pontos: 74, melhor_volta_fmt: "01:25.330" },
];

const MOCK_COMUNICADOS = [
  { tipo: "whatsapp", titulo: "Pista Liberada!", mensagem: "Aviso de pista enviado", enviado_em: "08:15", destinatarios: 132 },
  { tipo: "email", titulo: "Alteração de horário", mensagem: "Superbike passa para 11:30", enviado_em: "07:45", destinatarios: 132 },
  { tipo: "whatsapp", titulo: "Lembrete Check-in", mensagem: "Lembrete enviado aos pilotos", enviado_em: "07:00", destinatarios: 132 },
];

// ── Cores tema ────────────────────────────────────────────────
const theme = {
  green: "#39FF14",
  greenDark: "#1fad0a",
  greenMid: "#2dd40d",
  dark: "#0a0f0a",
  darkCard: "#111811",
  border: "#1a2e1a",
  text: "#e8f5e8",
  textMuted: "#6b8f6b",
  red: "#ff4444",
  amber: "#f59e0b",
  blue: "#3b82f6",
};

// ── Componentes auxiliares ────────────────────────────────────

function Badge({ status }) {
  const cfg = {
    concluida: { bg: "#0d2a0d", color: "#39FF14", label: "Concluída" },
    em_andamento: { bg: "#1a2200", color: "#f59e0b", label: "Em andamento" },
    agendada: { bg: "#0a1520", color: "#3b82f6", label: "Agendada" },
    publicado: { bg: "#0d2a0d", color: "#39FF14", label: "Publicado" },
    velocidade: { bg: "#0d2a0d", color: "#39FF14", label: "Velocidade" },
    motocross: { bg: "#1a0a0a", color: "#ff4444", label: "Motocross" },
  };
  const c = cfg[status] || { bg: "#111", color: "#888", label: status };
  return (
    <span style={{
      background: c.bg, color: c.color,
      fontSize: 11, fontWeight: 600, letterSpacing: "0.06em",
      padding: "2px 8px", borderRadius: 4,
      border: `1px solid ${c.color}33`, textTransform: "uppercase",
    }}>{c.label}</span>
  );
}

function KpiCard({ label, value, sub, accent }) {
  return (
    <div style={{
      background: theme.darkCard, border: `1px solid ${theme.border}`,
      borderRadius: 10, padding: "16px 18px",
      borderTop: accent ? `2px solid ${accent}` : undefined,
    }}>
      <p style={{ margin: 0, fontSize: 11, color: theme.textMuted, letterSpacing: "0.08em", textTransform: "uppercase" }}>{label}</p>
      <p style={{ margin: "6px 0 0", fontSize: 26, fontWeight: 700, color: accent || theme.text, fontFamily: "monospace" }}>{value}</p>
      {sub && <p style={{ margin: "2px 0 0", fontSize: 12, color: theme.textMuted }}>{sub}</p>}
    </div>
  );
}

function ProgressBar({ value, max, color }) {
  const pct = Math.round((value / max) * 100);
  return (
    <div style={{ background: "#1a1a1a", borderRadius: 4, height: 6, overflow: "hidden" }}>
      <div style={{ width: `${pct}%`, height: "100%", background: color || theme.green, borderRadius: 4, transition: "width 0.6s ease" }} />
    </div>
  );
}

function DonutChart({ data }) {
  const total = data.reduce((s, d) => s + d.total, 0);
  const colors = [theme.green, "#3b82f6", "#f59e0b", "#ec4899", "#8b5cf6", "#06b6d4"];
  let offset = 0;
  const r = 54, cx = 64, cy = 64, circ = 2 * Math.PI * r;

  return (
    <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
      <svg width={128} height={128} style={{ flexShrink: 0 }}>
        <circle cx={cx} cy={cy} r={r} fill="none" stroke="#1a2e1a" strokeWidth={16} />
        {data.map((d, i) => {
          const pct = d.total / total;
          const dash = pct * circ;
          const gap = circ - dash;
          const el = (
            <circle key={i} cx={cx} cy={cy} r={r} fill="none"
              stroke={colors[i % colors.length]} strokeWidth={16}
              strokeDasharray={`${dash} ${gap}`}
              strokeDashoffset={-offset * circ}
              style={{ transition: "stroke-dasharray 0.5s ease" }}
            />
          );
          offset += pct;
          return el;
        })}
        <text x={cx} y={cy - 6} textAnchor="middle" fontSize={18} fontWeight={700} fill={theme.green}>{total}</text>
        <text x={cx} y={cy + 12} textAnchor="middle" fontSize={10} fill={theme.textMuted}>pilotos</text>
      </svg>
      <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 6 }}>
        {data.map((d, i) => (
          <div key={i} style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <div style={{ width: 8, height: 8, borderRadius: "50%", background: colors[i % colors.length], flexShrink: 0 }} />
            <span style={{ fontSize: 12, color: theme.text, flex: 1 }}>{d.categoria}</span>
            <span style={{ fontSize: 12, color: theme.textMuted, fontFamily: "monospace" }}>{d.pct}%</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ── Seções do Dashboard ───────────────────────────────────────

function HeroBanner({ dash }) {
  return (
    <div style={{
      position: "relative", borderRadius: 14, overflow: "hidden",
      background: `linear-gradient(135deg, #0a150a 0%, #0d1f0d 60%, #0a0a0a 100%)`,
      border: `1px solid ${theme.border}`, marginBottom: 20,
    }}>
      {/* Pista vetorizada decorativa */}
      <svg style={{ position: "absolute", right: 0, top: 0, opacity: 0.07, width: 320, height: "100%" }} viewBox="0 0 320 200" preserveAspectRatio="xMidYMid slice">
        <ellipse cx={220} cy={100} rx={150} ry={70} fill="none" stroke={theme.green} strokeWidth={24} />
        <ellipse cx={220} cy={100} rx={110} ry={50} fill="none" stroke={theme.green} strokeWidth={8} />
        <line x1={70} y1={100} x2={0} y2={100} stroke={theme.green} strokeWidth={24} />
      </svg>

      <div style={{ position: "relative", padding: "22px 24px" }}>
        <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", flexWrap: "wrap", gap: 12 }}>
          <div>
            <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 6 }}>
              <div style={{
                background: theme.green, color: "#000", fontWeight: 800,
                fontSize: 13, padding: "3px 10px", borderRadius: 6, letterSpacing: "0.05em"
              }}>⚡ MX CONTROL</div>
              <Badge status={dash.tipo} />
              <Badge status={dash.status} />
            </div>
            <h1 style={{ margin: 0, fontSize: 22, fontWeight: 700, color: theme.text }}>{dash.evento_nome}</h1>
            <p style={{ margin: "4px 0 0", fontSize: 13, color: theme.textMuted }}>
              📍 {dash.local} · {dash.pista}
            </p>
          </div>
          <div style={{ textAlign: "right" }}>
            <p style={{ margin: 0, fontSize: 11, color: theme.textMuted, textTransform: "uppercase", letterSpacing: "0.08em" }}>Período</p>
            <p style={{ margin: "2px 0 0", fontSize: 14, fontWeight: 600, color: theme.green, fontFamily: "monospace" }}>
              {dash.data_inicio} → {dash.data_fim}
            </p>
          </div>
        </div>

        {/* Progress check-in */}
        <div style={{ marginTop: 16 }}>
          <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 6 }}>
            <span style={{ fontSize: 12, color: theme.textMuted }}>Check-in concluído</span>
            <span style={{ fontSize: 12, color: theme.green, fontFamily: "monospace", fontWeight: 600 }}>
              {dash.checkins_feitos}/{dash.confirmados} ({dash.pct_checkin}%)
            </span>
          </div>
          <ProgressBar value={dash.checkins_feitos} max={dash.confirmados} color={theme.green} />
        </div>
      </div>
    </div>
  );
}

function KpiRow({ dash }) {
  return (
    <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(150px, 1fr))", gap: 12, marginBottom: 20 }}>
      <KpiCard label="Inscritos" value={dash.total_inscritos} sub={`+18% vs último evento`} accent={theme.green} />
      <KpiCard label="Categorias" value={dash.total_categorias} sub="ativas" accent={theme.blue} />
      <KpiCard label="Receita" value={`R$ ${dash.receita_total.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}`} sub="+25% vs último evento" accent={theme.amber} />
      <KpiCard label="Baterias" value={`${dash.baterias_concluidas}/${dash.total_baterias}`} sub="concluídas" accent="#ec4899" />
    </div>
  );
}

function CronogramaSection({ data }) {
  const [ativo, setAtivo] = useState(null);
  return (
    <div style={{ background: theme.darkCard, border: `1px solid ${theme.border}`, borderRadius: 12, padding: "16px 18px", marginBottom: 16 }}>
      <h3 style={{ margin: "0 0 14px", fontSize: 13, color: theme.textMuted, textTransform: "uppercase", letterSpacing: "0.08em" }}>
        🏁 Cronograma do dia
      </h3>
      <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
        {data.map((b, i) => (
          <div key={i} onClick={() => setAtivo(ativo === i ? null : i)}
            style={{
              display: "flex", alignItems: "center", gap: 10,
              padding: "8px 10px", borderRadius: 8, cursor: "pointer",
              background: b.status === "em_andamento" ? "#1a2200" :
                ativo === i ? "#111f11" : "transparent",
              border: b.status === "em_andamento" ? `1px solid ${theme.amber}44` :
                ativo === i ? `1px solid ${theme.border}` : "1px solid transparent",
              transition: "all 0.2s",
            }}>
            <span style={{
              fontSize: 12, fontFamily: "monospace", fontWeight: 700,
              color: b.status === "em_andamento" ? theme.amber : theme.textMuted,
              minWidth: 38,
            }}>{b.data_hora}</span>
            <div style={{ flex: 1 }}>
              <p style={{ margin: 0, fontSize: 13, color: theme.text, fontWeight: b.status === "em_andamento" ? 600 : 400 }}>{b.bateria_nome}</p>
              <p style={{ margin: 0, fontSize: 11, color: theme.textMuted }}>{b.pilotos_inscritos} pilotos</p>
            </div>
            <Badge status={b.status} />
          </div>
        ))}
      </div>
    </div>
  );
}

function RankingSection({ data }) {
  const medals = ["🥇", "🥈", "🥉"];
  return (
    <div style={{ background: theme.darkCard, border: `1px solid ${theme.border}`, borderRadius: 12, padding: "16px 18px", marginBottom: 16 }}>
      <h3 style={{ margin: "0 0 14px", fontSize: 13, color: theme.textMuted, textTransform: "uppercase", letterSpacing: "0.08em" }}>
        🏆 Top 5 ranking geral
      </h3>
      <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
        {data.map((r, i) => (
          <div key={i} style={{
            display: "flex", alignItems: "center", gap: 10,
            padding: "8px 10px", borderRadius: 8,
            background: i === 0 ? "#1a1400" : "transparent",
            border: i === 0 ? `1px solid ${theme.amber}44` : "1px solid transparent",
          }}>
            <span style={{ fontSize: 18, width: 28 }}>{medals[i] || `#${r.posicao_geral}`}</span>
            <div style={{
              width: 32, height: 32, borderRadius: "50%",
              background: theme.green + "22", border: `1px solid ${theme.green}55`,
              display: "flex", alignItems: "center", justifyContent: "center",
              fontSize: 12, fontWeight: 700, color: theme.green, fontFamily: "monospace",
            }}>#{r.numero_largada}</div>
            <div style={{ flex: 1 }}>
              <p style={{ margin: 0, fontSize: 13, color: theme.text, fontWeight: 500 }}>{r.piloto_nome}</p>
              <p style={{ margin: 0, fontSize: 11, color: theme.textMuted }}>{r.categoria} · ⏱ {r.melhor_volta_fmt}</p>
            </div>
            <span style={{ fontSize: 16, fontWeight: 700, color: theme.green, fontFamily: "monospace" }}>{r.total_pontos} pts</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function ComunicadosSection({ data }) {
  const icons = { whatsapp: "💬", email: "📧", push: "🔔" };
  return (
    <div style={{ background: theme.darkCard, border: `1px solid ${theme.border}`, borderRadius: 12, padding: "16px 18px", marginBottom: 16 }}>
      <h3 style={{ margin: "0 0 14px", fontSize: 13, color: theme.textMuted, textTransform: "uppercase", letterSpacing: "0.08em" }}>
        📡 Comunicações recentes
      </h3>
      <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
        {data.map((c, i) => (
          <div key={i} style={{
            display: "flex", alignItems: "center", gap: 10,
            padding: "8px 10px", borderRadius: 8, border: `1px solid ${theme.border}`,
          }}>
            <span style={{ fontSize: 18 }}>{icons[c.tipo] || "📢"}</span>
            <div style={{ flex: 1 }}>
              <p style={{ margin: 0, fontSize: 13, color: theme.text, fontWeight: 500 }}>{c.titulo}</p>
              <p style={{ margin: 0, fontSize: 11, color: theme.textMuted }}>
                Enviado para {c.destinatarios} pilotos
              </p>
            </div>
            <span style={{ fontSize: 11, color: theme.textMuted, fontFamily: "monospace" }}>{c.enviado_em}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function NinjaBanner() {
  return (
    <div style={{
      background: `linear-gradient(135deg, #050f05 0%, #0a1f0a 100%)`,
      border: `1px solid ${theme.green}33`, borderRadius: 12,
      padding: "20px 24px", marginBottom: 16,
      position: "relative", overflow: "hidden",
    }}>
      {/* SVG decorativo - silhueta de moto/pista */}
      <svg style={{ position: "absolute", right: 16, top: "50%", transform: "translateY(-50%)", opacity: 0.18 }}
        width={160} height={80} viewBox="0 0 160 80">
        {/* silhueta estilizada de moto */}
        <ellipse cx={110} cy={60} rx={18} ry={18} fill="none" stroke={theme.green} strokeWidth={4} />
        <ellipse cx={40} cy={60} rx={18} ry={18} fill="none" stroke={theme.green} strokeWidth={4} />
        <path d="M40 42 L58 30 L90 30 L110 42 M75 30 L80 18 L100 22 L110 30"
          fill="none" stroke={theme.green} strokeWidth={3} strokeLinecap="round" />
        <path d="M58 60 L110 60" stroke={theme.green} strokeWidth={4} />
      </svg>

      <div style={{ position: "relative" }}>
        <p style={{ margin: "0 0 4px", fontSize: 11, color: theme.green, textTransform: "uppercase", letterSpacing: "0.1em", fontWeight: 600 }}>
          Destaque da categoria
        </p>
        <h2 style={{ margin: "0 0 4px", fontSize: 18, fontWeight: 700, color: theme.text }}>
          Kawasaki Ninja ZX-6R 636
        </h2>
        <p style={{ margin: 0, fontSize: 12, color: theme.textMuted }}>
          Interlagos · Circuito Completo 4.309 km · 32 inscritos
        </p>
        <div style={{ marginTop: 12, display: "flex", gap: 16 }}>
          {[
            { l: "Melhor volta", v: "01:23.456" },
            { l: "Líder", v: "#21 Pedro H." },
            { l: "Próx. corrida", v: "14:30" },
          ].map((s, i) => (
            <div key={i}>
              <p style={{ margin: 0, fontSize: 10, color: theme.textMuted, textTransform: "uppercase", letterSpacing: "0.06em" }}>{s.l}</p>
              <p style={{ margin: "2px 0 0", fontSize: 14, fontWeight: 700, color: theme.green, fontFamily: "monospace" }}>{s.v}</p>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// ── App principal ─────────────────────────────────────────────
export default function App() {
  const [tab, setTab] = useState("dashboard");
  const [dash] = useState(MOCK_DASHBOARD);

  const tabs = [
    { id: "dashboard", label: "Dashboard" },
    { id: "inscricoes", label: "Inscrições" },
    { id: "cronograma", label: "Cronograma" },
    { id: "ranking", label: "Ranking" },
    { id: "comunicacao", label: "Comunicação" },
    { id: "financeiro", label: "Financeiro" },
  ];

  return (
    <div style={{ background: theme.dark, minHeight: "100vh", fontFamily: "system-ui, sans-serif", color: theme.text }}>
      {/* Sidebar */}
      <div style={{ display: "flex", minHeight: "100vh" }}>
        <aside style={{
          width: 200, background: "#060d06", borderRight: `1px solid ${theme.border}`,
          padding: "20px 0", flexShrink: 0, display: "flex", flexDirection: "column",
        }}>
          <div style={{ padding: "0 16px 20px", borderBottom: `1px solid ${theme.border}` }}>
            <div style={{
              background: theme.green, color: "#000", fontWeight: 900,
              fontSize: 15, padding: "6px 12px", borderRadius: 8, display: "inline-block",
              letterSpacing: "0.05em"
            }}>⚡ MX</div>
            <span style={{ marginLeft: 8, fontSize: 15, fontWeight: 700, color: theme.text }}>CONTROL</span>
          </div>
          <nav style={{ flex: 1, padding: "12px 0" }}>
            {tabs.map(t => (
              <button key={t.id} onClick={() => setTab(t.id)} style={{
                display: "block", width: "100%", textAlign: "left",
                padding: "9px 16px", fontSize: 13, fontWeight: tab === t.id ? 600 : 400,
                color: tab === t.id ? theme.green : theme.textMuted,
                background: tab === t.id ? theme.green + "11" : "transparent",
                border: "none", borderLeft: tab === t.id ? `2px solid ${theme.green}` : "2px solid transparent",
                cursor: "pointer", transition: "all 0.15s",
              }}>{t.label}</button>
            ))}
          </nav>
          <div style={{ padding: "16px", borderTop: `1px solid ${theme.border}` }}>
            <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
              <div style={{
                width: 30, height: 30, borderRadius: "50%",
                background: theme.green + "22", border: `1px solid ${theme.green}55`,
                display: "flex", alignItems: "center", justifyContent: "center",
                fontSize: 11, fontWeight: 700, color: theme.green,
              }}>M</div>
              <div>
                <p style={{ margin: 0, fontSize: 12, color: theme.text, fontWeight: 500 }}>Marcos</p>
                <p style={{ margin: 0, fontSize: 10, color: theme.textMuted }}>Organizador</p>
              </div>
            </div>
          </div>
        </aside>

        {/* Main */}
        <main style={{ flex: 1, padding: "24px", overflowY: "auto" }}>
          {tab === "dashboard" && (
            <>
              <HeroBanner dash={dash} />
              <KpiRow dash={dash} />
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16 }}>
                <div>
                  <NinjaBanner />
                  <div style={{ background: theme.darkCard, border: `1px solid ${theme.border}`, borderRadius: 12, padding: "16px 18px" }}>
                    <h3 style={{ margin: "0 0 14px", fontSize: 13, color: theme.textMuted, textTransform: "uppercase", letterSpacing: "0.08em" }}>
                      Inscritos por categoria
                    </h3>
                    <DonutChart data={MOCK_CATEGORIAS} />
                  </div>
                </div>
                <div>
                  <CronogramaSection data={MOCK_CRONOGRAMA} />
                </div>
              </div>
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16, marginTop: 16 }}>
                <RankingSection data={MOCK_RANKING} />
                <ComunicadosSection data={MOCK_COMUNICADOS} />
              </div>
            </>
          )}

          {tab === "cronograma" && (
            <div style={{ maxWidth: 720 }}>
              <h2 style={{ margin: "0 0 20px", fontSize: 20, fontWeight: 700, color: theme.text }}>Cronograma completo</h2>
              <CronogramaSection data={MOCK_CRONOGRAMA} />
            </div>
          )}

          {tab === "ranking" && (
            <div style={{ maxWidth: 720 }}>
              <h2 style={{ margin: "0 0 20px", fontSize: 20, fontWeight: 700, color: theme.text }}>Ranking geral</h2>
              <RankingSection data={MOCK_RANKING} />
            </div>
          )}

          {tab === "comunicacao" && (
            <div style={{ maxWidth: 720 }}>
              <h2 style={{ margin: "0 0 20px", fontSize: 20, fontWeight: 700, color: theme.text }}>Comunicação</h2>
              <ComunicadosSection data={MOCK_COMUNICADOS} />
            </div>
          )}

          {tab !== "dashboard" && tab !== "cronograma" && tab !== "ranking" && tab !== "comunicacao" && (
            <div style={{ display: "flex", alignItems: "center", justifyContent: "center", height: 300 }}>
              <div style={{ textAlign: "center" }}>
                <p style={{ fontSize: 40, marginBottom: 12 }}>🚧</p>
                <p style={{ color: theme.textMuted, fontSize: 15 }}>Seção <strong style={{ color: theme.text }}>{tab}</strong> — conecte à API para carregar os dados reais.</p>
              </div>
            </div>
          )}
        </main>
      </div>
    </div>
  );
}
