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
VALUES
  (1, 25, '[{"knowledgePoint":"GESP1级/运算符与表达式","questionCount":6},{"knowledgePoint":"GESP1级/循环结构","questionCount":5},{"knowledgePoint":"GESP1级/分支结构","questionCount":2},{"knowledgePoint":"GESP1级/计算机基础","questionCount":2},{"knowledgePoint":"GESP1级/变量与数据类型","questionCount":1},{"knowledgePoint":"GESP1级/输入输出","questionCount":1},{"knowledgePoint":"GESP1级/算法基础","questionCount":1},{"knowledgePoint":"GESP1级/字符串","questionCount":1},{"knowledgePoint":"GESP1级/综合","questionCount":1},{"knowledgePoint":"GESP1级/概念判断","questionCount":1},{"knowledgePoint":"GESP1级/函数","questionCount":1},{"knowledgePoint":"GESP1级/结构体与类","questionCount":1},{"knowledgePoint":"GESP1级/数学与进制","questionCount":1},{"knowledgePoint":"GESP1级/数组","questionCount":1}]', now(), now(), false),
  (2, 25, '[{"knowledgePoint":"GESP2级/循环结构","questionCount":6},{"knowledgePoint":"GESP2级/运算符与表达式","questionCount":4},{"knowledgePoint":"GESP2级/算法基础","questionCount":2},{"knowledgePoint":"GESP2级/计算机基础","questionCount":2},{"knowledgePoint":"GESP2级/分支结构","questionCount":1},{"knowledgePoint":"GESP2级/变量与数据类型","questionCount":1},{"knowledgePoint":"GESP2级/概念判断","questionCount":1},{"knowledgePoint":"GESP2级/输入输出","questionCount":1},{"knowledgePoint":"GESP2级/综合","questionCount":1},{"knowledgePoint":"GESP2级/函数","questionCount":1},{"knowledgePoint":"GESP2级/指针与引用","questionCount":1},{"knowledgePoint":"GESP2级/字符串","questionCount":1},{"knowledgePoint":"GESP2级/结构体与类","questionCount":1},{"knowledgePoint":"GESP2级/排序与查找","questionCount":1},{"knowledgePoint":"GESP2级/数组","questionCount":1}]', now(), now(), false),
  (3, 25, '[{"knowledgePoint":"GESP3级/数组与字符数组","questionCount":3},{"knowledgePoint":"GESP3级/位运算","questionCount":3},{"knowledgePoint":"GESP3级/进制转换与进制字面量","questionCount":2},{"knowledgePoint":"GESP3级/字符串处理","questionCount":2},{"knowledgePoint":"GESP3级/原码反码补码与整数表示","questionCount":2},{"knowledgePoint":"GESP3级/控制结构与程序阅读","questionCount":2},{"knowledgePoint":"GESP3级/枚举与基础算法","questionCount":2},{"knowledgePoint":"GESP3级/ASCII/字符编码","questionCount":2},{"knowledgePoint":"GESP3级/运算符、表达式与类型转换","questionCount":2},{"knowledgePoint":"GESP3级/计算机基础常识","questionCount":2},{"knowledgePoint":"GESP3级/C++语法规则与编译模型","questionCount":1},{"knowledgePoint":"GESP3级/函数与标准库","questionCount":1},{"knowledgePoint":"GESP3级/算法描述与流程图","questionCount":1}]', now(), now(), false),
  (4, 25, '[{"knowledgePoint":"GESP4级/数组","questionCount":3},{"knowledgePoint":"GESP4级/排序与查找","questionCount":2},{"knowledgePoint":"GESP4级/函数","questionCount":2},{"knowledgePoint":"GESP4级/运算符与表达式","questionCount":2},{"knowledgePoint":"GESP4级/指针与引用","questionCount":2},{"knowledgePoint":"GESP4级/变量与数据类型","questionCount":2},{"knowledgePoint":"GESP4级/循环结构","questionCount":2},{"knowledgePoint":"GESP4级/字符串","questionCount":1},{"knowledgePoint":"GESP4级/分支结构","questionCount":1},{"knowledgePoint":"GESP4级/结构体与类","questionCount":1},{"knowledgePoint":"GESP4级/计算机基础","questionCount":1},{"knowledgePoint":"GESP4级/概念判断","questionCount":1},{"knowledgePoint":"GESP4级/综合","questionCount":1},{"knowledgePoint":"GESP4级/复杂度","questionCount":1},{"knowledgePoint":"GESP4级/算法基础","questionCount":1},{"knowledgePoint":"GESP4级/递归","questionCount":1},{"knowledgePoint":"GESP4级/输入输出","questionCount":1}]', now(), now(), false),
  (5, 25, '[{"knowledgePoint":"GESP5级/排序与查找","questionCount":4},{"knowledgePoint":"GESP5级/算法基础","questionCount":3},{"knowledgePoint":"GESP5级/递归","questionCount":2},{"knowledgePoint":"GESP5级/数组","questionCount":2},{"knowledgePoint":"GESP5级/数学与进制","questionCount":2},{"knowledgePoint":"GESP5级/循环结构","questionCount":2},{"knowledgePoint":"GESP5级/分支结构","questionCount":1},{"knowledgePoint":"GESP5级/概念判断","questionCount":1},{"knowledgePoint":"GESP5级/函数","questionCount":1},{"knowledgePoint":"GESP5级/复杂度","questionCount":1},{"knowledgePoint":"GESP5级/综合","questionCount":1},{"knowledgePoint":"GESP5级/计算机基础","questionCount":1},{"knowledgePoint":"GESP5级/运算符与表达式","questionCount":1},{"knowledgePoint":"GESP5级/字符串","questionCount":1},{"knowledgePoint":"GESP5级/输入输出","questionCount":1},{"knowledgePoint":"GESP5级/指针与引用","questionCount":1}]', now(), now(), false),
  (6, 25, '[{"knowledgePoint":"GESP6级/算法基础","questionCount":6},{"knowledgePoint":"GESP6级/函数","questionCount":2},{"knowledgePoint":"GESP6级/排序与查找","questionCount":2},{"knowledgePoint":"GESP6级/计算机基础","questionCount":2},{"knowledgePoint":"GESP6级/结构体与类","questionCount":2},{"knowledgePoint":"GESP6级/递归","questionCount":2},{"knowledgePoint":"GESP6级/数组","questionCount":1},{"knowledgePoint":"GESP6级/字符串","questionCount":1},{"knowledgePoint":"GESP6级/概念判断","questionCount":1},{"knowledgePoint":"GESP6级/循环结构","questionCount":1},{"knowledgePoint":"GESP6级/分支结构","questionCount":1},{"knowledgePoint":"GESP6级/输入输出","questionCount":1},{"knowledgePoint":"GESP6级/运算符与表达式","questionCount":1},{"knowledgePoint":"GESP6级/数学与进制","questionCount":1},{"knowledgePoint":"GESP6级/指针与引用","questionCount":1}]', now(), now(), false),
  (7, 25, '[{"knowledgePoint":"GESP7级/算法基础","questionCount":4},{"knowledgePoint":"GESP7级/函数","questionCount":2},{"knowledgePoint":"GESP7级/数组","questionCount":2},{"knowledgePoint":"GESP7级/排序与查找","questionCount":2},{"knowledgePoint":"GESP7级/运算符与表达式","questionCount":2},{"knowledgePoint":"GESP7级/递归","questionCount":2},{"knowledgePoint":"GESP7级/变量与数据类型","questionCount":1},{"knowledgePoint":"GESP7级/循环结构","questionCount":1},{"knowledgePoint":"GESP7级/分支结构","questionCount":1},{"knowledgePoint":"GESP7级/复杂度","questionCount":1},{"knowledgePoint":"GESP7级/计算机基础","questionCount":1},{"knowledgePoint":"GESP7级/结构体与类","questionCount":1},{"knowledgePoint":"GESP7级/指针与引用","questionCount":1},{"knowledgePoint":"GESP7级/综合","questionCount":1},{"knowledgePoint":"GESP7级/概念判断","questionCount":1},{"knowledgePoint":"GESP7级/数学与进制","questionCount":1},{"knowledgePoint":"GESP7级/字符串","questionCount":1}]', now(), now(), false),
  (8, 25, '[{"knowledgePoint":"GESP8级/算法基础","questionCount":3},{"knowledgePoint":"GESP8级/排序与查找","questionCount":2},{"knowledgePoint":"GESP8级/数组","questionCount":2},{"knowledgePoint":"GESP8级/函数","questionCount":2},{"knowledgePoint":"GESP8级/运算符与表达式","questionCount":2},{"knowledgePoint":"GESP8级/数学与进制","questionCount":2},{"knowledgePoint":"GESP8级/综合","questionCount":2},{"knowledgePoint":"GESP8级/概念判断","questionCount":1},{"knowledgePoint":"GESP8级/循环结构","questionCount":1},{"knowledgePoint":"GESP8级/分支结构","questionCount":1},{"knowledgePoint":"GESP8级/计算机基础","questionCount":1},{"knowledgePoint":"GESP8级/变量与数据类型","questionCount":1},{"knowledgePoint":"GESP8级/递归","questionCount":1},{"knowledgePoint":"GESP8级/复杂度","questionCount":1},{"knowledgePoint":"GESP8级/结构体与类","questionCount":1},{"knowledgePoint":"GESP8级/指针与引用","questionCount":1},{"knowledgePoint":"GESP8级/字符串","questionCount":1}]', now(), now(), false)
ON CONFLICT ("subject_id") DO UPDATE SET
  "question_count" = EXCLUDED."question_count",
  "rule_json" = EXCLUDED."rule_json",
  "modify_time" = now(),
  "deleted" = false;
