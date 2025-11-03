-- ========= schema =========
create schema if not exists v2;

-- ========= tabelas núcleo =========
create table if not exists v2.escolas (
  id_escola   text primary key,
  nome_escola text not null
);

create table if not exists v2.turmas (
  id_turma    text not null,
  school_id   text not null references v2.escolas(id_escola) on delete cascade,
  nome_turma  text not null,
  primary key (id_turma, school_id)
);

create table if not exists v2.perfis (
  user_id   uuid primary key,
  role      text not null check (role in ('MASTER','SCHOOL_ADMIN','TEACHER')),
  school_id text null references v2.escolas(id_escola) on delete set null
);

create table if not exists v2.professores (
  id_professor uuid not null,
  id_escola    text not null references v2.escolas(id_escola) on delete cascade,
  id_turma     text not null,
  primary key (id_professor, id_escola, id_turma),
  foreign key (id_turma, id_escola) references v2.turmas(id_turma, school_id) on delete cascade
);

create table if not exists v2.alunos (
  id_aluno   bigserial primary key,
  school_id  text not null references v2.escolas(id_escola) on delete cascade,
  id_turma   text not null,
  nome_aluno text not null,
  foreign key (id_turma, school_id) references v2.turmas(id_turma, school_id) on delete cascade
);

create table if not exists v2.grupos (
  id_grupo    bigserial primary key,
  school_id   text not null references v2.escolas(id_escola) on delete cascade,
  id_turma    text not null,
  nome_grupo  text not null,
  foreign key (id_turma, school_id) references v2.turmas(id_turma, school_id) on delete cascade
);

create table if not exists v2.alunos_grupos (
  id_aluno bigint not null references v2.alunos(id_aluno) on delete cascade,
  id_grupo bigint not null references v2.grupos(id_grupo) on delete cascade,
  primary key (id_aluno, id_grupo)
);

-- pontos (⭐ alunos / 💎 grupos)
create table if not exists v2.pontos_alunos (
  id_ponto    bigserial primary key,
  school_id   text not null references v2.escolas(id_escola) on delete cascade,
  id_turma    text not null,
  id_aluno    bigint not null references v2.alunos(id_aluno) on delete cascade,
  quantidade  integer not null,
  motivo      text,
  created_at  timestamptz not null default now(),
  created_by  uuid not null,
  foreign key (id_turma, school_id) references v2.turmas(id_turma, school_id) on delete cascade
);

create table if not exists v2.pontos_grupos (
  id_ponto    bigserial primary key,
  school_id   text not null references v2.escolas(id_escola) on delete cascade,
  id_turma    text not null,
  id_grupo    bigint not null references v2.grupos(id_grupo) on delete cascade,
  quantidade  integer not null,
  motivo      text,
  created_at  timestamptz not null default now(),
  created_by  uuid not null,
  foreign key (id_turma, school_id) references v2.turmas(id_turma, school_id) on delete cascade
);

-- loja
create table if not exists v2.loja_itens (
  item_id         bigserial primary key,
  school_id       text not null references v2.escolas(id_escola) on delete cascade,
  tipo            text not null check (tipo in ('ALUNO','GRUPO')),
  nome            text not null,
  descricao       text,
  custo_estrela   integer,
  custo_diamante  integer,
  ativo           boolean not null default true
);

create table if not exists v2.resgates_alunos (
  id             bigserial primary key,
  aluno_id       bigint not null references v2.alunos(id_aluno) on delete cascade,
  school_id      text not null references v2.escolas(id_escola) on delete cascade,
  item_id        bigint not null references v2.loja_itens(item_id) on delete restrict,
  quantidade     integer not null default 1,
  total_estrela  integer not null,
  created_at     timestamptz not null default now(),
  created_by     uuid not null,
  observacao     text
);

