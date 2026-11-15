
BEGIN;

-- ============================================================
-- 1. VINCULAÇÃO COM SUPABASE AUTH:
--    Essa vinculação é pra reconhecer através do id do Supabase Auth 
-- (mais pra frente do código tem um Trigger que vincula o auth_id no momento da criação do usuário)
-- ============================================================

ALTER TABLE public."Usuario"
ADD COLUMN IF NOT EXISTS auth_user_id UUID
REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS usuario_auth_uidx
ON public."Usuario"(auth_user_id);

-- ============================================================
-- 2. FUNÇÕES AUXILIARES
-- SECURITY DEFINER evita recursão entre políticas RLS.
-- ============================================================

CREATE OR REPLACE FUNCTION public.meu_id()
RETURNS INTEGER
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT u.id_usuario
    FROM public."Usuario" u
    WHERE u.auth_user_id = (SELECT auth.uid())
      AND COALESCE(u.status_conta, 'ativo') = 'ativo'
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.meu_tipo()
RETURNS TEXT
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT u.tipo_usuario::text
    FROM public."Usuario" u
    WHERE u.auth_user_id = (SELECT auth.uid())
      AND COALESCE(u.status_conta, 'ativo') = 'ativo'
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.sou_professor()
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT COALESCE(public.meu_tipo() = 'professor', FALSE);
$$;

CREATE OR REPLACE FUNCTION public.sou_aluno()
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT COALESCE(public.meu_tipo() = 'aluno', FALSE);
$$;

CREATE OR REPLACE FUNCTION public.professor_do_grupo(p_grupo INTEGER)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public."Grupo" g
        WHERE g.id_grupo = p_grupo
          AND g.id_professor = public.meu_id()
          AND public.sou_professor()
    );
$$;

CREATE OR REPLACE FUNCTION public.aluno_do_grupo(p_grupo INTEGER)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public."Grupo_Aluno" ga
        WHERE ga.id_grupo = p_grupo
          AND ga.id_aluno = public.meu_id()
          AND COALESCE(ga.status, 'ativo') = 'ativo'
          AND public.sou_aluno()
    );
$$;

CREATE OR REPLACE FUNCTION public.participa_grupo(p_grupo INTEGER)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT public.professor_do_grupo(p_grupo)
        OR public.aluno_do_grupo(p_grupo);
$$;

CREATE OR REPLACE FUNCTION public.participa_aula(p_aula INTEGER)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public."Aula" a
        WHERE a.id_aula = p_aula
          AND public.participa_grupo(a.id_grupo)
    );
$$;

CREATE OR REPLACE FUNCTION public.professor_da_aula(p_aula INTEGER)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public."Aula" a
        WHERE a.id_aula = p_aula
          AND public.professor_do_grupo(a.id_grupo)
    );
$$;

CREATE OR REPLACE FUNCTION public.aluno_da_aula(p_aula INTEGER)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public."Aula" a
        WHERE a.id_aula = p_aula
          AND public.aluno_do_grupo(a.id_grupo)
    );
$$;

CREATE OR REPLACE FUNCTION public.professor_do_aluno_grupo(
    p_grupo_aluno INTEGER
)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public."Grupo_Aluno" ga
        WHERE ga.id_grupo_aluno = p_grupo_aluno
          AND public.professor_do_grupo(ga.id_grupo)
    );
$$;

CREATE OR REPLACE FUNCTION public.sou_aluno_grupo(
    p_grupo_aluno INTEGER
)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public."Grupo_Aluno" ga
        WHERE ga.id_grupo_aluno = p_grupo_aluno
          AND ga.id_aluno = public.meu_id()
    );
$$;

CREATE OR REPLACE FUNCTION public.participa_partida(
    p_partida INTEGER
)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public."Partida" p
        WHERE p.id_partida = p_partida
          AND (
              public.participa_grupo(p.id_grupo)
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.professor_da_partida(
    p_partida INTEGER
)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public."Partida" p
        WHERE p.id_partida = p_partida
          AND public.professor_do_grupo(p.id_grupo)
    );
$$;

CREATE OR REPLACE FUNCTION public.aluno_da_atividade(
    p_atividade INTEGER
)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public."Atividade" atv
        JOIN public."Aula" a ON a.id_aula = atv.id_aula
        WHERE atv.id_atividade = p_atividade
          AND public.aluno_do_grupo(a.id_grupo)
    );
$$;

CREATE OR REPLACE FUNCTION public.professor_da_atividade(
    p_atividade INTEGER
)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public."Atividade" atv
        JOIN public."Aula" a ON a.id_aula = atv.id_aula
        WHERE atv.id_atividade = p_atividade
          AND public.professor_do_grupo(a.id_grupo)
    );
$$;

CREATE OR REPLACE FUNCTION public.aluno_elegivel_grupo(
    p_grupo INTEGER,
    p_aluno INTEGER
)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public."Grupo_Aluno" ga
        JOIN public."Usuario" u
          ON u.id_usuario = ga.id_aluno
        WHERE ga.id_grupo = p_grupo
          AND ga.id_aluno = p_aluno
          AND ga.status = 'ativo'
          AND u.tipo_usuario = 'aluno'
          AND COALESCE(u.status_conta, 'ativo') = 'ativo'
    );
$$;

CREATE OR REPLACE FUNCTION public.aluno_elegivel_aula(
    p_aula INTEGER,
    p_aluno INTEGER
)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public."Aula" a
        WHERE a.id_aula = p_aula
          AND public.aluno_elegivel_grupo(a.id_grupo, p_aluno)
    );
$$;

-- ============================================================
-- 3. ATIVAR RLS EM TODAS AS TABELAS
-- ============================================================

ALTER TABLE public."Usuario" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."Grupo" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."Grupo_Aluno" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."Aula" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."Presenca" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."Convite_Grupo" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."Solicitacao_Entrada" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."Partida" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."Partida_Set" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."Fundamento" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."Avaliacao_Fundamento" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."Anotacao_Aula" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."Atividade" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."Entrega_Atividade" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."Comentario_Aula" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."Desafio" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."Ranking_Grupo" ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 4. LIMPEZA DE POLÍTICAS EXISTENTES
-- Remove políticas antigas para evitar permissões conflitantes.
-- ============================================================

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT schemaname, tablename, policyname
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename IN (
            'Usuario', 'Grupo', 'Grupo_Aluno', 'Aula',
            'Presenca', 'Convite_Grupo', 'Solicitacao_Entrada',
            'Partida', 'Partida_Set', 'Fundamento',
            'Avaliacao_Fundamento', 'Anotacao_Aula',
            'Atividade', 'Entrega_Atividade',
            'Comentario_Aula', 'Desafio', 'Ranking_Grupo'
          )
    LOOP
        EXECUTE format(
            'DROP POLICY IF EXISTS %I ON %I.%I',
            r.policyname, r.schemaname, r.tablename
        );
    END LOOP;
END $$;

-- ============================================================
-- 5. USUARIO
-- ============================================================

