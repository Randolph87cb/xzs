-- ----------------------------
-- Sequence structure for t_exam_paper_answer_id_seq
-- ----------------------------
DROP SEQUENCE IF EXISTS "public"."t_exam_paper_answer_id_seq";
CREATE SEQUENCE "public"."t_exam_paper_answer_id_seq" 
INCREMENT 1
MINVALUE  1
MAXVALUE 2147483647
START 1
CACHE 1;

-- ----------------------------
-- Sequence structure for t_exam_paper_id_seq
-- ----------------------------
DROP SEQUENCE IF EXISTS "public"."t_exam_paper_id_seq";
CREATE SEQUENCE "public"."t_exam_paper_id_seq" 
INCREMENT 1
MINVALUE  1
MAXVALUE 2147483647
START 1
CACHE 1;

-- ----------------------------
-- Sequence structure for t_exam_paper_question_customer_answer_id_seq
-- ----------------------------
DROP SEQUENCE IF EXISTS "public"."t_exam_paper_question_customer_answer_id_seq";
CREATE SEQUENCE "public"."t_exam_paper_question_customer_answer_id_seq" 
INCREMENT 1
MINVALUE  1
MAXVALUE 2147483647
START 1
CACHE 1;

-- ----------------------------
-- Sequence structure for t_message_id_seq
-- ----------------------------
DROP SEQUENCE IF EXISTS "public"."t_message_id_seq";
CREATE SEQUENCE "public"."t_message_id_seq" 
INCREMENT 1
MINVALUE  1
MAXVALUE 2147483647
START 1
CACHE 1;

-- ----------------------------
-- Sequence structure for t_message_user_id_seq
-- ----------------------------
DROP SEQUENCE IF EXISTS "public"."t_message_user_id_seq";
CREATE SEQUENCE "public"."t_message_user_id_seq" 
INCREMENT 1
MINVALUE  1
MAXVALUE 2147483647
START 1
CACHE 1;

-- ----------------------------
-- Sequence structure for t_question_id_seq
-- ----------------------------
DROP SEQUENCE IF EXISTS "public"."t_question_id_seq";
CREATE SEQUENCE "public"."t_question_id_seq" 
INCREMENT 1
MINVALUE  1
MAXVALUE 2147483647
START 1
CACHE 1;

-- ----------------------------
-- Sequence structure for t_smart_training_config_id_seq
-- ----------------------------
DROP SEQUENCE IF EXISTS "public"."t_smart_training_config_id_seq";
CREATE SEQUENCE "public"."t_smart_training_config_id_seq"
INCREMENT 1
MINVALUE  1
MAXVALUE 2147483647
START 1
CACHE 1;

-- ----------------------------
-- Sequence structure for t_subject_id_seq
-- ----------------------------
DROP SEQUENCE IF EXISTS "public"."t_subject_id_seq";
CREATE SEQUENCE "public"."t_subject_id_seq" 
INCREMENT 1
MINVALUE  1
MAXVALUE 2147483647
START 1
CACHE 1;

-- ----------------------------
-- Sequence structure for t_task_exam_customer_answer_id_seq
-- ----------------------------
DROP SEQUENCE IF EXISTS "public"."t_task_exam_customer_answer_id_seq";
CREATE SEQUENCE "public"."t_task_exam_customer_answer_id_seq" 
INCREMENT 1
MINVALUE  1
MAXVALUE 2147483647
START 1
CACHE 1;

-- ----------------------------
-- Sequence structure for t_task_exam_id_seq
-- ----------------------------
DROP SEQUENCE IF EXISTS "public"."t_task_exam_id_seq";
CREATE SEQUENCE "public"."t_task_exam_id_seq" 
INCREMENT 1
MINVALUE  1
MAXVALUE 2147483647
START 1
CACHE 1;

-- ----------------------------
-- Sequence structure for t_text_content_id_seq
-- ----------------------------
DROP SEQUENCE IF EXISTS "public"."t_text_content_id_seq";
CREATE SEQUENCE "public"."t_text_content_id_seq" 
INCREMENT 1
MINVALUE  1
MAXVALUE 2147483647
START 1
CACHE 1;

-- ----------------------------
-- Sequence structure for t_user_event_log_id_seq
-- ----------------------------
DROP SEQUENCE IF EXISTS "public"."t_user_event_log_id_seq";
CREATE SEQUENCE "public"."t_user_event_log_id_seq" 
INCREMENT 1
MINVALUE  1
MAXVALUE 2147483647
START 1
CACHE 1;

-- ----------------------------
-- Sequence structure for t_user_id_seq
-- ----------------------------
DROP SEQUENCE IF EXISTS "public"."t_user_id_seq";
CREATE SEQUENCE "public"."t_user_id_seq" 
INCREMENT 1
MINVALUE  1
MAXVALUE 2147483647
START 1
CACHE 1;

-- ----------------------------
-- Sequence structure for t_user_token_id_seq
-- ----------------------------
DROP SEQUENCE IF EXISTS "public"."t_user_token_id_seq";
CREATE SEQUENCE "public"."t_user_token_id_seq" 
INCREMENT 1
MINVALUE  1
MAXVALUE 2147483647
START 1
CACHE 1;

-- ----------------------------
-- Table structure for t_exam_paper
-- ----------------------------
DROP TABLE IF EXISTS "public"."t_exam_paper";
CREATE TABLE "public"."t_exam_paper" (
  "id" int4 NOT NULL DEFAULT nextval('t_exam_paper_id_seq'::regclass),
  "name" varchar(255) COLLATE "pg_catalog"."default",
  "subject_id" int4,
  "paper_type" int4,
  "grade_level" int4,
  "score" int4,
  "question_count" int4,
  "suggest_time" int4,
  "limit_start_time" timestamp(6),
  "limit_end_time" timestamp(6),
  "frame_text_content_id" int4,
  "create_user" int4,
  "create_time" timestamp(6),
  "deleted" bool,
  "task_exam_id" int4
)
;

-- ----------------------------
-- Records of t_exam_paper
-- ----------------------------