create table if not exists v2.resgates_grupos (
  id              bigserial primary key,
  grupo_id        bigint not null references v2.grupos(id_grupo) on delete cascade,
  school_id       text not null references v2.escolas(id_escola) on delete cascade,
  item_id         bigint not null references v2.loja_itens(item_id) on delete restrict,
  quantidade      integer not null default 1,
  total_diamante  integer not null,
  created_at      timestamptz not null default now(),
  created_by      uuid not null,
  observacao      text
);

-- ========= grants básicos =========
grant usage on schema v2 to anon, authenticated;
grant select, insert, update, delete on all tables in schema v2 to anon, authenticated;
alter default privileges in schema v2 grant select, insert, update, delete on tables to anon, authenticated;

-- ========= calendário (2025+ atual) =========
create or replace view v2.vw_cal_meses as
select date_trunc('month', d)::date as periodo_inicio,
       to_char(date_trunc('month', d), 'YYYY-MM') as periodo_label,
       extract(year from d)::int as ano,
       extract(month from d)::int as mes
from generate_series(date '2025-01-01', date_trunc('month', current_date), interval '1 month') d;

create or replace view v2.vw_cal_trimestres as
with m as (select * from v2.vw_cal_meses)
select distinct
  make_date(ano, ((ceil(mes/3.0)::int - 1)*3 + 1), 1) as periodo_inicio,
  (ano::text || '-T' || ceil(mes/3.0)::int)           as periodo_label,
  ano, ceil(mes/3.0)::int as trimestre
from m order by periodo_inicio;

create or replace view v2.vw_cal_semestral as
with m as (select * from v2.vw_cal_meses)
select distinct
  make_date(ano, case when mes<=6 then 1 else 7 end, 1) as periodo_inicio,
  (ano::text || '-S' || case when mes<=6 then 1 else 2 end) as periodo_label,
  ano, case when mes<=6 then 1 else 2 end as semestre
from m order by periodo_inicio;

create or replace view v2.vw_cal_anos as
select make_date(yr,1,1) as periodo_inicio,
       yr::text as periodo_label,
       yr as ano
from generate_series(2025, extract(year from current_date)::int, 1) as yr
order by periodo_inicio;

-- ========= universos =========
create or replace view v2.vw_universo_alunos as
select a.school_id, a.id_turma, a.id_aluno, a.nome_aluno
from v2.alunos a;

create or replace view v2.vw_universo_grupos as
select g.school_id, g.id_turma, g.id_grupo, g.nome_grupo
from v2.grupos g;

-- ========= período helper =========
create or replace function v2.fn_periodo_range(label text)
returns table (ini date, fim date)
language sql immutable as $$
  with x as (
    select label,
           split_part(label,'-',1)::int as y,
           split_part(label,'-',2)      as rest
  )
  select
    case
      when rest is null then make_date(y,1,1)
      when rest like 'T%' then make_date(y, ((substring(rest from 2)::int -1)*3)+1, 1)
      when rest like 'S%' then make_date(y, case when substring(rest from 2)::int=1 then 1 else 7 end, 1)
      else to_date(label||'-01','YYYY-MM-DD')
    end as ini,
    case
      when rest is null then make_date(y+1,1,1)
      when rest like 'T%' then (make_date(y, ((substring(rest from 2)::int -1)*3)+1, 1) + interval '3 month')::date
      when rest like 'S%' then (make_date(y, case when substring(rest from 2)::int=1 then 1 else 7 end, 1) + interval '6 month')::date
      else (date_trunc('month', to_date(label||'-01','YYYY-MM-DD')) + interval '1 month')::date
    end as fim
  from x;
$$;

-- ========= agregadores & rankings (alunos) =========
create or replace function v2.fn_sum_aluno_periodo(p_label text)
returns table (school_id text, id_turma text, id_aluno bigint, pontos_totais bigint)
language sql stable as $$
  with r as (select * from v2.fn_periodo_range(p_label))
  select pa.school_id, pa.id_turma, pa.id_aluno, coalesce(sum(pa.quantidade),0)::bigint as pontos_totais
  from v2.pontos_alunos pa, r
  where pa.created_at::date >= r.ini and pa.created_at::date < r.fim
  group by 1,2,3
