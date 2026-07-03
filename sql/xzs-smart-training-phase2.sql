ALTER TABLE "public"."t_question"
  ADD COLUMN IF NOT EXISTS "knowledge_point" varchar(255) COLLATE "pg_catalog"."default";

UPDATE "public"."t_question"
SET "knowledge_point" = '综合'
WHERE "knowledge_point" IS NULL OR "knowledge_point" = '';

CREATE SEQUENCE IF NOT EXISTS "public"."t_smart_training_config_id_seq"
  INCREMENT 1
  MINVALUE 1
  MAXVALUE 2147483647
  START 1
  CACHE 1;

CREATE TABLE IF NOT EXISTS "public"."t_smart_training_config" (
  "id" int4 NOT NULL DEFAULT nextval('t_smart_training_config_id_seq'::regclass),
  "subject_id" int4,
  "question_count" int4,
  "rule_json" text COLLATE "pg_catalog"."default",
  "create_time" timestamp(6),
  "modify_time" timestamp(6),
  "deleted" bool
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 't_smart_training_config_pkey'
  ) THEN
    ALTER TABLE "public"."t_smart_training_config"
      ADD CONSTRAINT "t_smart_training_config_pkey" PRIMARY KEY ("id");
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uk_smart_training_config_subject'
  ) THEN
    ALTER TABLE "public"."t_smart_training_config"
      ADD CONSTRAINT "uk_smart_training_config_subject" UNIQUE ("subject_id");
  END IF;
END $$;

ALTER SEQUENCE "public"."t_smart_training_config_id_seq"
  OWNED BY "public"."t_smart_training_config"."id";

INSERT INTO "public"."t_smart_training_config" ("subject_id", "question_count", "rule_json", "create_time", "modify_time", "deleted")
SELECT s."id", 20, '[{"knowledgePoint":"综合","questionCount":20}]', now(), now(), false
FROM "public"."t_subject" s
WHERE s."deleted" = false
  AND EXISTS (
    SELECT 1 FROM "public"."t_question" q
    WHERE q."subject_id" = s."id"
      AND q."deleted" = false
      AND q."status" = 1
      AND q."knowledge_point" = '综合'
  )
ON CONFLICT ("subject_id") DO NOTHING;
