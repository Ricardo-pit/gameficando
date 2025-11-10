-- Dados de exemplo (pode remover depois)
insert into v2.escolas (id_escola, nome_escola) values
  ('ALPHA','Escola Alpha')
on conflict do nothing;

insert into v2.turmas (id_turma, school_id, nome_turma) values
  ('6A','ALPHA','6º Ano A'),
  ('6B','ALPHA','6º Ano B')
on conflict do nothing;

insert into v2.grupos (id_grupo, school_id, nome_grupo) values
  ('G1','ALPHA','Equipe Sol'),
  ('G2','ALPHA','Equipe Lua')
on conflict do nothing;

insert into v2.alunos (id_aluno, school_id, id_turma, id_grupo, nome_aluno) values
  ('A1','ALPHA','6A','G1','Ana'),
  ('A2','ALPHA','6A','G1','Bruno'),
  ('A3','ALPHA','6A','G2','Carla'),
  ('A4','ALPHA','6A','G2','Diego')
on conflict do nothing;

-- pontos aluno (mar/2025)
insert into v2.pontos_alunos (aluno_id, school_id, pontos, data, detalhe) values
  ('A1','ALPHA',15,'2025-03-05','tarefas'),
  ('A2','ALPHA',14,'2025-03-06','participação'),
  ('A3','ALPHA',20,'2025-03-07','projeto'),
  ('A4','ALPHA',18,'2025-03-08','desafio');

-- pontos grupo (mar/2025)
insert into v2.pontos_grupos (grupo_id, school_id, pontos, data, detalhe) values
  ('G1','ALPHA',30,'2025-03-09','1º lugar bimestre'),
  ('G2','ALPHA',27,'2025-03-09','2º lugar bimestre');