CREATE POLICY usuario_select
ON public."Usuario"
FOR SELECT TO authenticated
USING (
    id_usuario = (SELECT public.meu_id())
    OR EXISTS (
        SELECT 1
        FROM public."Grupo" g
        WHERE g.id_professor = "Usuario".id_usuario
          AND public.aluno_do_grupo(g.id_grupo)
    )
    OR EXISTS (
        SELECT 1
        FROM public."Grupo_Aluno" ga
        WHERE ga.id_aluno = "Usuario".id_usuario
          AND public.participa_grupo(ga.id_grupo)
    )
);

CREATE POLICY usuario_insert
ON public."Usuario"
FOR INSERT TO authenticated
WITH CHECK (
    auth_user_id = (SELECT auth.uid())
    AND tipo_usuario IN ('professor', 'aluno')
    AND COALESCE(status_conta, 'ativo') = 'ativo'
);

CREATE POLICY usuario_update
ON public."Usuario"
FOR UPDATE TO authenticated
USING (id_usuario = (SELECT public.meu_id()))
WITH CHECK (id_usuario = (SELECT public.meu_id()));

-- ============================================================
-- 6. GRUPO
-- ============================================================

CREATE POLICY grupo_select
ON public."Grupo"
FOR SELECT TO authenticated
USING (public.participa_grupo(id_grupo));

CREATE POLICY grupo_insert
ON public."Grupo"
FOR INSERT TO authenticated
WITH CHECK (
    public.sou_professor()
    AND id_professor = (SELECT public.meu_id())
);

CREATE POLICY grupo_update
ON public."Grupo"
FOR UPDATE TO authenticated
USING (public.professor_do_grupo(id_grupo))
WITH CHECK (
    public.professor_do_grupo(id_grupo)
    AND id_professor = (SELECT public.meu_id())
);

CREATE POLICY grupo_delete
ON public."Grupo"
FOR DELETE TO authenticated
USING (public.professor_do_grupo(id_grupo));

-- ============================================================
-- 7. GRUPO_ALUNO
-- ============================================================

CREATE POLICY grupo_aluno_select
ON public."Grupo_Aluno"
FOR SELECT TO authenticated
USING (
    public.participa_grupo(id_grupo)
    OR id_aluno = (SELECT public.meu_id())
);

CREATE POLICY grupo_aluno_insert
ON public."Grupo_Aluno"
FOR INSERT TO authenticated
WITH CHECK (
    public.professor_do_grupo(id_grupo)
    AND EXISTS (
        SELECT 1 FROM public."Usuario" u
        WHERE u.id_usuario = id_aluno
          AND u.tipo_usuario = 'aluno'
    )
);

CREATE POLICY grupo_aluno_update
ON public."Grupo_Aluno"
FOR UPDATE TO authenticated
USING (public.professor_do_grupo(id_grupo))
WITH CHECK (public.professor_do_grupo(id_grupo));

CREATE POLICY grupo_aluno_delete
ON public."Grupo_Aluno"
FOR DELETE TO authenticated
USING (
    public.professor_do_grupo(id_grupo)
    OR id_aluno = (SELECT public.meu_id())
);

-- ============================================================
-- 8. AULA
-- ============================================================

CREATE POLICY aula_select
ON public."Aula"
FOR SELECT TO authenticated
USING (public.participa_grupo(id_grupo));

CREATE POLICY aula_insert
ON public."Aula"
FOR INSERT TO authenticated
WITH CHECK (
    public.professor_do_grupo(id_grupo)
    AND limite_alunos BETWEEN 1 AND 6
    AND (
        data_hora_fim IS NULL
        OR data_hora_fim > data_hora_inicio
    )
);

CREATE POLICY aula_update
ON public."Aula"
FOR UPDATE TO authenticated
USING (public.professor_do_grupo(id_grupo))
WITH CHECK (
    public.professor_do_grupo(id_grupo)
    AND limite_alunos BETWEEN 1 AND 6
    AND (
        data_hora_fim IS NULL
        OR data_hora_fim > data_hora_inicio
    )
);

CREATE POLICY aula_delete
ON public."Aula"
FOR DELETE TO authenticated
USING (public.professor_do_grupo(id_grupo));

-- ============================================================
-- 9. PRESENCA
-- ============================================================

CREATE POLICY presenca_select
ON public."Presenca"
FOR SELECT TO authenticated
USING (
    id_aluno = (SELECT public.meu_id())
    OR public.professor_da_aula(id_aula)
);

CREATE POLICY presenca_insert
ON public."Presenca"
FOR INSERT TO authenticated
WITH CHECK (
    public.aluno_elegivel_aula(id_aula, id_aluno)
    AND (
        (
            id_aluno = (SELECT public.meu_id())
            AND public.sou_aluno()
            AND data_registro_professor IS NULL
        )
        OR public.professor_da_aula(id_aula)
    )
);

CREATE POLICY presenca_update
ON public."Presenca"
FOR UPDATE TO authenticated
USING (
    (
        id_aluno = (SELECT public.meu_id())
        AND public.aluno_da_aula(id_aula)
    )
    OR public.professor_da_aula(id_aula)
)
WITH CHECK (
    public.aluno_elegivel_aula(id_aula, id_aluno)
    AND (
        id_aluno = (SELECT public.meu_id())
        OR public.professor_da_aula(id_aula)
    )
);

CREATE POLICY presenca_delete
ON public."Presenca"
FOR DELETE TO authenticated
USING (public.professor_da_aula(id_aula));

-- ============================================================
-- 10. CONVITE_GRUPO
-- Códigos são privados ao professor.
-- ============================================================

CREATE POLICY convite_select
ON public."Convite_Grupo"
FOR SELECT TO authenticated
USING (public.professor_do_grupo(id_grupo));

CREATE POLICY convite_insert
ON public."Convite_Grupo"
FOR INSERT TO authenticated
WITH CHECK (
    public.professor_do_grupo(id_grupo)
    AND data_expiracao > data_criacao
);

CREATE POLICY convite_update
ON public."Convite_Grupo"
FOR UPDATE TO authenticated
USING (public.professor_do_grupo(id_grupo))
WITH CHECK (public.professor_do_grupo(id_grupo));

CREATE POLICY convite_delete
ON public."Convite_Grupo"
FOR DELETE TO authenticated
USING (public.professor_do_grupo(id_grupo));

-- ============================================================
-- 11. SOLICITACAO_ENTRADA
-- ============================================================

CREATE POLICY solicitacao_select
ON public."Solicitacao_Entrada"
FOR SELECT TO authenticated
USING (
    id_aluno = (SELECT public.meu_id())
    OR public.professor_do_grupo(id_grupo)
);

CREATE POLICY solicitacao_insert
ON public."Solicitacao_Entrada"
FOR INSERT TO authenticated
WITH CHECK (
    public.sou_aluno()
    AND id_aluno = (SELECT public.meu_id())
    AND status = 'pendente'
);

CREATE POLICY solicitacao_update
ON public."Solicitacao_Entrada"
FOR UPDATE TO authenticated
USING (
    public.professor_do_grupo(id_grupo)
    OR id_aluno = (SELECT public.meu_id())
)
WITH CHECK (
    public.professor_do_grupo(id_grupo)
    OR id_aluno = (SELECT public.meu_id())
);

