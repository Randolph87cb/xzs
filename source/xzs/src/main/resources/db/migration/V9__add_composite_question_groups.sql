CREATE SEQUENCE IF NOT EXISTS public.t_question_group_id_seq
    INCREMENT 1 MINVALUE 1 MAXVALUE 2147483647 START 1 CACHE 1;

CREATE TABLE IF NOT EXISTS public.t_question_group (
    id int4 NOT NULL DEFAULT nextval('public.t_question_group_id_seq'::regclass),
    group_type int4 NOT NULL,
    subject_id int4 NOT NULL,
    grade_level int4,
    difficult int4,
    knowledge_point varchar(255),
    info_text_content_id int4 NOT NULL,
    group_code varchar(255),
    import_batch varchar(255),
    import_source varchar(500),
    import_parent_order int4,
    create_user int4,
    status int4 NOT NULL DEFAULT 1,
    create_time timestamp(6),
    deleted bool NOT NULL DEFAULT false,
    CONSTRAINT t_question_group_pkey PRIMARY KEY (id),
    CONSTRAINT ck_question_group_type CHECK (group_type IN (1, 2))
);

ALTER TABLE public.t_question
    ADD COLUMN IF NOT EXISTS question_group_id int4,
    ADD COLUMN IF NOT EXISTS group_item_order int4;

ALTER TABLE public.t_question
    DROP CONSTRAINT IF EXISTS ck_question_group_assignment;
ALTER TABLE public.t_question
    ADD CONSTRAINT ck_question_group_assignment CHECK (
        (question_group_id IS NULL AND group_item_order IS NULL)
        OR (question_group_id IS NOT NULL AND group_item_order IS NOT NULL AND group_item_order > 0)
    );

CREATE UNIQUE INDEX IF NOT EXISTS uk_question_group_import_parent
    ON public.t_question_group (import_batch, import_source, import_parent_order)
    WHERE deleted = false
      AND import_batch IS NOT NULL
      AND import_source IS NOT NULL
      AND import_parent_order IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_question_group_subject_type_status
    ON public.t_question_group (subject_id, group_type, status, deleted);

CREATE INDEX IF NOT EXISTS idx_question_group_knowledge_status
    ON public.t_question_group (knowledge_point, status, deleted);

CREATE UNIQUE INDEX IF NOT EXISTS uk_question_group_item_order
    ON public.t_question (question_group_id, group_item_order)
    WHERE deleted = false AND question_group_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_question_question_group
    ON public.t_question (question_group_id, status, deleted, group_item_order);
