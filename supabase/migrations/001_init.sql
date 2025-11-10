-- ============== SCHEMA LIMPO v2 (multi-escolas) ==============
create schema if not exists v2;

-- 0) TABELAS-BASE
create table if not exists v2.escolas (
  id_escola   text primary key,
  nome_escola text not null
);

-- chaves compostas por (id, school_id) evitam problemas de FK
create table if not exists v2.turmas (
  id_turma    text not null,
  school_id   text not null references v2.escolas(id_escola) on delete cascade,
  nome_turma  text not null,
  primary key (id_turma, school_id)
);

create table if not exists v2.grupos (
  id_grupo    text not null,
  school_id   text not null references v2.escolas(id_escola) on delete cascade,
  nome_grupo  text not null,
  primary key (id_grupo, school_id)
);

create table if not exists v2.alunos (
  id_aluno    text not null,
  school_id   text not null references v2.escolas(id_escola) on delete cascade,
  id_turma    text not null,
  id_grupo    text null,
  nome_aluno  text not null,
  primary key (id_aluno, school_id),
  foreign key (id_turma, school_id) references v2.turmas(id_turma, school_id) on delete cascade,
  foreign key (id_grupo, school_id) references v2.grupos(id_grupo, school_id) on delete set null
);

-- pontos (individuais e de grupo)
create table if not exists v2.pontos_alunos (
  id          bigserial primary key,
  aluno_id    text not null,
  school_id   text not null references v2.escolas(id_escola) on delete cascade,
  pontos      int  not null,
  data        date not null default current_date,
  detalhe     text,
  foreign key (aluno_id, school_id) references v2.alunos(id_aluno, school_id) on delete cascade
);

create table if not exists v2.pontos_grupos (
  id          bigserial primary key,
  grupo_id    text not null,
  school_id   text not null references v2.escolas(id_escola) on delete cascade,
  pontos      int  not null,
  data        date not null default current_date,
  detalhe     text,
  foreign key (grupo_id, school_id) references v2.grupos(id_grupo, school_id) on delete cascade
);

-- perfis e associação professor ↔ turma
create table if not exists v2.perfis (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  role        text not null check (role in ('MASTER','SCHOOL_ADMIN','TEACHER')),
  school_id   text null references v2.escolas(id_escola),
  created_at  timestamptz default now()
);

create table if not exists v2.professores_turmas (
  user_id    uuid not null references auth.users(id) on delete cascade,
  school_id  text not null references v2.escolas(id_escola) on delete cascade,
  id_turma   text not null,
  primary key (user_id, school_id, id_turma),
  foreign key (id_turma, school_id) references v2.turmas(id_turma, school_id) on delete cascade
);

-- 1) CALENDÁRIO
create or replace view v2.vw_cal_meses as
select
  date_trunc('month', d)::date               as periodo_inicio,
  to_char(date_trunc('month', d), 'YYYY-MM') as periodo_label,
  extract(year from d)::int                  as ano,
  extract(month from d)::int                 as mes
from generate_series(date '2025-01-01', date_trunc('month', current_date), interval '1 month') d;

create or replace view v2.vw_cal_trimestres as
with m as (select * from v2.vw_cal_meses)
select distinct
  make_date(ano, (ceil(mes/3.0)::int - 1)*3 + 1, 1) as periodo_inicio,
  (ano::text || '-T' || ceil(mes/3.0)::int)         as periodo_label,
  ano,
  ceil(mes/3.0)::int                                 as trimestre
from m
order by periodo_inicio;

create or replace view v2.vw_cal_semestral as
with m as (select * from v2.vw_cal_meses)
select distinct
  make_date(ano, case when mes <= 6 then 1 else 7 end, 1) as periodo_inicio,
  (ano::text || '-S' || case when mes <= 6 then 1 else 2 end) as periodo_label,
  ano,
  case when mes <= 6 then 1 else 2 end as semestre
from m
order by periodo_inicio;

create or replace view v2.vw_cal_anos as
select
  make_date(yr, 1, 1) as periodo_inicio,
  yr::text            as periodo_label,
  yr                  as ano
from generate_series(2025, extract(year from current_date)::int, 1) as yr
order by periodo_inicio;

-- 2) UNIVERSO (joins por chave composta)
create or replace view v2.vw_universo_alunos as
select
  a.school_id,
  a.id_turma, t.nome_turma,
  a.id_aluno, a.nome_aluno
from v2.alunos a
join v2.turmas t
  on t.id_turma=a.id_turma and t.school_id=a.school_id;

create or replace view v2.vw_universo_grupos as
select distinct
  a.school_id,
  a.id_turma, t.nome_turma,
  a.id_grupo, g.nome_grupo
