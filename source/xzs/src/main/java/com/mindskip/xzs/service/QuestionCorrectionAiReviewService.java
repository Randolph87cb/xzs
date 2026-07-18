package com.mindskip.xzs.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.commons.lang3.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.client.RestTemplate;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;

@Service
public class QuestionCorrectionAiReviewService {

    private static final Logger logger = LoggerFactory.getLogger(QuestionCorrectionAiReviewService.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final String PROVIDER = "openai_compatible";
    private static final String DEFAULT_PROMPT =
            "你是信息学客观题错题改正审核助手。请只给老师预审建议，不要替老师做最终审核。";

    private final JdbcTemplate jdbcTemplate;
    private final String configSecret;
    private final SecureRandom secureRandom = new SecureRandom();

    public QuestionCorrectionAiReviewService(
            JdbcTemplate jdbcTemplate,
            @Value("${xzs.ai.config-secret:${XZS_AI_CONFIG_SECRET:}}") String configSecret) {
        this.jdbcTemplate = jdbcTemplate;
        this.configSecret = configSecret;
    }

    public Map<String, Object> selectConfig(Integer teacherUserId) {
        List<Map<String, Object>> rows = jdbcTemplate.queryForList(
                "select provider, base_url, model, api_key_cipher, enabled, prompt, create_time, modify_time " +
                        "from t_teacher_ai_review_config where teacher_user_id = ?",
                teacherUserId);
        Map<String, Object> result = new HashMap<>();
        if (!rows.isEmpty()) {
            Map<String, Object> row = rows.get(0);
            result.put("provider", row.get("provider"));
            result.put("baseUrl", row.get("base_url"));
            result.put("model", row.get("model"));
            result.put("enabled", row.get("enabled"));
            result.put("prompt", row.get("prompt"));
            result.put("createTime", row.get("create_time"));
            result.put("modifyTime", row.get("modify_time"));
            result.put("hasApiKey", StringUtils.isNotBlank((String) row.get("api_key_cipher")));
            return result;
        }

        result.put("provider", PROVIDER);
        result.put("baseUrl", "");
        result.put("model", "");
        result.put("enabled", false);
        result.put("prompt", "");
        result.put("hasApiKey", false);
        return result;
    }

    public String saveConfig(Integer teacherUserId, SaveConfigRequest request) {
        String baseUrl = StringUtils.trimToEmpty(request.getBaseUrl());
        String model = StringUtils.trimToEmpty(request.getModel());
        boolean enabled = request.getEnabled() == null || request.getEnabled();
        if (StringUtils.isBlank(baseUrl)) {
            return "接口地址不能为空";
        }
        if (StringUtils.isBlank(model)) {
            return "模型不能为空";
        }

        List<Map<String, Object>> rows = jdbcTemplate.queryForList(
                "select id, api_key_cipher from t_teacher_ai_review_config where teacher_user_id = ?",
                teacherUserId);
        String apiKeyCipher = rows.isEmpty() ? null : (String) rows.get(0).get("api_key_cipher");
        if (Boolean.TRUE.equals(request.getClearApiKey())) {
            apiKeyCipher = null;
        }
        if (StringUtils.isNotBlank(request.getApiKey())) {
            if (StringUtils.isBlank(configSecret)) {
                return "服务端未配置 XZS_AI_CONFIG_SECRET，不能保存 API Key";
            }
            apiKeyCipher = encrypt(request.getApiKey().trim());
        }
        if (enabled && StringUtils.isBlank(apiKeyCipher)) {
            return "启用 AI 预审时 API Key 不能为空";
        }

        if (rows.isEmpty()) {
            jdbcTemplate.update(
                    "insert into t_teacher_ai_review_config " +
                            "(teacher_user_id, provider, base_url, model, api_key_cipher, enabled, prompt, create_time, modify_time) " +
                            "values (?, ?, ?, ?, ?, ?, ?, now(), now())",
                    teacherUserId,
                    PROVIDER,
                    baseUrl,
                    model,
                    apiKeyCipher,
                    enabled,
                    StringUtils.trimToNull(request.getPrompt()));
        } else {
            jdbcTemplate.update(
                    "update t_teacher_ai_review_config set provider = ?, base_url = ?, model = ?, api_key_cipher = ?, enabled = ?, prompt = ?, modify_time = now() " +
                            "where teacher_user_id = ?",
                    PROVIDER,
                    baseUrl,
                    model,
                    apiKeyCipher,
                    enabled,
                    StringUtils.trimToNull(request.getPrompt()),
                    teacherUserId);
        }
        return null;
    }

    public void triggerAfterCommit(final Integer correctionId, final String triggerType) {
        if (correctionId == null) {
            return;
        }
        Runnable task = new Runnable() {
            @Override
            public void run() {
                CompletableFuture.runAsync(new Runnable() {
                    @Override
                    public void run() {
                        preReview(correctionId, triggerType);
                    }
                });
            }
        };
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    task.run();
                }
            });
        } else {
            task.run();
        }
    }

    public void preReview(Integer correctionId, String triggerType) {
        try {
            List<Map<String, Object>> contextRows = jdbcTemplate.queryForList(contextSql(), correctionId);
            if (contextRows.isEmpty()) {
                insertTerminalRecord(correctionId, null, triggerType, "SKIPPED", null, null, null, "改错记录不存在", null);
                return;
            }

            Map<String, Object> context = contextRows.get(0);
            Integer teacherUserId = (Integer) context.get("teacher_user_id");
            if (teacherUserId == null) {
                insertTerminalRecord(correctionId, null, triggerType, "SKIPPED", null, null, null, "错题所属班级没有负责老师", null);
                return;
            }

            List<Map<String, Object>> configRows = jdbcTemplate.queryForList(
                    "select * from t_teacher_ai_review_config where teacher_user_id = ?",
                    teacherUserId);
            if (configRows.isEmpty()) {
                insertTerminalRecord(correctionId, teacherUserId, triggerType, "SKIPPED", null, null, null, "负责老师未配置 AI 预审", null);
                return;
            }
            Map<String, Object> config = configRows.get(0);
            if (!Boolean.TRUE.equals(config.get("enabled"))) {
                insertTerminalRecord(correctionId, teacherUserId, triggerType, "SKIPPED", null, null, null, "负责老师未启用 AI 预审", null);
                return;
            }
            String apiKeyCipher = (String) config.get("api_key_cipher");
            if (StringUtils.isBlank(apiKeyCipher)) {
                insertTerminalRecord(correctionId, teacherUserId, triggerType, "SKIPPED", null, null, null, "负责老师未配置 API Key", null);
                return;
            }

            Integer recordId = jdbcTemplate.queryForObject(
                    "insert into t_question_correction_ai_review_record " +
                            "(correction_id, teacher_user_id, trigger_type, status, request_time, create_time) " +
                            "values (?, ?, ?, 'RUNNING', now(), now()) returning id",
                    Integer.class,
                    correctionId,
                    teacherUserId,
                    StringUtils.defaultIfBlank(triggerType, "AUTO_SUBMIT"));

            String apiKey = decrypt(apiKeyCipher);
            String rawContent = callOpenAiCompatible(context, config, apiKey);
            AiSuggestion suggestion = parseSuggestion(rawContent);
            jdbcTemplate.update(
                    "update t_question_correction_ai_review_record set status = 'SUCCESS', review_result = ?, review_comment = ?, confidence = ?, reason = ?, raw_content = ?, finish_time = now() where id = ?",
                    suggestion.reviewResult,
                    suggestion.reviewComment,
                    suggestion.confidence,
                    suggestion.reason,
                    rawContent,
                    recordId);
        } catch (Exception e) {
            logger.warn("question correction ai review failed, correctionId={}", correctionId, e);
            insertTerminalRecord(correctionId, null, triggerType, "FAILED", null, null, null, "AI 预审调用失败：" + StringUtils.left(e.getMessage(), 500), null);
        }
    }

    private String contextSql() {
        return "select c.*, coalesce(c.class_id, u.class_id) as correction_class_id, cls.teacher_id as teacher_user_id, " +
                "q.question_type, q.correct, a.answer as student_answer, " +
                "tc.content::jsonb ->> 'titleContent' as title, " +
                "tc.content::jsonb ->> 'questionItemObjects' as items, " +
                "tc.content::jsonb ->> 'analyze' as analyze " +
                "from t_question_correction_record c " +
                "join t_user u on u.id = c.user_id " +
                "left join t_class cls on cls.id = coalesce(c.class_id, u.class_id) and cls.deleted = false " +
                "join t_question q on q.id = c.question_id " +
                "join t_text_content tc on tc.id = q.info_text_content_id " +
                "join t_exam_paper_question_customer_answer a on a.id = c.customer_answer_id " +
                "where c.deleted = false and c.id = ?";
    }

    private String callOpenAiCompatible(Map<String, Object> context, Map<String, Object> config, String apiKey) throws Exception {
        String baseUrl = StringUtils.trimToEmpty((String) config.get("base_url"));
        String endpoint = baseUrl.endsWith("/chat/completions") ? baseUrl : StringUtils.removeEnd(baseUrl, "/") + "/chat/completions";

        Map<String, Object> body = new HashMap<>();
        body.put("model", config.get("model"));
        body.put("temperature", 0.1);
        body.put("messages", buildMessages(context, config));

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        headers.setBearerAuth(apiKey);

        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(10000);
        factory.setReadTimeout(30000);
        RestTemplate restTemplate = new RestTemplate(factory);
        ResponseEntity<String> response = restTemplate.postForEntity(endpoint, new HttpEntity<>(body, headers), String.class);
        JsonNode root = MAPPER.readTree(response.getBody());
        JsonNode content = root.path("choices").path(0).path("message").path("content");
        if (content.isMissingNode() || StringUtils.isBlank(content.asText())) {
            throw new IllegalStateException("AI 响应缺少 message.content");
        }
        return content.asText();
    }

    private List<Map<String, String>> buildMessages(Map<String, Object> context, Map<String, Object> config) {
        String systemPrompt = StringUtils.defaultIfBlank((String) config.get("prompt"), DEFAULT_PROMPT);
        Map<String, String> system = new HashMap<>();
        system.put("role", "system");
        system.put("content", systemPrompt);

        Map<String, String> user = new HashMap<>();
        user.put("role", "user");
        user.put("content",
                "请审核学生的错题改正是否说明了错误原因，并给出合理正确思路。只能输出 JSON：" +
                        "{\"reviewResult\":\"APPROVED|REJECTED|UNCERTAIN\",\"reviewComment\":\"给老师的审核意见\",\"confidence\":0.0,\"reason\":\"简短理由\"}\n\n" +
                        "题型：" + valueText(context.get("question_type")) + "\n" +
                        "题干：" + valueText(context.get("title")) + "\n" +
                        "选项：" + valueText(context.get("items")) + "\n" +
                        "解析：" + valueText(context.get("analyze")) + "\n" +
                        "学生答案：" + valueText(context.get("student_answer")) + "\n" +
                        "正确答案：" + valueText(context.get("correct")) + "\n" +
                        "学生填写的错误原因：" + valueText(context.get("student_wrong_reason")) + "\n" +
                        "学生填写的正确思路：" + valueText(context.get("student_correct_thinking")));
        List<Map<String, String>> messages = new ArrayList<>();
        messages.add(system);
        messages.add(user);
        return messages;
    }

    private AiSuggestion parseSuggestion(String rawContent) throws Exception {
        String json = extractJson(rawContent);
        JsonNode root = MAPPER.readTree(json);
        AiSuggestion suggestion = new AiSuggestion();
        suggestion.reviewResult = normalizeReviewResult(root.path("reviewResult").asText(null));
        suggestion.reviewComment = StringUtils.defaultIfBlank(root.path("reviewComment").asText(null), root.path("suggestion").asText(null));
        suggestion.reason = root.path("reason").asText(null);
        if (root.has("confidence") && root.get("confidence").isNumber()) {
            BigDecimal confidence = root.get("confidence").decimalValue();
            if (confidence.compareTo(BigDecimal.ZERO) < 0) {
                confidence = BigDecimal.ZERO;
            }
            if (confidence.compareTo(BigDecimal.ONE) > 0) {
                confidence = BigDecimal.ONE;
            }
            suggestion.confidence = confidence;
        }
        if (StringUtils.isBlank(suggestion.reviewComment)) {
            suggestion.reviewComment = "AI 未给出明确审核意见，请老师人工判断。";
        }
        return suggestion;
    }

    private String extractJson(String rawContent) {
        String trimmed = StringUtils.trimToEmpty(rawContent);
        if (trimmed.startsWith("```")) {
            int firstLine = trimmed.indexOf('\n');
            int lastFence = trimmed.lastIndexOf("```");
            if (firstLine >= 0 && lastFence > firstLine) {
                return trimmed.substring(firstLine + 1, lastFence).trim();
            }
        }
        int start = trimmed.indexOf('{');
        int end = trimmed.lastIndexOf('}');
        if (start >= 0 && end > start) {
            return trimmed.substring(start, end + 1);
        }
        return trimmed;
    }

    private String normalizeReviewResult(String value) {
        String normalized = StringUtils.upperCase(StringUtils.trimToEmpty(value));
        if ("APPROVED".equals(normalized) || "REJECTED".equals(normalized)) {
            return normalized;
        }
        return "UNCERTAIN";
    }

    private void insertTerminalRecord(Integer correctionId, Integer teacherUserId, String triggerType, String status,
                                      String reviewResult, String reviewComment, BigDecimal confidence,
                                      String message, String rawContent) {
        jdbcTemplate.update(
                "insert into t_question_correction_ai_review_record " +
                        "(correction_id, teacher_user_id, trigger_type, status, review_result, review_comment, confidence, reason, raw_content, error_message, finish_time, create_time) " +
                        "values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, now(), now())",
                correctionId,
                teacherUserId,
                StringUtils.defaultIfBlank(triggerType, "AUTO_SUBMIT"),
                status,
                reviewResult,
                reviewComment,
                confidence,
                message,
                rawContent,
                message);
    }

    private String encrypt(String plainText) {
        try {
            byte[] iv = new byte[12];
            secureRandom.nextBytes(iv);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, keySpec(), new GCMParameterSpec(128, iv));
            byte[] cipherText = cipher.doFinal(plainText.getBytes(StandardCharsets.UTF_8));
            byte[] combined = new byte[iv.length + cipherText.length];
            System.arraycopy(iv, 0, combined, 0, iv.length);
            System.arraycopy(cipherText, 0, combined, iv.length, cipherText.length);
            return Base64.getEncoder().encodeToString(combined);
        } catch (Exception e) {
            throw new IllegalStateException("API Key 加密失败", e);
        }
    }

    private String decrypt(String cipherText) {
        if (StringUtils.isBlank(configSecret)) {
            throw new IllegalStateException("服务端未配置 XZS_AI_CONFIG_SECRET，不能读取 API Key");
        }
        try {
            byte[] combined = Base64.getDecoder().decode(cipherText);
            byte[] iv = new byte[12];
            byte[] encrypted = new byte[combined.length - iv.length];
            System.arraycopy(combined, 0, iv, 0, iv.length);
            System.arraycopy(combined, iv.length, encrypted, 0, encrypted.length);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, keySpec(), new GCMParameterSpec(128, iv));
            return new String(cipher.doFinal(encrypted), StandardCharsets.UTF_8);
        } catch (Exception e) {
            throw new IllegalStateException("API Key 解密失败", e);
        }
    }

    private SecretKeySpec keySpec() throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        byte[] key = digest.digest(configSecret.getBytes(StandardCharsets.UTF_8));
        return new SecretKeySpec(key, "AES");
    }

    private String valueText(Object value) {
        return value == null ? "" : String.valueOf(value);
    }

    private static class AiSuggestion {
        private String reviewResult;
        private String reviewComment;
        private BigDecimal confidence;
        private String reason;
    }

    public static class SaveConfigRequest {
        private String baseUrl;
        private String model;
        private String apiKey;
        private Boolean clearApiKey;
        private Boolean enabled;
        private String prompt;

        public String getBaseUrl() {
            return baseUrl;
        }

        public void setBaseUrl(String baseUrl) {
            this.baseUrl = baseUrl;
        }

        public String getModel() {
            return model;
        }

        public void setModel(String model) {
            this.model = model;
        }

        public String getApiKey() {
            return apiKey;
        }

        public void setApiKey(String apiKey) {
            this.apiKey = apiKey;
        }

        public Boolean getClearApiKey() {
            return clearApiKey;
        }

        public void setClearApiKey(Boolean clearApiKey) {
            this.clearApiKey = clearApiKey;
        }

        public Boolean getEnabled() {
            return enabled;
        }

        public void setEnabled(Boolean enabled) {
            this.enabled = enabled;
        }

        public String getPrompt() {
            return prompt;
        }

        public void setPrompt(String prompt) {
            this.prompt = prompt;
        }
    }
}
