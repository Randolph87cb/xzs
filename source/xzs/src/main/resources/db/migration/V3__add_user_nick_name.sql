ALTER TABLE "public"."t_user"
  ADD COLUMN "nick_name" varchar(255) COLLATE "pg_catalog"."default";

UPDATE "public"."t_user"
SET "nick_name" = COALESCE(NULLIF(BTRIM("real_name"), ''), "user_name")
WHERE "nick_name" IS NULL;
