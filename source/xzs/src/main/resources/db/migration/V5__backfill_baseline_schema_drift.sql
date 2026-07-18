CREATE TABLE IF NOT EXISTS "public"."t_class" (
  "id" serial PRIMARY KEY,
  "name" varchar(255) COLLATE "pg_catalog"."default" NOT NULL,
  "grade_level" int4,
  "teacher_id" int4 NOT NULL,
  "status" int4 NOT NULL DEFAULT 1,
  "create_time" timestamp(6),
  "modify_time" timestamp(6),
  "deleted" bool NOT NULL DEFAULT false
);

ALTER TABLE "public"."t_user"
  ADD COLUMN IF NOT EXISTS "class_id" int4;

ALTER TABLE "public"."t_exam_paper_answer"
  ADD COLUMN IF NOT EXISTS "class_id" int4;

ALTER TABLE "public"."t_exam_paper_question_customer_answer"
  ADD COLUMN IF NOT EXISTS "class_id" int4;

ALTER TABLE "public"."t_question_correction_record"
  ADD COLUMN IF NOT EXISTS "class_id" int4;

ALTER TABLE "public"."t_task_exam"
  ADD COLUMN IF NOT EXISTS "class_id" int4;

ALTER TABLE "public"."t_question"
  ADD COLUMN IF NOT EXISTS "question_code" varchar(255) COLLATE "pg_catalog"."default",
  ADD COLUMN IF NOT EXISTS "import_batch" varchar(255) COLLATE "pg_catalog"."default",
  ADD COLUMN IF NOT EXISTS "import_source" varchar(500) COLLATE "pg_catalog"."default",
  ADD COLUMN IF NOT EXISTS "import_question_order" int4;

CREATE INDEX IF NOT EXISTS "idx_class_teacher"
  ON "public"."t_class" ("teacher_id", "deleted");

CREATE INDEX IF NOT EXISTS "idx_class_grade"
  ON "public"."t_class" ("grade_level", "deleted");

CREATE INDEX IF NOT EXISTS "idx_user_class_role"
  ON "public"."t_user" ("class_id", "role", "deleted");

CREATE INDEX IF NOT EXISTS "idx_exam_paper_answer_class"
  ON "public"."t_exam_paper_answer" ("class_id", "create_time");

CREATE INDEX IF NOT EXISTS "idx_customer_answer_class"
  ON "public"."t_exam_paper_question_customer_answer" ("class_id", "create_time");

CREATE INDEX IF NOT EXISTS "idx_question_correction_class_status"
  ON "public"."t_question_correction_record" ("class_id", "review_status", "submit_time");

CREATE INDEX IF NOT EXISTS "idx_task_exam_class"
  ON "public"."t_task_exam" ("class_id", "deleted");

CREATE UNIQUE INDEX IF NOT EXISTS "uk_question_import_source_order"
  ON "public"."t_question" ("import_batch", "import_source", "import_question_order");
