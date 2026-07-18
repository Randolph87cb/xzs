CREATE TABLE IF NOT EXISTS "public"."t_teacher_ai_review_config" (
  "id" serial PRIMARY KEY,
  "teacher_user_id" int4 NOT NULL UNIQUE,
  "provider" varchar(32) NOT NULL DEFAULT 'openai_compatible',
  "base_url" varchar(512) NOT NULL,
  "model" varchar(128) NOT NULL,
  "api_key_cipher" text,
  "enabled" bool NOT NULL DEFAULT true,
  "prompt" text,
  "create_time" timestamp(6),
  "modify_time" timestamp(6)
);

CREATE TABLE IF NOT EXISTS "public"."t_question_correction_ai_review_record" (
  "id" serial PRIMARY KEY,
  "correction_id" int4 NOT NULL,
  "teacher_user_id" int4,
  "trigger_type" varchar(32) NOT NULL DEFAULT 'AUTO_SUBMIT',
  "status" varchar(32) NOT NULL,
  "review_result" varchar(32),
  "review_comment" text,
  "confidence" numeric(5, 4),
  "reason" text,
  "raw_content" text,
  "error_message" text,
  "request_time" timestamp(6),
  "finish_time" timestamp(6),
  "create_time" timestamp(6)
);

CREATE INDEX IF NOT EXISTS "idx_teacher_ai_review_config_teacher"
  ON "public"."t_teacher_ai_review_config" ("teacher_user_id");

CREATE INDEX IF NOT EXISTS "idx_question_correction_ai_review_latest"
  ON "public"."t_question_correction_ai_review_record" ("correction_id", "create_time" DESC, "id" DESC);