-- ----------------------------
-- Table structure for t_class
-- ----------------------------
DROP TABLE IF EXISTS "public"."t_class";
CREATE TABLE "public"."t_class" (
  "id" serial PRIMARY KEY,
  "name" varchar(255) COLLATE "pg_catalog"."default" NOT NULL,
  "grade_level" int4,
  "teacher_id" int4 NOT NULL,
  "status" int4 NOT NULL DEFAULT 1,
  "create_time" timestamp(6),
  "modify_time" timestamp(6),
  "deleted" bool NOT NULL DEFAULT false
)
;

-- ----------------------------
-- Records of t_class
-- ----------------------------

CREATE INDEX "idx_class_teacher" ON "public"."t_class" ("teacher_id", "deleted");
CREATE INDEX "idx_class_grade" ON "public"."t_class" ("grade_level", "deleted");

-- ----------------------------
-- Table structure for t_exam_paper_answer
-- ----------------------------
DROP TABLE IF EXISTS "public"."t_exam_paper_answer";
CREATE TABLE "public"."t_exam_paper_answer" (
  "id" int4 NOT NULL DEFAULT nextval('t_exam_paper_answer_id_seq'::regclass),
  "exam_paper_id" int4,
  "paper_name" varchar(255) COLLATE "pg_catalog"."default",
  "paper_type" int4,
  "subject_id" int4,
  "system_score" int4,
  "user_score" int4,
  "paper_score" int4,
  "question_correct" int4,
  "question_count" int4,
  "do_time" int4,
  "status" int4,
  "create_user" int4,
  "create_time" timestamp(6),
  "task_exam_id" int4,
  "class_id" int4
)
;

-- ----------------------------
-- Records of t_exam_paper_answer
-- ----------------------------

-- ----------------------------
-- Table structure for t_exam_paper_question_customer_answer
-- ----------------------------
DROP TABLE IF EXISTS "public"."t_exam_paper_question_customer_answer";
CREATE TABLE "public"."t_exam_paper_question_customer_answer" (
  "id" int4 NOT NULL DEFAULT nextval('t_exam_paper_question_customer_answer_id_seq'::regclass),
  "question_id" int4,
  "exam_paper_id" int4,
  "exam_paper_answer_id" int4,
  "question_type" int4,
  "subject_id" int4,
  "customer_score" int4,
  "question_score" int4,
  "answer" varchar(255) COLLATE "pg_catalog"."default",
  "text_content_id" int4,
  "do_right" bool,
  "create_user" int4,
  "create_time" timestamp(6),
  "item_order" int4,
  "class_id" int4
)
;

-- ----------------------------
-- Records of t_exam_paper_question_customer_answer
-- ----------------------------

-- ----------------------------
-- Table structure for t_message
-- ----------------------------
DROP TABLE IF EXISTS "public"."t_message";
CREATE TABLE "public"."t_message" (
  "id" int4 NOT NULL DEFAULT nextval('t_message_id_seq'::regclass),
  "title" varchar(255) COLLATE "pg_catalog"."default",
  "content" varchar(500) COLLATE "pg_catalog"."default",
  "send_user_id" int4,
  "send_user_name" varchar(255) COLLATE "pg_catalog"."default",
  "send_real_name" varchar(255) COLLATE "pg_catalog"."default",
  "read_count" int4,
  "receive_user_count" int4,
  "create_time" timestamp(6)
)
;

-- ----------------------------
-- Records of t_message
-- ----------------------------

-- ----------------------------
-- Table structure for t_message_user
-- ----------------------------
DROP TABLE IF EXISTS "public"."t_message_user";
CREATE TABLE "public"."t_message_user" (
  "id" int4 NOT NULL DEFAULT nextval('t_message_user_id_seq'::regclass),
  "message_id" int4,
  "receive_user_id" int4,
  "receive_user_name" varchar(255) COLLATE "pg_catalog"."default",
  "receive_real_name" varchar(255) COLLATE "pg_catalog"."default",
  "readed" bool,
  "read_time" timestamp(6),
  "create_time" timestamp(6)
)
;

-- ----------------------------
-- Records of t_message_user
-- ----------------------------

-- ----------------------------
-- Table structure for t_question
-- ----------------------------
DROP TABLE IF EXISTS "public"."t_question";
CREATE TABLE "public"."t_question" (
  "id" int4 NOT NULL DEFAULT nextval('t_question_id_seq'::regclass),
  "question_type" int4,
  "subject_id" int4,
  "score" int4,
  "grade_level" int4,
  "difficult" int4,
  "knowledge_point" varchar(255) COLLATE "pg_catalog"."default",
  "question_code" varchar(255) COLLATE "pg_catalog"."default",
  "import_batch" varchar(255) COLLATE "pg_catalog"."default",
  "import_source" varchar(500) COLLATE "pg_catalog"."default",
  "import_question_order" int4,
  "correct" text COLLATE "pg_catalog"."default",
  "info_text_content_id" int4,
  "create_user" int4,
  "status" int4,
  "create_time" timestamp(6),
  "deleted" bool
)
;

-- ----------------------------
-- Records of t_question
-- ----------------------------

-- ----------------------------
-- Table structure for t_smart_training_config
-- ----------------------------
DROP TABLE IF EXISTS "public"."t_smart_training_config";
CREATE TABLE "public"."t_smart_training_config" (
  "id" int4 NOT NULL DEFAULT nextval('t_smart_training_config_id_seq'::regclass),
  "subject_id" int4,
  "question_count" int4,
  "rule_json" text COLLATE "pg_catalog"."default",
  "create_time" timestamp(6),
  "modify_time" timestamp(6),
  "deleted" bool
)
;

-- ----------------------------
-- Table structure for t_question_review_record
-- ----------------------------
DROP TABLE IF EXISTS "public"."t_question_review_record";
CREATE TABLE "public"."t_question_review_record" (
  "id" serial PRIMARY KEY,
  "question_id" int4 NOT NULL,
  "review_type" varchar(32) COLLATE "pg_catalog"."default" NOT NULL,
  "review_round" int4 NOT NULL,
  "before_value" text COLLATE "pg_catalog"."default",
  "after_value" text COLLATE "pg_catalog"."default",
  "reviewer_id" int4,
  "reviewer_name" varchar(255) COLLATE "pg_catalog"."default",
  "review_comment" text COLLATE "pg_catalog"."default",
  "create_time" timestamp(6),
  "deleted" bool DEFAULT false
)
;