from v2.alunos a
join v2.turmas t
  on t.id_turma=a.id_turma and t.school_id=a.school_id
left join v2.grupos g
  on g.id_grupo=a.id_grupo and g.school_id=a.school_id
where a.id_grupo is not null;

-- 3) AGG ALUNOS
create or replace view v2.vw_agg_alunos_mensal as
select
  u.school_id, u.id_turma, u.id_aluno,
  m.periodo_inicio, m.periodo_label,
  coalesce(sum(pa.pontos),0) as pontos_totais
from v2.vw_universo_alunos u
cross join v2.vw_cal_meses m
left join v2.pontos_alunos pa
  on pa.aluno_id=u.id_aluno and pa.school_id=u.school_id
 and date_trunc('month', pa.data)=m.periodo_inicio
group by u.school_id, u.id_turma, u.id_aluno, m.periodo_inicio, m.periodo_label;

create or replace view v2.vw_agg_alunos_trimestral as
with pa_tri as (
  select pa.*,
         extract(year from pa.data)::int as ano,
         ceil(extract(month from pa.data)::int/3.0)::int as trimestre
  from v2.pontos_alunos pa
)
select
  u.school_id, u.id_turma, u.id_aluno,
  ct.periodo_inicio, ct.periodo_label,
  coalesce(sum(p.pontos),0) as pontos_totais
from v2.vw_universo_alunos u
cross join v2.vw_cal_trimestres ct
left join pa_tri p
  on p.aluno_id=u.id_aluno and p.school_id=u.school_id
 and p.ano=ct.ano and p.trimestre=ct.trimestre
group by u.school_id, u.id_turma, u.id_aluno, ct.periodo_inicio, ct.periodo_label;

create or replace view v2.vw_agg_alunos_semestral as
with pa_se as (
  select pa.*,
         extract(year from pa.data)::int as ano,
         case when extract(month from pa.data)::int<=6 then 1 else 2 end as semestre
  from v2.pontos_alunos pa
)
select
  u.school_id, u.id_turma, u.id_aluno,
  cs.periodo_inicio, cs.periodo_label,
  coalesce(sum(p.pontos),0) as pontos_totais
from v2.vw_universo_alunos u
cross join v2.vw_cal_semestral cs
left join pa_se p
  on p.aluno_id=u.id_aluno and p.school_id=u.school_id
 and p.ano=cs.ano
 and p.semestre=(case when extract(month from cs.periodo_inicio)::int<=6 then 1 else 2 end)
group by u.school_id, u.id_turma, u.id_aluno, cs.periodo_inicio, cs.periodo_label;

create or replace view v2.vw_agg_alunos_anual as
with pa_an as (
  select pa.*, extract(year from pa.data)::int as ano
  from v2.pontos_alunos pa
)
select
  u.school_id, u.id_turma, u.id_aluno,
  ca.periodo_inicio, ca.periodo_label,
  coalesce(sum(p.pontos),0) as pontos_totais
from v2.vw_universo_alunos u
cross join v2.vw_cal_anos ca
left join pa_an p
  on p.aluno_id=u.id_aluno and p.school_id=u.school_id
 and p.ano=ca.ano
group by u.school_id, u.id_turma, u.id_aluno, ca.periodo_inicio, ca.periodo_label;

-- 4) RANKINGS ALUNOS
create or replace view v2.vw_ranking_alunos_mensal_full as
select
  a.school_id,
  a.id_turma, u.nome_turma,
  a.periodo_inicio, a.periodo_label,
  u.id_aluno, u.nome_aluno,
  a.pontos_totais,
  rank() over (
    partition by a.school_id, a.id_turma, a.periodo_inicio
    order by a.pontos_totais desc, u.nome_aluno asc
  ) as posicao
from v2.vw_agg_alunos_mensal a
join v2.vw_universo_alunos u
  on u.school_id=a.school_id and u.id_turma=a.id_turma and u.id_aluno=a.id_aluno;

create or replace view v2.vw_ranking_alunos_trimestral_full as
select
  a.school_id,
  a.id_turma, u.nome_turma,
  a.periodo_inicio, a.periodo_label,
  u.id_aluno, u.nome_aluno,
  a.pontos_totais,
  rank() over (
    partition by a.school_id, a.id_turma, a.periodo_inicio
    order by a.pontos_totais desc, u.nome_aluno asc
  ) as posicao
from v2.vw_agg_alunos_trimestral a
join v2.vw_universo_alunos u
  on u.school_id=a.school_id and u.id_turma=a.id_turma and u.id_aluno=a.id_aluno;

