ALTER TABLE "public"."t_question_correction_ai_review_record"
  ADD COLUMN IF NOT EXISTS "teacher_reason" text,
  ADD COLUMN IF NOT EXISTS "student_feedback" text,
  ADD COLUMN IF NOT EXISTS "missing_points" jsonb;

UPDATE "public"."t_question_correction_ai_review_record"
SET "teacher_reason" = "reason"
WHERE "teacher_reason" IS NULL
  AND "reason" IS NOT NULL;

UPDATE "public"."t_question_correction_ai_review_record"
SET "student_feedback" = "review_comment"
WHERE "student_feedback" IS NULL
  AND "review_comment" IS NOT NULL;