CREATE INDEX "idx_question_review_record_question_type"
  ON "public"."t_question_review_record" ("question_id", "review_type", "review_round");

-- ----------------------------
-- Table structure for t_question_correction_record
-- ----------------------------
DROP TABLE IF EXISTS "public"."t_question_correction_record";
CREATE TABLE "public"."t_question_correction_record" (
  "id" serial PRIMARY KEY,
  "user_id" int4 NOT NULL,
  "question_id" int4 NOT NULL,
  "exam_paper_answer_id" int4,
  "customer_answer_id" int4 NOT NULL,
  "student_wrong_reason" text COLLATE "pg_catalog"."default",
  "student_correct_thinking" text COLLATE "pg_catalog"."default",
  "reviewed_wrong_reason" text COLLATE "pg_catalog"."default",
  "reviewed_correct_thinking" text COLLATE "pg_catalog"."default",
  "review_status" varchar(32) COLLATE "pg_catalog"."default",
  "reviewer_id" int4,
  "reviewer_name" varchar(255) COLLATE "pg_catalog"."default",
  "review_comment" text COLLATE "pg_catalog"."default",
  "resubmit_count" int4 DEFAULT 0,
  "submit_time" timestamp(6),
  "review_time" timestamp(6),
  "deleted" bool DEFAULT false,
  "class_id" int4
)
;

-- ----------------------------
-- Table structure for t_question_correction_review_record
-- ----------------------------
DROP TABLE IF EXISTS "public"."t_question_correction_review_record";
CREATE TABLE "public"."t_question_correction_review_record" (
  "id" serial PRIMARY KEY,
  "correction_id" int4 NOT NULL,
  "review_round" int4,
  "review_result" varchar(32) COLLATE "pg_catalog"."default",
  "student_wrong_reason" text COLLATE "pg_catalog"."default",
  "student_correct_thinking" text COLLATE "pg_catalog"."default",
  "before_wrong_reason" text COLLATE "pg_catalog"."default",
  "before_correct_thinking" text COLLATE "pg_catalog"."default",
  "after_wrong_reason" text COLLATE "pg_catalog"."default",
  "after_correct_thinking" text COLLATE "pg_catalog"."default",
  "reviewer_id" int4,
  "reviewer_name" varchar(255) COLLATE "pg_catalog"."default",
  "review_comment" text COLLATE "pg_catalog"."default",
  "create_time" timestamp(6)
)
;

CREATE UNIQUE INDEX "uk_question_correction_customer_answer"
  ON "public"."t_question_correction_record" ("customer_answer_id", "user_id")
  WHERE "deleted" = false;

CREATE INDEX "idx_question_correction_record_status_submit"
  ON "public"."t_question_correction_record" ("review_status", "submit_time");
CREATE INDEX "idx_question_correction_class_status"
  ON "public"."t_question_correction_record" ("class_id", "review_status", "submit_time");

CREATE INDEX "idx_question_correction_review_record_correction"
  ON "public"."t_question_correction_review_record" ("correction_id", "review_round");

CREATE INDEX "idx_question_correction_review_record_time"
  ON "public"."t_question_correction_review_record" ("correction_id", "create_time");