$$;

create or replace view v2.vw_rank_alunos as
select u.school_id, u.id_turma, u.id_aluno, u.nome_aluno,
       p.periodo_label,
       coalesce(s.pontos_totais,0) as pontos_totais,
       dense_rank() over (partition by u.school_id, u.id_turma, p.periodo_label
                          order by coalesce(s.pontos_totais,0) desc, u.nome_aluno asc) as posicao
from v2.vw_universo_alunos u
cross join (
  select periodo_label from v2.vw_cal_meses
  union all select periodo_label from v2.vw_cal_trimestres
  union all select periodo_label from v2.vw_cal_semestral
  union all select periodo_label from v2.vw_cal_anos
) p
left join lateral v2.fn_sum_aluno_periodo(p.periodo_label) s
  on s.school_id = u.school_id and s.id_turma = u.id_turma and s.id_aluno = u.id_aluno;

-- ========= agregadores & rankings (grupos) =========
create or replace function v2.fn_sum_grupo_periodo(p_label text)
returns table (school_id text, id_turma text, id_grupo bigint, pontos_totais bigint)
language sql stable as $$
  with r as (select * from v2.fn_periodo_range(p_label))
  select pg.school_id, pg.id_turma, pg.id_grupo, coalesce(sum(pg.quantidade),0)::bigint as pontos_totais
  from v2.pontos_grupos pg, r
  where pg.created_at::date >= r.ini and pg.created_at::date < r.fim
  group by 1,2,3
$$;

create or replace view v2.vw_rank_grupos as
select u.school_id, u.id_turma, u.id_grupo, u.nome_grupo,
       p.periodo_label,
       coalesce(s.pontos_totais,0) as pontos_totais,
       dense_rank() over (partition by u.school_id, u.id_turma, p.periodo_label
                          order by coalesce(s.pontos_totais,0) desc, u.nome_grupo asc) as posicao
from v2.vw_universo_grupos u
cross join (
  select periodo_label from v2.vw_cal_meses
  union all select periodo_label from v2.vw_cal_trimestres
  union all select periodo_label from v2.vw_cal_semestral
  union all select periodo_label from v2.vw_cal_anos
) p
left join lateral v2.fn_sum_grupo_periodo(p.periodo_label) s
  on s.school_id = u.school_id and s.id_turma = u.id_turma and s.id_grupo = u.id_grupo;

-- ========= saldos & RPC loja =========
create or replace view v2.vw_saldo_estrelas_alunos as
select a.id_aluno, a.school_id,
       coalesce((select sum(quantidade) from v2.pontos_alunos pa where pa.id_aluno=a.id_aluno),0)
     - coalesce((select sum(total_estrela) from v2.resgates_alunos ra where ra.aluno_id=a.id_aluno),0)
       as saldo_estrelas
from v2.alunos a;

create or replace view v2.vw_saldo_diamantes_grupos as
select g.id_grupo, g.school_id,
       coalesce((select sum(quantidade) from v2.pontos_grupos pg where pg.id_grupo=g.id_grupo),0)
     - coalesce((select sum(total_diamante) from v2.resgates_grupos rg where rg.grupo_id=g.id_grupo),0)
       as saldo_diamantes
from v2.grupos g;

create or replace function v2.rpc_loja_aluno(aluno_id_input bigint)
returns table(item_id bigint, nome text, descricao text, custo_estrela int, compravel boolean)
language sql stable as $$
  with a as (select * from v2.alunos where id_aluno=aluno_id_input)
  select i.item_id, i.nome, i.descricao, i.custo_estrela,
         (coalesce(s.saldo_estrelas,0) >= coalesce(i.custo_estrela,999999)) as compravel
  from v2.loja_itens i
  join a on a.school_id = i.school_id
  left join v2.vw_saldo_estrelas_alunos s on s.id_aluno = a.id_aluno
  where i.ativo = true and i.tipo = 'ALUNO';