CREATE POLICY solicitacao_delete
ON public."Solicitacao_Entrada"
FOR DELETE TO authenticated
USING (
    public.professor_do_grupo(id_grupo)
    OR id_aluno = (SELECT public.meu_id())
);

-- ============================================================
-- 12. PARTIDA
-- Leitura aos membros; gravação via backend confiável.
-- ============================================================

CREATE POLICY partida_select
ON public."Partida"
FOR SELECT TO authenticated
USING (public.participa_grupo(id_grupo));

-- INSERT/UPDATE/DELETE:
-- Sem políticas para authenticated.
-- Criar/confirmar/contestar/validar partidas via RPC segura
-- ou backend com service_role, com validação de identidade.
-- Impede manipulação direta do ranking e dos resultados.

-- ============================================================
-- 13. PARTIDA_SET
-- ============================================================

CREATE POLICY partida_set_select
ON public."Partida_Set"
FOR SELECT TO authenticated
USING (public.participa_partida(id_partida));

-- Escrita exclusivamente via operação segura de partidas.

-- ============================================================
-- 14. FUNDAMENTO
-- ============================================================

CREATE POLICY fundamento_select
ON public."Fundamento"
FOR SELECT TO authenticated
USING (TRUE);

-- Cadastro/edição do catálogo por administrador/backend.

-- ============================================================
-- 15. AVALIACAO_FUNDAMENTO
-- ============================================================

CREATE POLICY avaliacao_select
ON public."Avaliacao_Fundamento"
FOR SELECT TO authenticated
USING (
    public.sou_aluno_grupo(id_grupo_aluno)
    OR public.professor_do_aluno_grupo(id_grupo_aluno)
);

CREATE POLICY avaliacao_insert
ON public."Avaliacao_Fundamento"
FOR INSERT TO authenticated
WITH CHECK (
    id_professor = (SELECT public.meu_id())
    AND public.professor_do_aluno_grupo(id_grupo_aluno)
);

CREATE POLICY avaliacao_update
ON public."Avaliacao_Fundamento"
FOR UPDATE TO authenticated
USING (
    id_professor = (SELECT public.meu_id())
    AND public.professor_do_aluno_grupo(id_grupo_aluno)
)
WITH CHECK (
    id_professor = (SELECT public.meu_id())
    AND public.professor_do_aluno_grupo(id_grupo_aluno)
);

CREATE POLICY avaliacao_delete
ON public."Avaliacao_Fundamento"
FOR DELETE TO authenticated
USING (
    id_professor = (SELECT public.meu_id())
    AND public.professor_do_aluno_grupo(id_grupo_aluno)
);

-- ============================================================
-- 16. ANOTACAO_AULA
-- Anotações privadas do aluno.
-- ============================================================

CREATE POLICY anotacao_select
ON public."Anotacao_Aula"
FOR SELECT TO authenticated
USING (id_aluno = (SELECT public.meu_id()));

CREATE POLICY anotacao_insert
ON public."Anotacao_Aula"
FOR INSERT TO authenticated
WITH CHECK (
    id_aluno = (SELECT public.meu_id())
    AND public.aluno_da_aula(id_aula)
);

CREATE POLICY anotacao_update
ON public."Anotacao_Aula"
FOR UPDATE TO authenticated
USING (id_aluno = (SELECT public.meu_id()))
WITH CHECK (
    id_aluno = (SELECT public.meu_id())
    AND public.aluno_da_aula(id_aula)
);

CREATE POLICY anotacao_delete
ON public."Anotacao_Aula"
FOR DELETE TO authenticated
USING (id_aluno = (SELECT public.meu_id()));

-- ============================================================
-- 17. ATIVIDADE
-- ============================================================

CREATE POLICY atividade_select
ON public."Atividade"
FOR SELECT TO authenticated
USING (public.participa_aula(id_aula));

CREATE POLICY atividade_insert
ON public."Atividade"
FOR INSERT TO authenticated
WITH CHECK (public.professor_da_aula(id_aula));

CREATE POLICY atividade_update
ON public."Atividade"
FOR UPDATE TO authenticated
USING (public.professor_da_aula(id_aula))
WITH CHECK (public.professor_da_aula(id_aula));

CREATE POLICY atividade_delete
ON public."Atividade"
FOR DELETE TO authenticated
USING (public.professor_da_aula(id_aula));

-- ============================================================
-- 18. ENTREGA_ATIVIDADE
-- ============================================================

CREATE POLICY entrega_select
ON public."Entrega_Atividade"
FOR SELECT TO authenticated
USING (
    id_aluno = (SELECT public.meu_id())
    OR public.professor_da_atividade(id_atividade)
);

CREATE POLICY entrega_insert
ON public."Entrega_Atividade"
FOR INSERT TO authenticated
WITH CHECK (
    id_aluno = (SELECT public.meu_id())
    AND public.aluno_da_atividade(id_atividade)
    AND feedback_professor IS NULL
);

CREATE POLICY entrega_update
ON public."Entrega_Atividade"
FOR UPDATE TO authenticated
USING (
    (
        id_aluno = (SELECT public.meu_id())
        AND public.aluno_da_atividade(id_atividade)
    )
    OR public.professor_da_atividade(id_atividade)
)
WITH CHECK (
    (
        id_aluno = (SELECT public.meu_id())
        AND public.aluno_da_atividade(id_atividade)
    )
    OR public.professor_da_atividade(id_atividade)
);

CREATE POLICY entrega_delete
ON public."Entrega_Atividade"
FOR DELETE TO authenticated
USING (
    id_aluno = (SELECT public.meu_id())
    OR public.professor_da_atividade(id_atividade)
);

-- ============================================================
-- 19. COMENTARIO_AULA
-- ============================================================

CREATE POLICY comentario_select
ON public."Comentario_Aula"
FOR SELECT TO authenticated
USING (public.participa_aula(id_aula));

CREATE POLICY comentario_insert
ON public."Comentario_Aula"
FOR INSERT TO authenticated
WITH CHECK (
    id_professor = (SELECT public.meu_id())
    AND public.professor_da_aula(id_aula)
);

CREATE POLICY comentario_update
ON public."Comentario_Aula"
FOR UPDATE TO authenticated
USING (
    id_professor = (SELECT public.meu_id())
    AND public.professor_da_aula(id_aula)
)
WITH CHECK (
    id_professor = (SELECT public.meu_id())
    AND public.professor_da_aula(id_aula)
);

CREATE POLICY comentario_delete
ON public."Comentario_Aula"
FOR DELETE TO authenticated
USING (
    id_professor = (SELECT public.meu_id())
    AND public.professor_da_aula(id_aula)
);

-- ============================================================
-- 20. DESAFIO
-- ============================================================

CREATE POLICY desafio_select
ON public."Desafio"
FOR SELECT TO authenticated
USING (public.participa_grupo(id_grupo));

CREATE POLICY desafio_insert
ON public."Desafio"
FOR INSERT TO authenticated
WITH CHECK (
    public.sou_aluno()
    AND id_aluno_desafiante = (SELECT public.meu_id())
    AND id_aluno_desafiante <> id_aluno_desafiado
    AND public.aluno_elegivel_grupo(
        id_grupo, id_aluno_desafiante
    )
    AND public.aluno_elegivel_grupo(
        id_grupo, id_aluno_desafiado
    )
    AND status = 'pendente'
    AND id_partida IS NULL
);