-- ----------------------------
-- Records of t_smart_training_config
-- ----------------------------
INSERT INTO "public"."t_smart_training_config" ("id", "subject_id", "question_count", "rule_json", "create_time", "modify_time", "deleted") VALUES (1, 1, 25, '[{"knowledgePoint":"GESP1级/运算符与表达式","minCount":2,"maxCount":6,"weight":128,"enabled":true},{"knowledgePoint":"GESP1级/循环结构","minCount":2,"maxCount":6,"weight":105,"enabled":true},{"knowledgePoint":"GESP1级/分支结构","minCount":1,"maxCount":3,"weight":16,"enabled":true},{"knowledgePoint":"GESP1级/计算机基础","minCount":1,"maxCount":3,"weight":12,"enabled":true},{"knowledgePoint":"GESP1级/变量与数据类型","minCount":1,"maxCount":3,"weight":11,"enabled":true},{"knowledgePoint":"GESP1级/输入输出","minCount":0,"maxCount":2,"weight":7,"enabled":true},{"knowledgePoint":"GESP1级/算法基础","minCount":0,"maxCount":2,"weight":6,"enabled":true},{"knowledgePoint":"GESP1级/字符串","minCount":0,"maxCount":2,"weight":4,"enabled":true},{"knowledgePoint":"GESP1级/综合","minCount":0,"maxCount":2,"weight":4,"enabled":true},{"knowledgePoint":"GESP1级/概念判断","minCount":0,"maxCount":1,"weight":3,"enabled":true},{"knowledgePoint":"GESP1级/函数","minCount":0,"maxCount":1,"weight":1,"enabled":true},{"knowledgePoint":"GESP1级/结构体与类","minCount":0,"maxCount":1,"weight":1,"enabled":true},{"knowledgePoint":"GESP1级/数学与进制","minCount":0,"maxCount":1,"weight":1,"enabled":true},{"knowledgePoint":"GESP1级/数组","minCount":0,"maxCount":1,"weight":1,"enabled":true}]', now(), now(), false);
INSERT INTO "public"."t_smart_training_config" ("id", "subject_id", "question_count", "rule_json", "create_time", "modify_time", "deleted") VALUES (2, 2, 25, '[{"knowledgePoint":"GESP2级/循环结构","minCount":2,"maxCount":6,"weight":132,"enabled":true},{"knowledgePoint":"GESP2级/运算符与表达式","minCount":2,"maxCount":6,"weight":88,"enabled":true},{"knowledgePoint":"GESP2级/算法基础","minCount":1,"maxCount":3,"weight":20,"enabled":true},{"knowledgePoint":"GESP2级/计算机基础","minCount":1,"maxCount":3,"weight":16,"enabled":true},{"knowledgePoint":"GESP2级/分支结构","minCount":1,"maxCount":3,"weight":12,"enabled":true},{"knowledgePoint":"GESP2级/变量与数据类型","minCount":0,"maxCount":2,"weight":8,"enabled":true},{"knowledgePoint":"GESP2级/概念判断","minCount":0,"maxCount":2,"weight":4,"enabled":true},{"knowledgePoint":"GESP2级/输入输出","minCount":0,"maxCount":2,"weight":4,"enabled":true},{"knowledgePoint":"GESP2级/综合","minCount":0,"maxCount":2,"weight":4,"enabled":true},{"knowledgePoint":"GESP2级/函数","minCount":0,"maxCount":1,"weight":3,"enabled":true},{"knowledgePoint":"GESP2级/指针与引用","minCount":0,"maxCount":1,"weight":3,"enabled":true},{"knowledgePoint":"GESP2级/字符串","minCount":0,"maxCount":1,"weight":2,"enabled":true},{"knowledgePoint":"GESP2级/结构体与类","minCount":0,"maxCount":1,"weight":1,"enabled":true},{"knowledgePoint":"GESP2级/排序与查找","minCount":0,"maxCount":1,"weight":1,"enabled":true},{"knowledgePoint":"GESP2级/数组","minCount":0,"maxCount":1,"weight":1,"enabled":true}]', now(), now(), false);
INSERT INTO "public"."t_smart_training_config" ("id", "subject_id", "question_count", "rule_json", "create_time", "modify_time", "deleted") VALUES (3, 3, 25, '[{"knowledgePoint":"GESP3级/数组与字符数组","minCount":1,"maxCount":5,"weight":60,"enabled":true},{"knowledgePoint":"GESP3级/位运算","minCount":1,"maxCount":5,"weight":56,"enabled":true},{"knowledgePoint":"GESP3级/进制转换与进制字面量","minCount":1,"maxCount":5,"weight":33,"enabled":true},{"knowledgePoint":"GESP3级/字符串处理","minCount":1,"maxCount":3,"weight":27,"enabled":true},{"knowledgePoint":"GESP3级/原码反码补码与整数表示","minCount":1,"maxCount":3,"weight":26,"enabled":true},{"knowledgePoint":"GESP3级/控制结构与程序阅读","minCount":1,"maxCount":3,"weight":25,"enabled":true},{"knowledgePoint":"GESP3级/枚举与基础算法","minCount":1,"maxCount":3,"weight":16,"enabled":true},{"knowledgePoint":"GESP3级/ASCII/字符编码","minCount":1,"maxCount":3,"weight":16,"enabled":true},{"knowledgePoint":"GESP3级/运算符、表达式与类型转换","minCount":1,"maxCount":3,"weight":14,"enabled":true},{"knowledgePoint":"GESP3级/计算机基础常识","minCount":1,"maxCount":3,"weight":12,"enabled":true},{"knowledgePoint":"GESP3级/C++语法规则与编译模型","minCount":0,"maxCount":2,"weight":9,"enabled":true},{"knowledgePoint":"GESP3级/函数与标准库","minCount":0,"maxCount":2,"weight":5,"enabled":true},{"knowledgePoint":"GESP3级/算法描述与流程图","minCount":0,"maxCount":1,"weight":1,"enabled":true}]', now(), now(), false);
INSERT INTO "public"."t_smart_training_config" ("id", "subject_id", "question_count", "rule_json", "create_time", "modify_time", "deleted") VALUES (4, 4, 25, '[{"knowledgePoint":"GESP4级/数组","minCount":1,"maxCount":5,"weight":64,"enabled":true},{"knowledgePoint":"GESP4级/排序与查找","minCount":1,"maxCount":5,"weight":47,"enabled":true},{"knowledgePoint":"GESP4级/函数","minCount":1,"maxCount":5,"weight":33,"enabled":true},{"knowledgePoint":"GESP4级/运算符与表达式","minCount":1,"maxCount":3,"weight":26,"enabled":true},{"knowledgePoint":"GESP4级/指针与引用","minCount":1,"maxCount":3,"weight":21,"enabled":true},{"knowledgePoint":"GESP4级/变量与数据类型","minCount":1,"maxCount":3,"weight":20,"enabled":true},{"knowledgePoint":"GESP4级/循环结构","minCount":1,"maxCount":3,"weight":16,"enabled":true},{"knowledgePoint":"GESP4级/字符串","minCount":1,"maxCount":3,"weight":11,"enabled":true},{"knowledgePoint":"GESP4级/分支结构","minCount":0,"maxCount":2,"weight":8,"enabled":true},{"knowledgePoint":"GESP4级/结构体与类","minCount":0,"maxCount":2,"weight":6,"enabled":true},{"knowledgePoint":"GESP4级/计算机基础","minCount":0,"maxCount":2,"weight":5,"enabled":true},{"knowledgePoint":"GESP4级/概念判断","minCount":0,"maxCount":2,"weight":4,"enabled":true},{"knowledgePoint":"GESP4级/综合","minCount":0,"maxCount":2,"weight":4,"enabled":true},{"knowledgePoint":"GESP4级/复杂度","minCount":0,"maxCount":1,"weight":3,"enabled":true},{"knowledgePoint":"GESP4级/算法基础","minCount":0,"maxCount":1,"weight":3,"enabled":true},{"knowledgePoint":"GESP4级/递归","minCount":0,"maxCount":1,"weight":2,"enabled":true},{"knowledgePoint":"GESP4级/输入输出","minCount":0,"maxCount":1,"weight":2,"enabled":true}]', now(), now(), false);
INSERT INTO "public"."t_smart_training_config" ("id", "subject_id", "question_count", "rule_json", "create_time", "modify_time", "deleted") VALUES (5, 5, 25, '[{"knowledgePoint":"GESP5级/排序与查找","minCount":1,"maxCount":5,"weight":74,"enabled":true},{"knowledgePoint":"GESP5级/算法基础","minCount":1,"maxCount":5,"weight":48,"enabled":true},{"knowledgePoint":"GESP5级/递归","minCount":1,"maxCount":5,"weight":36,"enabled":true},{"knowledgePoint":"GESP5级/数组","minCount":1,"maxCount":3,"weight":22,"enabled":true},{"knowledgePoint":"GESP5级/数学与进制","minCount":1,"maxCount":3,"weight":16,"enabled":true},{"knowledgePoint":"GESP5级/循环结构","minCount":1,"maxCount":3,"weight":15,"enabled":true},{"knowledgePoint":"GESP5级/分支结构","minCount":1,"maxCount":3,"weight":11,"enabled":true},{"knowledgePoint":"GESP5级/概念判断","minCount":0,"maxCount":2,"weight":8,"enabled":true},{"knowledgePoint":"GESP5级/函数","minCount":0,"maxCount":2,"weight":5,"enabled":true},{"knowledgePoint":"GESP5级/复杂度","minCount":0,"maxCount":2,"weight":4,"enabled":true},{"knowledgePoint":"GESP5级/综合","minCount":0,"maxCount":1,"weight":3,"enabled":true},{"knowledgePoint":"GESP5级/计算机基础","minCount":0,"maxCount":1,"weight":2,"enabled":true},{"knowledgePoint":"GESP5级/运算符与表达式","minCount":0,"maxCount":1,"weight":2,"enabled":true},{"knowledgePoint":"GESP5级/字符串","minCount":0,"maxCount":1,"weight":2,"enabled":true},{"knowledgePoint":"GESP5级/输入输出","minCount":0,"maxCount":1,"weight":1,"enabled":true},{"knowledgePoint":"GESP5级/指针与引用","minCount":0,"maxCount":1,"weight":1,"enabled":true}]', now(), now(), false);
INSERT INTO "public"."t_smart_training_config" ("id", "subject_id", "question_count", "rule_json", "create_time", "modify_time", "deleted") VALUES (6, 6, 25, '[{"knowledgePoint":"GESP6级/算法基础","minCount":2,"maxCount":6,"weight":121,"enabled":true},{"knowledgePoint":"GESP6级/函数","minCount":1,"maxCount":3,"weight":27,"enabled":true},{"knowledgePoint":"GESP6级/排序与查找","minCount":1,"maxCount":3,"weight":26,"enabled":true},{"knowledgePoint":"GESP6级/计算机基础","minCount":1,"maxCount":3,"weight":19,"enabled":true},{"knowledgePoint":"GESP6级/结构体与类","minCount":1,"maxCount":3,"weight":14,"enabled":true},{"knowledgePoint":"GESP6级/递归","minCount":1,"maxCount":3,"weight":13,"enabled":true},{"knowledgePoint":"GESP6级/数组","minCount":0,"maxCount":2,"weight":9,"enabled":true},{"knowledgePoint":"GESP6级/字符串","minCount":0,"maxCount":2,"weight":7,"enabled":true},{"knowledgePoint":"GESP6级/概念判断","minCount":0,"maxCount":1,"weight":3,"enabled":true},{"knowledgePoint":"GESP6级/循环结构","minCount":0,"maxCount":1,"weight":3,"enabled":true},{"knowledgePoint":"GESP6级/分支结构","minCount":0,"maxCount":1,"weight":2,"enabled":true},{"knowledgePoint":"GESP6级/输入输出","minCount":0,"maxCount":1,"weight":2,"enabled":true},{"knowledgePoint":"GESP6级/运算符与表达式","minCount":0,"maxCount":1,"weight":2,"enabled":true},{"knowledgePoint":"GESP6级/数学与进制","minCount":0,"maxCount":1,"weight":1,"enabled":true},{"knowledgePoint":"GESP6级/指针与引用","minCount":0,"maxCount":1,"weight":1,"enabled":true}]', now(), now(), false);
INSERT INTO "public"."t_smart_training_config" ("id", "subject_id", "question_count", "rule_json", "create_time", "modify_time", "deleted") VALUES (7, 7, 25, '[{"knowledgePoint":"GESP7级/算法基础","minCount":2,"maxCount":6,"weight":85,"enabled":true},{"knowledgePoint":"GESP7级/函数","minCount":1,"maxCount":3,"weight":27,"enabled":true},{"knowledgePoint":"GESP7级/数组","minCount":1,"maxCount":3,"weight":24,"enabled":true},{"knowledgePoint":"GESP7级/排序与查找","minCount":1,"maxCount":3,"weight":22,"enabled":true},{"knowledgePoint":"GESP7级/运算符与表达式","minCount":1,"maxCount":3,"weight":18,"enabled":true},{"knowledgePoint":"GESP7级/递归","minCount":1,"maxCount":3,"weight":11,"enabled":true},{"knowledgePoint":"GESP7级/变量与数据类型","minCount":0,"maxCount":2,"weight":8,"enabled":true},{"knowledgePoint":"GESP7级/循环结构","minCount":0,"maxCount":2,"weight":5,"enabled":true},{"knowledgePoint":"GESP7级/分支结构","minCount":0,"maxCount":2,"weight":4,"enabled":true},{"knowledgePoint":"GESP7级/复杂度","minCount":0,"maxCount":1,"weight":3,"enabled":true},{"knowledgePoint":"GESP7级/计算机基础","minCount":0,"maxCount":1,"weight":3,"enabled":true},{"knowledgePoint":"GESP7级/结构体与类","minCount":0,"maxCount":1,"weight":3,"enabled":true},{"knowledgePoint":"GESP7级/指针与引用","minCount":0,"maxCount":1,"weight":3,"enabled":true},{"knowledgePoint":"GESP7级/综合","minCount":0,"maxCount":1,"weight":3,"enabled":true},{"knowledgePoint":"GESP7级/概念判断","minCount":0,"maxCount":1,"weight":2,"enabled":true},{"knowledgePoint":"GESP7级/数学与进制","minCount":0,"maxCount":1,"weight":2,"enabled":true},{"knowledgePoint":"GESP7级/字符串","minCount":0,"maxCount":1,"weight":2,"enabled":true}]', now(), now(), false);
INSERT INTO "public"."t_smart_training_config" ("id", "subject_id", "question_count", "rule_json", "create_time", "modify_time", "deleted") VALUES (8, 8, 25, '[{"knowledgePoint":"GESP8级/算法基础","minCount":1,"maxCount":5,"weight":50,"enabled":true},{"knowledgePoint":"GESP8级/排序与查找","minCount":1,"maxCount":3,"weight":27,"enabled":true},{"knowledgePoint":"GESP8级/数组","minCount":1,"maxCount":3,"weight":26,"enabled":true},{"knowledgePoint":"GESP8级/函数","minCount":1,"maxCount":3,"weight":23,"enabled":true},{"knowledgePoint":"GESP8级/运算符与表达式","minCount":1,"maxCount":3,"weight":20,"enabled":true},{"knowledgePoint":"GESP8级/数学与进制","minCount":1,"maxCount":3,"weight":15,"enabled":true},{"knowledgePoint":"GESP8级/综合","minCount":1,"maxCount":3,"weight":14,"enabled":true},{"knowledgePoint":"GESP8级/概念判断","minCount":1,"maxCount":3,"weight":11,"enabled":true},{"knowledgePoint":"GESP8级/循环结构","minCount":1,"maxCount":3,"weight":11,"enabled":true},{"knowledgePoint":"GESP8级/分支结构","minCount":0,"maxCount":2,"weight":8,"enabled":true},{"knowledgePoint":"GESP8级/计算机基础","minCount":0,"maxCount":2,"weight":8,"enabled":true},{"knowledgePoint":"GESP8级/变量与数据类型","minCount":0,"maxCount":1,"weight":3,"enabled":true},{"knowledgePoint":"GESP8级/递归","minCount":0,"maxCount":1,"weight":3,"enabled":true},{"knowledgePoint":"GESP8级/复杂度","minCount":0,"maxCount":1,"weight":3,"enabled":true},{"knowledgePoint":"GESP8级/结构体与类","minCount":0,"maxCount":1,"weight":1,"enabled":true},{"knowledgePoint":"GESP8级/指针与引用","minCount":0,"maxCount":1,"weight":1,"enabled":true},{"knowledgePoint":"GESP8级/字符串","minCount":0,"maxCount":1,"weight":1,"enabled":true}]', now(), now(), false);