$$;

create or replace function v2.rpc_resgatar_item_aluno(aluno_id_input bigint, item_id_input bigint, quantidade_input int, observacao_input text)
returns table(saldo_antes int, custo_total int, saldo_depois int)
language plpgsql as $$
declare
  sid text; custo int; sal int; total int;
begin
  select school_id into sid from v2.alunos where id_aluno = aluno_id_input;
  select custo_estrela into custo from v2.loja_itens where item_id=item_id_input and school_id=sid and tipo='ALUNO' and ativo=true;
  if custo is null then raise exception 'Item inválido'; end if;
  select saldo_estrelas into sal from v2.vw_saldo_estrelas_alunos where id_aluno = aluno_id_input;
  total := custo * greatest(quantidade_input,1);
  if sal < total then raise exception 'Saldo insuficiente'; end if;

  insert into v2.resgates_alunos (aluno_id, school_id, item_id, quantidade, total_estrela, created_by, observacao)
  values (aluno_id_input, sid, item_id_input, greatest(quantidade_input,1), total, auth.uid(), observacao_input);

  return query select sal, total, sal - total;
end;
$$;

create or replace function v2.rpc_loja_grupo(grupo_id_input bigint)
returns table(item_id bigint, nome text, descricao text, custo_diamante int, compravel boolean)
language sql stable as $$
  with g as (select * from v2.grupos where id_grupo=grupo_id_input)
  select i.item_id, i.nome, i.descricao, i.custo_diamante,
         (coalesce(s.saldo_diamantes,0) >= coalesce(i.custo_diamante,999999)) as compravel
  from v2.loja_itens i
  join g on g.school_id = i.school_id
  left join v2.vw_saldo_diamantes_grupos s on s.id_grupo = g.id_grupo
  where i.ativo = true and i.tipo = 'GRUPO';
$$;

create or replace function v2.rpc_resgatar_item_grupo(grupo_id_input bigint, item_id_input bigint, quantidade_input int, observacao_input text)
returns table(saldo_antes int, custo_total int, saldo_depois int)
language plpgsql as $$
declare
  sid text; custo int; sal int; total int;
begin
  select school_id into sid from v2.grupos where id_grupo = grupo_id_input;
  select custo_diamante into custo from v2.loja_itens where item_id=item_id_input and school_id=sid and tipo='GRUPO' and ativo=true;
  if custo is null then raise exception 'Item inválido'; end if;
  select saldo_diamantes into sal from v2.vw_saldo_diamantes_grupos where id_grupo = grupo_id_input;
  total := custo * greatest(quantidade_input,1);
  if sal < total then raise exception 'Saldo insuficiente'; end if;

  insert into v2.resgates_grupos (grupo_id, school_id, item_id, quantidade, total_diamante, created_by, observacao)
  values (grupo_id_input, sid, item_id_input, greatest(quantidade_input,1), total, auth.uid(), observacao_input);

  return query select sal, total, sal - total;
end;
$$;

-- ========= RLS =========
alter table v2.escolas enable row level security;
alter table v2.turmas enable row level security;
alter table v2.alunos enable row level security;
alter table v2.grupos enable row level security;
alter table v2.alunos_grupos enable row level security;
alter table v2.pontos_alunos enable row level security;
alter table v2.pontos_grupos enable row level security;
alter table v2.loja_itens enable row level security;
alter table v2.resgates_alunos enable row level security;
alter table v2.resgates_grupos enable row level security;
alter table v2.perfis enable row level security;
alter table v2.professores enable row level security;

create or replace function v2.is_master() returns boolean language sql stable as
$$ select exists (select 1 from v2.perfis p where p.user_id = auth.uid() and p.role='MASTER') $$;

