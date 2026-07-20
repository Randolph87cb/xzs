CREATE INDEX IF NOT EXISTS "idx_exam_paper_answer_user_paper_time"
  ON "public"."t_exam_paper_answer" ("create_user", "exam_paper_id", "create_time" DESC);

CREATE INDEX IF NOT EXISTS "idx_customer_answer_user_question_wrong_time"
  ON "public"."t_exam_paper_question_customer_answer" ("create_user", "question_id", "create_time" DESC)
  WHERE do_right = FALSE;

CREATE INDEX IF NOT EXISTS "idx_question_correction_customer_user_latest"
  ON "public"."t_question_correction_record" ("customer_answer_id", "user_id", "id" DESC)
  WHERE deleted = FALSE;