-- ----------------------------
-- Table structure for t_subject
-- ----------------------------
DROP TABLE IF EXISTS "public"."t_subject";
CREATE TABLE "public"."t_subject" (
  "id" int4 NOT NULL DEFAULT nextval('t_subject_id_seq'::regclass),
  "name" varchar(255) COLLATE "pg_catalog"."default",
  "level" int4,
  "level_name" varchar(255) COLLATE "pg_catalog"."default",
  "item_order" int4,
  "deleted" bool
)
;


-- ----------------------------
-- Records of t_subject
-- ----------------------------
INSERT INTO "public"."t_subject" ("id", "name", "level", "level_name", "item_order", "deleted") VALUES (1, 'GESP 1级', 1, 'GESP 1级', 1, false);
INSERT INTO "public"."t_subject" ("id", "name", "level", "level_name", "item_order", "deleted") VALUES (2, 'GESP 2级', 2, 'GESP 2级', 2, false);
INSERT INTO "public"."t_subject" ("id", "name", "level", "level_name", "item_order", "deleted") VALUES (3, 'GESP 3级', 3, 'GESP 3级', 3, false);
INSERT INTO "public"."t_subject" ("id", "name", "level", "level_name", "item_order", "deleted") VALUES (4, 'GESP 4级', 4, 'GESP 4级', 4, false);
INSERT INTO "public"."t_subject" ("id", "name", "level", "level_name", "item_order", "deleted") VALUES (5, 'GESP 5级', 5, 'GESP 5级', 5, false);
INSERT INTO "public"."t_subject" ("id", "name", "level", "level_name", "item_order", "deleted") VALUES (6, 'GESP 6级', 6, 'GESP 6级', 6, false);
INSERT INTO "public"."t_subject" ("id", "name", "level", "level_name", "item_order", "deleted") VALUES (7, 'GESP 7级', 7, 'GESP 7级', 7, false);
INSERT INTO "public"."t_subject" ("id", "name", "level", "level_name", "item_order", "deleted") VALUES (8, 'GESP 8级', 8, 'GESP 8级', 8, false);
INSERT INTO "public"."t_subject" ("id", "name", "level", "level_name", "item_order", "deleted") VALUES (9, 'CSP-J', 9, 'CSP-J', 9, false);
INSERT INTO "public"."t_subject" ("id", "name", "level", "level_name", "item_order", "deleted") VALUES (10, 'CSP-S', 10, 'CSP-S', 10, false);