create or replace view v2.vw_ranking_alunos_semestral_full as
select
  a.school_id,
  a.id_turma, u.nome_turma,
  a.periodo_inicio, a.periodo_label,
  u.id_aluno, u.nome_aluno,
  a.pontos_totais,
  rank() over (
    partition by a.school_id, a.id_turma, a.periodo_inicio
    order by a.pontos_totais desc, u.nome_aluno asc
  ) as posicao
from v2.vw_agg_alunos_semestral a
join v2.vw_universo_alunos u
  on u.school_id=a.school_id and u.id_turma=a.id_turma and u.id_aluno=a.id_aluno;

create or replace view v2.vw_ranking_alunos_anual_full as
select
  a.school_id,
  a.id_turma, u.nome_turma,
  a.periodo_inicio, a.periodo_label,
  u.id_aluno, u.nome_aluno,
  a.pontos_totais,
  rank() over (
    partition by a.school_id, a.id_turma, a.periodo_inicio
    order by a.pontos_totais desc, u.nome_aluno asc
  ) as posicao
from v2.vw_agg_alunos_anual a
join v2.vw_universo_alunos u
  on u.school_id=a.school_id and u.id_turma=a.id_turma and u.id_aluno=a.id_aluno;

-- 5) AGG & RANKINGS GRUPOS
create or replace view v2.vw_agg_grupos_mensal as
select
  u.school_id, u.id_turma, u.id_grupo,
  m.periodo_inicio, m.periodo_label,
  coalesce(sum(pg.pontos),0) as pontos_totais
from v2.vw_universo_grupos u
cross join v2.vw_cal_meses m
left join v2.pontos_grupos pg
  on pg.grupo_id=u.id_grupo and pg.school_id=u.school_id
 and date_trunc('month', pg.data)=m.periodo_inicio
group by u.school_id, u.id_turma, u.id_grupo, m.periodo_inicio, m.periodo_label;

create or replace view v2.vw_agg_grupos_trimestral as
with pg_tri as (
  select pg.*,
         extract(year from pg.data)::int as ano,
         ceil(extract(month from pg.data)::int/3.0)::int as trimestre
  from v2.pontos_grupos pg
)
select
  u.school_id, u.id_turma, u.id_grupo,
  ct.periodo_inicio, ct.periodo_label,
  coalesce(sum(p.pontos),0) as pontos_totais
from v2.vw_universo_grupos u
cross join v2.vw_cal_trimestres ct
left join pg_tri p
  on p.grupo_id=u.id_grupo and p.school_id=u.school_id
 and p.ano=ct.ano and p.trimestre=ct.trimestre
group by u.school_id, u.id_turma, u.id_grupo, ct.periodo_inicio, ct.periodo_label;

create or replace view v2.vw_agg_grupos_semestral as
with pg_se as (
  select pg.*,
         extract(year from pg.data)::int as ano,
         case when extract(month from pg.data)::int<=6 then 1 else 2 end as semestre
  from v2.pontos_grupos pg
)
select
  u.school_id, u.id_turma, u.id_grupo,
  cs.periodo_inicio, cs.periodo_label,
  coalesce(sum(p.pontos),0) as pontos_totais
from v2.vw_universo_grupos u
cross join v2.vw_cal_semestral cs
left join pg_se p
  on p.grupo_id=u.id_grupo and p.school_id=u.school_id
 and p.ano=cs.ano
 and p.semestre=(case when extract(month from cs.periodo_inicio)::int<=6 then 1 else 2 end)
group by u.school_id, u.id_turma, u.id_grupo, cs.periodo_inicio, cs.periodo_label;

create or replace view v2.vw_agg_grupos_anual as
with pg_an as (
  select pg.*, extract(year from pg.data)::int as ano
  from v2.pontos_grupos pg
)
select
  u.school_id, u.id_turma, u.id_grupo,
  ca.periodo_inicio, ca.periodo_label,
  coalesce(sum(p.pontos),0) as pontos_totais
from v2.vw_universo_grupos u
cross join v2.vw_cal_anos ca
left join pg_an p
  on p.grupo_id=u.id_grupo and p.school_id=u.school_id
 and p.ano=ca.ano
group by u.school_id, u.id_turma, u.id_grupo, ca.periodo_inicio, ca.periodo_label;

create or replace view v2.vw_ranking_grupos_mensal_full as
select
  g.school_id,
  g.id_turma, u.nome_turma,
  g.periodo_inicio, g.periodo_label,
  u.id_grupo, u.nome_grupo,
  g.pontos_totais,
  rank() over (
    partition by g.school_id, g.id_turma, g.periodo_inicio
    order by g.pontos_totais desc, u.nome_grupo asc
  ) as posicao
from v2.vw_agg_grupos_mensal g
join v2.vw_universo_grupos u
  on u.school_id=g.school_id and u.id_turma=g.id_turma and u.id_grupo=g.id_grupo;

