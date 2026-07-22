CREATE INDEX IF NOT EXISTS "idx_question_list_filter_id_desc"
  ON "public"."t_question" ("deleted", "subject_id", "grade_level", "question_type", "knowledge_point", "id" DESC);

CREATE INDEX IF NOT EXISTS "idx_exam_paper_list_filter_id_desc"
  ON "public"."t_exam_paper" ("deleted", "paper_type", "subject_id", "grade_level", "id" DESC);

CREATE INDEX IF NOT EXISTS "idx_exam_paper_answer_user_subject_id_desc"
  ON "public"."t_exam_paper_answer" ("create_user", "subject_id", "id" DESC);

CREATE INDEX IF NOT EXISTS "idx_exam_paper_answer_subject_class_id_desc"
  ON "public"."t_exam_paper_answer" ("subject_id", "class_id", "id" DESC);

CREATE INDEX IF NOT EXISTS "idx_customer_answer_paper_answer_item_order"
  ON "public"."t_exam_paper_question_customer_answer" ("exam_paper_answer_id", "item_order");

CREATE INDEX IF NOT EXISTS "idx_user_deleted_user_name"
  ON "public"."t_user" ("deleted", "user_name");

CREATE INDEX IF NOT EXISTS "idx_user_deleted_wx_open_id_present"
  ON "public"."t_user" ("deleted", "wx_open_id")
  WHERE "wx_open_id" IS NOT NULL;

CREATE INDEX IF NOT EXISTS "idx_task_customer_answer_user_task"
  ON "public"."t_task_exam_customer_answer" ("create_user", "task_exam_id");

CREATE INDEX IF NOT EXISTS "idx_user_event_log_user_id_desc"
  ON "public"."t_user_event_log" ("user_id", "id" DESC);

CREATE INDEX IF NOT EXISTS "idx_user_event_log_user_name_desc"
  ON "public"."t_user_event_log" ("user_name", "id" DESC);