-- ----------------------------
-- Table structure for t_task_exam
-- ----------------------------
DROP TABLE IF EXISTS "public"."t_task_exam";
CREATE TABLE "public"."t_task_exam" (
  "id" int4 NOT NULL DEFAULT nextval('t_task_exam_id_seq'::regclass),
  "title" varchar(255) COLLATE "pg_catalog"."default",
  "grade_level" int4,
  "frame_text_content_id" int4,
  "create_user" int4,
  "create_user_name" varchar(255) COLLATE "pg_catalog"."default",
  "create_time" timestamp(6),
  "deleted" bool,
  "class_id" int4
)
;

-- ----------------------------
-- Records of t_task_exam
-- ----------------------------

-- ----------------------------
-- Table structure for t_task_exam_customer_answer
-- ----------------------------
DROP TABLE IF EXISTS "public"."t_task_exam_customer_answer";
CREATE TABLE "public"."t_task_exam_customer_answer" (
  "id" int4 NOT NULL DEFAULT nextval('t_task_exam_customer_answer_id_seq'::regclass),
  "task_exam_id" int4,
  "text_content_id" int4,
  "create_user" int4,
  "create_time" timestamp(6)
)
;

-- ----------------------------
-- Records of t_task_exam_customer_answer
-- ----------------------------

-- ----------------------------
-- Table structure for t_text_content
-- ----------------------------
DROP TABLE IF EXISTS "public"."t_text_content";
CREATE TABLE "public"."t_text_content" (
  "id" int4 NOT NULL DEFAULT nextval('t_text_content_id_seq'::regclass),
  "content" text COLLATE "pg_catalog"."default",
  "create_time" timestamp(6)
)
;