create or replace view v2.vw_ranking_grupos_trimestral_full as
select
  g.school_id,
  g.id_turma, u.nome_turma,
  g.periodo_inicio, g.periodo_label,
  u.id_grupo, u.nome_grupo,
  g.pontos_totais,
  rank() over (
    partition by g.school_id, g.id_turma, g.periodo_inicio
    order by g.pontos_totais desc, u.nome_grupo asc
  ) as posicao
from v2.vw_agg_grupos_trimestral g
join v2.vw_universo_grupos u
  on u.school_id=g.school_id and u.id_turma=g.id_turma and u.id_grupo=g.id_grupo;

create or replace view v2.vw_ranking_grupos_semestral_full as
select
  g.school_id,
  g.id_turma, u.nome_turma,
  g.periodo_inicio, g.periodo_label,
  u.id_grupo, u.nome_grupo,
  g.pontos_totais,
  rank() over (
    partition by g.school_id, g.id_turma, g.periodo_inicio
    order by g.pontos_totais desc, u.nome_grupo asc
  ) as posicao
from v2.vw_agg_grupos_semestral g
join v2.vw_universo_grupos u
  on u.school_id=g.school_id and u.id_turma=g.id_turma and u.id_grupo=g.id_grupo;

create or replace view v2.vw_ranking_grupos_anual_full as
select
  g.school_id,
  g.id_turma, u.nome_turma,
  g.periodo_inicio, g.periodo_label,
  u.id_grupo, u.nome_grupo,
  g.pontos_totais,
  rank() over (
    partition by g.school_id, g.id_turma, g.periodo_inicio
    order by g.pontos_totais desc, u.nome_grupo asc
  ) as posicao
from v2.vw_agg_grupos_anual g
join v2.vw_universo_grupos u
  on u.school_id=g.school_id and u.id_turma=g.id_turma and u.id_grupo=g.id_grupo;

-- 6) Views auxiliares
create or replace view v2.vw_escolas as
select id_escola, nome_escola
from v2.escolas
order by nome_escola;

-- 7) RLS: leitura liberada, escrita restrita por perfil

-- habilita RLS
alter table v2.pontos_alunos enable row level security;
alter table v2.pontos_grupos enable row level security;

-- leitura (qualquer usuário autenticado/anon pode LER pontuações)
drop policy if exists sel_pontos_alunos on v2.pontos_alunos;
create policy sel_pontos_alunos on v2.pontos_alunos
for select using (true);

drop policy if exists sel_pontos_grupos on v2.pontos_grupos;
create policy sel_pontos_grupos on v2.pontos_grupos
for select using (true);

-- escrita: apenas TEACHER da escola e associado à turma do aluno/grupo
drop policy if exists ins_pontos_alunos on v2.pontos_alunos;
create policy ins_pontos_alunos on v2.pontos_alunos
for insert with check (
  exists (
    select 1
    from v2.perfis pf
    where pf.user_id = auth.uid()
      and pf.role in ('MASTER','SCHOOL_ADMIN','TEACHER')
      and pf.school_id = v2.pontos_alunos.school_id
  )
  and exists (
    select 1
    from v2.alunos a
    join v2.professores_turmas pt
      on pt.user_id = auth.uid()
     and pt.school_id = a.school_id
     and pt.id_turma = a.id_turma
    where a.id_aluno = v2.pontos_alunos.aluno_id
      and a.school_id = v2.pontos_alunos.school_id
  )
);

drop policy if exists ins_pontos_grupos on v2.pontos_grupos;
create policy ins_pontos_grupos on v2.pontos_grupos
for insert with check (
  exists (
    select 1
    from v2.perfis pf
    where pf.user_id = auth.uid()
      and pf.role in ('MASTER','SCHOOL_ADMIN','TEACHER')
      and pf.school_id = v2.pontos_grupos.school_id
  )
  and exists (
    select 1
    from v2.alunos a
    join v2.professores_turmas pt
      on pt.user_id = auth.uid()
     and pt.school_id = a.school_id
     and pt.id_turma = a.id_turma
    where a.id_grupo = v2.pontos_grupos.grupo_id
      and a.school_id = v2.pontos_grupos.school_id
  )
);

-- 8) PERMISSÕES p/ frontend (somente SELECT e INSERT de pontos)
grant usage on schema v2 to anon, authenticated;
grant select on all tables in schema v2 to anon, authenticated;
grant usage  on all sequences in schema v2 to anon, authenticated;
alter default privileges in schema v2 grant select on tables to anon, authenticated;

grant insert on v2.pontos_alunos to authenticated;
grant insert on v2.pontos_grupos to authenticated;