create or replace function v2.my_school() returns text language sql stable as
$$ select school_id from v2.perfis where user_id = auth.uid() limit 1 $$;

create policy p_perfis_sel_master on v2.perfis for select using (v2.is_master() or user_id = auth.uid());
create policy p_perfis_mod_master on v2.perfis for all using (v2.is_master()) with check (v2.is_master());

create policy p_escolas_sel on v2.escolas for select using (v2.is_master() or id_escola = v2.my_school());
create policy p_escolas_mod on v2.escolas for all using (v2.is_master()) with check (true);

create policy p_turmas_sel on v2.turmas for select using (v2.is_master() or school_id = v2.my_school());
create policy p_turmas_ins on v2.turmas for insert with check (v2.is_master() or school_id = v2.my_school());
create policy p_turmas_upd on v2.turmas for update using (v2.is_master() or school_id = v2.my_school()) with check (v2.is_master() or school_id = v2.my_school());
create policy p_turmas_del on v2.turmas for delete using (v2.is_master() or school_id = v2.my_school());

create policy p_alunos_sel on v2.alunos for select using (v2.is_master() or school_id = v2.my_school());
create policy p_alunos_ins on v2.alunos for insert with check (v2.is_master() or school_id = v2.my_school());
create policy p_alunos_upd on v2.alunos for update using (v2.is_master() or school_id = v2.my_school()) with check (v2.is_master() or school_id = v2.my_school());
create policy p_alunos_del on v2.alunos for delete using (v2.is_master() or school_id = v2.my_school());

create policy p_grupos_sel on v2.grupos for select using (v2.is_master() or school_id = v2.my_school());
create policy p_grupos_ins on v2.grupos for insert with check (v2.is_master() or school_id = v2.my_school());
create policy p_grupos_upd on v2.grupos for update using (v2.is_master() or school_id = v2.my_school()) with check (v2.is_master() or school_id = v2.my_school());
create policy p_grupos_del on v2.grupos for delete using (v2.is_master() or school_id = v2.my_school());

create policy p_prof_sel on v2.professores for select using (v2.is_master() or id_escola = v2.my_school());
create policy p_prof_mod on v2.professores for all using (v2.is_master() or id_escola = v2.my_school()) with check (v2.is_master() or id_escola = v2.my_school());

create policy p_pa_sel on v2.pontos_alunos for select using (v2.is_master() or school_id = v2.my_school());
create policy p_pa_ins on v2.pontos_alunos for insert with check (
  v2.is_master()
  or (
    school_id = v2.my_school()
    and exists (
      select 1 from v2.professores pr
      where pr.id_professor = auth.uid()
        and pr.id_escola = school_id
        and pr.id_turma = id_turma
    )
  )
);
create policy p_pg_sel on v2.pontos_grupos for select using (v2.is_master() or school_id = v2.my_school());
create policy p_pg_ins on v2.pontos_grupos for insert with check (
  v2.is_master()
  or (
    school_id = v2.my_school()
    and exists (
      select 1 from v2.professores pr
      where pr.id_professor = auth.uid()
        and pr.id_escola = school_id
        and pr.id_turma = id_turma
    )
  )
);

create policy p_loja_sel on v2.loja_itens for select using (v2.is_master() or school_id = v2.my_school());
create policy p_loja_mod on v2.loja_itens for all using (v2.is_master() or school_id = v2.my_school()) with check (v2.is_master() or school_id = v2.my_school());

create policy p_res_al_sel on v2.resgates_alunos for select using (v2.is_master() or school_id = v2.my_school());
create policy p_res_al_ins on v2.resgates_alunos for insert with check (v2.is_master() or school_id = v2.my_school());

create policy p_res_gr_sel on v2.resgates_grupos for select using (v2.is_master() or school_id = v2.my_school());
create policy p_res_gr_ins on v2.resgates_grupos for insert with check (v2.is_master() or school_id = v2.my_school());