-- ----------------------------
-- Records of t_text_content
-- ----------------------------

-- ----------------------------
-- Table structure for t_user
-- ----------------------------
DROP TABLE IF EXISTS "public"."t_user";
CREATE TABLE "public"."t_user" (
  "id" int4 NOT NULL DEFAULT nextval('t_user_id_seq'::regclass),
  "user_uuid" uuid,
  "user_name" varchar(255) COLLATE "pg_catalog"."default",
  "password" varchar(255) COLLATE "pg_catalog"."default",
  "real_name" varchar(255) COLLATE "pg_catalog"."default",
  "age" int4,
  "sex" int4,
  "birth_day" timestamp(6),
  "user_level" int4,
  "phone" varchar(255) COLLATE "pg_catalog"."default",
  "role" int4,
  "status" int4,
  "image_path" varchar(255) COLLATE "pg_catalog"."default",
  "create_time" timestamp(6),
  "modify_time" timestamp(6),
  "last_active_time" timestamp(6),
  "deleted" bool,
  "wx_open_id" varchar COLLATE "pg_catalog"."default",
  "class_id" int4
)
;

-- ----------------------------
-- Records of t_user
-- ----------------------------
INSERT INTO "public"."t_user" VALUES (2, '55bad52c-cdf7-4321-87b8-e37d958b24cf', 'admin', 'D1AGFL+Gx37t0NPG4d6biYP5Z31cNbwhK5w1lUeiHB2zagqbk8efYfSjYoh1Z/j1dkiRjHU+b0EpwzCh8IGsksJjzD65ci5LsnodQVf4Uj6D3pwoscXGqmkjjpzvSJbx42swwNTA+QoDU8YLo7JhtbUK2X0qCjFGpd+8eJ5BGvk=', '管理员', 18, 1, '2019-09-02 00:00:00', 13, '1561651651616156', 3, 1, NULL, '2019-07-23 07:17:16.923', '2020-02-08 10:52:42.234', '2019-07-23 07:17:16.923', 'f', NULL, NULL);
INSERT INTO "public"."t_user" VALUES (1, 'b41eaab1-926a-4824-94e8-da9259986ab6', 'student', 'RA6atJcbedAQUA/3jTcC85RuVuedZEgkeWUCiagtwhz6SjEKerC4IvFQe1OGSvbk+tPZGfkInRrmipPgHU6tzcpaQfdJkV9cXSGoxyldrWSFxblfpGGDxVisQrtrH7N1AEyi6u3h4iYrwkf4sPV8xoU8ZpOhlKmLEjDEq/an6rQ=', '学生', 16, 2, '1979-06-05 00:00:00', 1, '19171171610', 1, 1, 'https://www.mindskip.net:9008/image/ba607a75-83ba-4530-8e23-660b72dc4953/头像.jpg', '2019-07-23 05:02:29.027', '2020-02-05 09:36:52.138', '2019-07-23 05:02:29.027', 'f', NULL, NULL);

-- ----------------------------
-- Table structure for t_user_event_log
-- ----------------------------
DROP TABLE IF EXISTS "public"."t_user_event_log";
CREATE TABLE "public"."t_user_event_log" (
  "id" int4 NOT NULL DEFAULT nextval('t_user_event_log_id_seq'::regclass),
  "user_id" int4,
  "user_name" varchar(255) COLLATE "pg_catalog"."default",
  "real_name" varchar(255) COLLATE "pg_catalog"."default",
  "content" text COLLATE "pg_catalog"."default",
  "create_time" timestamp(6)
)
;

-- ----------------------------
-- Records of t_user_event_log
-- ----------------------------

-- ----------------------------
-- Table structure for t_user_token
-- ----------------------------
DROP TABLE IF EXISTS "public"."t_user_token";
CREATE TABLE "public"."t_user_token" (
  "id" int4 NOT NULL DEFAULT nextval('t_user_token_id_seq'::regclass),
  "token" uuid,
  "user_id" int4,
  "wx_open_id" varchar(255) COLLATE "pg_catalog"."default",
  "create_time" timestamp(6),
  "end_time" timestamp(6),
  "user_name" varchar(255) COLLATE "pg_catalog"."default"
)
;

-- ----------------------------
-- Records of t_user_token
-- ----------------------------

-- ----------------------------
-- Alter sequences owned by
-- ----------------------------
ALTER SEQUENCE "public"."t_exam_paper_answer_id_seq"
OWNED BY "public"."t_exam_paper_answer"."id";
SELECT setval('"public"."t_exam_paper_answer_id_seq"', 1, true);

-- ----------------------------
-- Alter sequences owned by
-- ----------------------------
ALTER SEQUENCE "public"."t_exam_paper_id_seq"
OWNED BY "public"."t_exam_paper"."id";
SELECT setval('"public"."t_exam_paper_id_seq"', 1, true);

-- ----------------------------
-- Alter sequences owned by
-- ----------------------------
ALTER SEQUENCE "public"."t_exam_paper_question_customer_answer_id_seq"
OWNED BY "public"."t_exam_paper_question_customer_answer"."id";
SELECT setval('"public"."t_exam_paper_question_customer_answer_id_seq"', 1, true);

-- ----------------------------
-- Alter sequences owned by
-- ----------------------------
ALTER SEQUENCE "public"."t_message_id_seq"
OWNED BY "public"."t_message"."id";
SELECT setval('"public"."t_message_id_seq"', 1, true);

-- ----------------------------
-- Alter sequences owned by
-- ----------------------------
ALTER SEQUENCE "public"."t_message_user_id_seq"
OWNED BY "public"."t_message_user"."id";
SELECT setval('"public"."t_message_user_id_seq"', 1, true);

-- ----------------------------
-- Alter sequences owned by
-- ----------------------------
ALTER SEQUENCE "public"."t_question_id_seq"
OWNED BY "public"."t_question"."id";
SELECT setval('"public"."t_question_id_seq"', 1, true);