-- Aceitar/recusar desafios via RPC segura.
-- Evita que o desafiante aceite o próprio desafio
-- ou altere indevidamente os participantes.

-- ============================================================
-- 21. RANKING_GRUPO
-- ============================================================

CREATE POLICY ranking_select
ON public."Ranking_Grupo"
FOR SELECT TO authenticated
USING (public.participa_grupo(id_grupo));

-- Ranking somente leitura para usuários comuns.
-- Pontos, vitórias e derrotas devem ser atualizados
-- por backend confiável após confirmação da partida.

-- ============================================================
-- 22. PROTEÇÃO DE COLUNAS E PERMISSÕES
-- ============================================================

-- Bloqueia acesso direto às funções auxiliares para anon.
REVOKE ALL ON FUNCTION public.meu_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.meu_tipo() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sou_professor() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sou_aluno() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.professor_do_grupo(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.aluno_do_grupo(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.participa_grupo(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.participa_aula(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.professor_da_aula(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.aluno_da_aula(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.professor_do_aluno_grupo(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sou_aluno_grupo(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.participa_partida(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.professor_da_partida(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.aluno_da_atividade(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.professor_da_atividade(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.aluno_elegivel_grupo(INTEGER, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.aluno_elegivel_aula(INTEGER, INTEGER) FROM PUBLIC;

-- Concede execução somente aos usuários autenticados.
GRANT EXECUTE ON FUNCTION public.meu_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.meu_tipo() TO authenticated;
GRANT EXECUTE ON FUNCTION public.sou_professor() TO authenticated;
GRANT EXECUTE ON FUNCTION public.sou_aluno() TO authenticated;
GRANT EXECUTE ON FUNCTION public.professor_do_grupo(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.aluno_do_grupo(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.participa_grupo(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.participa_aula(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.professor_da_aula(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.aluno_da_aula(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.professor_do_aluno_grupo(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sou_aluno_grupo(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.participa_partida(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.professor_da_partida(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.aluno_da_atividade(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.professor_da_atividade(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.aluno_elegivel_grupo(INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.aluno_elegivel_aula(INTEGER, INTEGER) TO authenticated;

-- Impede o uso direto das tabelas por usuários anônimos.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;

-- Remove permissões genéricas previamente concedidas.
-- A partir daqui, cada tabela recebe permissões específicas.
REVOKE ALL ON
    public."Usuario",
    public."Grupo",
    public."Grupo_Aluno",
    public."Aula",
    public."Presenca",
    public."Convite_Grupo",
    public."Solicitacao_Entrada",
    public."Partida",
    public."Partida_Set",
    public."Fundamento",
    public."Avaliacao_Fundamento",
    public."Anotacao_Aula",
    public."Atividade",
    public."Entrega_Atividade",
    public."Comentario_Aula",
    public."Desafio",
    public."Ranking_Grupo"
FROM authenticated;

-- Permissões de leitura.
GRANT SELECT ON
    public."Grupo",
    public."Grupo_Aluno",
    public."Aula",
    public."Presenca",
    public."Convite_Grupo",
    public."Solicitacao_Entrada",
    public."Partida",
    public."Partida_Set",
    public."Fundamento",
    public."Avaliacao_Fundamento",
    public."Anotacao_Aula",
    public."Atividade",
    public."Entrega_Atividade",
    public."Comentario_Aula",
    public."Desafio",
    public."Ranking_Grupo"
TO authenticated;

-- Usuario: nunca expor senha_hash ou auth_user_id
-- pela API de leitura.
GRANT SELECT (
    id_usuario, nome, email, telefone,
    tipo_usuario, status_conta
)
ON public."Usuario" TO authenticated;

-- Cadastro de usuário.
GRANT INSERT (
    nome, email, telefone, tipo_usuario,
    status_conta, auth_user_id, senha_hash
)
ON public."Usuario" TO authenticated;

-- Edição somente de dados básicos.
GRANT UPDATE (nome, telefone)
ON public."Usuario" TO authenticated;

-- Grupos.
GRANT INSERT, UPDATE, DELETE
ON public."Grupo" TO authenticated;

-- Matrículas.
GRANT INSERT, UPDATE, DELETE
ON public."Grupo_Aluno" TO authenticated;

-- Aulas.
GRANT INSERT, UPDATE, DELETE
ON public."Aula" TO authenticated;

-- Presença: aluno não pode editar campos reservados.
-- Para distinguir edição de aluno/professor, utilizar RPC.
GRANT INSERT (
    id_aula, id_aluno, status,
    data_confirmacao, motivo_cancelamento
)
ON public."Presenca" TO authenticated;

GRANT UPDATE (
    status, data_confirmacao, motivo_cancelamento
)
ON public."Presenca" TO authenticated;

GRANT DELETE ON public."Presenca" TO authenticated;

-- Convites.
GRANT INSERT, UPDATE, DELETE
ON public."Convite_Grupo" TO authenticated;

-- Solicitações.
GRANT INSERT, UPDATE, DELETE
ON public."Solicitacao_Entrada" TO authenticated;

-- Avaliações.
GRANT INSERT, UPDATE, DELETE
ON public."Avaliacao_Fundamento" TO authenticated;

-- Anotações.
GRANT INSERT, UPDATE, DELETE
ON public."Anotacao_Aula" TO authenticated;

-- Atividades.
GRANT INSERT, UPDATE, DELETE
ON public."Atividade" TO authenticated;

-- Entregas: feedback não pode ser editado diretamente
-- pelo aluno; professor usa RPC para registrar feedback.
GRANT INSERT (
    id_atividade, id_aluno, arquivo_url,
    resposta_texto, data_entrega, status
)
ON public."Entrega_Atividade" TO authenticated;

GRANT UPDATE (
    arquivo_url, resposta_texto, data_entrega
)
ON public."Entrega_Atividade" TO authenticated;

GRANT DELETE
ON public."Entrega_Atividade" TO authenticated;

-- Comentários.
GRANT INSERT, UPDATE, DELETE
ON public."Comentario_Aula" TO authenticated;

-- Desafios: somente criação direta.
GRANT INSERT (
    id_aluno_desafiante,
    id_aluno_desafiado,
    id_grupo,
    data_desafio,
    status
)
ON public."Desafio" TO authenticated;

-- Sem permissão de escrita direta em:
-- Partida, Partida_Set, Fundamento e Ranking_Grupo.

-- ============================================================
-- 23. PERMISSÕES DE SEQUÊNCIAS IDENTITY
-- ============================================================

GRANT USAGE ON ALL SEQUENCES IN SCHEMA public
TO authenticated;

COMMIT;

-- ============================================================
-- 23. FUNÇÃO PARA E TRIGGER PARA O LIMITE DE AULAS
-- ============================================================


CREATE OR REPLACE FUNCTION public.validar_limite_aula()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
    v_limite INTEGER;
    v_confirmados INTEGER;
BEGIN
    -- Apenas presenças confirmadas ocupam vagas
    IF NEW.status <> 'confirmado' THEN
        RETURN NEW;
    END IF;

    -- Bloqueia confirmações simultâneas na mesma aula
    SELECT limite_alunos
    INTO v_limite
    FROM public."Aula"
    WHERE id_aula = NEW.id_aula
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Aula não encontrada';
    END IF;

    -- Conta quantos alunos já confirmaram
    SELECT COUNT(*)
    INTO v_confirmados
    FROM public."Presenca"
    WHERE id_aula = NEW.id_aula
      AND status = 'confirmado'
      AND id_presenca IS DISTINCT FROM
          CASE
              WHEN TG_OP = 'UPDATE'
              THEN NEW.id_presenca
              ELSE NULL
          END;

    -- Compara com o limite cadastrado na aula
    IF v_confirmados >= v_limite THEN
        RAISE EXCEPTION
            'Aula lotada! Limite de % alunos atingido.',
            v_limite;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_limite_aula
ON public."Presenca";

CREATE TRIGGER trg_validar_limite_aula
BEFORE INSERT OR UPDATE
ON public."Presenca"
FOR EACH ROW
EXECUTE FUNCTION public.validar_limite_aula();

-- COMPLEMENTO AO RLS ORIGINAL - 15/11/2026
-- APLICAR APOS o SQL original (1099 linhas), em ambiente de homologacao.
-- Nao recria tabelas e nao substitui o arquivo original.
-- Pressupoe colunas e status conforme o SQL e a documentacao fornecidos.
-- Nao inclui regras de Storage, cron nem regras oficiais de pontuacao de tenis.
-- IMPORTANTE: confirme restricoes NOT NULL e CHECK existentes antes de executar.
BEGIN;

-- 1. VINCULACAO AUTH E PERFIL AUTOMATICO
-- Cadastro sempre como aluno; professor somente via operacao administrativa.
ALTER TABLE public."Usuario" ALTER COLUMN senha_hash DROP NOT NULL;
CREATE OR REPLACE FUNCTION public.criar_perfil_usuario()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NEW.email IS NULL THEN RAISE EXCEPTION 'Email obrigatorio'; END IF;
  INSERT INTO public."Usuario"(auth_user_id,nome,email,telefone,tipo_usuario,status_conta)
  VALUES (NEW.id,
          LEFT(COALESCE(NULLIF(BTRIM(NEW.raw_user_meta_data->>'nome'),''),'Novo usuario'),150),
          NEW.email, LEFT(COALESCE(NEW.raw_user_meta_data->>'telefone',''),30),
          'aluno','ativo');
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.criar_perfil_usuario();

-- 2. FUNCOES AUXILIARES NECESSARIAS PARA AS RPCs DOCUMENTADAS
CREATE OR REPLACE FUNCTION public.grupo_da_aula(p_aula integer)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT id_grupo FROM public."Aula" WHERE id_aula=p_aula
$$;
CREATE OR REPLACE FUNCTION public.grupo_da_atividade(p_atividade integer)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT a.id_grupo FROM public."Atividade" t
  JOIN public."Aula" a ON a.id_aula=t.id_aula WHERE t.id_atividade=p_atividade
$$;
CREATE OR REPLACE FUNCTION public.matriculado(p_grupo integer,p_aluno integer)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.aluno_elegivel_grupo(p_grupo,p_aluno)
$$;
CREATE OR REPLACE FUNCTION public.grupo_da_matricula(p_matricula integer)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT id_grupo FROM public."Grupo_Aluno" WHERE id_grupo_aluno=p_matricula
$$;
CREATE OR REPLACE FUNCTION public.aluno_da_matricula(p_matricula integer)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT id_aluno FROM public."Grupo_Aluno" WHERE id_grupo_aluno=p_matricula
$$;
CREATE OR REPLACE FUNCTION public.grupo_da_partida(p_partida integer)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT id_grupo FROM public."Partida" WHERE id_partida=p_partida
$$;

-- 3. INTEGRIDADE DE MATRICULAS/PRESENCAS/RANKING (verificar duplicatas preexistentes)
CREATE UNIQUE INDEX IF NOT EXISTS presenca_aula_aluno_uidx ON public."Presenca"(id_aula,id_aluno);
CREATE UNIQUE INDEX IF NOT EXISTS matricula_grupo_aluno_uidx ON public."Grupo_Aluno"(id_grupo,id_aluno);
CREATE UNIQUE INDEX IF NOT EXISTS ranking_grupo_aluno_uidx ON public."Ranking_Grupo"(id_grupo,id_aluno);
CREATE UNIQUE INDEX IF NOT EXISTS partida_numero_set_uidx ON public."Partida_Set"(id_partida,numero_set);

-- 4. SUBSTITUIR TRIGGER DE PRESENCA ORIGINAL POR VERSAO COM VALIDACAO DE MATRICULA
-- Contagem de vagas apenas ao entrar no estado confirmado; updates de confirmados nao consomem nova vaga.
CREATE OR REPLACE FUNCTION public.validar_limite_aula()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_limite integer; v_grupo integer; v_total integer;
BEGIN
  IF TG_OP='UPDATE' AND (NEW.id_aula IS DISTINCT FROM OLD.id_aula
      OR NEW.id_aluno IS DISTINCT FROM OLD.id_aluno) THEN
    RAISE EXCEPTION 'Nao e permitido transferir registro de presenca';
  END IF;
  SELECT limite_alunos,id_grupo INTO v_limite,v_grupo
  FROM public."Aula" WHERE id_aula=NEW.id_aula FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Aula inexistente'; END IF;
  IF NOT public.matriculado(v_grupo,NEW.id_aluno) THEN
    RAISE EXCEPTION 'Aluno sem matricula ativa';
  END IF;
  -- Somente uma nova confirmacao ocupa vaga adicional.
  -- Atualizar um registro ja confirmado nao deve falhar quando a aula esta cheia.
IF NEW.status = 'confirmado' THEN
    IF TG_OP = 'INSERT' THEN
        NULL;
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.status = 'confirmado' THEN
            RETURN NEW;
        END IF;
    END IF;

    SELECT COUNT(*) INTO v_total
    FROM public."Presenca"
    WHERE id_aula = NEW.id_aula
      AND status = 'confirmado';

    IF v_total >= v_limite THEN
        RAISE EXCEPTION 'Aula lotada (limite: %)', v_limite;
    END IF;
END IF;

  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_validar_limite_aula ON public."Presenca";
CREATE TRIGGER trg_validar_limite_aula BEFORE INSERT OR UPDATE ON public."Presenca"
FOR EACH ROW EXECUTE FUNCTION public.validar_limite_aula();

-- Impede diminuir o limite para menos que as vagas ocupadas.
CREATE OR REPLACE FUNCTION public.validar_alteracao_limite()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_total integer;
BEGIN
  IF NEW.limite_alunos NOT BETWEEN 1 AND 6 THEN
    RAISE EXCEPTION 'Limite deve estar entre 1 e 6';
  END IF;
  IF NEW.id_grupo IS DISTINCT FROM OLD.id_grupo THEN
    RAISE EXCEPTION 'Nao e permitido transferir aula entre grupos';
  END IF;
  IF NEW.limite_alunos<OLD.limite_alunos THEN
    SELECT count(*) INTO v_total FROM public."Presenca"
    WHERE id_aula=NEW.id_aula AND status='confirmado';
    IF v_total>NEW.limite_alunos THEN
      RAISE EXCEPTION 'Limite inferior ao numero de confirmados';
    END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_validar_alteracao_limite ON public."Aula";
CREATE TRIGGER trg_validar_alteracao_limite BEFORE UPDATE ON public."Aula"
FOR EACH ROW EXECUTE FUNCTION public.validar_alteracao_limite();

-- 5. RPCs DOCUMENTADAS (13 FUNCOES) E FUNCOES ADMINISTRATIVAS (2)
-- 7. RPC: ENTRAR COM CODIGO DE CONVITE
CREATE OR REPLACE FUNCTION public.entrar_grupo_por_codigo(p_codigo text) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_grupo integer; v_aluno integer:=public.meu_id();
BEGIN
 IF NOT public.sou_aluno() THEN RAISE EXCEPTION 'Somente alunos'; END IF;
 SELECT id_grupo INTO v_grupo FROM public."Convite_Grupo" WHERE codigo=p_codigo AND status='ativo' AND data_expiracao>now() FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Convite invalido ou expirado'; END IF;
 INSERT INTO public."Grupo_Aluno"(id_grupo,id_aluno,nivel,data_entrada,status)
 VALUES(v_grupo,v_aluno,NULL,now(),'ativo')
 ON CONFLICT (id_grupo,id_aluno) DO UPDATE SET status='ativo',data_entrada=now();
 RETURN v_grupo;
END $$;

-- 8. RPC: SAIR DO GRUPO
CREATE OR REPLACE FUNCTION public.sair_grupo(p_grupo integer) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT public.sou_aluno() THEN RAISE EXCEPTION 'Somente alunos'; END IF;
 UPDATE public."Grupo_Aluno" SET status='inativo' WHERE id_grupo=p_grupo AND id_aluno=public.meu_id() AND status='ativo';
 IF NOT FOUND THEN RAISE EXCEPTION 'Matricula ativa nao encontrada'; END IF;
END $$;

-- 9. RPC: CONFIRMAR/CANCELAR PRESENCA (status permitidos)
CREATE OR REPLACE FUNCTION public.responder_presenca(p_aula integer,p_confirmar boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_grupo integer:=public.grupo_da_aula(p_aula);
BEGIN
 IF NOT public.sou_aluno() OR NOT public.aluno_do_grupo(v_grupo) THEN RAISE EXCEPTION 'Sem permissao'; END IF;
 INSERT INTO public."Presenca"(id_aula,id_aluno,status,data_confirmacao)
 VALUES(p_aula,public.meu_id(),CASE WHEN p_confirmar THEN 'confirmado' ELSE 'cancelado' END,now())
 ON CONFLICT (id_aula,id_aluno) DO UPDATE SET status=EXCLUDED.status,data_confirmacao=EXCLUDED.data_confirmacao;
END $$;

-- 10. RPC: PROFESSOR REGISTRA PRESENCA
CREATE OR REPLACE FUNCTION public.registrar_presenca_professor(p_aula integer,p_aluno integer,p_status text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT public.professor_do_grupo(public.grupo_da_aula(p_aula)) THEN RAISE EXCEPTION 'Sem permissao'; END IF;
 IF p_status NOT IN ('confirmado','ausente','cancelado') THEN RAISE EXCEPTION 'Status invalido'; END IF;
 INSERT INTO public."Presenca"(id_aula,id_aluno,status,data_registro_professor)
 VALUES(p_aula,p_aluno,p_status,now())
 ON CONFLICT (id_aula,id_aluno) DO UPDATE SET status=EXCLUDED.status,data_registro_professor=now();
END $$;

-- 11. RPC: DESAFIO / RESPOSTA
CREATE OR REPLACE FUNCTION public.criar_desafio(p_grupo integer,p_desafiado integer) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_id integer;
BEGIN
 IF NOT public.sou_aluno() OR p_desafiado=public.meu_id() OR NOT public.matriculado(p_grupo,public.meu_id()) OR NOT public.matriculado(p_grupo,p_desafiado)
 THEN RAISE EXCEPTION 'Desafio nao permitido'; END IF;
 INSERT INTO public."Desafio"(id_aluno_desafiante,id_aluno_desafiado,id_grupo,data_desafio,status)
 VALUES(public.meu_id(),p_desafiado,p_grupo,now(),'pendente') RETURNING id_desafio INTO v_id;
 RETURN v_id;
END $$;
CREATE OR REPLACE FUNCTION public.responder_desafio(p_desafio integer,p_aceitar boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_desafio public."Desafio"%ROWTYPE;
BEGIN
 SELECT * INTO v_desafio FROM public."Desafio" WHERE id_desafio=p_desafio FOR UPDATE;
 IF NOT FOUND OR v_desafio.id_aluno_desafiado IS DISTINCT FROM public.meu_id() OR v_desafio.status<>'pendente'
 OR NOT public.aluno_do_grupo(v_desafio.id_grupo) THEN RAISE EXCEPTION 'Resposta nao permitida'; END IF;
 UPDATE public."Desafio" SET status=CASE WHEN p_aceitar THEN 'aceito' ELSE 'recusado' END,data_resposta=now() WHERE id_desafio=p_desafio;
END $$;

-- 12. RPC: REGISTRAR RESULTADO (sets em JSONB, ex. [{"j1":6,"j2":4},{"j1":6,"j2":3}])
CREATE OR REPLACE FUNCTION public.registrar_resultado(p_grupo integer,p_adversario integer,p_sets jsonb) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_id integer; v_j1 integer:=public.meu_id(); v_item jsonb; v_n integer:=0; v_s1 integer:=0; v_s2 integer:=0; v_g1 integer; v_g2 integer;
BEGIN
 IF NOT public.sou_aluno() OR v_j1=p_adversario OR NOT public.matriculado(p_grupo,v_j1) OR NOT public.matriculado(p_grupo,p_adversario)
 THEN RAISE EXCEPTION 'Jogadores invalidos'; END IF;
 IF jsonb_typeof(p_sets) IS DISTINCT FROM 'array' OR jsonb_array_length(p_sets) NOT BETWEEN 1 AND 5 THEN RAISE EXCEPTION 'Informe entre 1 e 5 sets'; END IF;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_sets) LOOP
  IF jsonb_typeof(v_item->'j1')<>'number' OR jsonb_typeof(v_item->'j2')<>'number' THEN RAISE EXCEPTION 'Games invalidos'; END IF;
  v_g1:=(v_item->>'j1')::integer; v_g2:=(v_item->>'j2')::integer;
  IF v_g1<0 OR v_g2<0 OR v_g1=v_g2 OR v_g1>99 OR v_g2>99 THEN RAISE EXCEPTION 'Placar de set invalido'; END IF;
  v_n:=v_n+1;
  IF v_g1>v_g2 THEN v_s1:=v_s1+1; ELSE v_s2:=v_s2+1; END IF;
 END LOOP;
 IF v_s1=v_s2 THEN RAISE EXCEPTION 'Partida deve ter vencedor'; END IF;
 INSERT INTO public."Partida"(id_grupo,id_jogador1,id_jogador2,id_registrador,id_vencedor,data_partida,data_registro,status,pontuacao_jogador1,pontuacao_jogador2)
 VALUES(p_grupo,v_j1,p_adversario,v_j1,CASE WHEN v_s1>v_s2 THEN v_j1 ELSE p_adversario END,now(),now(),'aguardando_confirmacao',v_s1,v_s2)
 RETURNING id_partida INTO v_id;
 v_n:=0;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_sets) LOOP
  v_n:=v_n+1;
  INSERT INTO public."Partida_Set"(id_partida,numero_set,games_jogador1,games_jogador2)
  VALUES(v_id,v_n,(v_item->>'j1')::integer,(v_item->>'j2')::integer);
 END LOOP;
 RETURN v_id;
END $$;

-- 13. RECONSTRUIR RANKING A PARTIR DAS PARTIDAS CONFIRMADAS
-- Evita contagem duplicada em confirmacoes repetidas e permite corrigir placares.
CREATE OR REPLACE FUNCTION public.recalcular_ranking_grupo(p_grupo integer) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 -- Serializa recalculos simultaneos do mesmo grupo.
 PERFORM pg_catalog.pg_advisory_xact_lock(7391, p_grupo);
 -- Esta funcao NAO e exposta ao cliente; chamada somente por RPCs internas e job administrativo.
 INSERT INTO public."Ranking_Grupo"(id_grupo,id_aluno,pontos,vitorias,derrotas,atualizado_em)
 SELECT p_grupo,ga.id_aluno,0,0,0,now() FROM public."Grupo_Aluno" ga WHERE ga.id_grupo=p_grupo
 ON CONFLICT(id_grupo,id_aluno) DO NOTHING;
 UPDATE public."Ranking_Grupo" r SET
  vitorias=(SELECT COUNT(*) FROM public."Partida" p WHERE p.id_grupo=p_grupo AND p.status='confirmada' AND p.id_vencedor=r.id_aluno),
  derrotas=(SELECT COUNT(*) FROM public."Partida" p WHERE p.id_grupo=p_grupo AND p.status='confirmada' AND (p.id_jogador1=r.id_aluno OR p.id_jogador2=r.id_aluno) AND p.id_vencedor<>r.id_aluno),
  pontos=3*(SELECT COUNT(*) FROM public."Partida" p WHERE p.id_grupo=p_grupo AND p.status='confirmada' AND p.id_vencedor=r.id_aluno),
  atualizado_em=now()
 WHERE r.id_grupo=p_grupo;
END $$;

-- 14. CONFIRMAR OU CONTESTAR PARTIDA
CREATE OR REPLACE FUNCTION public.responder_resultado(
    p_partida INTEGER,
    p_confirmar BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_p public."Partida"%ROWTYPE;
BEGIN
    -- Busca e bloqueia a partida durante a operação
    SELECT *
    INTO v_p
    FROM public."Partida"
    WHERE id_partida = p_partida
    FOR UPDATE;

    -- Verifica se a partida existe
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Partida nao encontrada';
    END IF;

    -- Verifica se a partida aguarda confirmacao
    IF v_p.status <> 'aguardando_confirmacao' THEN
        RAISE EXCEPTION 'Partida nao aguarda confirmacao';
    END IF;

    -- Apenas o adversario de quem registrou pode responder
    IF NOT (
        (v_p.id_registrador = v_p.id_jogador1
         AND public.meu_id() = v_p.id_jogador2)
        OR
        (v_p.id_registrador = v_p.id_jogador2
         AND public.meu_id() = v_p.id_jogador1)
    ) THEN
        RAISE EXCEPTION 'Resposta nao permitida';
    END IF;

    -- Verifica matricula ativa no grupo
    IF NOT public.matriculado(v_p.id_grupo, public.meu_id()) THEN
        RAISE EXCEPTION 'Sem matricula ativa';
    END IF;

    -- Confirma ou contesta o resultado
    UPDATE public."Partida"
    SET
        status = CASE
            WHEN p_confirmar THEN 'confirmada'
            ELSE 'contestada'
        END,
        data_confirmacao = CASE
            WHEN p_confirmar THEN NOW()
            ELSE NULL
        END
    WHERE id_partida = p_partida;

    -- Atualiza ranking apenas se a partida foi confirmada
    IF p_confirmar THEN
        PERFORM public.recalcular_ranking_grupo(v_p.id_grupo);
    END IF;

END;
$$;

CREATE OR REPLACE FUNCTION public.validar_partida_professor(p_partida integer,p_aprovar boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_p public."Partida"%ROWTYPE;
BEGIN
 SELECT * INTO v_p FROM public."Partida" WHERE id_partida=p_partida FOR UPDATE;
 IF NOT FOUND OR NOT public.professor_do_grupo(v_p.id_grupo) OR v_p.status NOT IN ('aguardando_confirmacao','contestada') THEN
  RAISE EXCEPTION 'Validacao nao permitida'; END IF;
 UPDATE public."Partida" SET status=CASE WHEN p_aprovar THEN 'confirmada' ELSE 'rejeitada' END,
  id_validador=public.meu_id(),data_confirmacao=CASE WHEN p_aprovar THEN now() ELSE NULL END WHERE id_partida=p_partida;
 IF p_aprovar THEN PERFORM public.recalcular_ranking_grupo(v_p.id_grupo); END IF;
END $$;

-- 15. FUNCAO DE JOB: somente role administrativa/service_role, nunca authenticated
CREATE OR REPLACE FUNCTION public.confirmar_partidas_vencidas() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_p record; v_count integer:=0;
BEGIN
 FOR v_p IN SELECT id_partida,id_grupo FROM public."Partida"
  WHERE status='aguardando_confirmacao' AND data_registro<=now()-interval '24 hours'
  ORDER BY id_partida FOR UPDATE SKIP LOCKED
 LOOP
  UPDATE public."Partida" SET status='confirmada',data_confirmacao=now() WHERE id_partida=v_p.id_partida;
  PERFORM public.recalcular_ranking_grupo(v_p.id_grupo);
  v_count:=v_count+1;
 END LOOP;
 RETURN v_count;
END $$;

-- 16. RPC: SOLICITACOES E GESTAO DE MATRICULAS
CREATE OR REPLACE FUNCTION public.solicitar_entrada(p_grupo integer) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_id integer;
BEGIN
 IF NOT public.sou_aluno() THEN RAISE EXCEPTION 'Somente alunos'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public."Grupo" WHERE id_grupo=p_grupo AND COALESCE(status,'ativo')='ativo') THEN RAISE EXCEPTION 'Turma indisponivel'; END IF;
 IF public.matriculado(p_grupo,public.meu_id()) THEN RAISE EXCEPTION 'Ja matriculado'; END IF;
 IF EXISTS(SELECT 1 FROM public."Solicitacao_Entrada" WHERE id_grupo=p_grupo AND id_aluno=public.meu_id() AND status='pendente') THEN RAISE EXCEPTION 'Solicitacao ja pendente'; END IF;
 INSERT INTO public."Solicitacao_Entrada"(id_grupo,id_aluno,data_solicitacao,status)
 VALUES(p_grupo,public.meu_id(),now(),'pendente') RETURNING id_solicitacao INTO v_id;
 RETURN v_id;
END $$;
CREATE OR REPLACE FUNCTION public.responder_solicitacao(p_solicitacao integer,p_aprovar boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_s public."Solicitacao_Entrada"%ROWTYPE;
BEGIN
 SELECT * INTO v_s FROM public."Solicitacao_Entrada" WHERE id_solicitacao=p_solicitacao FOR UPDATE;
 IF NOT FOUND OR NOT public.professor_do_grupo(v_s.id_grupo) OR v_s.status<>'pendente' THEN RAISE EXCEPTION 'Resposta nao permitida'; END IF;
 IF p_aprovar THEN
  INSERT INTO public."Grupo_Aluno"(id_grupo,id_aluno,data_entrada,status)
  VALUES(v_s.id_grupo,v_s.id_aluno,now(),'ativo')
  ON CONFLICT(id_grupo,id_aluno) DO UPDATE SET status='ativo',data_entrada=now();
 END IF;
 UPDATE public."Solicitacao_Entrada" SET status=CASE WHEN p_aprovar THEN 'aceita' ELSE 'recusada' END,data_resposta=now()
 WHERE id_solicitacao=p_solicitacao;
END $$;
CREATE OR REPLACE FUNCTION public.remover_aluno_grupo(p_grupo integer,p_aluno integer) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT public.professor_do_grupo(p_grupo) THEN RAISE EXCEPTION 'Sem permissao'; END IF;
 UPDATE public."Grupo_Aluno" SET status='inativo' WHERE id_grupo=p_grupo AND id_aluno=p_aluno AND status='ativo';
 IF NOT FOUND THEN RAISE EXCEPTION 'Matricula nao encontrada'; END IF;
END $$;

-- 17. RPC: PROFESSOR AVALIA ENTREGA (sem liberar UPDATE de feedback ao aluno)
CREATE OR REPLACE FUNCTION public.avaliar_entrega(p_entrega integer,p_feedback text,p_status text DEFAULT 'avaliada') RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_atividade integer;
BEGIN
 SELECT id_atividade INTO v_atividade FROM public."Entrega_Atividade" WHERE id_entrega=p_entrega FOR UPDATE;
 IF NOT FOUND OR NOT public.professor_do_grupo(public.grupo_da_atividade(v_atividade)) THEN RAISE EXCEPTION 'Sem permissao'; END IF;
 IF p_status NOT IN ('avaliada','devolvida') THEN RAISE EXCEPTION 'Status invalido'; END IF;
 UPDATE public."Entrega_Atividade" SET feedback_professor=p_feedback,status=p_status WHERE id_entrega=p_entrega;
END $$;


-- 6. REVOGAR CAMINHOS DIRETOS QUE CONTORNAM RPCs
-- Usuario: impedir cadastro direto e elevacao para professor.
DROP POLICY IF EXISTS usuario_insert ON public."Usuario";
REVOKE ALL ON public."Usuario" FROM authenticated;
GRANT SELECT(id_usuario,nome,email,telefone,tipo_usuario,status_conta) ON public."Usuario" TO authenticated;
GRANT UPDATE(nome,telefone) ON public."Usuario" TO authenticated;
-- Matricula, solicitacao, presenca: somente via RPC.
DROP POLICY IF EXISTS grupo_aluno_insert ON public."Grupo_Aluno";
DROP POLICY IF EXISTS grupo_aluno_update ON public."Grupo_Aluno";
DROP POLICY IF EXISTS grupo_aluno_delete ON public."Grupo_Aluno";
DROP POLICY IF EXISTS solicitacao_insert ON public."Solicitacao_Entrada";
DROP POLICY IF EXISTS solicitacao_update ON public."Solicitacao_Entrada";
DROP POLICY IF EXISTS solicitacao_delete ON public."Solicitacao_Entrada";
DROP POLICY IF EXISTS presenca_insert ON public."Presenca";
DROP POLICY IF EXISTS presenca_update ON public."Presenca";
DROP POLICY IF EXISTS presenca_delete ON public."Presenca";
DROP POLICY IF EXISTS desafio_insert ON public."Desafio";
REVOKE ALL ON public."Grupo_Aluno",public."Solicitacao_Entrada",public."Presenca",public."Desafio" FROM authenticated;
GRANT SELECT ON public."Grupo_Aluno",public."Solicitacao_Entrada",public."Presenca",public."Desafio" TO authenticated;
-- Evitar que o aluno altere o status da entrega ou feedback diretamente.
-- Revoga INSERT por tabela antes de reatribuir somente colunas autorizadas.
REVOKE ALL ON public."Entrega_Atividade" FROM authenticated;
GRANT SELECT ON public."Entrega_Atividade" TO authenticated;
GRANT INSERT(id_atividade,id_aluno,arquivo_url,resposta_texto,data_entrega)
ON public."Entrega_Atividade" TO authenticated;
GRANT UPDATE(arquivo_url,resposta_texto,data_entrega)
ON public."Entrega_Atividade" TO authenticated;

-- 7. RESTRINGIR EXECUCAO DAS FUNCOES NOVAS
-- PostgreSQL concede EXECUTE a PUBLIC por padrao; revogar explicitamente.
DO $$ DECLARE r record; BEGIN
 FOR r IN SELECT p.oid::regprocedure AS assinatura FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname=ANY(ARRAY[
 'criar_perfil_usuario','validar_limite_aula','validar_alteracao_limite',
 'grupo_da_aula','grupo_da_atividade','matriculado','grupo_da_matricula',
 'aluno_da_matricula','grupo_da_partida','entrar_grupo_por_codigo',
 'sair_grupo','responder_presenca','registrar_presenca_professor',
 'criar_desafio','responder_desafio','registrar_resultado',
 'recalcular_ranking_grupo','responder_resultado','validar_partida_professor',
 'confirmar_partidas_vencidas','solicitar_entrada','responder_solicitacao',
 'remover_aluno_grupo','avaliar_entrega'])
 LOOP EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',r.assinatura); END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION
 public.grupo_da_aula(integer),public.grupo_da_atividade(integer),
 public.matriculado(integer,integer),public.grupo_da_matricula(integer),
 public.aluno_da_matricula(integer),public.grupo_da_partida(integer),
 public.entrar_grupo_por_codigo(text),public.sair_grupo(integer),
 public.responder_presenca(integer,boolean),
 public.registrar_presenca_professor(integer,integer,text),
 public.criar_desafio(integer,integer),public.responder_desafio(integer,boolean),
 public.registrar_resultado(integer,integer,jsonb),
 public.responder_resultado(integer,boolean),
 public.validar_partida_professor(integer,boolean),
 public.solicitar_entrada(integer),public.responder_solicitacao(integer,boolean),
 public.remover_aluno_grupo(integer,integer),public.avaliar_entrega(integer,text,text)
 TO authenticated;
GRANT EXECUTE ON FUNCTION public.recalcular_ranking_grupo(integer),
 public.confirmar_partidas_vencidas() TO service_role;
COMMIT;