-- ----------------------------
-- Alter sequences owned by
-- ----------------------------
ALTER SEQUENCE "public"."t_smart_training_config_id_seq"
OWNED BY "public"."t_smart_training_config"."id";
SELECT setval('"public"."t_smart_training_config_id_seq"', 8, true);

-- ----------------------------
-- Alter sequences owned by
-- ----------------------------
ALTER SEQUENCE "public"."t_subject_id_seq"
OWNED BY "public"."t_subject"."id";
SELECT setval('"public"."t_subject_id_seq"', 10, true);

-- ----------------------------
-- Alter sequences owned by
-- ----------------------------
ALTER SEQUENCE "public"."t_task_exam_customer_answer_id_seq"
OWNED BY "public"."t_task_exam_customer_answer"."id";
SELECT setval('"public"."t_task_exam_customer_answer_id_seq"', 1, true);

-- ----------------------------
-- Alter sequences owned by
-- ----------------------------
ALTER SEQUENCE "public"."t_task_exam_id_seq"
OWNED BY "public"."t_task_exam"."id";
SELECT setval('"public"."t_task_exam_id_seq"', 1, true);

-- ----------------------------
-- Alter sequences owned by
-- ----------------------------
ALTER SEQUENCE "public"."t_text_content_id_seq"
OWNED BY "public"."t_text_content"."id";
SELECT setval('"public"."t_text_content_id_seq"', 1, true);

-- ----------------------------
-- Alter sequences owned by
-- ----------------------------
ALTER SEQUENCE "public"."t_user_event_log_id_seq"
OWNED BY "public"."t_user_event_log"."id";
SELECT setval('"public"."t_user_event_log_id_seq"', 1, true);

-- ----------------------------
-- Alter sequences owned by
-- ----------------------------
ALTER SEQUENCE "public"."t_user_id_seq"
OWNED BY "public"."t_user"."id";
SELECT setval('"public"."t_user_id_seq"', 3, true);

-- ----------------------------
-- Alter sequences owned by
-- ----------------------------
ALTER SEQUENCE "public"."t_user_token_id_seq"
OWNED BY "public"."t_user_token"."id";
SELECT setval('"public"."t_user_token_id_seq"', 1, true);

-- ----------------------------
-- Primary Key structure for table t_exam_paper
-- ----------------------------
ALTER TABLE "public"."t_exam_paper" ADD CONSTRAINT "t_exam_paper_pkey" PRIMARY KEY ("id");

-- ----------------------------
-- Primary Key structure for table t_exam_paper_answer
-- ----------------------------
ALTER TABLE "public"."t_exam_paper_answer" ADD CONSTRAINT "t_exam_paper_answer_pkey" PRIMARY KEY ("id");
CREATE INDEX "idx_exam_paper_answer_class" ON "public"."t_exam_paper_answer" ("class_id", "create_time");

-- ----------------------------
-- Primary Key structure for table t_exam_paper_question_customer_answer
-- ----------------------------
ALTER TABLE "public"."t_exam_paper_question_customer_answer" ADD CONSTRAINT "t_exam_paper_question_customer_answer_pkey" PRIMARY KEY ("id");
CREATE INDEX "idx_customer_answer_class" ON "public"."t_exam_paper_question_customer_answer" ("class_id", "create_time");

-- ----------------------------
-- Primary Key structure for table t_message
-- ----------------------------
ALTER TABLE "public"."t_message" ADD CONSTRAINT "t_message_pkey" PRIMARY KEY ("id");

-- ----------------------------
-- Primary Key structure for table t_message_user
-- ----------------------------
ALTER TABLE "public"."t_message_user" ADD CONSTRAINT "t_message_user_pkey" PRIMARY KEY ("id");

-- ----------------------------
-- Primary Key structure for table t_question
-- ----------------------------
ALTER TABLE "public"."t_question" ADD CONSTRAINT "t_question_pkey" PRIMARY KEY ("id");
CREATE UNIQUE INDEX "uk_question_import_source_order"
  ON "public"."t_question" ("import_batch", "import_source", "import_question_order");

-- ----------------------------
-- Primary Key structure for table t_smart_training_config
-- ----------------------------
ALTER TABLE "public"."t_smart_training_config" ADD CONSTRAINT "t_smart_training_config_pkey" PRIMARY KEY ("id");
ALTER TABLE "public"."t_smart_training_config" ADD CONSTRAINT "uk_smart_training_config_subject" UNIQUE ("subject_id");

-- ----------------------------
-- Primary Key structure for table t_subject
-- ----------------------------
ALTER TABLE "public"."t_subject" ADD CONSTRAINT "t_subject_pkey" PRIMARY KEY ("id");

-- ----------------------------
-- Primary Key structure for table t_task_exam
-- ----------------------------
ALTER TABLE "public"."t_task_exam" ADD CONSTRAINT "t_task_exam_pkey" PRIMARY KEY ("id");
CREATE INDEX "idx_task_exam_class" ON "public"."t_task_exam" ("class_id", "deleted");

-- ----------------------------
-- Primary Key structure for table t_task_exam_customer_answer
-- ----------------------------
ALTER TABLE "public"."t_task_exam_customer_answer" ADD CONSTRAINT "t_task_exam_customer_answer_pkey" PRIMARY KEY ("id");

-- ----------------------------
-- Primary Key structure for table t_text_content
-- ----------------------------
ALTER TABLE "public"."t_text_content" ADD CONSTRAINT "t_text_content_pkey" PRIMARY KEY ("id");

-- ----------------------------
-- Primary Key structure for table t_user
-- ----------------------------
ALTER TABLE "public"."t_user" ADD CONSTRAINT "t_user_pkey" PRIMARY KEY ("id");
CREATE INDEX "idx_user_class_role" ON "public"."t_user" ("class_id", "role", "deleted");

-- ----------------------------
-- Primary Key structure for table t_user_event_log
-- ----------------------------
ALTER TABLE "public"."t_user_event_log" ADD CONSTRAINT "t_user_event_log_pkey" PRIMARY KEY ("id");

-- ----------------------------
-- Primary Key structure for table t_user_token
-- ----------------------------
ALTER TABLE "public"."t_user_token" ADD CONSTRAINT "t_user_token_pkey" PRIMARY KEY ("id");
